# S02: CLASS CATALOG

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Core Classes

### SIMPLE_BROWSER
**Purpose**: Main facade for browser operations
**Inherits**: SB_ANY
**Key Features**:
- `navigate_to (url)`, `navigate (url)`: Load URL
- `set_html_content (html)`, `with_html (html)`: Set HTML
- `load_htmx_page (body)`, `with_htmx (body)`: HTMX+Alpine page
- `set_title (title)`, `titled (title)`: Window title
- `set_size (w, h)`, `size (w, h)`: Window dimensions
- `set_min_size`, `set_max_size`, `set_fixed_size`: Size constraints
- `eval (script)`: Execute JavaScript
- `inject (script)`: Inject JavaScript on load
- `on_call (name, handler)`: Bind Eiffel callback
- `respond (seq, result)`: Return success to JS
- `respond_error (seq, error)`: Return error to JS
- `run`: Start event loop (blocking)
- `close`, `dispose`: Cleanup

### BROWSER_ENGINE (deferred)
**Purpose**: Abstract interface for browser implementations
**Inherits**: SB_ANY
**Key Features**:
- `is_ready`: Engine initialized?
- `last_error`: Error message
- `window_handle`: Native HWND
- `navigate (url)`: Load URL
- `set_html (html)`: Set content
- `set_title (title)`: Window title
- `set_size (w, h, hints)`: Dimensions with hints
- `eval_js (script)`: Execute JavaScript
- `init_js (script)`: Inject on load
- `bind (name, callback)`: Native binding
- `unbind (name)`: Remove binding
- `return_value (seq, status, result)`: JS return
- `run`, `terminate`, `dispose`: Lifecycle
- Size_hint_* constants: none, min, max, fixed

### WEBVIEW_ENGINE
**Purpose**: WebView2 implementation via webview/webview
**Inherits**: BROWSER_ENGINE
**Key Features**:
- All BROWSER_ENGINE features implemented
- `make`: Create standalone window
- `make_with_window (handle)`: Embed in parent
- `ctx`: Opaque webview pointer
- `callback_registry`: Binding storage
- `dispatch_callback`: C-to-Eiffel bridge
- Inline C externals for all webview functions

### SB_ANY
**Purpose**: Common ancestor with debug support
**Inherits**: ANY
**Key Features**:
- `is_debug_mode`: Debug flag
- `enable_debug_mode`: Enable DevTools
