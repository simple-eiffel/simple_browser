# 7S-02: STANDARDS

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Applicable Standards

### Browser Engine

1. **WebView2 (Windows)**
   - Microsoft Edge Chromium-based
   - Documentation: https://docs.microsoft.com/microsoft-edge/webview2/
   - Requires WebView2 Runtime

2. **webview/webview C Library**
   - GitHub: https://github.com/webview/webview
   - Cross-platform wrapper (WebView2/WebKit/GTK)
   - C API with callback support

### Web Standards

1. **HTML5**: Full HTML5 support via Chromium
2. **CSS3**: Complete CSS3 implementation
3. **JavaScript/ECMAScript**: ES2020+
4. **DOM API**: Standard DOM manipulation

### Integration Standards

1. **HTMX**: AJAX-style interactions
   - CDN: https://unpkg.com/htmx.org@2
   - Attributes: hx-get, hx-post, hx-trigger, etc.

2. **Alpine.js**: Lightweight reactivity
   - CDN: https://unpkg.com/alpinejs@3
   - Directives: x-data, x-show, x-on, etc.

### API Patterns

1. **JavaScript Bindings**
   - Name → Eiffel callback mapping
   - Async Promise resolution
   - JSON argument passing
   - Sequence ID for response correlation

2. **Window Configuration**
   - Size hints: none, min, max, fixed
   - Title setting
   - Debug mode (DevTools)

## webview API Reference

| Function | Purpose |
|----------|---------|
| webview_create | Create webview instance |
| webview_destroy | Clean up resources |
| webview_run | Start event loop |
| webview_terminate | Stop event loop |
| webview_navigate | Load URL |
| webview_set_html | Set HTML content |
| webview_set_title | Set window title |
| webview_set_size | Set window size |
| webview_init | Inject JavaScript on load |
| webview_eval | Execute JavaScript |
| webview_bind | Bind native function |
| webview_return | Return value to JS |
