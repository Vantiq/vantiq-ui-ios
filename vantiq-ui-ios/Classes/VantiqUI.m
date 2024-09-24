//
//  VantiqUI.m
//  Pods-vantiq-ui-ios_Example
//
//  Created by Swan on 9/12/24.
//

#import <Foundation/Foundation.h>
#import "VantiqUI.h"
#import "JWT.h"

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
        NSString *authToken = [credentials objectForKey:@"accessToken"];
        [_v verify:authToken username:username completionHandler:^(NSArray *data, NSHTTPURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^ {
                NSString *resultStr = @"";
                handler(![self formError:response error:error resultStr:&resultStr], resultStr);
            });
        }];
    } else {
        handler(false, @"");
    }
}

- (void)authWithOAuth:(NSString *)namespace urlScheme:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSString *errorStr))handler {
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
            
            // performs authentication request
            UIViewController *rootViewController = UIApplication.sharedApplication.delegate.window.rootViewController;
            VantiqUIcurrentAuthorizationFlow = [OIDAuthState authStateByPresentingAuthorizationRequest:request
                presentingViewController:rootViewController
                callback:^(OIDAuthState *_Nullable authState, NSError *_Nullable error) {
                NSString *errorStr = error ? [error localizedDescription] : @"";
                if (authState) {
                    NSLog(@"Got authorization tokens. Access token: %@", authState.lastTokenResponse.accessToken);
                    [self decodeJWT:authState.lastTokenResponse.idToken];
                    self->_v.accessToken = authState.lastTokenResponse.accessToken;
                    self->idToken = authState.lastTokenResponse.idToken;
                    
                    // store the credentials securely
                    NSDictionary *credentialsDict = [NSDictionary dictionaryWithObjectsAndKeys:self->_v.accessToken, @"accessToken", self->idToken, @"idToken", nil];
                    [self storeCredentials:[self dictionaryToJSONString:credentialsDict]];
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

/*
 *  storeCredentials, retrieveCredentials, areCredentialsPresent
 *      - helpers to securely store authentication credentials, both OAuth and username/password
 */
- (void)storeCredentials:(NSString *)credentials {
    NSURLCredential *credential = [NSURLCredential credentialWithUser:_username password:credentials persistence:NSURLCredentialPersistencePermanent];
    [[NSURLCredentialStorage sharedCredentialStorage] setCredential:credential forProtectionSpace:protSpace];
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
@end
