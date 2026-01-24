# S05: CONSTRAINTS

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Technical Constraints

### Platform Constraints
- **Windows 10/11**: WebView2 required
- WebView2 Runtime must be installed
- Edge Chromium provides rendering

### Threading Constraints
- `run` is blocking (event loop)
- For non-blocking: use SCOOP processor
- Callbacks execute on main thread

### Memory Constraints
- WebView2 uses separate process
- ~100MB+ memory overhead
- Each browser instance adds overhead

### JavaScript Binding Constraints
- Bindings must be registered before page load for init access
- Callback receives JSON string (not parsed)
- Must respond to complete Promise
- Sequence ID must match for correct response

## API Constraints

### Fluent Methods
- Return `like Current` for chaining
- All return same instance
- State mutations apply immediately

### HTML Content
- No automatic escaping
- Application responsible for XSS prevention
- UTF-8 encoding required

### URL Navigation
- Supports standard protocols
- No URL validation
- file:// has local access

### Size Configuration
| Hint | Effect |
|------|--------|
| Size_hint_none | Resizable, specified default |
| Size_hint_min | Minimum size constraint |
| Size_hint_max | Maximum size constraint |
| Size_hint_fixed | Non-resizable |

## WebView2 Constraints

### Runtime Requirements
- WebView2 Runtime (usually pre-installed W11)
- Falls back to Edge installation
- Must be present at launch

### Feature Limitations
- No download management API
- No print API exposed
- DevTools always enabled (stability)
- Cookie management not exposed

## Error Handling

### Initialization Errors
- `is_valid` returns False
- `last_error` contains message
- Check before operations

### Runtime Errors
- JavaScript errors in console
- Binding errors via respond_error
- No exception propagation from JS
