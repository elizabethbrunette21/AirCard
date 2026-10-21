// Read-only registry queries on an already-trusted iPhone. No file access.
// Protocol: pymobiledevice3/services/companion.py, GetValueFromRegistry.
#define main AirCardOriginalMain
#include "../../Sources/device_helper.m"
#undef main
#include <assert.h>

static NSDictionary *ValueSummary(id reply) {
    if (![reply isKindOfClass:NSDictionary.class])
        return @{@"ok": @NO, @"error": @"invalid_reply"};
    if (reply[@"Error"]) {
        NSArray *known = @[@"UnsupportedWatchKey", @"TimeoutReply", @"NoPairedWatches"];
        id error = [known containsObject:reply[@"Error"]] ? reply[@"Error"] : @"query_rejected";
        return @{@"ok": @NO, @"error": error};
    }
    id value = reply[@"RetrievedValueDictionary"];
    if (!value) return @{@"ok": @NO, @"error": @"missing_value"};
    NSString *type = [value isKindOfClass:NSDictionary.class] ? @"dictionary" :
        [value isKindOfClass:NSString.class] ? @"string" :
        [value isKindOfClass:NSNumber.class] ? @"number" : @"other";
    // Deliberately omit values and dictionary keys: they may identify devices.
    return @{@"ok": @YES, @"valueType": type};
}

static id Query(NSDictionary *request) {
    AMDServiceConnectionRef service = NULL;
    int status = AMDeviceSecureStartService(
        TargetDevice, CFSTR("com.apple.companion_proxy"), NULL, &service);
    if (status != 0 || !service) {
        if (service) AMDServiceConnectionInvalidate(service);
        return nil;
    }
    status = AMDServiceConnectionSendMessage(
        service, (__bridge CFDictionaryRef)request, kCFPropertyListXMLFormat_v1_0);
    CFTypeRef raw = NULL;
    CFPropertyListFormat format = kCFPropertyListXMLFormat_v1_0;
    if (status == 0) status = AMDServiceConnectionReceiveMessage(service, &raw, &format);
    id reply = CFBridgingRelease(raw);
    AMDServiceConnectionInvalidate(service);
    return status == 0 ? reply : nil;
}

static void Timeout(int number) {
    (void)number;
    const char message[] = "{\"ok\":false,\"error\":\"registry_timeout\"}\n";
    (void)write(STDOUT_FILENO, message, sizeof(message) - 1);
    _exit(124);
}

static void SelfTest(void) {
    assert(![ValueSummary(nil)[@"ok"] boolValue]);
    assert(![ValueSummary(@[])[@"ok"] boolValue]);
    assert(![ValueSummary(@{})[@"ok"] boolValue]);
    assert([ValueSummary(@{@"Error": @"UnsupportedWatchKey"})[@"error"]
        isEqual:@"UnsupportedWatchKey"]);
    assert([ValueSummary(@{@"Error": @"PRIVATE-ERROR"})[@"error"]
        isEqual:@"query_rejected"]);
    NSDictionary *summary = ValueSummary(@{@"RetrievedValueDictionary":
        @{@"PRIVATE-KEY": @"PRIVATE-IDENTIFIER"}});
    assert([summary[@"ok"] boolValue]);
    assert([summary[@"valueType"] isEqual:@"dictionary"]);
    assert([[summary description] rangeOfString:@"PRIVATE-"].location == NSNotFound);
    summary = ValueSummary(@{@"RetrievedValueDictionary": @"PRIVATE-PATH"});
    assert([summary[@"valueType"] isEqual:@"string"]);
    assert([[summary description] rangeOfString:@"PRIVATE-"].location == NSNotFound);
    puts("Registry value validation and redaction passed.");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
            SelfTest();
            return 0;
        }
        if (argc != 2) return 64;
        signal(SIGPIPE, SIG_IGN);
        signal(SIGALRM, Timeout);
        alarm(30);
        TargetIdentifier = CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8);
        BOOL connected = NO, session = NO;
        NSDictionary *result = nil;
        do {
            if (!TargetIdentifier || FindTarget() != 0 || !TargetDevice) {
                result = @{@"ok": @NO, @"error": @"phone_unavailable"};
                break;
            }
            if (AMDeviceConnect(TargetDevice) != 0) {
                result = @{@"ok": @NO, @"error": @"connect_failed"};
                break;
            }
            connected = YES;
            if (!AMDeviceIsPaired(TargetDevice) || AMDeviceValidatePairing(TargetDevice) != 0) {
                result = @{@"ok": @NO, @"error": @"existing_trust_required"};
                break;
            }
            if (AMDeviceStartSession(TargetDevice) != 0) {
                result = @{@"ok": @NO, @"error": @"session_failed"};
                break;
            }
            session = YES;
            id registry = Query(@{@"Command": @"GetDeviceRegistry"});
            id devices = [registry isKindOfClass:NSDictionary.class]
                && !registry[@"Error"] ? registry[@"PairedDevicesArray"] : nil;
            if (![devices isKindOfClass:NSArray.class] || [devices count] != 1
                || ![devices[0] isKindOfClass:NSString.class] || [devices[0] length] == 0) {
                result = @{@"ok": @NO, @"error": @"single_paired_identifier_required"};
                break;
            }
            NSMutableArray *queries = NSMutableArray.array;
            // NanoRegistry names are hypotheses here; rejection is an expected result.
            for (NSString *key in @[@"productType", @"systemVersion", @"localPairingDataStorePath"]) {
                id reply = Query(@{@"Command": @"GetValueFromRegistry",
                    @"GetValueGizmoUDIDKey": devices[0], @"GetValueKeyKey": key});
                [queries addObject:@{@"key": key, @"result": ValueSummary(reply)}];
            }
            // Completion is not evidence that any key is supported.
            result = @{@"completed": @YES, @"queries": queries};
        } while (NO);
        if (session) AMDeviceStopSession(TargetDevice);
        if (connected) AMDeviceDisconnect(TargetDevice);
        if (TargetDevice) CFRelease(TargetDevice);
        if (TargetIdentifier) CFRelease(TargetIdentifier);
        alarm(0);
        PrintJSON(result);
        return [result[@"completed"] boolValue] ? 0 : 2;
    }
}
