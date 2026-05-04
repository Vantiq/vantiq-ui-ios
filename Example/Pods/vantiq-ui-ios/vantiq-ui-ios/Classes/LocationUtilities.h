//
//  LocationUtilities.h
//  Vantiq-ios
//
//  Created by Swan on 8/23/19.
//  Copyright © 2019 Vantiq, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LocationUtilities : NSObject
+ (NSDictionary *)assembleDictionary:(CLLocation *)location;
+ (void)addExtras:(CLLocation *)location toDictionary:(NSMutableDictionary *)locationDict;
@end

NS_ASSUME_NONNULL_END
