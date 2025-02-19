/*
 Copyright 2009-2011 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*CHECKLIST:
   1) Foreground or device awake (app open & paused):
       A) Click opens app, shows popup & saves notification
       B) Open app shows popup and saves notification
   2) Foreground or device awake (app closed):
       A) Click opens app, shows popup & saves notification
       B) Open app shows popup and saves notification
   3) Background or device asleep (app open & paused):
       A) Click opens app, shows popup & saves notification
       B) Open app shows popup and saves notification
   4) Background or device asleep (app closed):
       A) Click opens app, shows popup & saves notification
       B) Open app shows popup and saves notification
 */

#import "PushPlugin.h"
#import "AppDelegate+notification.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

@import Firebase;
@import FirebaseCore;
@import FirebaseMessaging;

@implementation PushPlugin : CDVPlugin

@synthesize notificationMessage;
@synthesize isInline;
@synthesize coldstart;
@synthesize callbackId;
@synthesize clearBadge;
@synthesize forceShow;
@synthesize handlerObj;
@synthesize usesFCM;
@synthesize fcmSenderId;
@synthesize fcmTopics;
@synthesize isNotificationReceivedCalled;


- (void)initRegistration {
    [[FIRMessaging messaging] tokenWithCompletion:^(NSString *token, NSError *error) {
        if (error != nil) {
            NSLog(@"[PushPlugin] Error getting FCM registration token: %@", error);
        } else {
            NSLog(@"[PushPlugin] FCM registration token: %@", token);
            
            id topics = [self fcmTopics];
            if (topics != nil) {
                for (NSString *topic in topics) {
                    NSLog(@"[PushPlugin] subscribe to topic: %@", topic);
                    id pubSub = [FIRMessaging messaging];
                    [pubSub subscribeToTopic:topic];
                }
            }
            
            [self registerWithToken: token];
        }
    }];
}


// Method to delete Firebase Instance ID
- (void)deleteInstanceId:(CDVInvokedUrlCommand *)command {
    [[FIRMessaging messaging] deleteFCMTokenForSenderID:fcmSenderId
                                             completion:^(NSError * _Nullable error) {
        NSString* pluginResult;
        if (error != nil) {
            pluginResult = error.localizedDescription;
        } else {
            pluginResult = @"Instance ID deleted successfully";
        }
        [self successWithMessage:command.callbackId withMsg:pluginResult];
    }];
}

//  FCM refresh token
//  Unclear how this is testable under normal circumstances
- (void)onTokenRefresh {
#if !TARGET_IPHONE_SIMULATOR
    // A rotation of the registration tokens is happening, so the app needs to request a new token.
    NSLog(@"[PushPlugin] The FCM registration token needs to be changed.");
    [self initRegistration];
#endif
}


- (void)unregister:(CDVInvokedUrlCommand *)command {
    NSArray* topics = [command argumentAtIndex:0];
    
    if (topics != nil) {
        id pubSub = [FIRMessaging messaging];
        for (NSString *topic in topics) {
            NSLog(@"[PushPlugin] unsubscribe from topic: %@", topic);
            [pubSub unsubscribeFromTopic:topic];
        }
    } else {
        [[UIApplication sharedApplication] unregisterForRemoteNotifications];
        [self successWithMessage:command.callbackId withMsg:@"unregistered"];
    }
}

- (void)subscribe:(CDVInvokedUrlCommand *)command {
    NSString* topic = [command argumentAtIndex:0];
    
    if (topic != nil) {
        NSLog(@"[PushPlugin] subscribe from topic: %@", topic);
        id pubSub = [FIRMessaging messaging];
        [pubSub subscribeToTopic:topic];
        NSLog(@"[PushPlugin] Successfully subscribe to topic %@", topic);
        [self successWithMessage:command.callbackId withMsg:[NSString stringWithFormat:@"Successfully subscribe to topic %@", topic]];
    } else {
        NSLog(@"[PushPlugin] There is no topic to subscribe");
        [self successWithMessage:command.callbackId withMsg:@"There is no topic to subscribe"];
    }
}

- (void)unsubscribe:(CDVInvokedUrlCommand *)command {
    NSString* topic = [command argumentAtIndex:0];
    
    if (topic != nil) {
        NSLog(@"[PushPlugin] unsubscribe from topic: %@", topic);
        id pubSub = [FIRMessaging messaging];
        [pubSub unsubscribeFromTopic:topic];
        NSLog(@"[PushPlugin] Successfully unsubscribe from topic %@", topic);
        [self successWithMessage:command.callbackId withMsg:[NSString stringWithFormat:@"Successfully unsubscribe from topic %@", topic]];
    } else {
        NSLog(@"[PushPlugin] There is no topic to unsubscribe");
        [self successWithMessage:command.callbackId withMsg:@"There is no topic to unsubscribe"];
    }
}

- (void)init:(CDVInvokedUrlCommand *)command {
    isNotificationReceivedCalled = false;
    NSMutableDictionary* options = [command.arguments objectAtIndex:0];
    NSMutableDictionary* iosOptions = [options objectForKey:@"ios"];
    // SAVE DEFAULT FOR IOS OPTIONS:===========================================>
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *iosDefaults = [[NSMutableDictionary alloc] init];
    id alertArg = [iosOptions objectForKey:@"alert"];
    id badgeArg = [iosOptions objectForKey:@"badge"];
    BOOL isAlert = NO;
    BOOL isBadge = NO;
    if (([alertArg isKindOfClass:[NSString class]] && [alertArg isEqualToString:@"true"]) || [alertArg boolValue]) {
        isAlert = YES;
    }
    if (([badgeArg isKindOfClass:[NSString class]] && [badgeArg isEqualToString:@"true"]) || [badgeArg boolValue]) {
        isBadge = YES;
    }
    [iosDefaults setObject:[iosOptions objectForKey:@"senderID"] forKey:@"senderID"];
    [iosDefaults setObject:[iosOptions objectForKey:@"icon"] forKey:@"icon"];
    [iosDefaults setObject:[NSNumber numberWithBool:isAlert] forKey:@"alert"];
    [iosDefaults setObject:[NSNumber numberWithBool:isBadge] forKey:@"badge"];
    [defaults setObject:iosDefaults forKey:@"iosDefaults"];
    [defaults synchronize];
    //END SAVE iosDefaults====================================================>
    
    id voipArg = [iosOptions objectForKey:@"voip"];
    if (([voipArg isKindOfClass:[NSString class]] && [voipArg isEqualToString:@"true"]) || [voipArg boolValue]) {
        [self.commandDelegate runInBackground:^ {
            NSLog(@"[PushPlugin] VoIP set to true");
            
            self.callbackId = command.callbackId;
            
            PKPushRegistry *pushRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
            pushRegistry.delegate = self;
            pushRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
        }];
    } else {
        NSLog(@"[PushPlugin] VoIP missing or false");
        [[NSNotificationCenter defaultCenter]
         addObserver:self selector:@selector(onTokenRefresh)
         name:FIRMessagingRegistrationTokenRefreshedNotification object:nil];
        
        [self.commandDelegate runInBackground:^ {
            NSLog(@"[PushPlugin] register called");
            self.callbackId = command.callbackId;
            
            [self doInit:iosOptions];
        }];
    }
}

- (void) doInit: (NSMutableDictionary *) iosOptions {
    NSLog(@"[PushPlugin] doInit called");
    NSArray* topics = [iosOptions objectForKey:@"topics"];
    [self setFcmTopics:topics];
    
    UNAuthorizationOptions authorizationOptions = UNAuthorizationOptionNone;
    
    // USE DEFAULTS TO SAVE DEFAULT NOTIFICATION PREFERENCES:
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *notificationPreferences = [[NSMutableDictionary alloc] init];
    [notificationPreferences setObject:[NSNumber numberWithBool:NO] forKey:@"is_user_configured"];
    
    id badgeArg = [iosOptions objectForKey:@"badge"];
    id isSoundArg = [iosOptions objectForKey:@"is_sound"];
    NSString *soundArg = [iosOptions objectForKey:@"sound"];
    id isVibrationArg = [iosOptions objectForKey:@"is_vibration"];
    id alertArg = [iosOptions objectForKey:@"alert"];
    id criticalArg = [iosOptions objectForKey:@"critical"];
    id clearBadgeArg = [iosOptions objectForKey:@"clearBadge"];
    id forceShowArg = [iosOptions objectForKey:@"forceShow"];
    
    if (([badgeArg isKindOfClass:[NSString class]] && [badgeArg isEqualToString:@"true"]) || [badgeArg boolValue])
    {
        authorizationOptions |= UNAuthorizationOptionBadge;
    }
    
    //SET/SAVE IF SOUND:
    if (([isSoundArg isKindOfClass:[NSString class]] && [isSoundArg isEqualToString:@"true"]) || [isSoundArg boolValue])
    {
        authorizationOptions |= UNAuthorizationOptionSound;
        [notificationPreferences setObject:[NSNumber numberWithBool:YES] forKey:@"is_sound"];
    } else {
        [notificationPreferences setObject:[NSNumber numberWithBool:NO] forKey:@"is_sound"];
    }
    
    //SET/SAVE SOUND:
    [notificationPreferences setObject:soundArg forKey:@"sound"];
    
    //SET/SAVE IF VIBRATION:
    if (([isVibrationArg isKindOfClass:[NSString class]] && [isVibrationArg isEqualToString:@"true"]) || [isVibrationArg boolValue])
    {
        [notificationPreferences setObject:[NSNumber numberWithBool:YES] forKey:@"is_vibration"];
    } else {
        [notificationPreferences setObject:[NSNumber numberWithBool:NO] forKey:@"is_vibration"];
    }
    
    [defaults setObject:notificationPreferences forKey:@"notificationPreferences"];
    [defaults synchronize];
    
    if (([alertArg isKindOfClass:[NSString class]] && [alertArg isEqualToString:@"true"]) || [alertArg boolValue])
    {
        authorizationOptions |= UNAuthorizationOptionAlert;
    }
    
    if (@available(iOS 12.0, *))
    {
        if ((([criticalArg isKindOfClass:[NSString class]] && [criticalArg isEqualToString:@"true"]) || [criticalArg boolValue]))
        {
            authorizationOptions |= UNAuthorizationOptionCriticalAlert;
        }
    }
    
    if (clearBadgeArg == nil || ([clearBadgeArg isKindOfClass:[NSString class]] && [clearBadgeArg isEqualToString:@"false"]) || ![clearBadgeArg boolValue]) {
        NSLog(@"[PushPlugin] register: setting badge to false");
        clearBadge = NO;
    } else {
        NSLog(@"[PushPlugin] register: setting badge to true");
        clearBadge = YES;
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];
    }
    NSLog(@"[PushPlugin] register: clear badge is set to %d", clearBadge);
    
    if (forceShowArg == nil || ([forceShowArg isKindOfClass:[NSString class]] && [forceShowArg isEqualToString:@"false"]) || ![forceShowArg boolValue]) {
        NSLog(@"[PushPlugin] register: setting forceShow to false");
        forceShow = NO;
    } else {
        NSLog(@"[PushPlugin] register: setting forceShow to true");
        forceShow = YES;
    }
    
    isInline = NO;
    
    NSLog(@"[PushPlugin] register: better button setup");
    // setup action buttons
    NSMutableSet<UNNotificationCategory *> *categories = [[NSMutableSet alloc] init];
    id categoryOptions = [iosOptions objectForKey:@"categories"];
    if (categoryOptions != nil && [categoryOptions isKindOfClass:[NSDictionary class]]) {
        for (id key in categoryOptions) {
            NSLog(@"[PushPlugin] categories: key %@", key);
            id category = [categoryOptions objectForKey:key];
            
            id yesButton = [category objectForKey:@"yes"];
            UNNotificationAction *yesAction;
            if (yesButton != nil && [yesButton  isKindOfClass:[NSDictionary class]]) {
                yesAction = [self createAction: yesButton];
            }
            id noButton = [category objectForKey:@"no"];
            UNNotificationAction *noAction;
            if (noButton != nil && [noButton  isKindOfClass:[NSDictionary class]]) {
                noAction = [self createAction: noButton];
            }
            id maybeButton = [category objectForKey:@"maybe"];
            UNNotificationAction *maybeAction;
            if (maybeButton != nil && [maybeButton  isKindOfClass:[NSDictionary class]]) {
                maybeAction = [self createAction: maybeButton];
            }
            
            // Identifier to include in your push payload and local notification
            NSString *identifier = key;
            
            NSMutableArray<UNNotificationAction *> *actions = [[NSMutableArray alloc] init];
            if (yesButton != nil) {
                [actions addObject:yesAction];
            }
            if (noButton != nil) {
                [actions addObject:noAction];
            }
            if (maybeButton != nil) {
                [actions addObject:maybeAction];
            }
            
            UNNotificationCategory *notificationCategory = [UNNotificationCategory categoryWithIdentifier:identifier
                                                                                                  actions:actions
                                                                                        intentIdentifiers:@[]
                                                                                                  options:UNNotificationCategoryOptionNone];
            
            NSLog(@"[PushPlugin] Adding category %@", key);
            [categories addObject:notificationCategory];
        }
    }
    
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center setNotificationCategories:categories];
    [self handleNotificationSettingsWithAuthorizationOptions:[NSNumber numberWithInteger:authorizationOptions]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleNotificationSettings:)
                                                 name:pushPluginApplicationDidBecomeActiveNotification
                                               object:nil];
    
    // Read GoogleService-Info.plist
    NSString *path = [[NSBundle mainBundle] pathForResource:@"GoogleService-Info" ofType:@"plist"];
    
    // Load the file content and read the data into arrays
    NSDictionary *dict = [[NSDictionary alloc] initWithContentsOfFile:path];
    fcmSenderId = [dict objectForKey:@"GCM_SENDER_ID"];
    BOOL isGcmEnabled = [[dict valueForKey:@"IS_GCM_ENABLED"] boolValue];
    
    NSLog(@"[PushPlugin] FCM Sender ID %@", fcmSenderId);
    
    //  GCM options
    [self setFcmSenderId: fcmSenderId];
    if(isGcmEnabled && [[self fcmSenderId] length] > 0) {
        NSLog(@"[PushPlugin] Using FCM Notification");
        [self setUsesFCM: YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            if([FIRApp defaultApp] == nil)
                [FIRApp configure];
            [self initRegistration];
        });
    } else {
        NSLog(@"[PushPlugin] Using APNS Notification");
        [self setUsesFCM:NO];
    }
    
    if (notificationMessage) {            // if there is a pending startup notification
        dispatch_async(dispatch_get_main_queue(), ^{
            // delay to allow JS event handlers to be setup
            [self performSelector:@selector(notificationReceived) withObject:nil afterDelay: 0.5];
        });
    }
}

- (UNNotificationAction *)createAction:(NSDictionary *)dictionary {
    NSLog(@"[PushPlugin] createAction called dictionary = %@", dictionary);
    NSString *identifier = [dictionary objectForKey:@"callback"];
    NSString *title = [dictionary objectForKey:@"title"];
    NSString *body = [dictionary objectForKey:@"body"];
    NSString *completeTitle = [NSString stringWithFormat:@"%@: %@", title, body];
    UNNotificationActionOptions options = UNNotificationActionOptionNone;
    
    id mode = [dictionary objectForKey:@"foreground"];
    if (mode != nil && (([mode isKindOfClass:[NSString class]] && [mode isEqualToString:@"true"]) || [mode boolValue])) {
        options |= UNNotificationActionOptionForeground;
    }
    id destructive = [dictionary objectForKey:@"destructive"];
    if (destructive != nil && (([destructive isKindOfClass:[NSString class]] && [destructive isEqualToString:@"true"]) || [destructive boolValue])) {
        options |= UNNotificationActionOptionDestructive;
    }
    
    return [UNNotificationAction actionWithIdentifier:identifier title:completeTitle options:options];
}

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    if (self.callbackId == nil) {
        NSLog(@"[PushPlugin] Unexpected call to didRegisterForRemoteNotificationsWithDeviceToken, ignoring: %@", deviceToken);
        return;
    }
    NSLog(@"[PushPlugin] register success: %@", deviceToken);
    
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    // [deviceToken description] is like "{length = 32, bytes = 0xd3d997af 967d1f43 b405374a 13394d2f ... 28f10282 14af515f }"
    NSString *token = [self hexadecimalStringFromData:deviceToken];
#else
    // [deviceToken description] is like "<124686a5 556a72ca d808f572 00c323b9 3eff9285 92445590 3225757d b83967be>"
    NSString *token = [[[[deviceToken description] stringByReplacingOccurrencesOfString:@"<"withString:@""]
                        stringByReplacingOccurrencesOfString:@">" withString:@""]
                       stringByReplacingOccurrencesOfString: @" " withString: @""];
#endif
    
#if !TARGET_IPHONE_SIMULATOR
    // Check what Notifications the user has turned on.  We registered for all three, but they may have manually disabled some or all of them.
    
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    __weak PushPlugin *weakSelf = self;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
        
        if(![weakSelf usesFCM]) {
            [weakSelf registerWithToken: token];
        }
    }];
#endif
}

- (NSString *)hexadecimalStringFromData:(NSData *)data {
    NSUInteger dataLength = data.length;
    if (dataLength == 0) {
        return nil;
    }
    
    const unsigned char *dataBuffer = data.bytes;
    NSMutableString *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];
    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02x", dataBuffer[i]];
    }
    return [hexString copy];
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    if (self.callbackId == nil) {
        NSLog(@"[PushPlugin] Unexpected call to didFailToRegisterForRemoteNotificationsWithError, ignoring: %@", error);
        return;
    }
    NSLog(@"[PushPlugin] register failed");
    [self failWithMessage:self.callbackId withMsg:@"" withError:error];
}

- (void)notificationReceived {
    isNotificationReceivedCalled = true;
    NSLog(@"[PushPlugin] PushPlugin.notificationReceived called");
    
    if (notificationMessage && self.callbackId != nil)
    {
        NSMutableDictionary* message = [NSMutableDictionary dictionaryWithCapacity:5];
        NSMutableDictionary* additionalData = [NSMutableDictionary dictionaryWithCapacity:4];
        
        for (id key in notificationMessage) {
            if ([key isEqualToString:@"aps"]) {
                id aps = [notificationMessage objectForKey:@"aps"];
                
                for(id key in aps) {
                    NSLog(@"[PushPlugin] key: %@", key);
                    id value = [aps objectForKey:key];
                    
                    if ([key isEqualToString:@"alert"]) {
                        if ([value isKindOfClass:[NSDictionary class]]) {
                            for (id messageKey in value) {
                                id messageValue = [value objectForKey:messageKey];
                                if ([messageKey isEqualToString:@"body"]) {
                                    [message setObject:messageValue forKey:@"message"];
                                } else if ([messageKey isEqualToString:@"title"]) {
                                    [message setObject:messageValue forKey:@"title"];
                                } else {
                                    [additionalData setObject:messageValue forKey:messageKey];
                                }
                            }
                        }
                        else {
                            [message setObject:value forKey:@"message"];
                        }
                    } else if ([key isEqualToString:@"title"]) {
                        [message setObject:value forKey:@"title"];
                    } else if ([key isEqualToString:@"badge"]) {
                        [message setObject:value forKey:@"count"];
                    } else if ([key isEqualToString:@"sound"]) {
                        [message setObject:value forKey:@"sound"];
                    } else if ([key isEqualToString:@"image"]) {
                        [message setObject:value forKey:@"image"];
                    } else {
                        [additionalData setObject:value forKey:key];
                    }
                }
            } else {
                [additionalData setObject:[notificationMessage objectForKey:key] forKey:key];
            }
        }
        
        if (isInline) {//FOREGROUND TRUE
            [additionalData setObject:[NSNumber numberWithBool:YES] forKey:@"foreground"];
        } else {
            [additionalData setObject:[NSNumber numberWithBool:NO] forKey:@"foreground"];
        }
        
        if (coldstart) {
            [additionalData setObject:[NSNumber numberWithBool:YES] forKey:@"coldstart"];
        } else {
            [additionalData setObject:[NSNumber numberWithBool:NO] forKey:@"coldstart"];
        }
        [self addTimestamp:message];
        
        [message setObject:additionalData forKey:@"additionalData"];
        
        if(isInline){
            NSLog(@"[PushPlugin] PushPlugin.notificationReceived isInline=YES, calling playSoundVibrate...");
            [self playSoundVibrate:additionalData];
        }
        
        // send notification message
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
        
        self.coldstart = NO;
        self.notificationMessage = nil;
        isNotificationReceivedCalled = false;
    }
}

// Method to play sound & vibrate
- (void) addTimestamp: (NSMutableDictionary *)data {
    NSLog(@"[PushPlugin] addTimestamp called data = %@", data);
    if(data != NULL){
        NSDate *currentDate = [NSDate date];
        NSTimeInterval timeInSeconds = [currentDate timeIntervalSince1970];
        long long timestamp = (long long)(timeInSeconds * 1000);
        NSNumber *timestampNumber = [NSNumber numberWithLongLong:timestamp];
        NSLog(@"[PushPlugin] addTimestamp timestampNumber = %@", timestampNumber);
        [data setObject:timestampNumber forKey:@"timestamp"];
    }
}

// Method to play sound & vibrate
- (void) playSoundVibrate: (NSMutableDictionary *)additionalData {
    NSLog(@"[PushPlugin] playSoundVibrate called");
    //GET JSON DATA PAYLOAD(SYSTEM PREFS):
    NSString *jsonPayloadString = [additionalData objectForKey:@"jsonPayload"];
    NSData *jsonPayloadData = [jsonPayloadString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSMutableDictionary *jsonPayload = [NSJSONSerialization JSONObjectWithData:jsonPayloadData options:NSJSONReadingMutableContainers error:&error];
    if (error) {
        NSLog(@"[PushPlugin] Error parsing JSON: %@", error.localizedDescription);
    } else {
        //GET USER PREFS:
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSMutableDictionary *notificationPreferences = [defaults objectForKey:@"notificationPreferences"];
        NSLog(@"[PushPlugin] notificationReceived got saved notificationPreferences = %@", notificationPreferences);
        BOOL isUserConfigured = [notificationPreferences[@"is_user_configured"] boolValue];
        BOOL isDefaultSound = [notificationPreferences[@"is_sound"] boolValue];
        BOOL isDefaultVibration = [notificationPreferences[@"is_vibration"] boolValue];
        NSString *defaultSound = [notificationPreferences objectForKey:@"sound"];
        //GET SYSTEM(MESSAGE SENT) PREFERENCES
        NSLog(@"[PushPlugin] jsonPayload: %@", jsonPayload);
        NSString *sound = [jsonPayload objectForKey:@"sound"];
        NSLog(@"[PushPlugin] system or message sent sound is %@", sound);
        bool isVibrate = [[jsonPayload objectForKey:@"vibration"] boolValue];
        NSLog(@"[PushPlugin] system or message sent isVibrate is %d", isVibrate);
        //SET PREFERENCES TO BE PLAYED:
        BOOL playIsSound = isUserConfigured==YES? isDefaultSound:![sound isEqualToString:@"NONE"];
        NSString *playSound = isUserConfigured==YES? defaultSound:sound;
        BOOL playIsVibrate = isUserConfigured==YES? isDefaultVibration:isVibrate;
        //PLAY SOUND:
        if(playIsSound == YES){
            NSLog(@"[PushPlugin] notificationReceived PLAYING SOUND!");
            [self playCustomSound:playSound];
        }
        //VIBRATE:
        if (playIsVibrate == YES) {
            NSLog(@"[PushPlugin] notificationReceived VIBRATING!");
            [self triggerVibration];
        }else{
            NSLog(@"[PushPlugin] notificationReceived NOT VIBRATING!");
        }
    }
}

// Method to play custom sound
- (void)playCustomSound:(NSString *)soundFileName {
    NSLog(@"[PushPlugin] playCustomSound called, sound: %@", soundFileName);
    
    // Set audio session category
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *setCategoryError = nil;
    [session setCategory:AVAudioSessionCategoryAmbient error:&setCategoryError];
    if (setCategoryError) {
        NSLog(@"[PushPlugin] Error setting audio session category: %@", setCategoryError.localizedDescription);
    }
    
    NSError *activationError = nil;
    [session setActive:YES error:&activationError];
    if (activationError) {
        NSLog(@"[PushPlugin] Error activating audio session: %@", activationError.localizedDescription);
    }
    
    if(![soundFileName isEqualToString:@"default"] && ![soundFileName isEqualToString:@"ringtone"]){
        NSString * playResult = [self doPlaySound:soundFileName];
    }else{
        SystemSoundID soundID = 1007;
        if([soundFileName isEqualToString:@"ringtone"]){
            soundID = 1315;
        }
        AudioServicesPlaySystemSound(soundID);
        [NSTimer scheduledTimerWithTimeInterval:3.0
                                         target:self
                                       selector:@selector(stopSound)
                                       userInfo:nil
                                        repeats:NO];
    }
}

- (void)playDefaultNotification:(CDVInvokedUrlCommand *)command {
    AudioServicesPlaySystemSound(1007); // 1007 is the system sound ID for the default notification
    [NSTimer scheduledTimerWithTimeInterval:3.0
                                     target:self
                                   selector:@selector(stopSound)
                                   userInfo:nil
                                    repeats:NO];
    NSString* pluginResult = @"Played default notification sound successfully";
    [self successWithMessage:command.callbackId withMsg:pluginResult];
}

- (void)playDefaultRingtone:(CDVInvokedUrlCommand *)command {
    AudioServicesPlaySystemSound(1315); // 1315 is the system sound ID for the default ringtone
    [NSTimer scheduledTimerWithTimeInterval:3.0
                                     target:self
                                   selector:@selector(stopSound)
                                   userInfo:nil
                                    repeats:NO];
    NSString* pluginResult = @"Played default ringtone sound successfully";
    [self successWithMessage:command.callbackId withMsg:pluginResult];
}

- (void)playSoundFile: (CDVInvokedUrlCommand *)command {
    NSString* sound = [command.arguments objectAtIndex:0];
    NSString* pluginResult = [self doPlaySound:sound];
    [self successWithMessage:command.callbackId withMsg:pluginResult];
}

- (NSString* )doPlaySound: (NSString* )sound {
    NSString *path = [[NSBundle mainBundle] pathForResource:sound ofType:@"caf"];
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    NSError *error = nil;
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&error];
    if (error) {
        NSString* pluginResult = [NSString stringWithFormat:@"Error initializing player: %@", error.localizedDescription];
        return pluginResult;
    }else{
        [self.audioPlayer prepareToPlay];
        [self.audioPlayer play];
        self.playbackTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                              target:self
                                                            selector:@selector(stopAudio)
                                                            userInfo:nil
                                                             repeats:NO];
        return @"Successfully played sound";
    }
}


- (void)stopSound {
    // Playing system sound ID 4095, which is an empty (silent) sound
    AudioServicesPlaySystemSound(4095);
}

- (void)stopAudio {
    if ([self.audioPlayer isPlaying]) {
        [self.audioPlayer stop];
        NSLog(@"Audio stopped after timeout.");
    }
    // Invalidate the timer
    [self.playbackTimer invalidate];
    self.playbackTimer = nil;
}



// Method to trigger vibration
- (void)triggerVibration {
    NSLog(@"[PushPlugin] PushPlugin.triggerVibration called");
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)getSavedNotifications:(CDVInvokedUrlCommand*)command {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *savedNotifications = [defaults objectForKey:@"savedNotifications"];
    if(savedNotifications == NULL){
        savedNotifications = @[];
    }
    NSLog(@"[PushPlugin] getSavedNotifications savedNotifications = %@", savedNotifications);
    [defaults removeObjectForKey:@"savedNotifications"];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:savedNotifications];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)removeSavedNotifications:(CDVInvokedUrlCommand*)command {
    NSLog(@"[PushPlugin] PushPlugin.removeSavedNotifications called");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *savedNotifications = [defaults objectForKey:@"savedNotifications"];
    if(savedNotifications == NULL){
        savedNotifications = @[];
    }
    NSUInteger arrayLength = savedNotifications.count;
    NSLog(@"[PushPlugin] PushPlugin.removeSavedNotifications count = %lu", arrayLength);
    [defaults removeObjectForKey:@"savedNotifications"];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:savedNotifications];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// Method to set notification preferences
- (void)setNotificationPreferences:(CDVInvokedUrlCommand *)command {
    NSMutableDictionary *notificationPreferences = [command.arguments objectAtIndex:0];
    NSLog(@"[PushPlugin] setNotificationPreferences called, notificationPreferences = %@", notificationPreferences);
    // Store it in NSUserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:notificationPreferences forKey:@"notificationPreferences"];
    [defaults synchronize];
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Set notification preferences."];
    [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
}


- (void)clearNotification:(CDVInvokedUrlCommand *)command {
    NSNumber *notId = [command.arguments objectAtIndex:0];
    [[UNUserNotificationCenter currentNotificationCenter] getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
        /*
         * If the server generates a unique "notId" for every push notification, there should only be one match in these arrays, but if not, it will delete
         * all notifications with the same value for "notId"
         */
        NSPredicate *matchingNotificationPredicate = [NSPredicate predicateWithFormat:@"request.content.userInfo.notId == %@", notId];
        NSArray<UNNotification *> *matchingNotifications = [notifications filteredArrayUsingPredicate:matchingNotificationPredicate];
        NSMutableArray<NSString *> *matchingNotificationIdentifiers = [NSMutableArray array];
        for (UNNotification *notification in matchingNotifications) {
            [matchingNotificationIdentifiers addObject:notification.request.identifier];
        }
        [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:matchingNotificationIdentifiers];

        NSString *message = [NSString stringWithFormat:@"Cleared notification with ID: %@", notId];
        CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
        [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
    }];
}

- (void)setApplicationIconBadgeNumber:(CDVInvokedUrlCommand *)command {
    NSMutableDictionary* options = [command.arguments objectAtIndex:0];
    int badge = [[options objectForKey:@"badge"] intValue] ?: 0;

    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:badge];

    NSString* message = [NSString stringWithFormat:@"app badge count set to %d", badge];
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
    [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
}

- (void)getApplicationIconBadgeNumber:(CDVInvokedUrlCommand *)command {
    NSInteger badge = [UIApplication sharedApplication].applicationIconBadgeNumber;

    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:(int)badge];
    [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
}

- (void)clearAllNotifications:(CDVInvokedUrlCommand *)command {
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

    NSString* message = [NSString stringWithFormat:@"cleared all notifications"];
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
    [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
}

- (void)hasPermission:(CDVInvokedUrlCommand *)command {
    id<UIApplicationDelegate> appDelegate = [UIApplication sharedApplication].delegate;
    if ([appDelegate respondsToSelector:@selector(checkUserHasRemoteNotificationsEnabledWithCompletionHandler:)]) {
        [appDelegate performSelector:@selector(checkUserHasRemoteNotificationsEnabledWithCompletionHandler:) withObject:^(BOOL isEnabled) {
            NSMutableDictionary* message = [NSMutableDictionary dictionaryWithCapacity:1];
            [message setObject:[NSNumber numberWithBool:isEnabled] forKey:@"isEnabled"];
            CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
            [self.commandDelegate sendPluginResult:commandResult callbackId:command.callbackId];
        }];
    }
}

- (void)successWithMessage:(NSString *)myCallbackId withMsg:(NSString *)message {
    if (myCallbackId != nil)
    {
        CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];
        [self.commandDelegate sendPluginResult:commandResult callbackId:myCallbackId];
    }
}

- (void)registerWithToken:(NSString *)token {
    // Send result to trigger 'registration' event but keep callback
    NSMutableDictionary* message = [NSMutableDictionary dictionaryWithCapacity:2];
    [message setObject:token forKey:@"registrationId"];
    if ([self usesFCM]) {
        [message setObject:@"FCM" forKey:@"registrationType"];
    } else {
        [message setObject:@"APNS" forKey:@"registrationType"];
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:message];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

- (void)failWithMessage:(NSString *)myCallbackId withMsg:(NSString *)message withError:(NSError *)error {
    NSString        *errorMessage = (error) ? [NSString stringWithFormat:@"%@ - %@", message, [error localizedDescription]] : message;
    CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];

    [self.commandDelegate sendPluginResult:commandResult callbackId:myCallbackId];
}

- (void) finish:(CDVInvokedUrlCommand *)command {
    NSLog(@"[PushPlugin] finish called");

    [self.commandDelegate runInBackground:^ {
        NSString* notId = [command.arguments objectAtIndex:0];

        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.1
                                             target:self
                                           selector:@selector(stopBackgroundTask:)
                                           userInfo:notId
                                            repeats:NO];
        });

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)stopBackgroundTask:(NSTimer *)timer {
    UIApplication *app = [UIApplication sharedApplication];

    NSLog(@"[PushPlugin] stopBackgroundTask called");

    if (handlerObj) {
        NSLog(@"[PushPlugin] handlerObj");
        completionHandler = [handlerObj[[timer userInfo]] copy];
        if (completionHandler) {
            NSLog(@"Push Plugin: stopBackgroundTask (remaining t: %f)", app.backgroundTimeRemaining);
            completionHandler(UIBackgroundFetchResultNewData);
            completionHandler = nil;
        }
    }
}


- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(NSString *)type {
    if([credentials.token length] == 0) {
        NSLog(@"[PushPlugin] VoIP register error - No device token:");
        return;
    }

    NSLog(@"[PushPlugin] VoIP register success");
    const unsigned *tokenBytes = [credentials.token bytes];
    NSString *sToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                        ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                        ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                        ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];

    [self registerWithToken:sToken];
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(NSString *)type {
    NSLog(@"[PushPlugin] pushRegistry:didReceiveIncomingPushWithPayload VoIP Notification received");
    self.notificationMessage = payload.dictionaryPayload;
    [self notificationReceived];
}

- (void)handleNotificationSettings:(NSNotification *)notification {
    [self handleNotificationSettingsWithAuthorizationOptions:nil];
}

- (void)handleNotificationSettingsWithAuthorizationOptions:(NSNumber *)authorizationOptionsObject {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions authorizationOptions = [authorizationOptionsObject unsignedIntegerValue];

    __weak UNUserNotificationCenter *weakCenter = center;
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {

        switch (settings.authorizationStatus) {
            case UNAuthorizationStatusNotDetermined:
            {
                [weakCenter requestAuthorizationWithOptions:authorizationOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
                    if (granted) {
                        [self performSelectorOnMainThread:@selector(registerForRemoteNotifications)
                                               withObject:nil
                                            waitUntilDone:NO];
                    }
                }];
                break;
            }
            case UNAuthorizationStatusAuthorized:
            {
                [self performSelectorOnMainThread:@selector(registerForRemoteNotifications)
                                       withObject:nil
                                    waitUntilDone:NO];
                break;
            }
            case UNAuthorizationStatusDenied:
            default:
                break;
        }
    }];
}

- (void)registerForRemoteNotifications {
    [[UIApplication sharedApplication] registerForRemoteNotifications];
}

@end
