//
//  LastActive.h
//  Vantiq-ios
//
//  Created by Swan on 5/22/17.
//  Copyright © 2017 Vantiq, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LastActive : NSObject
+ (LastActive *)sharedInstance;
- (void)enterForeground;
- (void)enterBackground;
- (NSDate *)lastActiveTime;
@end
