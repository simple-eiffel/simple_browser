# S06: BOUNDARIES

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## System Boundaries

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Eiffel Application                          │
├─────────────────────────────────────────────────────────────────┤
│                       simple_browser                             │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              SIMPLE_BROWSER (facade)                     │   │
│  │  - Navigation methods                                    │   │
│  │  - Window configuration                                  │   │
│  │  - JavaScript bindings                                   │   │
│  └───────────────────────────┬─────────────────────────────┘   │
│                              │                                   │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │            BROWSER_ENGINE (deferred)                     │   │
│  └───────────────────────────┬─────────────────────────────┘   │
│                              │                                   │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │              WEBVIEW_ENGINE                              │   │
│  │  - Inline C externals                                    │   │
│  │  - Callback trampoline                                   │   │
│  └───────────────────────────┬─────────────────────────────┘   │
│                              │                                   │
└──────────────────────────────┼───────────────────────────────────┘
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│                   webview/webview (C)                            │
│              webview_wrapper.h + webview.lib                     │
└──────────────────────────────┼───────────────────────────────────┘
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│                    WebView2 Runtime                              │
│              (Microsoft Edge Chromium)                           │
└──────────────────────────────┼───────────────────────────────────┘
                               │
┌──────────────────────────────┼───────────────────────────────────┐
│                     Web Content                                  │
│        (HTML, CSS, JavaScript, HTMX, Alpine.js)                 │
└─────────────────────────────────────────────────────────────────┘
```

## Interface Boundaries

### Public API
- SIMPLE_BROWSER: Main facade
- BROWSER_ENGINE: Abstract interface
- WEBVIEW_ENGINE: Default implementation

### Internal
- C externals in WEBVIEW_ENGINE
- callback_registry: Once hash table
- dispatch_callback: C-Eiffel bridge

## Data Flow

### Navigation
```
URL/HTML → SIMPLE_BROWSER → WEBVIEW_ENGINE → webview C → WebView2 → Browser
```

### JavaScript Binding (Eiffel → JS)
```
respond(seq, result) → WEBVIEW_ENGINE → webview_return → WebView2 → Promise resolves
```

### JavaScript Binding (JS → Eiffel)
```
window.fn(args) → WebView2 → webview callback → C trampoline → dispatch_callback → Eiffel handler
```

## Integration Points

### simple_htmx/simple_alpine
- load_htmx_page injects frameworks
- HTML generation feeds content

### simple_http
- Local server for HTMX requests
- Browser navigates to localhost
