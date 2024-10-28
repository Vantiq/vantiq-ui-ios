//
//  LastActive.m
//  Vantiq-ios
//
//  Created by Swan on 5/22/17.
//  Copyright © 2017 Vantiq, Inc. All rights reserved.
//

#import "LastActive.h"
#import <CoreMotion/CoreMotion.h>
#import "FancyDate.h"

@interface LastActive() {
    CMPedometer *ped;
    CFAbsoluteTime lastForegroundTime;
    CFAbsoluteTime lastBackgroundTime;
}
@end

static LastActive *_sharedLastActive = nil;

@implementation LastActive
+ (LastActive *)sharedInstance {
    @synchronized (self) {
        if (_sharedLastActive == nil) {
            _sharedLastActive = [LastActive new];
        }
    }
    return _sharedLastActive;
}

- (id)init {
    if (self = [super init]) {
        ped = nil;
    }
    return self;
}

- (void)enterForeground {
    lastForegroundTime = CFAbsoluteTimeGetCurrent();
    
}

- (void)enterBackground {
    lastBackgroundTime = CFAbsoluteTimeGetCurrent();
}

#define secondsBetweenReadings  900

/*
 *  lastActiveTime()
 *      - called when we're uploading a location waypoint and we need to upload a timestamp
 *          of when we consider the device to be 'last active'
 *      - if available, we'll use the pedometer step count by iterating back in time until
 *          we find a non-zero step count, otherwise we'll use either the last app foreground
 *          or background transition
 */
- (NSDate *)lastActiveTime {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime lastActiveTime = now;
    if (!ped && [CMPedometer isStepCountingAvailable]) {
        NSLog(@"getting new CMPedometer instance");
        ped = [CMPedometer new];
    }
    if (ped) {
        // the device supports step counting so let's use it to determine device activity
        CFAbsoluteTime endTime = now;
        CFAbsoluteTime startTime;
        __block BOOL foundSteps = false;
        __block NSDate *stepsDate;
        __block BOOL stepsError = false;
        
        // starting with now, iterate backwards through time looking for a fifteen-minute interval that
        // contains steps and, if so, use that interval as the last active time or unless the user has
        // foregrounded or backgrounded the app
        while (!stepsError && (endTime > lastBackgroundTime) &&
            (endTime > lastForegroundTime) && (endTime > (now - 604800))) {
            startTime = endTime - secondsBetweenReadings;
            [ped queryPedometerDataFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:startTime]
                toDate:[NSDate dateWithTimeIntervalSinceReferenceDate:endTime]
                withHandler:^(CMPedometerData * _Nullable pedometerData, NSError * _Nullable error) {
                if (error) {
                    NSLog(@"error on queryPedometerDataFromDate = %@", [error description]);
                    stepsError = true;
                }
                if ([pedometerData.numberOfSteps intValue] > 0) {
                    if (!foundSteps) {
                        foundSteps = true;
                        stepsDate = pedometerData.endDate;
                    }
                }
            }];
            if (foundSteps) {
                return stepsDate;
            }
            endTime = startTime;
        }
    }
    // we didn't find step counts so rely on the app's foreground and background times
    if (lastForegroundTime < lastBackgroundTime) {
        // we're in the background so use the last background time
        lastActiveTime = lastBackgroundTime;
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:lastActiveTime];
}

@end
