//
//  VantiqUI.m
//  Pods-vantiq-ui-ios_Example
//
//  Created by Swan on 9/12/24.
//

#import <Foundation/Foundation.h>
#import "VantiqUI.h"
#import "AppAuth.h"
#import "JWT.h"

@interface VantiqUI() {
    NSString *oAuthName;
    int tokenExpiration;
    NSString *idToken;
}
@property (readwrite, nonatomic) NSString *username;
@property (readwrite, nonatomic) Vantiq *v;
@property (readwrite, nonatomic) NSString *serverURL;
@end

@implementation VantiqUI
id<OIDExternalUserAgentSession> VantiqUIcurrentAuthorizationFlow;

- (id)init:(NSString *)serverURL {
    if (self = [super init]) {
        _serverURL = serverURL;
        _v = [[Vantiq alloc] initWithServer:serverURL];
    }
    return self;
}
- (void)serverType:(void (^)(BOOL isInternal, NSError *error))handler {
    [_v authenticate:@"" password:@"" completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
        if (response) {
            NSDictionary *headerFields = response.allHeaderFields;
            NSString *OAuthURL = [headerFields objectForKey:@"Www-Authenticate"];
            if (OAuthURL) {
                handler([OAuthURL isEqualToString:@"Vantiq"], error);
            } else {
                handler(false, error);
            }
        } else {
            handler(false, error);
        }
    }];
}

- (void)verifyAuthToken:(NSString *)authToken username:(NSString *)username completionHandler:(void (^)(BOOL isValid, NSError *error))handler {
    [_v verify:authToken username:username completionHandler:^(NSArray *data, NSHTTPURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            handler(!error, error);
        });
    }];
}

- (void)authWithOAuth:(NSString *)namespace urlScheme:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSString* authToken, NSError *error))handler {
    NSString *issuerURL = [[NSString stringWithString:_serverURL] lowercaseString];
    NSURL *url = [NSURL URLWithString:issuerURL];
    issuerURL = [NSString stringWithFormat:@"%@/auth/realms/%@", issuerURL, url.host];
    NSURL *issuer = [NSURL URLWithString:issuerURL];
    
    [OIDAuthorizationService discoverServiceConfigurationForIssuer:issuer
        completion:^(OIDServiceConfiguration *_Nullable configuration, NSError *_Nullable error) {
        if (configuration) {
            // build authentication request
            NSString *redirectStr = [NSString stringWithFormat:@"%@:/callback", urlScheme];
            NSURL *redirectURL = [NSURL URLWithString:redirectStr];
            OIDAuthorizationRequest *request = [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration
                clientId:clientId scopes:@[OIDScopeOpenID, OIDScopeProfile]
                redirectURL:redirectURL responseType:OIDResponseTypeCode additionalParameters:nil];
            
            // performs authentication request
            UIViewController *rootViewController = UIApplication.sharedApplication.delegate.window.rootViewController;
            VantiqUIcurrentAuthorizationFlow = [OIDAuthState authStateByPresentingAuthorizationRequest:request
                presentingViewController:rootViewController
                callback:^(OIDAuthState *_Nullable authState, NSError *_Nullable error) {
                if (authState) {
                    NSLog(@"Got authorization tokens. Access token: %@", authState.lastTokenResponse.accessToken);
                    [self decodeJWT:authState.lastTokenResponse.idToken];
                    self->_v.accessToken = authState.lastTokenResponse.accessToken;
                    self->idToken = authState.lastTokenResponse.idToken;
                    handler(self->_v.accessToken, nil);
                } else {
                    NSLog(@"Authorization error: %@", [error localizedDescription]);
                    handler(nil, error);
                }
            }];
        } else {
            NSLog(@"Error retrieving discovery document: %@", [error localizedDescription]);
            handler(nil, error);
        }
    }];
}

- (void)decodeJWT:(NSString *)jwt {
    JWTBuilder *decodeBuilder = [JWTBuilder decodeMessage:jwt];
    if (decodeBuilder) {
        NSDictionary *envelopedPayload = decodeBuilder.options(@1).decode;
        NSDictionary *payload = [envelopedPayload objectForKey:@"payload"];
        if (payload) {
            oAuthName = [payload objectForKey:@"preferred_username"];
            _username = [payload objectForKey:@"sub"];
            tokenExpiration = [[payload objectForKey:@"exp"] intValue];
            NSDate *exp = [NSDate dateWithTimeIntervalSince1970:tokenExpiration - 480];
            NSString *dateString = [NSDateFormatter localizedStringFromDate:exp
                dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterFullStyle];
            NSLog(@"token expiration = %@ (server = %@)", dateString, [payload objectForKey:@"iss"]);
        }
    }
}
@end


