//
//  VantiqUI.h
//  Pods
//
//  Created by Swan on 9/12/24.
//

#ifndef VantiqUI_h
#define VantiqUI_h

extern id<OIDExternalUserAgentSession> VantiqUIcurrentAuthorizationFlow;

@interface VantiqUI : NSObject
@property (readonly, nonatomic) Vantiq *v;
@property (readonly, nonatomic) NSString *username;

- (id)init:(NSString *)serverURL;
- (void)serverType:(void (^)(BOOL isInternal, NSError *error))handler;
- (void)verifyAuthToken:(NSString *)authToken username:(NSString *)username completionHandler:(void (^)(BOOL isValid, NSError *error))handler;
- (void)authWithOAuth:(NSString *)namespace urlScheme:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSString* authToken, NSError *error))handler;
@end
#endif /* VantiqUI_h */
