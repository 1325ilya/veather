//  BTBNetwork.m — /nowifi (no network at all) and /noupd (no forced update checks).
//
//  /nowifi blocks, in the app's own process:
//   * NSURLSession / NSURLConnection (URL protocol)
//   * WKWebView loads (content rule list)
//   * raw sockets and DNS from the app's own code: connect, connectx, getaddrinfo
//     (game engines and C libraries such as libcurl use these directly)
//  Loopback (localhost) stays allowed.

#import "BTBURLBlock.h"
#import "BTBWebBlock.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <errno.h>

static BOOL BTBIsLoopback(const struct sockaddr *address) {
	if (!address) return YES;
	if (address->sa_family == AF_INET) {
		const struct sockaddr_in *v4 = (const struct sockaddr_in *)address;
		return (ntohl(v4->sin_addr.s_addr) >> 24) == 127;
	}
	if (address->sa_family == AF_INET6) {
		const struct in6_addr *a = &((const struct sockaddr_in6 *)address)->sin6_addr;
		return IN6_IS_ADDR_LOOPBACK(a) || (IN6_IS_ADDR_V4MAPPED(a) && a->s6_addr[12] == 127);
	}
	return YES; // unix sockets etc.
}

static int btb_connect(int fd, const struct sockaddr *address, socklen_t length) {
	if (BTBFlagNoNetwork && !BTBIsLoopback(address)) {
		errno = ENETUNREACH;
		return -1;
	}
	return connect(fd, address, length);
}
BTB_INTERPOSE(btb_connect, connect)

static int btb_connectx(int fd, const sa_endpoints_t *endpoints, sae_associd_t associd, unsigned int flags,
						const struct iovec *iov, unsigned int iovcnt, size_t *len, sae_connid_t *connid) {
	if (BTBFlagNoNetwork && endpoints && !BTBIsLoopback(endpoints->sae_dstaddr)) {
		errno = ENETUNREACH;
		return -1;
	}
	return connectx(fd, endpoints, associd, flags, iov, iovcnt, len, connid);
}
BTB_INTERPOSE(btb_connectx, connectx)

void BTBFeatureNoNetwork(void) {
	BTBInstallURLFilter(^BTBURLDecision(NSURLRequest *request) {
		NSString *host = request.URL.host.lowercaseString;
		if ([host isEqualToString:@"localhost"] || [host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"::1"]) {
			return BTBURLDecisionAllow;
		}
		return BTBURLDecisionFail;
	});

	NSString *rules =
		@"[{\"trigger\":{\"url-filter\":\"^(https?|wss?)://\"},\"action\":{\"type\":\"block\"}},"
		@"{\"trigger\":{\"url-filter\":\"^(https?|wss?)://(localhost|127\\\\.0\\\\.0\\\\.1)[/:]\"},\"action\":{\"type\":\"ignore-previous-rules\"}}]";
	BTBInstallWebContentBlock(@"nowifi", rules);
}

void BTBFeatureNoUpdates(void) {
	// Update libraries (Siren, Harpy, ATAppUpdater…) and most apps ask the App Store
	// lookup API for the latest version; answer "no results" so they see nothing newer.
	BTBInstallURLFilter(^BTBURLDecision(NSURLRequest *request) {
		NSString *host = request.URL.host.lowercaseString;
		NSString *path = request.URL.path.lowercaseString;
		BOOL appStoreHost = [host hasSuffix:@"itunes.apple.com"] || [host hasSuffix:@"apps.apple.com"];
		if (appStoreHost && [path hasSuffix:@"/lookup"]) {
			return BTBURLDecisionEmptyLookup;
		}
		return BTBURLDecisionAllow;
	});
}
