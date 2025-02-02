//
//  VANTIQUIAppDelegate.h
//  vantiq-ui-ios
//
//  Created by Michael Swan on 09/13/2024.
//  Copyright (c) 2024 Michael Swan. All rights reserved.
//

@import UIKit;
#import "VantiqUI.h"
#import "AppAuth.h"

@interface VANTIQUIAppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow * _Nonnull window;
@property (readonly, nonatomic, nullable) NSString *APNSDeviceToken;
@property (nonatomic, nullable) VantiqUI *vui;
@end
