//
//  FancyDate.m
//  FeedFriendly
//
//  Created by Michael Swan on 3/15/11.
//  Copyright 2011 FeedFriendly, LLC. All rights reserved.
//  Permission given to Vantiq, Inc for use.
//

#import "FancyDate.h"


@implementation FancyDate

/*
 *  generateISODate
 */
+ (NSString *)generateISODate {
    NSString *dateString = [[NSDate date] description];
    // format the iOS-produced current date/time string to an alternate format
    dateString = [dateString stringByReplacingOccurrencesOfString:@" +" withString:@"+"];
    dateString = [dateString stringByReplacingOccurrencesOfString:@" " withString:@"T"];
    return dateString;
}

/*
 *    generateFancyDate
 *        - given a timestamp, generate a string that gives a human-
 *            readable version of the difference between the current
 *            time and the timestamp
 */
+ (NSString *)generateFancyDate:(CFAbsoluteTime)absTime shortDate:(BOOL)shortDate {
    NSString*    theDateStr;
    
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *now = [NSDate date];
    NSDate *ts = [NSDate dateWithTimeIntervalSince1970:absTime];
    NSDateComponents *units = [cal components:(NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute)
                                     fromDate:ts toDate:now options:0];
    
    if (shortDate) {
        if (units.day > 0) {
            // if we have a number of days, use days
            if (units.day == 1)
                theDateStr = NSLocalizedString(@"com.vantiq.vantiq.OneDay", @"");
            else
                theDateStr = [NSString stringWithFormat:NSLocalizedString(@"com.vantiq.vantiq.MoreDays", @""), units.day];
        } else if (units.hour > 0) {
            if (units.hour == 1)
                theDateStr = NSLocalizedString(@"com.vantiq.vantiq.OneHour", @"");
            else
                theDateStr = [NSString stringWithFormat:NSLocalizedString(@"com.vantiq.vantiq.MoreHours", @""), units.hour];
        } else if (units.minute == 1)
            theDateStr = NSLocalizedString(@"com.vantiq.vantiq.OneMinute", @"");
        else
            theDateStr = [NSString stringWithFormat:NSLocalizedString(@"com.vantiq.vantiq.MoreMinutes", @""), units.minute];
    } else {
        NSDateFormatter *dateFormatter;
        if (units.day > 0) {
            dateFormatter = [[NSDateFormatter alloc] init];
            NSString *language = [[NSLocale preferredLanguages] objectAtIndex:0];
            if (!language)
                language = @"en_US_POSIX";
            [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:language]];
        }
        if (units.day > 5) {
            // if the time interval is greater than five days, use date format
            [dateFormatter setDateFormat:@"MMM d, h:mm aaa"];
            theDateStr = [dateFormatter stringFromDate:ts];
        } else if (units.day > 0) {
            // if the time interval is greater than a day, just use a day/time format
            [dateFormatter setDateFormat:@"EEE h:mm aaa"];
            theDateStr = [dateFormatter stringFromDate:ts];
        } else if (units.hour > 0) {
            // if the time interval is more than one hour, just display differential hours
            NSInteger hours = units.hour;
            if (units.minute > 50) hours++;
            if (units.hour == 1) {
                theDateStr = NSLocalizedString(@"com.vantiq.vantiq.OneHourAgo", @"");
            } else {
                theDateStr = [NSString stringWithFormat:NSLocalizedString(@"com.vantiq.vantiq.MoreHoursAgo", @""), hours];
            }
        } else {
            // since the time interval is less than an hour, just display differential hours
            if (units.minute == 1) {
                theDateStr = NSLocalizedString(@"com.vantiq.vantiq.OneMinuteAgo", @"");
            } else {
                theDateStr = [NSString stringWithFormat:NSLocalizedString(@"com.vantiq.vantiq.MoreMinutesAgo", @""), units.minute];
            }
        }
    }
    return theDateStr;
}

@end

