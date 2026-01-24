# 7S-01: SCOPE

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Problem Domain

Embedded web browser functionality for Eiffel desktop applications. The library enables creating native windows with embedded browser rendering, supporting both URL navigation and direct HTML content with HTMX/Alpine.js integration.

## Target Users

1. **Desktop app developers** needing HTML-based UI
2. **HTMX/Alpine users** building reactive desktop apps
3. **Tool developers** displaying web content
4. **Dashboard builders** with web technologies
5. **Kiosk/display applications** showing web pages

## Primary Use Cases

1. Display web pages in native windows
2. Render local HTML content
3. Execute JavaScript in browser context
4. Bind Eiffel functions callable from JavaScript
5. Build desktop apps with HTMX+Alpine UI
6. Embed browser in existing windows

## Boundaries

### In Scope
- WebView2 browser engine (Windows)
- URL navigation
- HTML content rendering
- JavaScript execution (eval)
- JavaScript injection (init)
- Eiffel-to-JavaScript bindings
- Window configuration (title, size)
- HTMX/Alpine CDN auto-injection

### Out of Scope
- WebKit/Chromium on non-Windows (planned)
- Browser extensions
- DevTools (enabled for stability, not exposed)
- Download management
- Print functionality
- Cookie/storage management API

## Dependencies

- EiffelBase: Standard library
- webview/webview: C library (WebView2 wrapper)
- WebView2 Runtime: Microsoft Edge runtime
