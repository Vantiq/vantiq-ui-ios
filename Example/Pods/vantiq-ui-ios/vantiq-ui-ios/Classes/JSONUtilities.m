//
//  JSONUtilities.m
//  Vantiq-ios
//
//  Created by Swan on 1/27/17.
//  Copyright © 2017 Vantiq, Inc. All rights reserved.
//

#import "JSONUtilities.h"

@implementation JSONUtilities
/*
 *  dictionaryToJSONString()
 *      - given an NSDictionary, convert it to a string which is used to transmit via the SDK
 */
+ (NSString *)dictionaryToJSONString:(NSDictionary *)dict {
    NSError* error;
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
    if (jsonData) {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    return nil;
}

/*
 *  JSONStringToDictionary
 *      - helper to convert string-encoded JSON into an NSDictionary
 *      - necessary since all the parameters for the Client WebView come in as strings
 */
+ (NSDictionary *)JSONStringToDictionary:(NSString *)jsonString {
    NSError *error;
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    if (jsonData) {
        return [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    }
    return nil;
}
@end
