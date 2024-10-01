#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "KeychainItemWrapper.h"
#import "VantiqUI.h"

FOUNDATION_EXPORT double vantiq_ui_iosVersionNumber;
FOUNDATION_EXPORT const unsigned char vantiq_ui_iosVersionString[];

