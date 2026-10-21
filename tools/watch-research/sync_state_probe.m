// Research only: exercise Apple's sync-state logic using synthetic in-memory data.
// No pass import, device connection, IDS service or Wallet file access.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <objc/runtime.h>
#include <dlfcn.h>

#if !TARGET_OS_SIMULATOR
#error This probe must only be built for an Apple simulator.
#endif

// Signatures observed in the watchOS 26.5 NanoPassKit runtime.
@interface NSObject (WatchSyncResearch)
- (instancetype)initWithPassTypeIdentifier:(NSString *)type
                             serialNumber:(NSString *)serial
                          sequenceCounter:(NSNumber *)sequence
                             manifestHash:(NSData *)hash
                                 manifest:(NSDictionary *)manifest;
- (instancetype)initWithSyncStateItems:(NSArray *)items version:(NSUInteger)version;
- (void)compareWithBaselinePassSyncState:(id)baseline
                       outAddedSyncItems:(id __autoreleasing *)added
                     outUpdatedSyncItems:(id __autoreleasing *)updated
                     outRemovedSyncItems:(id __autoreleasing *)removed;
- (instancetype)initWithRole:(NSUInteger)role;
- (void)_shouldProcessAddOrUpdateChangeOfType:(NSUInteger)type
                        changeSyncStateItem:(id)change
                       librarySyncStateItem:(id)library
                    reconciledSyncStateItem:(id)reconciled
                            candidateChange:(id)candidate
                   shouldApplyToPassLibrary:(BOOL *)apply
               shouldApplyToReconciledState:(BOOL *)reconcile;
@end

static void Require(BOOL condition, NSString *message) {
    if (!condition) @throw [NSException exceptionWithName:@"ProbeFailure"
                                                 reason:message userInfo:nil];
}

static id Item(Class cls, NSUInteger sequence, uint8_t hashByte, NSString *imageHash) {
    uint8_t bytes[20];
    memset(bytes, hashByte, sizeof(bytes));
    return [[cls alloc] initWithPassTypeIdentifier:@"pass.example.watch-sync-research"
                                     serialNumber:@"synthetic-card"
                                  sequenceCounter:@(sequence)
                                     manifestHash:[NSData dataWithBytes:bytes length:sizeof(bytes)]
                                         manifest:@{@"test-image.png": imageHash}];
}

static NSDictionary *Difference(Class cls, id original, id changed) {
    id before = [[cls alloc] initWithSyncStateItems:@[original] version:1];
    id after = [[cls alloc] initWithSyncStateItems:@[changed] version:1];
    id added = nil, updated = nil, removed = nil;
    [after compareWithBaselinePassSyncState:before outAddedSyncItems:&added
                       outUpdatedSyncItems:&updated outRemovedSyncItems:&removed];
    Require(added && updated && removed, @"State comparison did not return collections");
    return @{@"added": @([added count]), @"updated": @([updated count]),
             @"removed": @([removed count])};
}

static NSDictionary *Decision(id engine, id changed, id library, id reconciled) {
    BOOL apply = NO, reconcile = NO;
    // NPKPassSyncChangeTypeToString(1) == Update; no transport is instantiated.
    [engine _shouldProcessAddOrUpdateChangeOfType:1 changeSyncStateItem:changed
                           librarySyncStateItem:library reconciledSyncStateItem:reconciled
                                candidateChange:nil shouldApplyToPassLibrary:&apply
                   shouldApplyToReconciledState:&reconcile];
    return @{@"applyToLibrary": @(apply), @"applyToReconciledState": @(reconcile)};
}

int main(void) {
    @autoreleasepool {
        @try {
            Require(getenv("SIMULATOR_UDID") != NULL, @"Simulator environment required");
            Require(dlopen("/System/Library/PrivateFrameworks/NanoPassKit.framework/NanoPassKit",
                           RTLD_NOW | RTLD_LOCAL) != NULL, @"NanoPassKit unavailable");
            Class itemClass = NSClassFromString(@"NPKPassSyncStateItem");
            Class stateClass = NSClassFromString(@"NPKPassSyncState");
            Class engineClass = NSClassFromString(@"NPKPassSyncEngine");
            Require(itemClass && stateClass && engineClass, @"Expected sync classes unavailable");
            SEL itemInit = @selector(initWithPassTypeIdentifier:serialNumber:sequenceCounter:manifestHash:manifest:);
            SEL stateInit = @selector(initWithSyncStateItems:version:);
            SEL compare = @selector(compareWithBaselinePassSyncState:outAddedSyncItems:outUpdatedSyncItems:outRemovedSyncItems:);
            SEL decide = @selector(_shouldProcessAddOrUpdateChangeOfType:changeSyncStateItem:librarySyncStateItem:reconciledSyncStateItem:candidateChange:shouldApplyToPassLibrary:shouldApplyToReconciledState:);
            Require([itemClass instancesRespondToSelector:itemInit] &&
                    [stateClass instancesRespondToSelector:stateInit] &&
                    [stateClass instancesRespondToSelector:compare] &&
                    [engineClass instancesRespondToSelector:@selector(initWithRole:)] &&
                    [engineClass instancesRespondToSelector:decide], @"Expected sync methods unavailable");
            Require(method_getNumberOfArguments(class_getInstanceMethod(engineClass, decide)) == 9,
                    @"Sync decision method signature changed");

            NSString *oldImage = @"1111111111111111111111111111111111111111";
            NSString *newImage = @"2222222222222222222222222222222222222222";
            id baseline = Item(itemClass, 7, 0x11, oldImage);
            id identical = Item(itemClass, 7, 0x11, oldImage);
            id changed = Item(itemClass, 7, 0x22, newImage);
            id staleHash = Item(itemClass, 7, 0x11, newImage);
            id newerLocal = Item(itemClass, 8, 0x33, oldImage);
            Require(baseline && identical && changed && staleHash && newerLocal, @"Cannot create synthetic states");

            // Role 0 is Watch. This object does not create NPKPassSyncService or IDS.
            id engine = [[engineClass alloc] initWithRole:0];
            Require(engine != nil, @"Cannot create sync engine");
            NSDictionary *unchangedDiff = Difference(stateClass, baseline, identical);
            NSDictionary *changedDiff = Difference(stateClass, baseline, changed);
            NSDictionary *staleHashDiff = Difference(stateClass, baseline, staleHash);
            NSDictionary *cleanDecision = Decision(engine, changed, baseline, identical);
            NSDictionary *conflictDecision = Decision(engine, changed, newerLocal, baseline);

            Require([baseline isEqual:identical], @"Identical states must compare equal");
            Require(![baseline isEqual:changed], @"Changed manifest hash should change state identity");
            Require([baseline isEqual:staleHash], @"Unexpected manifest-hash comparison behavior");
            Require([unchangedDiff isEqual:@{@"added": @0, @"updated": @0, @"removed": @0}], @"Unchanged state produced changes");
            Require([changedDiff isEqual:@{@"added": @0, @"updated": @1, @"removed": @0}], @"Artwork state was not classified as one update");
            Require([staleHashDiff isEqual:unchangedDiff], @"Stale hash control produced unexpected changes");
            Require([cleanDecision[@"applyToLibrary"] boolValue] &&
                    [cleanDecision[@"applyToReconciledState"] boolValue], @"Unconflicted same-sequence update was rejected");
            Require(![conflictDecision[@"applyToLibrary"] boolValue], @"Older update would replace a newer local state");

            NSDictionary *result = @{@"ok": @YES,
                @"system": NSProcessInfo.processInfo.operatingSystemVersionString,
                @"syntheticDataOnly": @YES, @"walletImportAttempted": @NO,
                @"unchanged": unchangedDiff, @"changedManifestSameSequence": changedDiff,
                @"changedManifestContentsWithStaleHash": staleHashDiff,
                @"unconflictedUpdate": cleanDecision, @"newerLocalConflict": conflictDecision};
            NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
            puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
            return 0;
        } @catch (NSException *exception) {
            fprintf(stderr, "Probe failed: %s\n", exception.reason.UTF8String);
            return 1;
        }
    }
}
