# 7S-04: SIMPLE-STAR INTEGRATION

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Ecosystem Dependencies

### External Libraries

1. **webview/webview**
   - Purpose: Cross-platform browser embedding
   - Type: C library with header
   - Files: webview_wrapper.h

2. **WebView2 Runtime**
   - Purpose: Microsoft Edge rendering
   - Type: System component
   - Distribution: Usually pre-installed on Windows 11

### No simple_* Dependencies

simple_browser has no dependencies on other simple_* libraries in core functionality.

## Libraries Using simple_browser

1. **simple_htmx applications**
   - Uses: load_htmx_page for HTMX+Alpine UI
   - Pattern: Generate HTML server-side, render in browser

2. **simple_alpine applications**
   - Uses: Alpine.js reactive UI in desktop context
   - Pattern: Client-side reactivity via JavaScript

3. **simple_vision applications**
   - Uses: SB_WIDGET for embedding in vision windows
   - Pattern: Browser as child widget

## Integration Patterns

### HTMX Desktop App

```eiffel
create browser.make
browser.titled ("My HTMX App")
       .size (1024, 768)
       .load_htmx_page (html_with_htmx_attributes)
browser.run
```

### JavaScript Bindings

```eiffel
browser.on_call ("eiffel_save", agent handle_save)
-- JavaScript: await window.eiffel_save({data: "test"})
```

### simple_http Integration

```eiffel
-- Browser makes HTMX requests to local server
server.handle_get ("/api/data", agent handle_data)
browser.navigate ("http://localhost:8080/")
```

## Namespace Conventions

- SIMPLE_BROWSER: Main facade
- BROWSER_ENGINE: Deferred interface
- WEBVIEW_ENGINE: WebView2 implementation
- SB_*: Vision widget integration
