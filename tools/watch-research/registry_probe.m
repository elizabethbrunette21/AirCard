// Device-only research probe: query NanoRegistry; write results in our own sandbox.
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

static id Send0(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

@interface RegistryProbe : UIResponder <UIApplicationDelegate, UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic) BOOL finished;
@end

@implementation RegistryProbe
- (void)saveResult:(NSDictionary *)result {
    // Paths can identify the pairing. Export only to ignored local research storage.
    NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    [data writeToURL:[directory URLByAppendingPathComponent:@"registry-result.json"]
            options:NSDataWritingAtomic error:nil];
    self.label.text = [result[@"pathFound"] boolValue]
        ? @"已取得登记目录。\n未读取卡包，未修改钱包。"
        : [NSString stringWithFormat:@"只读检查：%@\n未修改钱包。", result[@"status"]];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Probe"
                                                                        sessionRole:session.role];
    configuration.delegateClass = RegistryProbe.class;
    return configuration;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    self.label = [UILabel new];
    self.label.numberOfLines = 0;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    self.label.adjustsFontForContentSizeCategory = YES;
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [self.label.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [self.label.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor]]];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];
    [self saveResult:@{@"status": @"running", @"pathFound": @NO}];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!self.finished) {
            self.finished = YES;
            [self saveResult:@{@"status": @"timeout", @"pathFound": @NO}];
        }
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        @autoreleasepool {
            NSMutableDictionary *result = [@{@"status": @"completed", @"pathFound": @NO} mutableCopy];
            @try {
                void *framework = dlopen("/System/Library/PrivateFrameworks/NanoRegistry.framework/NanoRegistry", RTLD_LAZY | RTLD_LOCAL);
                result[@"frameworkLoaded"] = @(framework != NULL);
                if (framework) {
                    id registry = Send0(NSClassFromString(@"NRPairedDeviceRegistry"), @"sharedInstance");
                    id initialPaired = Send0(registry, @"getPairedDevices");
                    result[@"initialPairedDeviceCount"] = [initialPaired isKindOfClass:NSArray.class]
                        ? @([initialPaired count]) : @(-1);
                    // Allow the initial registry update to arrive; one bounded retry only.
                    [NSThread sleepForTimeInterval:3];
                    id paired = Send0(registry, @"getPairedDevices");
                    id allDevices = Send0(registry, @"getAllDevices");
                    result[@"pairedDeviceCount"] = [paired isKindOfClass:NSArray.class]
                        ? @([paired count]) : @(-1);
                    result[@"allDeviceCount"] = [allDevices isKindOfClass:NSArray.class]
                        ? @([allDevices count]) : @(-1);
                    id device = Send0(registry, @"getActivePairedDevice");
                    result[@"registryAvailable"] = @(registry != nil);
                    result[@"activeDeviceFound"] = @(device != nil);
                    NSString * __unsafe_unretained *key = (NSString * __unsafe_unretained *)dlsym(framework, "NRDevicePropertyLocalPairingDataStorePath");
                    SEL getter = NSSelectorFromString(@"valueForProperty:");
                    id path = key && [device respondsToSelector:getter]
                        ? ((id (*)(id, SEL, id))objc_msgSend)(device, getter, *key) : nil;
                    if ([path isKindOfClass:NSString.class] && [path length] > 0) {
                        result[@"pathFound"] = @YES;
                        result[@"pairingStorePath"] = path;
                    }
                    // Keep the system framework loaded for its background registry work.
                }
            } @catch (NSException *exception) {
                (void)exception;
                result[@"status"] = @"exception";
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self.finished) {
                    self.finished = YES;
                    [self saveResult:result];
                }
            });
        }
    });
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(RegistryProbe.class));
    }
}
