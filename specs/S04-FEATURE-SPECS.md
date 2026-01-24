# S04: FEATURE SPECIFICATIONS

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## SIMPLE_BROWSER Features

### navigate_to (url)
**Purpose**: Load URL in browser
**Behavior**: Delegates to engine.navigate
**Protocols**: http://, https://, file://, data:

### set_html_content (html)
**Purpose**: Set HTML content directly
**Behavior**: Delegates to engine.set_html
**Note**: Replaces current page

### load_htmx_page (body_html)
**Purpose**: Load HTML with HTMX+Alpine auto-injected
**Behavior**:
1. Creates full HTML document
2. Injects HTMX CDN: https://unpkg.com/htmx.org@2
3. Injects Alpine CDN: https://unpkg.com/alpinejs@3
4. Wraps body_html in proper structure
**Output**: Complete HTML page with frameworks

### set_title (title)
**Purpose**: Set window title
**Behavior**: Delegates to engine.set_title

### set_size (width, height)
**Purpose**: Set window dimensions
**Behavior**: Calls engine.set_size with Size_hint_none
**Variants**: set_min_size, set_max_size, set_fixed_size

### eval (script)
**Purpose**: Execute JavaScript immediately
**Behavior**: Delegates to engine.eval_js
**Note**: Result discarded, use bindings for returns

### inject (script)
**Purpose**: Inject JavaScript to run on every page load
**Behavior**: Delegates to engine.init_js
**Timing**: Before window.onload

### on_call (name, handler)
**Purpose**: Bind Eiffel procedure callable from JavaScript
**Behavior**:
1. Registers callback in engine
2. JavaScript: `await window.name(args)`
3. Handler receives (sequence_id, json_args)
**Usage**: Must call respond/respond_error with sequence_id

### respond (seq, result)
**Purpose**: Return success value to JavaScript caller
**Behavior**: Calls engine.return_value(seq, 0, result)
**Note**: result should be JSON-encoded

### respond_error (seq, error)
**Purpose**: Return error to JavaScript caller
**Behavior**: Calls engine.return_value(seq, 1, error)
**Effect**: Promise rejects in JavaScript

### run
**Purpose**: Start browser event loop
**Behavior**: Blocking call until window closed
**Note**: For non-blocking, use SCOOP processor

## WEBVIEW_ENGINE Features

### dispatch_callback (name, seq, req)
**Purpose**: C-to-Eiffel callback bridge
**Behavior**:
1. Looks up handler in callback_registry
2. Calls handler with (seq, req)
**Called From**: C trampoline function
