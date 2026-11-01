//  BTBIPadUI.m — /ipadui: make the app use its iPad interface on iPhone.
//  BetterThanBox also adds iPad (2) to UIDeviceFamily when this tweak is chosen.

#import "BTBCommon.h"
#import <UIKit/UIKit.h>

void BTBFeatureIPadUI(void) {
	BTBSwizzle([UIDevice class], @selector(userInterfaceIdiom), NO, ^UIUserInterfaceIdiom(id self) {
		return UIUserInterfaceIdiomPad;
	});
	BTBSwizzle([UITraitCollection class], @selector(userInterfaceIdiom), NO, ^UIUserInterfaceIdiom(id self) {
		return UIUserInterfaceIdiomPad;
	});
}
