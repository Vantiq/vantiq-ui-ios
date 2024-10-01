//
//  VantiqUI.m
//  Pods-vantiq-ui-ios_Example
//
//  Created by Swan on 9/12/24.
//

#import <Foundation/Foundation.h>
#import "VantiqUI.h"
#import "JWT.h"
#include "KeychainItemWrapper.h"

@interface VantiqUI() {
    NSString *oAuthName;
    int tokenExpiration;
    NSString *idToken;
    NSURLProtectionSpace *protSpace;
    NSString *protSpaceUser;
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
        
        // construct a synthetic URL with which to store login credentials
        NSURL *url = [NSURL URLWithString:serverURL];
        protSpace = [[NSURLProtectionSpace alloc] initWithHost:url.host
            port:[url.port integerValue] protocol:url.scheme
            realm:nil authenticationMethod:NSURLAuthenticationMethodHTTPDigest];
    }
    return self;
}

- (void)serverType:(void (^)(BOOL isInternal, NSString *errorStr))handler {
    [_v authenticate:@"" password:@"" completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
        NSString *errorStr = error ? [error localizedDescription] : @"";
        if (response) {
            NSDictionary *headerFields = response.allHeaderFields;
            NSString *OAuthURL = [headerFields objectForKey:@"Www-Authenticate"];
            if (OAuthURL) {
                handler([OAuthURL isEqualToString:@"Vantiq"], errorStr);
            } else {
                handler(false, errorStr);
            }
        } else {
            handler(false, errorStr);
        }
    }];
}

- (void)verifyAuthToken:(NSString *)username completionHandler:(void (^)(BOOL isValid, NSString *errorStr))handler {
    _username = username;
    NSDictionary *credentials = [self retrieveCredentials];
    if (credentials) {
        _v.accessToken = [credentials objectForKey:@"accessToken"];
        NSString *idToken = [credentials objectForKey:@"idToken"];
        if (idToken.length) {
            // if there's an ID token, this is OAuth so preemptively refresh the access token if necessary
            OIDAuthState *authState = [self retrieveAuthState];
            if (authState) {
                [authState performActionWithFreshTokens:^(NSString *_Nonnull accessToken,
                    NSString *_Nonnull idToken, NSError *_Nullable error) {
                    if (!error) {
                        [self storeCredentials:accessToken idToken:idToken];
                        [self refreshedVerifyAuthToken:accessToken username:username completionHandler:handler];
                    } else {
                        NSLog(@"performActionWithFreshTokens: %@", [error localizedDescription]);
                        [self refreshedVerifyAuthToken:self->_v.accessToken username:username completionHandler:handler];
                    }
                }];
            } else {
                [self refreshedVerifyAuthToken:_v.accessToken username:username completionHandler:handler];
            }
        } else {
            [self refreshedVerifyAuthToken:_v.accessToken username:username completionHandler:handler];
        }
    } else {
        handler(false, @"");
    }
}
    
- (void)refreshedVerifyAuthToken:(NSString *)authToken username:(NSString *)username completionHandler:(void (^)(BOOL isValid, NSString *errorStr))handler {
    [_v verify:authToken username:username completionHandler:^(NSArray *data, NSHTTPURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            NSString *resultStr = @"";
            handler(![self formError:response error:error resultStr:&resultStr], resultStr);
        });
    }];
}

- (void)authWithOAuth:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSString *errorStr))handler {
    NSString *issuerURL = [[NSString stringWithString:_serverURL] lowercaseString];
    NSURL *url = [NSURL URLWithString:issuerURL];
    issuerURL = [NSString stringWithFormat:@"%@/auth/realms/%@", issuerURL, url.host];
    NSURL *issuer = [NSURL URLWithString:issuerURL];
    
    [OIDAuthorizationService discoverServiceConfigurationForIssuer:issuer
        completion:^(OIDServiceConfiguration *_Nullable configuration, NSError *_Nullable error) {
        NSString *errorStr = error ? [error localizedDescription] : @"";
        if (configuration) {
            // build authentication request
            NSString *redirectStr = [NSString stringWithFormat:@"%@:/callback", urlScheme];
            NSURL *redirectURL = [NSURL URLWithString:redirectStr];
            OIDAuthorizationRequest *request = [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration
                clientId:clientId scopes:@[OIDScopeOpenID, OIDScopeProfile]
                redirectURL:redirectURL responseType:OIDResponseTypeCode additionalParameters:nil];
            
            // perform authentication request
            UIViewController *rootViewController = UIApplication.sharedApplication.delegate.window.rootViewController;
            VantiqUIcurrentAuthorizationFlow = [OIDAuthState authStateByPresentingAuthorizationRequest:request
                presentingViewController:rootViewController
                callback:^(OIDAuthState *_Nullable authState, NSError *_Nullable error) {
                NSString *errorStr = error ? [error localizedDescription] : @"";
                if (authState) {
                    [self decodeJWT:authState.lastTokenResponse.idToken];
                    
                    // store the credentials securely
                    [self storeCredentials:authState.lastTokenResponse.accessToken idToken:authState.lastTokenResponse.idToken];
                    // persist the returned state
                    [self storeAuthState:authState];
                    handler(errorStr);
                } else {
                    NSLog(@"Authorization error: %@", errorStr);
                    handler(errorStr);
                }
            }];
        } else {
            NSLog(@"Error retrieving discovery document: %@", errorStr);
            handler(errorStr);
        }
    }];
}

- (void)storeAuthState:(OIDAuthState *)authState {
    NSError *errRet;
    NSData *authStateData = [NSKeyedArchiver archivedDataWithRootObject:authState
        requiringSecureCoding:NO error:&errRet];
    KeychainItemWrapper *keychainItem =
        [[KeychainItemWrapper alloc] initWithIdentifier:@"com.vantiq.uiios.authstate" accessGroup:nil];
    [keychainItem setObject:authStateData forKey:(id)kSecAttrAccount];
}
- (OIDAuthState *)retrieveAuthState {
    NSError *errRet;
    KeychainItemWrapper *keychainItem =
        [[KeychainItemWrapper alloc] initWithIdentifier:@"com.vantiq.uiios.authstate" accessGroup:nil];
    NSData *data = [keychainItem objectForKey:(id)kSecAttrAccount];
    OIDAuthState *authState = [NSKeyedUnarchiver unarchivedObjectOfClass:[OIDAuthState class]
        fromData:data error:&errRet];
    return authState;
}

- (void)authState:(OIDAuthState *)state didEncounterAuthorizationError:(NSError *)error {
    NSLog(@"didEncounterAuthorizationError: %@", [error localizedDescription]);
}

- (void)authWithInternal:(NSString *)username password:(NSString *)password completionHandler:(void (^)(NSString *errorStr))handler {
    _username = username;
    [_v authenticate:username password:password completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
        NSString *resultStr = @"";
        [self formError:response error:error resultStr:&resultStr];
        if (!resultStr.length) {
            // store the credentials securely
            NSString *saveAccessToken = [NSString stringWithString:self->_v.accessToken];
            self->_v.accessToken = @"";
            [self storeCredentials:saveAccessToken idToken:@""];
            self->_v.accessToken = saveAccessToken;
        }
        handler(resultStr);
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

/*
 *  storeCredentials, retrieveCredentials, areCredentialsPresent
 *      - helpers to securely store authentication credentials, both OAuth and username/password
 */
- (void)storeCredentials:(NSString *)accessToken idToken:(NSString *)idToken {
    BOOL credentialsChanged = NO;
    if (![accessToken isEqualToString:_v.accessToken]) {
        _v.accessToken = accessToken;
        credentialsChanged = YES;
    }
    if (![idToken isEqualToString:idToken]) {
        idToken = idToken;
        credentialsChanged = YES;
    }
    if (credentialsChanged) {
        NSDictionary *credentialsDict = [NSDictionary dictionaryWithObjectsAndKeys:_v.accessToken,
            @"accessToken", idToken, @"idToken", nil];
        NSURLCredential *credential = [NSURLCredential credentialWithUser:_username password:[self dictionaryToJSONString:credentialsDict] persistence:NSURLCredentialPersistencePermanent];
        [[NSURLCredentialStorage sharedCredentialStorage] setCredential:credential forProtectionSpace:protSpace];
    }
}

- (NSDictionary *)retrieveCredentials {
    NSDictionary *credentials = [[NSURLCredentialStorage sharedCredentialStorage] credentialsForProtectionSpace:protSpace];
    if (credentials) {
        NSURL *credential = [credentials objectForKey:_username];
        if (credential) {
            return [self JSONStringToDictionary:credential.password];
        }
    }
    return nil;
}

- (BOOL)areCredentialsPresent {
    NSDictionary *credentials = [self retrieveCredentials];
    return credentials != nil;
}

/*
 *  dictionaryToJSONString()
 *      - given an NSDictionary, convert it to a string which is used to transmit via the SDK
 */
- (NSString *)dictionaryToJSONString:(NSDictionary *)dict {
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
- (NSDictionary *)JSONStringToDictionary:(NSString *)jsonString {
    NSError *error;
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
    if (jsonData) {
        return [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    }
    return nil;
}

/*
 *  formError
 *      - helper to create an error string based on network usage
 */
- (BOOL)formError:(NSHTTPURLResponse *)response error:(NSError *)error resultStr:(NSString **)resultStr {
    if (error) {
        *resultStr = [error localizedDescription];
        return YES;
    } else if ((response.statusCode < 200) || (response.statusCode > 299)) {
        *resultStr = [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode];
        return YES;
    }
    return NO;
}
@end
