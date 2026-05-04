//
//  WebViewController.h
//  vantiq-ui-ios
//
//  Created by Swan on 11/4/24.
//

#import <WebKit/WebKit.h>
#import "VantiqUI.h"

@interface WebViewController : UIViewController <WKNavigationDelegate>
@property (strong, nonatomic) VantiqUI *vui;
@property (strong, nonatomic) NSString *OAuthURL;
@property (strong, nonatomic) NSString *drpError;
@end
