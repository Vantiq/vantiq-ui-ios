//
//  WebViewController.m
//  vantiq-ui-ios
//
//  Created by Swan on 11/4/24.
//

#import "WebViewController.h"

// singleton-based WKProcessPool in order to synchronize cookies between instances
// of webview sessions since cookies are used to maintain OAuth parameters
@interface OAuthProcessPool : NSObject
+ (OAuthProcessPool *)sharedInstance;
@property (readwrite, nonatomic) WKProcessPool *processPool;
@end

static OAuthProcessPool *_sharedOauthProcessPool;
@implementation OAuthProcessPool
+ (OAuthProcessPool *)sharedInstance {
    @synchronized(self) {
        if (_sharedOauthProcessPool == nil) {
            _sharedOauthProcessPool = [OAuthProcessPool new];
        }
        return _sharedOauthProcessPool;
    }
}
- (id)init {
    if (self = [super init]) {
        self.processPool = [WKProcessPool new];
    }
    return self;
}
@end

@interface WebViewController () {
    WKWebView *webView;
    NSString *host;
    BOOL foundModelo;
    BOOL foundAccessToken;
    BOOL completingLogin;
}
@end

@implementation WebViewController

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    foundModelo = NO;
    foundAccessToken = NO;
    completingLogin = NO;
    
    // load the given authentication URL -- we use a singleton-based WKProcessPool
    // in order to synchronize cookies between instances of webview sessions since
    // cookies are used to maintain OAuth parameters
    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    config.processPool = [OAuthProcessPool sharedInstance].processPool;
    webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
    webView.navigationDelegate = self;
    webView.customUserAgent = @"Vantiq";
    if (@available(iOS 16.4, *)) {
        // allow Safari to inspect this WKWebView
        webView.inspectable = YES;
    }
    self.view = webView;
    self.drpError = @"";
    
    [self initiateDRP];
}

- (void)initiateDRP {
    NSURL *url = [NSURL URLWithString:_OAuthURL];
    host = url.host;
    NSLog(@"viewDidAppear: host=%@, url=%@", host, _OAuthURL);
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url];
    [webView loadRequest:urlRequest];
}

/**************************************************
 *    WKWebView Delegates
 */
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    
    NSLog(@"url.host = %@, path = %@, fragment = %@", url.host, url.path, url.fragment);
    NSLog(@"url.absoluteString = %@", url.absoluteString);
    
    // look for a particular URL that indicates the authentication has completed and is returning with a JWT
    if ([url.host isEqualToString:host] && url.path && url.fragment) {
        // the JWT and access token will be in the URL's query parameters
        NSArray *fragment = [url.fragment componentsSeparatedByString:@"&"];
        if ([url.path isEqualToString:@"/ui/drp/index.html"]) {
            NSLog(@"saw /ui/drp/index.html");
            for (NSUInteger i = 0; i < [fragment count]; i++) {
                // look for the 'id_token' query parameter, which should be our JWT
                NSArray *fragmentElem = [fragment[i] componentsSeparatedByString:@"="];
                if ([fragmentElem count] == 2) {
                    if ([fragmentElem[0] isEqualToString:@"id_token"]) {
                        [self->_vui decodeJWT:fragmentElem[1]];
                    } else if ([fragmentElem[0] isEqualToString:@"access_token"]) {
                        // save our access token
                        foundAccessToken = foundModelo = true;
                        self->_vui.v.accessToken = fragmentElem[1];
                        NSLog(@"setting OAuth accessToken = '%@'", self->_vui.v.accessToken);
                    }
                }
            }
        } else if (foundAccessToken) {
            // now we're looking for an instance of Modelo, which completes the public Client user authentication
            if ([url.absoluteString containsString:@"index.html#/modelo"]) {
                foundModelo = true;
            } else if ([url.absoluteString containsString:@"ide/index.html?errorCode"]) {
                NSLog(@"proceeding with existing user");
                // this is an indication that the user is already present and we already
                // have an auth token in place
                foundModelo = true;
            }
        }
    } else if ([url.host isEqualToString:host]) {
        if ([url.absoluteString containsString:@"execution=VERIFY_EMAIL"]) {
            // the calling app needs to put up a dialog to check for a verification email,
            // then needs to start the authentication process again
            NSLog(@"need to verify email");
            //self.drpError = @"com.vantiq.failed.drp.restart";
            //[self.vui dismissOAuthWebView];
            dispatch_async(dispatch_get_main_queue(), ^ {
                UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"Verify Email" message:@"Verify email please" preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                    NSLog(@"confirmed email verified");
                    [self initiateDRP];
                }];
                [confirm addAction:defaultAction];
                [self presentViewController:confirm animated:YES completion:nil];
            });
        } else if ([url.absoluteString containsString:@"redirect_uri"]) {
            NSLog(@"initiating redirect_uri delay");
            // this slight delay in processing the OAuth URL seems to solve a problem where the
            // DRP page gets stuck even though the URL has the code param
            [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer * _Nonnull timer) {
                decisionHandler(WKNavigationActionPolicyAllow);
            }];
            return;
        }
    }
        
    if (foundAccessToken && foundModelo) {
        if (!completingLogin) {
            completingLogin = YES;
            // instruct our parent controller to dismiss the webview UIViewController
            [self.vui dismissOAuthWebView];
        }
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"didFailNavigationWithError = %@", [error localizedDescription]);
}
@end
