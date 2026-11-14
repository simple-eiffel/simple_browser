/* sb_appkit.m - simple_browser's AppKit engine: WKWebView in an NSWindow (or in a parent view).
   docs/SIMPLE_BROWSER_SPEC.md, section 2 (the AppKit backend) and section 4 (the shared rules).

   The C side never calls Eiffel. Everything the page or the toolkit says is queued as an event
   (section 4.1), and the Eiffel loop takes it with `sb_next' after `sb_pump'. Every text the
   page sees (the bridge script, a binding's script, `evaluate''s wrapper) comes from shared code;
   this file only places it. */

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <pthread.h>
#include <float.h>
#include "sb_appkit.h"

/* ---------------------------------------------------------------- the event queue */

@interface SBEvent : NSObject
{
@public
	int kind, engine, a, b, c;
	NSString *text[3];
}
@end
@implementation SBEvent
@end

static NSMutableArray<SBEvent *> *s_queue;
static NSData *s_current[3];   /* the texts of the event `sb_next' took last, NUL-terminated UTF-8 */

static void sb_push(int a_kind, int an_engine, int a, int b, int c, NSString *t1, NSString *t2, NSString *t3)
{
	if (!s_queue) s_queue = [NSMutableArray array];
	SBEvent *e = [[SBEvent alloc] init];
	e->kind = a_kind; e->engine = an_engine; e->a = a; e->b = b; e->c = c;
	e->text[0] = t1 ?: @""; e->text[1] = t2 ?: @""; e->text[2] = t3 ?: @"";
	[s_queue addObject:e];
}

static NSString *sb_string(const char *a_text) { return [NSString stringWithUTF8String:a_text ? a_text : ""] ?: @""; }

/* `a_text' as a JSON string literal (quotes and escapes included). */
static NSString *sb_json_string(NSString *a_text)
{
	NSData *d = [NSJSONSerialization dataWithJSONObject:a_text ?: @"" options:NSJSONWritingFragmentsAllowed error:nil];
	return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"\"\"";
}

/* A URL as the page has it. Foundation escapes the fragment of an `about:' URL (about:blank#x
   reads back as about:blank%23x, with no fragment), where WebKit, GTK and WebView2 keep the `#':
   the first escaped one is put back, so every platform reports the same text. */
static NSString *sb_url_text(NSURL *a_url)
{
	NSString *s = [a_url absoluteString] ?: @"";
	if ([[[a_url scheme] lowercaseString] isEqualToString:@"about"]) {
		NSRange r = [s rangeOfString:@"%23"];
		if (r.location != NSNotFound) s = [s stringByReplacingCharactersInRange:r withString:@"#"];
	}
	return s;
}

/* ---------------------------------------------------------------- the application */

/* AppKit autoreleases objects in calls the program makes between pumps (a window's creation and
   closing among them); with no pool on the program's thread they would never be freed (simple_shell
   #53). An outer pool, pushed with the application and drained as each top-level pump starts. */
extern void *objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void *a_pool);
static void *s_outer_pool;
static int s_pump_depth;

static void sb_app(void)
{
	static BOOL s_done;
	if (s_done) return;
	s_done = YES;
	if (!s_outer_pool) s_outer_pool = objc_autoreleasePoolPush();
	[NSApplication sharedApplication];
	/* Coexisting with simple_gui or simple_shell in one process: a policy one of them set stays. */
	if ([NSApp activationPolicy] == NSApplicationActivationPolicyProhibited)
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	[NSApp finishLaunching];
}

int sb_is_gui_thread(void) { return pthread_main_np() ? 1 : 0; }

/* ---------------------------------------------------------------- an engine */

@class SBEngine;

/* The script message handler, holding its engine weakly: the user content controller retains
   its handlers, and the engine owns the controller. */
@interface SBMessageProxy : NSObject <WKScriptMessageHandler>
{
@public
	__weak SBEngine *engine;
}
@end

@interface SBEngine : NSObject <WKNavigationDelegate, WKUIDelegate, NSWindowDelegate>
{
@public
	int eid;
	NSWindow *window;          /* nil when embedded */
	WKWebView *view;
	NSString *bridge;          /* the shared bridge script */
	NSMutableArray<NSString *> *scripts;            /* `sb_add_script''s, in order */
	NSMutableArray<NSString *> *bound;              /* binding names, in order */
	NSMutableDictionary<NSString *, NSString *> *binding_script;
	BOOL deciding;             /* navigation decisions held for Eiffel */
	BOOL pass_next;            /* the program's own load: its next main-frame navigation is not asked */
	int next_decision;
	NSMutableDictionary<NSNumber *, void (^)(WKNavigationActionPolicy)> *held;
	BOOL load_failed;
	BOOL fixed;                /* a fixed size: a plain set_size holds to it until a min or max hint */
	NSString *echo_url;        /* tests: requests for it get a page showing their method and body */
	NSMutableDictionary<NSNumber *, NSURLRequest *> *held_request;   /* each held decision's request */
}
- (BOOL)echoes:(NSURLRequest *)a_request;
- (void)echo:(NSURLRequest *)a_request;
- (void)rebuildScripts;
@end

static SBEngine *s_engines[SB_MAX_ENGINES + 1];
static SBEngine *sb_engine(int e) { return e >= 1 && e <= SB_MAX_ENGINES ? s_engines[e] : nil; }

@implementation SBMessageProxy
/* A binding's call from the page: {name, seq, args}, args already JSON text (the bridge script
   stringifies them). */
- (void)userContentController:(WKUserContentController *)u didReceiveScriptMessage:(WKScriptMessage *)m
{
	(void)u;
	SBEngine *e = engine;
	if (!e || ![[m body] isKindOfClass:[NSDictionary class]]) return;
	NSDictionary *d = [m body];
	id l_name = d[@"name"], l_seq = d[@"seq"], l_args = d[@"args"];
	sb_push(SB_EVENT_CALL, e->eid, 0, 0, 0,
		[l_name isKindOfClass:[NSString class]] ? l_name : [l_name description],
		[l_seq isKindOfClass:[NSString class]] ? l_seq : [l_seq description],
		[l_args isKindOfClass:[NSString class]] ? l_args : @"[]");
}
@end

@implementation SBEngine

/* Every script the page gets at document start, in order: the bridge first, then the program's
   own (`inject'), then the bindings'. WKUserContentController cannot remove one script, so a
   change removes them all and adds them back. */
- (void)rebuildScripts
{
	WKUserContentController *u = [[view configuration] userContentController];
	[u removeAllUserScripts];
	/* the bridge and the bindings in the main frame only; the program's own scripts (`inject') in
	   every frame, on every platform */
	if ([bridge length])
		[u addUserScript:[[WKUserScript alloc] initWithSource:bridge injectionTime:WKUserScriptInjectionTimeAtDocumentStart
			forMainFrameOnly:YES inContentWorld:[WKContentWorld pageWorld]]];
	for (NSString *s in scripts)
		[u addUserScript:[[WKUserScript alloc] initWithSource:s injectionTime:WKUserScriptInjectionTimeAtDocumentStart
			forMainFrameOnly:NO inContentWorld:[WKContentWorld pageWorld]]];
	for (NSString *n in bound)
		[u addUserScript:[[WKUserScript alloc] initWithSource:binding_script[n] injectionTime:WKUserScriptInjectionTimeAtDocumentStart
			forMainFrameOnly:YES inContentWorld:[WKContentWorld pageWorld]]];
}

/* ---- navigation (sections 2 and 4.4, 4.5) */
- (void)webView:(WKWebView *)w decidePolicyForNavigationAction:(WKNavigationAction *)an_action
	decisionHandler:(void (^)(WKNavigationActionPolicy))a_handler
{
	(void)w;
	NSString *l_url = sb_url_text([[an_action request] URL]);
	/* A new window (target=_blank, window.open): never opened; reported. */
	if (![an_action targetFrame]) {
		a_handler(WKNavigationActionPolicyCancel);
		sb_push(SB_EVENT_NEW_WINDOW, eid, 0, 0, 0, l_url, nil, nil);
		return;
	}
	BOOL l_main = [[an_action targetFrame] isMainFrame];
	if (pass_next && l_main) { pass_next = NO; a_handler(WKNavigationActionPolicyAllow); return; }
	/* an iframe's first load (its own src or srcdoc) is part of the page's load, as the main
	   frame's own is: not asked; later navigations inside it are */
	if (!l_main && [an_action navigationType] == WKNavigationTypeOther && [[an_action sourceFrame] isMainFrame]) { a_handler(WKNavigationActionPolicyAllow); return; }
	if (!deciding) {
		if ([self echoes:[an_action request]]) { a_handler(WKNavigationActionPolicyCancel); [self echo:[an_action request]]; return; }
		a_handler(WKNavigationActionPolicyAllow);
		return;
	}
	int l_kind = 0;
	switch ([an_action navigationType]) {
		case WKNavigationTypeLinkActivated: l_kind = 1; break;
		case WKNavigationTypeFormSubmitted: case WKNavigationTypeFormResubmitted: l_kind = 2; break;
		case WKNavigationTypeBackForward: l_kind = 3; break;
		case WKNavigationTypeReload: l_kind = 4; break;
		default: l_kind = 0; break;
	}
	int d = ++next_decision;
	held[@(d)] = [a_handler copy];
	held_request[@(d)] = [an_action request];
	sb_push(SB_EVENT_NAVIGATING, eid, d, l_kind, l_main ? 1 : 0, l_url, nil, nil);
}
- (void)webView:(WKWebView *)w didStartProvisionalNavigation:(WKNavigation *)n { (void)w; (void)n; load_failed = NO; }
- (void)webView:(WKWebView *)w didFinishNavigation:(WKNavigation *)n
{
	(void)w; (void)n;
	if (!load_failed) sb_push(SB_EVENT_LOADED, eid, 0, 0, 0, nil, nil, nil);
}
- (void)failed:(NSError *)an_error
{
	/* our own Cancel (or a load replaced by the next) says nothing */
	if ([[an_error domain] isEqualToString:NSURLErrorDomain] && [an_error code] == NSURLErrorCancelled) return;
	if ([[an_error domain] isEqualToString:@"WebKitErrorDomain"] && [an_error code] == 102) return;   /* frame load interrupted by policy change */
	load_failed = YES;
	sb_push(SB_EVENT_LOADED, eid, 1, 0, 0, [an_error localizedDescription], nil, nil);
}
- (void)webView:(WKWebView *)w didFailNavigation:(WKNavigation *)n withError:(NSError *)an_error { (void)w; (void)n; [self failed:an_error]; }
- (void)webView:(WKWebView *)w didFailProvisionalNavigation:(WKNavigation *)n withError:(NSError *)an_error { (void)w; (void)n; [self failed:an_error]; }
/* Nothing opens a window on its own (section 4.5). A target=_blank link was refused and reported
   by the navigation action above, so it never gets here; window.open comes here directly. */
- (WKWebView *)webView:(WKWebView *)w createWebViewWithConfiguration:(WKWebViewConfiguration *)c
	forNavigationAction:(WKNavigationAction *)an_action windowFeatures:(WKWindowFeatures *)f
{
	(void)w; (void)c; (void)f;
	sb_push(SB_EVENT_NEW_WINDOW, eid, 0, 0, 0, sb_url_text([[an_action request] URL]), nil, nil);
	return nil;
}

/* ---- tests: the echo page (`test_echo_at') */
- (BOOL)echoes:(NSURLRequest *)a_request
{
	return [echo_url length] && [[[a_request URL] absoluteString] isEqualToString:echo_url];
}
/* The request's method, a line break, then its body, in element `echo' of a page at its URL (the
   request itself is refused: the reserved name never reaches the network). */
- (void)echo:(NSURLRequest *)a_request
{
	NSString *l_body = [a_request HTTPBody] ? [[NSString alloc] initWithData:[a_request HTTPBody] encoding:NSUTF8StringEncoding] : @"";
	NSString *l_text = [NSString stringWithFormat:@"%@\n%@", [a_request HTTPMethod] ?: @"GET", l_body ?: @""];
	l_text = [[[l_text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
		stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
	pass_next = YES;
	[view loadHTMLString:[NSString stringWithFormat:@"<!DOCTYPE html><html><body><pre id=\"echo\">%@</pre></body></html>", l_text] baseURL:[a_request URL]];
}

/* ---- the title, by notification (section 4.7) */
- (void)observeValueForKeyPath:(NSString *)p ofObject:(id)o change:(NSDictionary *)ch context:(void *)ctx
{
	(void)p; (void)o; (void)ch; (void)ctx;
	sb_push(SB_EVENT_TITLE, eid, 0, 0, 0, [view title] ?: @"", nil, nil);
}

/* ---- the window's close button: the loop ends; the window stays until `sb_destroy' */
- (BOOL)windowShouldClose:(NSWindow *)w { (void)w; sb_push(SB_EVENT_CLOSED, eid, 0, 0, 0, nil, nil, nil); return NO; }
@end

int sb_create(void *a_parent, int a_ephemeral, int a_debug)
{
	if (!pthread_main_np()) return 0;
	sb_app();
	int l_id = 0;
	for (int i = 1; i <= SB_MAX_ENGINES && !l_id; i++) if (!s_engines[i]) l_id = i;
	if (!l_id) return 0;
	SBEngine *e = [[SBEngine alloc] init];
	e->eid = l_id;
	e->scripts = [NSMutableArray array];
	e->bound = [NSMutableArray array];
	e->binding_script = [NSMutableDictionary dictionary];
	e->held = [NSMutableDictionary dictionary];
	e->held_request = [NSMutableDictionary dictionary];
	WKWebViewConfiguration *k = [[WKWebViewConfiguration alloc] init];
	/* window.open from a script reaches the navigation delegate, to be reported and refused
	   (section 4.5); without this WebKit drops it silently unless a click started it */
	[[k preferences] setJavaScriptCanOpenWindowsAutomatically:YES];
	[k setWebsiteDataStore:a_ephemeral ? [WKWebsiteDataStore nonPersistentDataStore] : [WKWebsiteDataStore defaultDataStore]];
	SBMessageProxy *l_proxy = [[SBMessageProxy alloc] init];
	l_proxy->engine = e;
	[[k userContentController] addScriptMessageHandler:l_proxy contentWorld:[WKContentWorld pageWorld] name:@"sb"];
	e->view = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600) configuration:k];
	[e->view setNavigationDelegate:e];
	[e->view setUIDelegate:e];
	if (a_debug && [e->view respondsToSelector:@selector(setInspectable:)]) [e->view setInspectable:YES];
	[e->view addObserver:e forKeyPath:@"title" options:NSKeyValueObservingOptionNew context:NULL];
	if (a_parent) {
		id p = (__bridge id)a_parent;
		NSView *l_parent = [p isKindOfClass:[NSWindow class]] ? [(NSWindow *)p contentView] : ([p isKindOfClass:[NSView class]] ? p : nil);
		if (!l_parent) { [e->view removeObserver:e forKeyPath:@"title"]; return 0; }
		[e->view setTranslatesAutoresizingMaskIntoConstraints:NO];
		[l_parent addSubview:e->view];
		[NSLayoutConstraint activateConstraints:@[
			[e->view.leadingAnchor constraintEqualToAnchor:l_parent.leadingAnchor],
			[e->view.trailingAnchor constraintEqualToAnchor:l_parent.trailingAnchor],
			[e->view.topAnchor constraintEqualToAnchor:l_parent.topAnchor],
			[e->view.bottomAnchor constraintEqualToAnchor:l_parent.bottomAnchor]]];
	} else {
		e->window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
			styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
			backing:NSBackingStoreBuffered defer:NO];
		[e->window setReleasedWhenClosed:NO];
		[e->window setDelegate:e];
		[e->window setContentView:e->view];
		[e->window center];
	}
	s_engines[l_id] = e;
	return l_id;
}

void sb_destroy(int an_id)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	/* WebKit requires every held decision to be answered */
	for (NSNumber *k in [e->held allKeys]) e->held[k](WKNavigationActionPolicyCancel);
	[e->held removeAllObjects];
	[e->held_request removeAllObjects];
	[e->view removeObserver:e forKeyPath:@"title"];
	[e->view stopLoading];
	[e->view setNavigationDelegate:nil];
	[e->view setUIDelegate:nil];
	[[[e->view configuration] userContentController] removeAllScriptMessageHandlers];
	if (e->window) { [e->window setDelegate:nil]; [e->window orderOut:nil]; [e->window close]; }
	else [e->view removeFromSuperview];
	/* events still queued for it go nowhere */
	NSIndexSet *l_its = [s_queue indexesOfObjectsPassingTest:^BOOL(SBEvent *x, NSUInteger i, BOOL *stop) { (void)i; (void)stop; return x->engine == an_id; }];
	[s_queue removeObjectsAtIndexes:l_its];
	s_engines[an_id] = nil;
}

void *sb_window(int an_id)
{
	SBEngine *e = sb_engine(an_id);
	return e ? (__bridge void *)(e->window ?: (id)e->view) : NULL;
}

/* ---------------------------------------------------------------- the window */

void sb_set_title(int an_id, const char *a_title) { SBEngine *e = sb_engine(an_id); if (e->window) [e->window setTitle:sb_string(a_title)]; }

/* Sizes in points (logical pixels), as Windows' DPI-aware ones: 0 none, 1 min, 2 max, 3 fixed. */
void sb_set_size(int an_id, int a_width, int a_height, int a_hint)
{
	SBEngine *e = sb_engine(an_id);
	if (!e || !e->window) return;
	NSSize s = NSMakeSize(a_width, a_height);
	NSWindowStyleMask m = [e->window styleMask];
	if (a_hint == 0 && e->fixed) return;   /* a fixed size holds against a plain set_size */
	if (a_hint == 1 || a_hint == 2) {
		/* a limit ends a fixed size: the window can be resized again */
		e->fixed = NO;
		if (!(m & NSWindowStyleMaskResizable)) { m |= NSWindowStyleMaskResizable; [e->window setStyleMask:m]; }
	}
	switch (a_hint) {
		case 1: case 2: {
			/* a new limit applies to the window now, not only to the user's next drag */
			NSSize l_now = [[e->window contentView] frame].size;
			if (a_hint == 1) { [e->window setContentMinSize:s]; l_now.width = MAX(l_now.width, s.width); l_now.height = MAX(l_now.height, s.height); }
			else { [e->window setContentMaxSize:s]; l_now.width = MIN(l_now.width, s.width); l_now.height = MIN(l_now.height, s.height); }
			[e->window setContentSize:l_now];
			break;
		}
		case 3:
			e->fixed = YES;
			[e->window setStyleMask:m & ~NSWindowStyleMaskResizable];
			[e->window setContentMinSize:NSMakeSize(0, 0)];
			[e->window setContentMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
			[e->window setContentSize:s];
			break;
		default: {
			/* the window's own limits hold against the program as against the user */
			NSSize l_min = [e->window contentMinSize], l_max = [e->window contentMaxSize];
			s.width = MAX(s.width, l_min.width); s.height = MAX(s.height, l_min.height);
			if (l_max.width > 0) s.width = MIN(s.width, l_max.width);
			if (l_max.height > 0) s.height = MIN(s.height, l_max.height);
			if (!(m & NSWindowStyleMaskResizable)) [e->window setStyleMask:m | NSWindowStyleMaskResizable];
			[e->window setContentSize:s];
			break;
		}
	}
}

/* Shown, not made key: the person at the keyboard decides what comes forward. */
void sb_show(int an_id) { SBEngine *e = sb_engine(an_id); if (e->window) [e->window orderFront:nil]; }

/* ---------------------------------------------------------------- loading */

void sb_navigate(int an_id, const char *a_url)
{
	SBEngine *e = sb_engine(an_id);
	NSURL *u = [NSURL URLWithString:sb_string(a_url)];
	if (!e || !u) return;
	e->pass_next = YES;   /* the program's own load is not asked (section 4.4) */
	[e->view loadRequest:[NSURLRequest requestWithURL:u]];
}

void sb_set_html(int an_id, const char *a_html, const char *a_base_url)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	NSString *l_base = sb_string(a_base_url);
	e->pass_next = YES;
	[e->view loadHTMLString:sb_string(a_html) baseURL:[l_base length] ? [NSURL URLWithString:l_base] : nil];
}

/* ---------------------------------------------------------------- scripts */

void sb_eval(int an_id, const char *a_script)
{
	SBEngine *e = sb_engine(an_id);
	if (e) [e->view evaluateJavaScript:sb_string(a_script) completionHandler:nil];
}

void sb_add_script(int an_id, const char *a_script)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	[e->scripts addObject:sb_string(a_script)];
	[e rebuildScripts];
}

void sb_set_bridge(int an_id, const char *a_script)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	e->bridge = sb_string(a_script);
	[e rebuildScripts];
	[e->view evaluateJavaScript:e->bridge completionHandler:nil];   /* the page shown now too */
}

void sb_bind(int an_id, const char *a_name, const char *a_script)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	NSString *n = sb_string(a_name), *s = sb_string(a_script);
	if (![e->bound containsObject:n]) [e->bound addObject:n];
	e->binding_script[n] = s;
	[e rebuildScripts];
	[e->view evaluateJavaScript:s completionHandler:nil];
}

void sb_unbind(int an_id, const char *a_name)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	NSString *n = sb_string(a_name);
	[e->bound removeObject:n];
	[e->binding_script removeObjectForKey:n];
	[e rebuildScripts];
	[e->view evaluateJavaScript:[NSString stringWithFormat:@"delete window[%@];", sb_json_string(n)] completionHandler:nil];
}

/* `a_json' is valid JSON text: shared code checked it (section 4.3). */
void sb_answer(int an_id, const char *a_seq, int a_status, const char *a_json)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	NSString *l_js = [NSString stringWithFormat:@"window.__sb.answer(%@, %d, %@);", sb_json_string(sb_string(a_seq)), a_status, sb_string(a_json)];
	[e->view evaluateJavaScript:l_js completionHandler:nil];
}

/* `a_body' is shared code's wrapper with the program's expression in it: a function body that
   returns the result as JSON text (section 4.2). */
void sb_evaluate(int an_id, int a_ticket, const char *a_body)
{
	SBEngine *e = sb_engine(an_id);
	if (!e) return;
	int l_engine = an_id;
	[e->view callAsyncJavaScript:sb_string(a_body) arguments:nil inFrame:nil inContentWorld:[WKContentWorld pageWorld]
		completionHandler:^(id a_result, NSError *an_error) {
			if (an_error) {
				NSString *l_message = an_error.userInfo[@"WKJavaScriptExceptionMessage"] ?: [an_error localizedDescription];
				sb_push(SB_EVENT_EVALUATED, l_engine, a_ticket, 1, 0, sb_json_string(l_message), nil, nil);
			} else
				sb_push(SB_EVENT_EVALUATED, l_engine, a_ticket, 0, 0, [a_result isKindOfClass:[NSString class]] ? a_result : @"null", nil, nil);
		}];
}

/* ---------------------------------------------------------------- navigation decisions */

void sb_test_echo_at(int an_id, const char *a_url) { SBEngine *e = sb_engine(an_id); if (e) e->echo_url = sb_string(a_url); }

void sb_set_deciding(int an_id, int a_on) { SBEngine *e = sb_engine(an_id); if (e) e->deciding = a_on != 0; }

void sb_decide(int an_id, int a_decision, int a_allow)
{
	SBEngine *e = sb_engine(an_id);
	void (^h)(WKNavigationActionPolicy) = e ? e->held[@(a_decision)] : nil;
	if (!h) return;
	NSURLRequest *r = e->held_request[@(a_decision)];
	[e->held removeObjectForKey:@(a_decision)];
	[e->held_request removeObjectForKey:@(a_decision)];
	if (a_allow && r && [e echoes:r]) { h(WKNavigationActionPolicyCancel); [e echo:r]; return; }
	h(a_allow ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}

/* ---------------------------------------------------------------- the loop */

static int sb_handle_one(NSDate *an_until)
{
	@autoreleasepool {
		NSEvent *n = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:an_until inMode:NSDefaultRunLoopMode dequeue:YES];
		if (!n) return 0;
		[NSApp sendEvent:n];
	}
	return 1;
}

int sb_pump(int a_ms)
{
	sb_app();
	if (s_pump_depth++ == 0) { objc_autoreleasePoolPop(s_outer_pool); s_outer_pool = objc_autoreleasePoolPush(); }
	NSDate *l_until = [NSDate dateWithTimeIntervalSinceNow:MAX(a_ms, 0) / 1000.0];
	while ([s_queue count] == 0 && [l_until timeIntervalSinceNow] > 0) if (!sb_handle_one(l_until)) break;
	while (sb_handle_one([NSDate distantPast])) {}   /* what is already waiting goes through too */
	s_pump_depth--;
	return [s_queue count] > 0 ? 1 : 0;
}

static int sb_take(NSUInteger i, int *a_kind, int *an_engine, int *a, int *b, int *c);

int sb_next(int *a_kind, int *an_engine, int *a, int *b, int *c)
{
	return [s_queue count] > 0 ? sb_take(0, a_kind, an_engine, a, b, c) : 0;
}

/* The oldest event of engine `e' (each engine's loop takes its own; two browsers in one process
   don't take each other's). */
int sb_next_for(int an_engine, int *a_kind, int *a, int *b, int *c)
{
	int l_engine;
	for (NSUInteger i = 0; i < [s_queue count]; i++)
		if (s_queue[i]->engine == an_engine) return sb_take(i, a_kind, &l_engine, a, b, c);
	return 0;
}

static int sb_take(NSUInteger i, int *a_kind, int *an_engine, int *a, int *b, int *c)
{
	SBEvent *e = s_queue[i];
	[s_queue removeObjectAtIndex:i];
	*a_kind = e->kind; *an_engine = e->engine; *a = e->a; *b = e->b; *c = e->c;
	for (int i = 0; i < 3; i++) {
		NSMutableData *d = [[e->text[i] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy] ?: [NSMutableData data];
		[d appendBytes:"" length:1];
		s_current[i] = d;
	}
	return 1;
}

const char *sb_text(int i) { return i >= 1 && i <= 3 && s_current[i - 1] ? (const char *)[s_current[i - 1] bytes] : ""; }
int sb_text_length(int i) { return i >= 1 && i <= 3 && s_current[i - 1] ? (int)[s_current[i - 1] length] - 1 : 0; }

/* The program ends its loop (SIMPLE_BROWSER.close): no event (`closed' is the user's), only a wake,
   so a pump waiting for one returns at once. */
void sb_terminate(int an_id)
{
	if (!sb_engine(an_id)) return;
	NSEvent *n = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
		modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
	[NSApp postEvent:n atStart:NO];
}

/* ---------------------------------------------------------------- tests */

/* This engine's window, if on screen, and any other window on screen holding a web view no engine
   made (one WebKit opened by itself): a new-window request must never add one. Other engines'
   windows don't count. */
static BOOL sb_holds_web_view(NSView *v)
{
	NSMutableArray<NSView *> *q = [NSMutableArray arrayWithObject:v ?: [[NSView alloc] init]];
	while ([q count]) { NSView *x = q[0]; [q removeObjectAtIndex:0]; if ([x isKindOfClass:[WKWebView class]]) return YES; [q addObjectsFromArray:[x subviews]]; }
	return NO;
}
int sb_test_window_count(int an_id)
{
	SBEngine *e = sb_engine(an_id);
	int n = 0;
	for (NSWindow *w in [NSApp windows]) {
		if (![w isVisible] || !sb_holds_web_view([w contentView])) continue;
		BOOL l_ours = NO, l_this = NO;
		for (int i = 1; i <= SB_MAX_ENGINES; i++)
			if (s_engines[i] && (s_engines[i]->window == w || [s_engines[i]->view window] == w)) { l_ours = YES; if (i == an_id) l_this = YES; }
		if (l_this || !l_ours) n++;
	}
	(void)e;
	return n;
}
int sb_test_content_width(int an_id) { SBEngine *e = sb_engine(an_id); return e ? (int)lround(NSWidth([e->view bounds])) : 0; }
int sb_test_content_height(int an_id) { SBEngine *e = sb_engine(an_id); return e ? (int)lround(NSHeight([e->view bounds])) : 0; }
int sb_test_is_resizable(int an_id) { SBEngine *e = sb_engine(an_id); return e && e->window && ([e->window styleMask] & NSWindowStyleMaskResizable) ? 1 : 0; }
