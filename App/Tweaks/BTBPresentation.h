//  BTBPresentation.h — one hook on -presentViewController:animated:completion:
//  shared by several tweaks (ads, rate prompts, iPad popover fix).

#import "BTBCommon.h"
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, BTBPresentDecision) {
	BTBPresentAllow = 0,
	BTBPresentBlock,        // don't present, call completion
	BTBPresentAutoDismiss   // present without animation and dismiss right away, so the
	                        // presenter's "did dismiss" callbacks still fire (no hangs)
};

typedef BTBPresentDecision (^BTBPresentFilter)(UIViewController *presenter, UIViewController *controller);

void BTBAddPresentationFilter(BTBPresentFilter filter);

/// Class names of full-screen ads from common SDKs (prefix + ad keyword).
BOOL BTBIsAdControllerClass(Class cls);
