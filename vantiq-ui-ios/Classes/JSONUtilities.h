//
//  JSONUtilities.h
//  Vantiq-ios
//
//  Created by Swan on 1/27/17.
//  Copyright © 2017 Vantiq, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface JSONUtilities : NSObject
+ (NSString *)dictionaryToJSONString:(NSDictionary *)dict;
+ (NSDictionary *)JSONStringToDictionary:(NSString *)jsonString;
@end
