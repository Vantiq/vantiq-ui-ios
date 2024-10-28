//
//  VANTIQUIAppDelegate.m
//  vantiq-ui-ios
//
//  Created by Michael Swan on 09/13/2024.
//  Copyright (c) 2024 Michael Swan. All rights reserved.
//

#import "VANTIQUIAppDelegate.h"
#import <UserNotifications/UserNotifications.h>
#import "../../vantiq-ui-ios/Classes/LastActive.h"

@interface VANTIQUIAppDelegate () {}
@property (readwrite, nonatomic) NSString *APNSDeviceToken;
@end

@implementation VANTIQUIAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    _vui = nil;
    
    // allow the user to select which type of notifications to receive, if any
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = (id<UNUserNotificationCenterDelegate>)self;
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionBadge)
        completionHandler:^(BOOL granted, NSError * _Nullable error){
        if (error) {
            NSLog(@"Error in registering for notifications: %@", [error localizedDescription]);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^ {
                // register for an APNS token
                [[UIApplication sharedApplication] registerForRemoteNotifications];
            });
        };
    }];
    
    // Override point for customization after application launch.
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString *, id> *)options {
  // Sends the URL to the current authorization flow (if any) which will
  // process it if it relates to an authorization response.
  if ([VantiqUIcurrentAuthorizationFlow resumeExternalUserAgentFlowWithURL:url]) {
      VantiqUIcurrentAuthorizationFlow = nil;
      return YES;
  }
  // Your additional URL handling (if any) goes here.
  return NO;
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    // remember token for use in registering it with the Vantiq server
    _APNSDeviceToken = [VantiqUI convertAPNSToken:deviceToken];
    NSLog(@"APNSDeviceToken = %@", _APNSDeviceToken);
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(nonnull NSError *)error {
    NSLog(@"Failed to receive token: %@", [error localizedDescription]);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(nonnull NSDictionary *)userInfo
    fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))fetchCompletionHandler {
    NSLog(@"didReceiveRemoteNotification: userInfo (state = %ld) = %@", application.applicationState, userInfo);
    if (_vui) {
        [_vui processPushNotification:userInfo completionHandler:^(BOOL notificationHandled) {
            if (notificationHandled) {
                NSLog(@"didReceiveRemoteNotification: calling completion handler.");
                fetchCompletionHandler(UIBackgroundFetchResultNewData);;
            } else {
                // this notification must be handled (or not) by the app
                id notifyData = [userInfo objectForKey:@"data"];
                if (notifyData) {
                    NSString *dataType = [notifyData objectForKey:@"type"];
                    NSLog(@"didReceiveRemoteNotification: unhandled notification type = '%@'.", dataType);
                }
                fetchCompletionHandler(UIBackgroundFetchResultNewData);
            }
        }];
    } else {
        // user hasn't logged in so nothing to do yet
        fetchCompletionHandler(UIBackgroundFetchResultNoData);
    }
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))fetchCompletionHandler {
    if (_vui) {
        // do our background tasks and call the completion handler when we're finished
        [_vui doBFTasksWithCompletionHandler:NO completionHandler:^(BOOL notificationHandled) {
            fetchCompletionHandler(UIBackgroundFetchResultNewData);
        }];
    }
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [[LastActive sharedInstance] enterBackground];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    [[LastActive sharedInstance] enterForeground];
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
