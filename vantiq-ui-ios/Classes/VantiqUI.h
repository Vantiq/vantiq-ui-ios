//
//  VantiqUI.h
//  Pods
//
//  Created by Swan on 9/12/24.
//

#ifndef VantiqUI_h
#define VantiqUI_h
#import "Vantiq.h"
#import "AppAuth.h"

extern id<OIDExternalUserAgentSession> VantiqUIcurrentAuthorizationFlow;

@interface VantiqUI : NSObject
@property (readonly, nonatomic) Vantiq *v;
@property (readonly, nonatomic) NSString *username;

- (id)init:(NSString *)serverURL;
- (void)serverType:(void (^)(BOOL isInternal, NSString *errorStr))handler;
- (void)verifyAuthToken:(NSString *)username completionHandler:(void (^)(BOOL isValid, NSString *errorStr))handler;
- (void)authWithOAuth:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSString *errorStr))handler;
- (void)authWithInternal:(NSString *)username password:(NSString *)password completionHandler:(void (^)(NSString *errorStr))handler;

- (BOOL)formError:(NSHTTPURLResponse *)response error:(NSError *)error resultStr:(NSString **)resultStr;
@end
#endif /* VantiqUI_h */
