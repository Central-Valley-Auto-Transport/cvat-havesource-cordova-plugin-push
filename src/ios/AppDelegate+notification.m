//
//  AppDelegate+notification.m
//  pushtest
//
//  Created by Robert Easterday on 10/26/12.
//
//

#import "AppDelegate+notification.h"
#import "PushPlugin.h"
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

static char launchNotificationKey;
static char coldstartKey;
NSString *const pushPluginApplicationDidBecomeActiveNotification = @"pushPluginApplicationDidBecomeActiveNotification";


@implementation AppDelegate (notification)


- (id) getCommandInstance:(NSString*)className
{
    return [self.viewController getCommandInstance:className];
}

// its dangerous to override a method from within a category.
// Instead we will use method swizzling. we set this up in the load call.
+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];

        SEL originalSelector = @selector(init);
        SEL swizzledSelector = @selector(pushPluginSwizzledInit);

        Method original = class_getInstanceMethod(class, originalSelector);
        Method swizzled = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod =
        class_addMethod(class,
                        originalSelector,
                        method_getImplementation(swizzled),
                        method_getTypeEncoding(swizzled));

        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(original),
                                method_getTypeEncoding(original));
        } else {
            method_exchangeImplementations(original, swizzled);
        }
    });
}

- (AppDelegate *)pushPluginSwizzledInit
{
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;

    [[NSNotificationCenter defaultCenter]addObserver:self
                                            selector:@selector(pushPluginOnApplicationDidBecomeActive:)
                                                name:UIApplicationDidBecomeActiveNotification
                                              object:nil];

    // This actually calls the original init method over in AppDelegate. Equivilent to calling super
    // on an overrided method, this is not recursive, although it appears that way. neat huh?
    return [self pushPluginSwizzledInit];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    [pushHandler didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    [pushHandler didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    NSLog(@"[PushPlugin] didReceiveRemoteNotification with fetchCompletionHandler, isNotificationReceivedCalled = %d, application.applicationState=%ld, userInfo = %@", pushHandler.isNotificationReceivedCalled, (long)application.applicationState, userInfo);
    if(pushHandler.isNotificationReceivedCalled == YES){
        NSLog(@"[PushPlugin] didReceiveRemoteNotification pushHandler.isNotificationReceivedCalled TRUE, RESOLVING...");
        return;
    }
    NSMutableDictionary *myUserInfo = [userInfo mutableCopy];
    [pushHandler addTimestamp:myUserInfo];
    
    NSMutableDictionary *additionalData = [[NSMutableDictionary alloc] init];
    for (id key in userInfo) {
        [additionalData setObject:[userInfo objectForKey:key] forKey:key];
    }
    
    // app is in the background or inactive, so only call notification callback if this is a silent push
    if (application.applicationState != UIApplicationStateActive) {

        NSLog(@"[PushPlugin] didReceiveRemoteNotification, APP NOT ACTIVE");

        // do some convoluted logic to find out if this should be a silent push.
        long silent = 0;
        id aps = [userInfo objectForKey:@"aps"];
        id contentAvailable = [aps objectForKey:@"content-available"];
        if ([contentAvailable isKindOfClass:[NSString class]] && [contentAvailable isEqualToString:@"1"]) {
            silent = 1;
        } else if ([contentAvailable isKindOfClass:[NSNumber class]]) {
            silent = [contentAvailable integerValue];
        }
        NSNumber *iosPayloadIsVibrate = [aps objectForKey:@"isVibrate"];
        NSString *iosPayloadSound = [aps objectForKey:@"sound"];
        NSLog(@"[PushPlugin] didReceiveRemoteNotification, APP NOT ACTIVE, silent = %ld, iosPayloadIsVibrate=%@, iosPayloadSound=%@", silent, iosPayloadIsVibrate, iosPayloadSound);

        if (silent == 1) {
            NSLog(@"[PushPlugin] didReceiveRemoteNotification this should be a silent push");
            void (^safeHandler)(UIBackgroundFetchResult) = ^(UIBackgroundFetchResult result){
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionHandler(result);
                });
            };


            if (pushHandler.handlerObj == nil) {
                pushHandler.handlerObj = [NSMutableDictionary dictionaryWithCapacity:2];
            }

            id notId = [userInfo objectForKey:@"notId"];
            if (notId != nil) {
                NSLog(@"[PushPlugin] didReceiveRemoteNotification notId %@", notId);
                [pushHandler.handlerObj setObject:safeHandler forKey:notId];
            } else {
                NSLog(@"[PushPlugin] didReceiveRemoteNotification notId handler");
                [pushHandler.handlerObj setObject:safeHandler forKey:@"handler"];
            }
            
            if ([iosPayloadSound isEqualToString:@"NONE"] && iosPayloadIsVibrate && [iosPayloadIsVibrate boolValue] == YES) {
                [pushHandler triggerVibration];
            }
            
            pushHandler.notificationMessage = userInfo;
            pushHandler.isInline = NO;
            [pushHandler notificationReceived];
        } else {
            NSLog(@"[PushPlugin] didReceiveRemoteNotification Save push for later");
            [pushHandler playSoundVibrate:additionalData];
            self.launchNotification = myUserInfo;
            completionHandler(UIBackgroundFetchResultNewData);
        }

    } else {
        NSLog(@"[PushPlugin] didReceiveRemoteNotification, ACTIVE CALLING completionHandler...");
        if(pushHandler.isNotificationReceivedCalled == NO){
            pushHandler.notificationMessage = userInfo;
            pushHandler.isInline = NO;
            [pushHandler notificationReceived];
        }else{
            completionHandler(UIBackgroundFetchResultNoData);
        }
        //self.launchNotification = myUserInfo;
        //completionHandler(UIBackgroundFetchResultNewData);
    }
}

- (void)checkUserHasRemoteNotificationsEnabledWithCompletionHandler:(nonnull void (^)(BOOL))completionHandler
{
    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {

        switch (settings.authorizationStatus)
        {
            case UNAuthorizationStatusDenied:
            case UNAuthorizationStatusNotDetermined:
                completionHandler(NO);
                break;
            case UNAuthorizationStatusAuthorized:
                completionHandler(YES);
                break;
        }
    }];
}

- (void)pushPluginOnApplicationDidBecomeActive:(NSNotification *)notification {
    NSLog(@"[PushPlugin] pushPluginOnApplicationDidBecomeActive, notification = %@", notification);

    NSString *firstLaunchKey = @"firstLaunchKey";
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"phonegap-plugin-push"];
    if (![defaults boolForKey:firstLaunchKey]) {
        NSLog(@"[PushPlugin] application first launch: remove badge icon number");
        [defaults setBool:YES forKey:firstLaunchKey];
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    }

    UIApplication *application = notification.object;

    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    if (pushHandler.clearBadge) {
        NSLog(@"[PushPlugin] clearing badge");
        //zero badge
        application.applicationIconBadgeNumber = 0;
    } else {
        NSLog(@"[PushPlugin] skip clear badge");
    }

    NSLog(@"[PushPlugin] pushPluginOnApplicationDidBecomeActive launchNotification = %@", self.launchNotification);
    if (self.launchNotification) {
        pushHandler.isInline = NO;
        pushHandler.coldstart = [self.coldstart boolValue];
        pushHandler.notificationMessage = self.launchNotification;
        self.launchNotification = nil;
        self.coldstart = [NSNumber numberWithBool:NO];
        [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:pushPluginApplicationDidBecomeActiveNotification object:nil];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
    NSLog( @"[PushPlugin] AppleDelegate+notification userNotificationCenter NotificationCenter Handle push from foreground" );
    // custom code to handle push while app is in the foreground
    PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
    pushHandler.notificationMessage = notification.request.content.userInfo;
    pushHandler.isInline = YES;
    [pushHandler notificationReceived];

    UNNotificationPresentationOptions presentationOption = UNNotificationPresentationOptionNone;
    if (@available(iOS 10, *)) {
        //if(pushHandler.forceShow) {
            presentationOption = UNNotificationPresentationOptionAlert;
        //}
    }
    completionHandler(presentationOption);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void(^)(void))completionHandler
{
    NSLog(@"[PushPlugin] didReceiveNotificationResponse: actionIdentifier %@, notification: %@", response.actionIdentifier,
          response.notification.request.content.userInfo);
    NSMutableDictionary *userInfo = [response.notification.request.content.userInfo mutableCopy];
    [userInfo setObject:response.actionIdentifier forKey:@"actionCallback"];
    NSLog(@"[PushPlugin] userInfo %@", userInfo);

    switch ([UIApplication sharedApplication].applicationState) {
        case UIApplicationStateActive:
        {
            PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];
            pushHandler.notificationMessage = userInfo;
            pushHandler.isInline = NO;
            //[pushHandler notificationReceived];
            completionHandler();
            break;
        }
        case UIApplicationStateInactive:
        {
            NSLog(@"[PushPlugin] coldstart");
            
            if([response.actionIdentifier rangeOfString:@"UNNotificationDefaultActionIdentifier"].location == NSNotFound) {
                self.launchNotification = userInfo;
            }
            else {
                self.launchNotification = response.notification.request.content.userInfo;
            }
            
            self.coldstart = [NSNumber numberWithBool:YES];
            break;
        }
        case UIApplicationStateBackground:
        {
            void (^safeHandler)(void) = ^(void){
                dispatch_async(dispatch_get_main_queue(), ^{
                    completionHandler();
                });
            };

            PushPlugin *pushHandler = [self getCommandInstance:@"PushNotification"];

            if (pushHandler.handlerObj == nil) {
                pushHandler.handlerObj = [NSMutableDictionary dictionaryWithCapacity:2];
            }

            id notId = [userInfo objectForKey:@"notId"];
            if (notId != nil) {
                NSLog(@"[PushPlugin] notId %@", notId);
                [pushHandler.handlerObj setObject:safeHandler forKey:notId];
            } else {
                NSLog(@"[PushPlugin] notId handler");
                [pushHandler.handlerObj setObject:safeHandler forKey:@"handler"];
            }

            pushHandler.notificationMessage = userInfo;
            pushHandler.isInline = NO;

            [pushHandler performSelectorOnMainThread:@selector(notificationReceived) withObject:pushHandler waitUntilDone:NO];
        }
    }
}

// The accessors use an Associative Reference since you can't define a iVar in a category
// http://developer.apple.com/library/ios/#documentation/cocoa/conceptual/objectivec/Chapters/ocAssociativeReferences.html
- (NSMutableArray *)launchNotification
{
    return objc_getAssociatedObject(self, &launchNotificationKey);
}

- (void)setLaunchNotification:(NSDictionary *)aDictionary
{
    objc_setAssociatedObject(self, &launchNotificationKey, aDictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSNumber *)coldstart
{
    return objc_getAssociatedObject(self, &coldstartKey);
}

- (void)setColdstart:(NSNumber *)aNumber
{
    objc_setAssociatedObject(self, &coldstartKey, aNumber, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)dealloc
{
    self.launchNotification = nil; // clear the association and release the object
    self.coldstart = nil;
}

@end
