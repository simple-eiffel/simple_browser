# 7S-03: SOLUTIONS

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Existing Solutions Comparison

### Embedded Browser Solutions

| Solution | Pros | Cons |
|----------|------|------|
| Electron | Full Chromium, mature | Heavy (~150MB), JS-centric |
| CEF | Full Chromium features | Complex, large binary |
| Qt WebEngine | Qt integration | Heavy Qt dependency |
| WebView2 | Light, Edge-based | Windows only |
| webview/webview | Tiny, cross-platform | Limited features |

### GUI Frameworks

| Solution | Pros | Cons |
|----------|------|------|
| EiffelVision2 | Native Eiffel | No modern web tech |
| wxWidgets | Cross-platform | C++ wrapper needed |
| FLTK | Lightweight | Basic web support |

### Eiffel Ecosystem

- EiffelVision2: Native widgets, no web
- No embedded browser library before simple_browser

## Why Build simple_browser?

1. **Web-Based UI**: Use HTML/CSS/JS for desktop apps
2. **HTMX+Alpine**: Server-side rendering patterns
3. **Small Footprint**: webview is tiny vs Electron
4. **Eiffel Integration**: Native bindings to Eiffel
5. **Simple API**: Fluent interface, minimal setup

## Design Decisions

1. **webview/webview Foundation**
   - Smallest viable browser wrapper
   - Cross-platform potential
   - C API maps well to Eiffel externals

2. **Engine Abstraction**
   - BROWSER_ENGINE deferred class
   - WEBVIEW_ENGINE as default implementation
   - Allows future alternative backends

3. **Fluent API**
   - Method chaining for configuration
   - Clean, readable code
   - Example: `browser.titled("App").size(800,600).navigate(url)`

4. **HTMX/Alpine Integration**
   - `load_htmx_page` auto-injects CDN scripts
   - Server-side rendering friendly
   - Modern reactive UI without framework overhead

5. **Callback Trampoline**
   - C-to-Eiffel callback via registry
   - Sequence ID for async Promise resolution
   - JSON argument passing
