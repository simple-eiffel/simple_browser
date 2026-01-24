# 7S-06: SIZING

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Implementation Size

### Class Count

| Category | Classes | LOC (approx) |
|----------|---------|--------------|
| Facade | 1 | 307 |
| Engine | 2 | 638 |
| Support | 1 | ~50 |
| Testing | 2 | ~100 |
| **Total** | **6** | **~1095** |

### Class Details

- SIMPLE_BROWSER: 307 lines (main facade)
- BROWSER_ENGINE: 174 lines (deferred interface)
- WEBVIEW_ENGINE: 464 lines (WebView2 implementation)
- SB_ANY: ~50 lines (debug support)

### External Code

- webview_wrapper.h: C header with callbacks
- webview library: Compiled C library

## Feature Count

### SIMPLE_BROWSER
| Category | Count |
|----------|-------|
| Navigation | 4 (navigate_to, set_html_content, load_htmx_page, navigate fluent) |
| Window Config | 5 (set_title, set_size, set_min_size, set_max_size, set_fixed_size) |
| JavaScript | 2 (eval, inject) |
| Bindings | 3 (on_call, respond, respond_error) |
| Lifecycle | 3 (run, close, dispose) |
| Fluent | 8 (titled, size, with_html, etc.) |

### BROWSER_ENGINE
| Category | Count |
|----------|-------|
| Navigation | 2 (navigate, set_html) |
| Window | 2 (set_title, set_size) |
| JavaScript | 2 (eval_js, init_js) |
| Bindings | 3 (bind, unbind, return_value) |
| Lifecycle | 3 (run, terminate, dispose) |
| Constants | 4 (size hints) |

## Complexity Assessment

| Feature | Complexity | Notes |
|---------|-----------|-------|
| Navigation | Low | Direct webview calls |
| Window config | Low | Direct webview calls |
| JavaScript exec | Low | Direct webview calls |
| Binding callbacks | High | C-Eiffel trampoline |
| HTMX injection | Low | String concatenation |

## Development Effort

| Phase | Effort | Status |
|-------|--------|--------|
| webview integration | 2 days | Complete |
| Facade design | 1 day | Complete |
| Callback trampoline | 2 days | Complete |
| Testing | 1 day | Complete |
| **Total** | **~6 days** | **Complete** |

## Runtime Requirements

- WebView2 Runtime: ~150MB on disk
- Process memory: ~100MB+ (Chromium overhead)
- Compile time: < 5 seconds
