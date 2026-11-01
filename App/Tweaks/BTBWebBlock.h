//  BTBWebBlock.h — WKContentRuleList attached to every WKWebView in the app,
//  so ads / network blocking also work for web content (separate WebKit process).

#import "BTBCommon.h"

/// `json` is a WebKit content blocker rule list. Safe to call several times with different identifiers.
void BTBInstallWebContentBlock(NSString *identifier, NSString *json);

/// Builds rules that block requests to the given domains (and their subdomains).
NSString *BTBWebRulesBlockingDomains(NSArray<NSString *> *domains);
