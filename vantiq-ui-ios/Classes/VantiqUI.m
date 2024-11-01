//
//  VantiqUI.m
//
//  Created by Swan on 9/12/24.
//

#import <Foundation/Foundation.h>
#import "VantiqUI.h"
#import "JWT.h"
#include "KeychainItemWrapper.h"
#include "LastActive.h"
#include "LocationUtilities.h"
#include "JSONUtilities.h"

@interface VantiqUI() {
    int tokenExpiration;
    NSString *internalPassword;
    NSURLProtectionSpace *protSpace;
    NSString *protSpaceUser;
    BOOL authValid;
    NSString *namespace;
    NSDateFormatter *dateFormatter;
    
    // location tracking
    double collaborationDistanceFilter;
    double collaborationAccuracy;
    // states of each type of tracking: may be 'off', 'coarse', or 'fine'
    NSString *collaborationTracking;
    CLLocationManager *locationManager;
    NSMutableDictionary *locationDict;
    BOOL receivedLocation;
    NSMutableDictionary *coordinates;
    CFAbsoluteTime lastUpdateTime;
    
    // background fetch
    BOOL    finishedILU, finishedPL;
    void (^_pushCompletionHandler)(BOOL notificationHandled);
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
            authValid = NO;
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
        
        // location tracking
        collaborationDistanceFilter = 100;
        collaborationAccuracy = kCLLocationAccuracyThreeKilometers;
        collaborationTracking = @"off";
        receivedLocation = false;
        locationManager = nil;
        locationDict = [NSMutableDictionary new];
        coordinates = [NSMutableDictionary new];
        [coordinates setValue:@"Point" forKey:@"type"];
        dateFormatter = [NSDateFormatter new];
        NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        [dateFormatter setLocale:enUSPOSIXLocale];
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
        lastUpdateTime = CFAbsoluteTimeGetCurrent();
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
            self->authValid = [self formError:response error:error resultStr:&resultStr] ? NO : YES;
            handler([self buildResponseDictionary:resultStr urlResponse:response]);
        });
    }];
}

- (void)authWithOAuth:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSDictionary *response))handler {
    NSString *issuerURL = [[NSString stringWithString:_serverURL] lowercaseString];
    NSURL *url = [NSURL URLWithString:issuerURL];
    issuerURL = [NSString stringWithFormat:@"%@/auth/realms/%@", issuerURL, url.host];
    NSURL *issuer = [NSURL URLWithString:issuerURL];
    
    authValid = NO;
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
                    self->authValid = YES;
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
                    self->authValid = error ? NO : YES;
                    handler([self buildResponseDictionary:resultStr urlResponse:nil]);
                }];
            } else {
                self->authValid = NO;
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
                self->authValid = YES;
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
            self->authValid = YES;
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
        [responseDict setObject:[NSNumber numberWithBool:authValid] forKey:@"authValid"];
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

#pragma mark - APNS Helpers
/**************************************************
 *  APNS Helpers
 */
/*
 *  convertAPNSToken
 *      - helper to convert an APNS device token into a device ID string
 *          suitable for registration to receive Vantiq push notifications
 */
+ (NSString *)convertAPNSToken:(NSData *)deviceToken {
    // we've received an APNS token
    NSMutableString *deviceID = [NSMutableString string];
    // iterate through the bytes and convert to hex
    unsigned char *ptr = (unsigned char *)[deviceToken bytes];
    for (NSInteger i=0; i < 32; ++i) {
        [deviceID appendString:[NSString stringWithFormat:@"%02x", ptr[i]]];
    }
    return deviceID;
}

/*
 *  processPushNotification
 *      - called from app delegate's didReceiveRemoteNotification method to
 *          process push notifications
 *      - we handle location related types (locationTracking, locationRequest)
 *          but return an unhandled status for all other types so the app has
 *          to decide what to do about them
 */
- (void)processPushNotification:(nonnull NSDictionary *)userInfo
    completionHandler:(void (^)(BOOL notificationHandled))completionHandler {
    id notifyData = [userInfo objectForKey:@"data"];
    if (notifyData) {
        // look inside the notification data to see what kind of
        // Vantiq notification was sent
        NSString *dataType = [notifyData objectForKey:@"type"];
        if ([dataType isEqualToString:@"locationTracking"]) {
            NSString *whereClause = [NSString stringWithFormat:@"{\"deviceId\":\"%@\", \"username\":\"%@\"}", _v.appUUID, _v.username];
            [_v select:@"ArsPushTarget" props:@[] where:whereClause completionHandler:^(NSArray *data, NSHTTPURLResponse *response, NSError *error) {
                NSString *resultStr;
                if (![self formError:response error:error resultStr:&resultStr]) {
                    if (data.count == 1) {
                        NSDictionary *apt = [NSDictionary dictionaryWithDictionary:data[0]];
                        if ([[apt objectForKey:@"level"] isKindOfClass:[NSString class]]) {
                            NSString *level = [apt objectForKey:@"level"];
                            if (level) {
                                if ([level isEqualToString:@"fine"]) {
                                    self->collaborationTracking = @"fine";
                                    // fine tracking may involve additional parameters
                                    id dValue = [apt objectForKey:@"desiredAccuracy"];
                                    if ([dValue respondsToSelector:@selector(doubleValue)]) {
                                        if ([dValue doubleValue] < self->collaborationAccuracy) {
                                            self->collaborationAccuracy = [dValue doubleValue];
                                        }
                                    }
                                    dValue = [apt objectForKey:@"distanceFilter"];
                                    if ([dValue respondsToSelector:@selector(doubleValue)]) {
                                        if ([dValue doubleValue] < self->collaborationDistanceFilter) {
                                            self->collaborationDistanceFilter = [dValue doubleValue];
                                        }
                                    }
                                } else if ([level isEqualToString:@"coarse"] &&
                                    ![self->collaborationTracking isEqualToString:@"fine"]) {
                                    self->collaborationTracking = @"coarse";
                                }
                            }
                        }
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self updateTracking];
                            if (![self->collaborationTracking isEqualToString:@"off"]) {
                                [NSTimer scheduledTimerWithTimeInterval:5.0 target:self
                                    selector:@selector(publishCurrentLocation:)
                                    userInfo:completionHandler repeats:NO];
                            } else {
                                completionHandler(YES);
                            }
                        });
                    }
                } else {
                    completionHandler(NO);
                }
            }];
        } else if ([dataType isEqualToString:@"locationRequest"]) {
            [self doBFTasksWithCompletionHandler:NO completionHandler:completionHandler];
        } else {
            completionHandler(NO);
        }
    }
}

#pragma mark - Location Tracking
/**************************************************
 *  Location Tracking
 */
- (void)publishCurrentLocation:(NSTimer *)timer {
    void (^_pushCompletionHandler)(BOOL notificationHandled) = timer.userInfo;
    [self publishLocation:NO completionHandler:^{
        _pushCompletionHandler(YES);
    }];
}

- (void)publishLocation:(BOOL)alwaysPublish completionHandler:(void (^)(void))completionHandler {
    if (alwaysPublish || receivedLocation) {
        NSString *lastActiveTime = [self timestampToString:[[LastActive sharedInstance] lastActiveTime]];
        [locationDict setValue:@[_v.username] forKey:@"username"];
        [locationDict setValue:lastActiveTime forKey:@"lastActive"];
        NSString *message = [JSONUtilities dictionaryToJSONString:locationDict];
        [locationDict removeObjectForKey:@"username"];
        [locationDict removeObjectForKey:@"lastActive"];
        
        // publish location data to the well-known topic
        [_v publish:@"/ars_collaboration/location/mc" message:message completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
            NSString *resultStr;
            if ([self formError:response error:error resultStr:&resultStr]) {
                NSLog(@"had trouble publishing: %@", resultStr);
            }
            self->receivedLocation = false;
            completionHandler();
        }];
    } else {
        completionHandler();
    }
}

- (void)updateTracking {
    if (!locationManager) {
        [self initManager];
    }
    if (locationManager) {
        if ([collaborationTracking isEqualToString:@"fine"]) {
            [locationManager stopMonitoringSignificantLocationChanges];
            if ([locationManager respondsToSelector:@selector(stopMonitoringVisits)]) {
                [locationManager stopMonitoringVisits];
            }
            [locationManager startUpdatingLocation];
            locationManager.desiredAccuracy = collaborationAccuracy;
            locationManager.distanceFilter = collaborationDistanceFilter;
        } else if ([collaborationTracking isEqualToString:@"coarse"]) {
            [locationManager stopUpdatingLocation];
            [locationManager startMonitoringSignificantLocationChanges];
            if ([locationManager respondsToSelector:@selector(startMonitoringVisits)]) {
                [locationManager startMonitoringVisits];
            }
        } else {
            // turning off all tracking
            [locationManager stopUpdatingLocation];
            [locationManager stopMonitoringSignificantLocationChanges];
            if ([locationManager respondsToSelector:@selector(stopMonitoringVisits)])
                [locationManager stopMonitoringVisits];
        }
    }
}

- (void)initManager {
    // register for location change events
    locationManager = [CLLocationManager new];
    locationManager.delegate = self;
    if ([locationManager respondsToSelector:@selector(requestAlwaysAuthorization)]) {
        // ask for permission
        [locationManager requestAlwaysAuthorization];
    }
    locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
    // filter readings in increments of 100 meters
    locationManager.distanceFilter = 100.0;
    // try to save on battery life
    locationManager.pausesLocationUpdatesAutomatically = YES;
    // allow tracking while in the background
    locationManager.allowsBackgroundLocationUpdates = YES;
    locationManager.showsBackgroundLocationIndicator = NO;
}

- (void)onCollectLocationSample:(CLLocation*)location {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CLLocationCoordinate2D c2d = location.coordinate;
    CLLocationDegrees lat = c2d.latitude;
    CLLocationDegrees lon = c2d.longitude;
    
    //  form the dictionary we'll send publish at background fetch time
    [locationDict setValue:[dateFormatter stringFromDate:location.timestamp] forKey:@"timestamp"];
    NSMutableArray* latlon = [NSMutableArray new];
    [latlon addObject:[NSNumber numberWithDouble:lon]];
    [latlon addObject:[NSNumber numberWithDouble:lat]];
    [coordinates setValue:latlon forKey:@"coordinates"];
    [locationDict setValue:coordinates forKey:@"location"];
    [LocationUtilities addExtras:location toDictionary:locationDict];
    receivedLocation = true;
    
    if (![collaborationTracking isEqualToString:@"off"] && (now >= (lastUpdateTime + 20))) {
        lastUpdateTime = now;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self publishLocation:NO completionHandler:^{
            }];
        });
    }
}

/*
 *  timestampToString
 *      - helper to convert timestamps into a string that can be published
 */
- (NSString *)timestampToString:(NSDate *)timestamp {
    NSString *dateString = [timestamp description];
    // format the iOS-produced current date/time string to an alternate format
    dateString = [dateString stringByReplacingOccurrencesOfString:@" +" withString:@"+"];
    dateString = [dateString stringByReplacingOccurrencesOfString:@" " withString:@"T"];
    return dateString;
}

#pragma mark - CLLocationManager Delegates
/**************************************************
 *  CLLocationManager Delegates
 */

/*
 *  didUpdateLocations
 *      - called asynchronously from the Location Manager whenever there is
 *          a significant location change during normal operation or whenever
 *          we're explicitly sampling during a Background Fetch interval
 */
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *newLocation = [locations lastObject];
    [self onCollectLocationSample:newLocation];
}

/*
 *  didVisit
 *      - called asynchronously from the Location Manager whenever the user
 *          visits "interesting places"
 */
- (void)locationManager:(CLLocationManager *)manager didVisit:(CLVisit *)visit {
    CLLocation *location = [[CLLocation alloc] initWithCoordinate:visit.coordinate altitude:0.0
        horizontalAccuracy:visit.horizontalAccuracy verticalAccuracy:0.0 timestamp:visit.departureDate];
    [self onCollectLocationSample:location];
}

#pragma mark - Background Task Processing
/**************************************************
 *  Background Task Processing
 */
/*
 *  doTasksWithCompletionHandler
 *      - start up operations that need to be run in the background
 */
- (void)doBFTasksWithCompletionHandler:(BOOL)alwaysPublish completionHandler:(void (^)(BOOL notificationHandled))completionHandler {
    _pushCompletionHandler = [completionHandler copy];
    finishedPL = finishedILU = false;
    [self publishLocation:alwaysPublish completionHandler:^{
        self->finishedILU = true;
        [self checkBFFinished];
    }];
    [self publishLocation:alwaysPublish completionHandler:^{
        self->finishedPL = true;
        [self checkBFFinished];
    }];
}

- (void)checkBFFinished {
    if (finishedILU && finishedPL) {
        _pushCompletionHandler(YES);
    }
}

#pragma mark - New User Creation
/**************************************************
 *  New User Creation
 */
- (void)createInternalUser:(NSString *)username password:(NSString *)password email:(NSString *)email
    firstName:(NSString *)firstName lastName:(NSString *)lastName phone:(NSString *)phone
    completionHandler:(void (^_Nonnull)(NSDictionary *_Nonnull response))handler {
    NSMutableDictionary *userDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:username, @"username",
        password, @"password", nil];
    if (email) [userDict setValue:email forKey:@"email"];
    if (firstName) [userDict setValue:firstName forKey:@"firstName"];
    if (lastName) [userDict setValue:lastName forKey:@"lastName"];
    if (phone) [userDict setValue:phone forKey:@"phone"];
    NSString *paramsStr = [self dictionaryToJSONString:userDict];
    paramsStr = paramsStr ? paramsStr : @"{}";
    [_v publicExecute:@"Registration.createInternalUser" params:paramsStr
        completionHandler:^(NSHTTPURLResponse *response, NSError *error) {
        NSString *resultStr = @"";
        self->authValid = [self formError:response error:error resultStr:&resultStr] ? NO : YES;
        handler([self buildResponseDictionary:resultStr urlResponse:response]);
    }];
}
@end
