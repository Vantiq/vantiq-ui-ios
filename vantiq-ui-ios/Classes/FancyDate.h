//
//  FancyDate.h
//  FeedFriendly
//
//  Created by Michael Swan on 3/15/11.
//  Copyright 2011 FeedFriendly, LLC. All rights reserved.
//  Permission given to Vantiq, Inc for use.
//

#import <Foundation/Foundation.h>


@interface FancyDate : NSObject

+ (NSString *)generateISODate;
+ (NSString *)generateFancyDate:(CFAbsoluteTime)absTime shortDate:(BOOL)shortDate;

@end
