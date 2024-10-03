//
//  VantiqUI.h
//  Pods
//
//  Created by Swan on 9/12/24.
//

#ifndef VantiqUI_h
#define VantiqUI_h
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#import "Vantiq.h"
#import "AppAuth.h"

extern id<OIDExternalUserAgentSession> VantiqUIcurrentAuthorizationFlow;

/**
The VantiqUI class declares the interface for authentication and subsequent interaction with a Vantiq server.
 */
@interface VantiqUI : NSObject
/**
Instance of the underlying Vantiq class for direct communication to the Vantiq SDK
 */
@property (readonly, nonatomic) Vantiq *v;
/**
 User name of the last authenticated user.
 */
@property (readonly, nonatomic) NSString *username;
/**
 Preferred user name of the last authenticated user.
 */
@property (readonly, nonatomic) NSString *preferredUsername;
/**
 Type of the server, will be either 'Internal' or 'OAuth'
 */
@property (readonly, nonatomic) NSString *serverType;

/**
Constructor for use with all other Vantiq UI and server operations.
 
@param serverURL       Server URL, e.g. https://dev.vantiq.com
@param namespace        Vantiq Namespace in which to operate, not currently used
 @param completionHandler
 */
- (id)init:(NSString *)serverURL namespace:(NSString *)targetNamespace completionHandler:(void (^)(NSDictionary *response))handler;

/**
Session Information Dictionary Keys
 
 The following keys are returned in the response dictionary returned by the following methods:
@see serverType:
@see verifyAuthToken:
@see authWithOAuth:clientId:completionHandler:
@see authWithInternal:password:completionHandler:
 
 Not all keys will be present depending on error conditions and the method.
 
 serverType (NSString): the type of authentication used by the given Vantiq server, either @"Internal" or @"OAuth"
 authValid (NSString): is the previously establed authentication token valid, either @"true" or @"false"
 username (NSString): the username of the authenticated user
 preferredUsername (NSString): the preferred username of the authenticated user, will be the same as the username for Internal authentication
 errorStr (NSString): a text description of any error that occurred, will be the empty string (@"") if there is no error
 statusCode (NSNumber): the HTTP status code of any related REST operations
 */

/**
The serverType method determines if the given server uses Internal (username/password) or OAuth (via
 Keycloak) for authentication. If a subsequent call to _verifyAuthToken_ indicates the current access token
 is invalid or doesn't exist, use the isInternal return to determine if the user should authenticate using
 authWithInternal or authWithOAuth.
 
@warning Please also note this method invokes a callback block associated with a network-
related block. Because this block is called from asynchronous network operations,
its code must be wrapped by a call to _dispatch_async(dispatch_get_main_queue(), ^ {...});_
to ensure any UI operations are completed on the main thread.
 
@see verifyAuthToken:completionHandler:
@see authWithInternal:password:completionHandler:
@see authWithOAuth:clientId:completionHandler:
 
@param handler      The handler block to execute.
 
@return response: dictionary containing session information, see Session Information Dictionary Keys above
*/
- (void)serverType:(void (^)(NSDictionary *response))completionHandler;

/**
The verifyAuthToken method determines if a previously opaquely-saved access token is still valid. If
 not, then one of _authWithInternal_ or _authWithOAuth_ must be called to generate a new access token.
 
@warning Please also note this method invokes a callback block associated with a network-
related block. Because this block is called from asynchronous network operations,
its code must be wrapped by a call to _dispatch_async(dispatch_get_main_queue(), ^ {...});_
to ensure any UI operations are completed on the main thread.
 
@see authWithInternal:password:completionHandler:
@see authWithOAuth:clientId:completionHandler:
 
@param username     The username previously returned in the class variable 'username' after a successful call to authWithInternal or authWithOAuth or an empty (@"") string otherwise.
@param handler      The handler block to execute.
 
@return response: dictionary containing session information, see Session Information Dictionary Keys above
*/
- (void)verifyAuthToken:(void (^)(NSDictionary *response))completionHandler;

/**
The authWithOAuth method retrieves an OAuth access token from a Keycloak server associated
 with the Vantiq server. This is an opaque access token maintained by the VantiqUI class. This
 method should be called if the _verifyAuthToken_ returns false in its _isInternal_ callback return.
 
@warning Please also note this method invokes a callback block associated with a network-
related block. Because this block is called from asynchronous network operations,
its code must be wrapped by a call to _dispatch_async(dispatch_get_main_queue(), ^ {...});_
to ensure any UI operations are completed on the main thread.
 
@see verifyAuthToken:completionHandler:
 
@param urlScheme     A URL scheme configured in the Keycloak server used to complete the OAuth authentication process
@param clientId     A Client ID configured in the Keycloak sever used to identify the mobile app
@param handler      The handler block to execute.
 
@return response: dictionary containing session information, see Session Information Dictionary Keys above
*/
- (void)authWithOAuth:(NSString *)urlScheme clientId:(NSString *)clientId completionHandler:(void (^)(NSDictionary *response))handler;

/**
The authWithInternal method retrieves an access token from the Vantiq server based on the
 user-supplied username and password. This is an opaque access token maintained by the VantiqUI class. This
 method should be called if the _verifyAuthToken_ returns true in its _isInternal_ callback return.
 
@warning Please also note this method invokes a callback block associated with a network-
related block. Because this block is called from asynchronous network operations,
its code must be wrapped by a call to _dispatch_async(dispatch_get_main_queue(), ^ {...});_
to ensure any UI operations are completed on the main thread.
 
@see verifyAuthToken:completionHandler:
 
@param username     The username entered by the user
@param password     The password entered by the user
@param handler      The handler block to execute.
 
@return response: dictionary containing session information, see Session Information Dictionary Keys above
*/
- (void)authWithInternal:(NSString *)username password:(NSString *)password completionHandler:(void (^)(NSDictionary *response))handler;

/**
The formError method is a helper to produce an error string based on the NSHTTPURLResponse
 and NSError responses from calls made directly to the Vantiq SDK via the _v_ class variable. If
 no error is returned by the Vantiq SDK, the _resultStr_ will return the empty (@"") string.
  
@param response     The NSHTTPURLResponse returned from the Vantiq SDK call
@param error     The NEError returned from the Vantiq SDK call
@param resultStr     Pointer to an NSString instance (note the double indirection)
 
@return errorStr: localized version of error encountered, if any, or an empty (@"") string otherwise. Check for zero-length string to indicate success.
*/
- (BOOL)formError:(NSHTTPURLResponse *)response error:(NSError *)error resultStr:(NSString **)resultStr;
@end
#pragma clang diagnostic pop
#endif /* VantiqUI_h */
