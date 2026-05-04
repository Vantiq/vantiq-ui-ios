//
//  LocationUtilities.m
//  Vantiq-ios
//
//  Created by Swan on 8/23/19.
//  Copyright © 2019 Vantiq, Inc. All rights reserved.
//

#import "LocationUtilities.h"

@implementation LocationUtilities

/*
 *  assembleDictionary
 *      - given a CLLocation object, assemble a dictionary of various interesting GPS data
 */
+ (NSDictionary *)assembleDictionary:(CLLocation *)location {
    CLLocationCoordinate2D c2d = location.coordinate;
    CLLocationDegrees lat = c2d.latitude;
    CLLocationDegrees lon = c2d.longitude;
    NSMutableDictionary *locationDict = [NSMutableDictionary new];
    [locationDict setObject:@(lat) forKey:@"latitude"];
    [locationDict setObject:@(lon) forKey:@"longitude"];
    [LocationUtilities addExtras:location toDictionary:locationDict];
    return locationDict;
}

+ (void)addExtras:(CLLocation *)location toDictionary:(NSMutableDictionary *)locationDict {
    [locationDict setObject:@(location.altitude) forKey:@"altitudeMeters"];
    [locationDict setObject:@(location.horizontalAccuracy) forKey:@"horizontalAccuracyMeters"];
    [locationDict setObject:@(location.verticalAccuracy) forKey:@"verticalAccuracyMeters"];
    [locationDict setObject:@(location.speed) forKey:@"speedMetersPerSecond"];
    [locationDict setObject:@(location.course) forKey:@"bearingDegrees"];
    if (location.floor) {
        [locationDict setObject:@(location.floor.level) forKey:@"floor"];
    }
}
@end
