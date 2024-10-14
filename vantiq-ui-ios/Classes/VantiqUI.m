//
//  VantiqUI.m
//
//  Created by Swan on 9/12/24.
//

#import <Foundation/Foundation.h>
#import "VantiqUI.h"
#import "JWT.h"
#include "KeychainItemWrapper.h"

@interface VantiqUI() {
    int tokenExpiration;
    NSString *internalPassword;
    NSURLProtectionSpace *protSpace;
    NSString *protSpaceUser;
    NSString *authValid;
    NSString *namespace;
    
}
@property (readwrite, nonatomic) NSString *username;
@property (readwrite, nonatomic) Vantiq *v;
@property (readwrite, nonatomic) NSString *serverURL;
@property (readwrite, nonatomic) NSString *preferredUsername;
@property (readwrite, nonatomic) NSString *serverType;
@end

@implementation VantiqUI
id<OIDExternalUserAgentSession> VantiqUIcurrentAuthorizationFlow;

- (id)init:(NSString *)serverURL namespace:(NSString *)targetNamespace completionHandler:(void (^)(NSDictionary *response))handler {
    if (self = [super init]) {
        _serverURL = serverURL;
        namespace = targetNamespace;
        _v = [[Vantiq alloc] initWithServer:serverURL];
        if (namespace && ![namespace isEqualToString:@""]) {
            _v.namespace = namespace;
        }
        
        // construct a synthetic URL with which to store login credentials
        NSURL *url = [NSURL URLWithString:serverURL];
        protSpace = [[NSURLProtectionSpace alloc] initWithHost:url.host
            port:[url.port integerValue] protocol:url.scheme
            realm:nil authenticationMethod:NSURLAuthenticationMethodHTTPDigest];
        
        // restore the last known session state from the Keychain
        NSDictionary *session = [self retrieveSession];
        tokenExpiration = 0;
        internalPassword = @"";
        if (session) {
            _v.accessToken = [session objectForKey:@"accessToken"];
            _serverType = [session objectForKey:@"serverType"];
            _username = [session objectForKey:@"username"];
            _preferredUsername = [session objectForKey:@"preferredUsername"];
            tokenExpiration = [[session objectForKey:@"tokenExpiration"] intValue];
            internalPassword = [session objectForKey:@"internalPassword"];
        } else {
            authValid = @"false";
        }
        
        if (!_serverType) {
            // need to determine the server type
            [self serverType:^(NSDictionary *response) {
                if (![response objectForKey:@"serverType"]) {
                    // couldn't find the server type
                    handler(response);
                } else {
                    // verify the auth token
                    [self verifyAuthToken:^(NSDictionary *response) {
                        handler(response);
                    }];
                }
            }];
        } else {
            // just need to verify the auth token
            [self verifyAuthToken:^(NSDictionary *response) {
                handler(response);
            }];
        }
    }
    return self;
}

- (void)serverType:(void (^)(NSDictionary *response))handler {
    [_v authenticate:@"" password:@"" completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
        NSString *errorStr = error ? [error localizedDescription] : @"";
        if (response) {
            NSDictionary *headerFields = response.allHeaderFields;
            NSString *OAuthURL = [headerFields objectForKey:@"Www-Authenticate"];
            if (OAuthURL) {
                self->_serverType = [OAuthURL isEqualToString:@"Vantiq"] ? @"Internal" : @"OAuth";
            }
        }
        handler([self buildResponseDictionary:errorStr urlResponse:response]);
    }];
}

- (void)verifyAuthToken:(void (^)(NSDictionary *response))handler {
    if (_serverType && [_serverType isEqualToString:@"OAuth"]) {
        // preemptively refresh the access token if necessary
        OIDAuthState *authState = [self retrieveAuthState];
        if (authState) {
            [authState performActionWithFreshTokens:^(NSString *_Nonnull accessToken,
                NSString *_Nonnull idToken, NSError *_Nullable error) {
                if (!error) {
                    if (![accessToken isEqualToString:self->_v.accessToken]) {
                        [self storeSession];
                    }
                    [self refreshedVerifyAuthToken:accessToken username:self->_username completionHandler:handler];
                } else {
                    NSLog(@"performActionWithFreshTokens: %@", [error localizedDescription]);
                    [self refreshedVerifyAuthToken:self->_v.accessToken username:self->_username completionHandler:handler];
                }
            }];
        } else {
            [self refreshedVerifyAuthToken:_v.accessToken username:_username completionHandler:handler];
        }
    } else {
        [self refreshedVerifyAuthToken:_v.accessToken username:_username completionHandler:handler];
    }
}
    
- (void)refreshedVerifyAuthToken:(NSString *)authToken username:(NSString *)username completionHandler:(void (^)(NSDictionary *response))handler {
    [_v verify:authToken username:username completionHandler:^(NSArray *data, NSHTTPURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            NSString *resultStr = @"";
            self->authValid = [self formError:response error:error resultStr:&resultStr] ? @"false" : @"true";
            handler([self buildResponseDictionary:resultStr urlResponse:response]);
        });
    }];
}

- (void)authWithOAuth:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSDictionary *response))handler {
    NSString *issuerURL = [[NSString stringWithString:_serverURL] lowercaseString];
    NSURL *url = [NSURL URLWithString:issuerURL];
    issuerURL = [NSString stringWithFormat:@"%@/auth/realms/%@", issuerURL, url.host];
    NSURL *issuer = [NSURL URLWithString:issuerURL];
    
    authValid = @"false";
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
                    
                    // store the session securely
                    self->_v.accessToken = authState.lastTokenResponse.accessToken;
                    self->authValid = @"true";
                    [self storeSession];
                    // persist the returned state
                    [self storeAuthState:authState];
                    handler([self buildResponseDictionary:errorStr urlResponse:nil]);
                } else {
                    NSLog(@"Authorization error: %@", errorStr);
                    handler([self buildResponseDictionary:errorStr urlResponse:nil]);
                }
            }];
        } else {
            NSLog(@"Error retrieving discovery document: %@", errorStr);
            handler([self buildResponseDictionary:errorStr urlResponse:nil]);
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
    if (data.length) {
        OIDAuthState *authState = [NSKeyedUnarchiver unarchivedObjectOfClass:[OIDAuthState class]
            fromData:data error:&errRet];
        return authState;
    }
    return nil;
}

/*
 *  ensureValidToken
 *      - called before any REST operation to try to ensure there is a valid auth token
 *      - for OAuth servers, this means using the AppAuth approach
 *      - for Internal servers, this means explicitly checking if the existing token is
 *          still valid and, if not, then silently starting a new authorization with our
 *          last-saved username/password
 */
- (void)ensureValidToken:(void (^)(NSDictionary *response))handler {
    NSString *resultStr = @"";
    if (_serverType) {
        if ([_serverType isEqualToString:@"OAuth"]) {
            OIDAuthState *authState = [self retrieveAuthState];
            if (authState) {
                [authState performActionWithFreshTokens:^(NSString *_Nonnull accessToken,
                    NSString *_Nonnull idToken, NSError *_Nullable error) {
                    if (!error) {
                        if (![accessToken isEqualToString:self->_v.accessToken]) {
                            self->_v.accessToken = accessToken;
                            [self decodeJWT:idToken];
                            [self storeAuthState:authState];
                            [self storeSession];
                        }
                    }
                    self->authValid = error ? @"false" : @"true";
                    handler([self buildResponseDictionary:resultStr urlResponse:nil]);
                }];
            } else {
                self->authValid = @"false";
                handler([self buildResponseDictionary:resultStr urlResponse:nil]);
            }
        } else {
            NSDate *exp = [NSDate dateWithTimeIntervalSince1970:tokenExpiration];
            NSDate *now = [[NSDate alloc] init];
            if ([now compare:exp] == NSOrderedDescending) {
                [self authWithInternal:_username password:internalPassword completionHandler:^(NSDictionary *response) {
                    handler(response);
                }];
            } else {
                self->authValid = @"true";
                handler([self buildResponseDictionary:resultStr urlResponse:nil]);
            }
        }
    }
}

- (void)authWithInternal:(NSString *)username password:(NSString *)password completionHandler:(void (^)(NSDictionary *response))handler {
    [_v authenticate:username password:password completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
        NSString *resultStr = @"";
        [self formError:response error:error resultStr:&resultStr];
        if (!resultStr.length) {
            self->_username = username;
            self->_preferredUsername = username;
            self->authValid = @"true";
            if (self->_v.idToken) {
                [self decodeJWT:self->_v.idToken];
            }
            self->internalPassword = password;
            // store the session securely
            [self storeSession];
        }
        handler([self buildResponseDictionary:resultStr urlResponse:response]);
    }];
}

- (void)decodeJWT:(NSString *)jwt {
    JWTBuilder *decodeBuilder = [JWTBuilder decodeMessage:jwt];
    if (decodeBuilder) {
        NSDictionary *envelopedPayload = decodeBuilder.options(@1).decode;
        NSDictionary *payload = [envelopedPayload objectForKey:@"payload"];
        if (payload) {
            _preferredUsername = [payload objectForKey:@"preferred_username"];
            _username = [payload objectForKey:@"sub"];
            tokenExpiration = [[payload objectForKey:@"exp"] intValue];
            NSDate *exp = [NSDate dateWithTimeIntervalSince1970:tokenExpiration];
            NSString *dateString = [NSDateFormatter localizedStringFromDate:exp
                dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterFullStyle];
            NSLog(@"token expiration = %@ (server = %@)", dateString, [payload objectForKey:@"iss"]);
        }
    }
}

/*
 *  storeSession, retrieveSession, isSessionPresent
 *      - helpers to securely store authentication credentials, both OAuth and username/password, plus
 *          other random bits of information that we'd like to pass back to the app
 */
- (void)storeSession {
    NSDictionary *credentialsDict = [NSDictionary dictionaryWithObjectsAndKeys:_v.accessToken,
        @"accessToken", _serverType, @"serverType", _username, @"username",
        _preferredUsername, @"preferredUsername", [NSNumber numberWithInt:tokenExpiration], @"tokenExpiration",
        internalPassword, @"internalPassword", nil];
    
    // use the NSURLCredential form of Keychain access to store session-oriented data
    // the username is just a common key (@"session") and the password is the JSON-
    // encoded dictionary of the session data to be persisted
    NSURLCredential *credential = [NSURLCredential credentialWithUser:@"session" password:[self dictionaryToJSONString:credentialsDict] persistence:NSURLCredentialPersistencePermanent];
    [[NSURLCredentialStorage sharedCredentialStorage] setCredential:credential forProtectionSpace:protSpace];
}

- (NSDictionary *)retrieveSession {
    NSDictionary *sessions = [[NSURLCredentialStorage sharedCredentialStorage] credentialsForProtectionSpace:protSpace];
    if (sessions) {
        // see comments in storeSession regarding NSURLCredential usage
        NSURL *session = [sessions objectForKey:@"session"];
        if (session) {
            return [self JSONStringToDictionary:session.password];
        }
    }
    return nil;
}

- (BOOL)isSessionPresent {
    NSDictionary *session = [self retrieveSession];
    return session != nil;
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

- (NSDictionary *)buildResponseDictionary:(NSString *)errorStr urlResponse:(NSHTTPURLResponse *)response {
    NSMutableDictionary *responseDict = [[NSMutableDictionary alloc] init];
    if (_serverType) {
        [responseDict setObject:_serverType forKey:@"serverType"];
    }
    if (authValid) {
        [responseDict setObject:authValid forKey:@"authValid"];
    }
    if (_username) {
        [responseDict setObject:_username forKey:@"username"];
    }
    if (_preferredUsername) {
        [responseDict setObject:_preferredUsername forKey:@"preferredUsername"];
    }
    [responseDict setObject:errorStr forKey:@"errorStr"];
    if (response) {
        [responseDict setObject:[NSNumber numberWithInteger:response.statusCode] forKey:@"statusCode"];
    }
    return responseDict;
}
@end
