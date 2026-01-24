# S01: PROJECT INVENTORY

**Library**: simple_browser
**Date**: 2026-01-23
**Status**: BACKWASH (reverse-engineered from implementation)

## Project Structure

```
simple_browser/
├── simple_browser.ecf          # Library configuration
├── src/
│   ├── core/
│   │   ├── simple_browser.e    # Main facade class
│   │   ├── browser_engine.e    # Deferred engine interface
│   │   ├── webview_engine.e    # WebView2 implementation
│   │   └── sb_any.e            # Debug mode support
│   └── vision/
│       └── sb_widget.e         # EiffelVision integration (optional)
├── lib/
│   ├── webview_wrapper.h       # C header with callbacks
│   └── webview.lib             # Compiled library (Windows)
├── testing/
│   ├── test_app.e              # Test application root
│   └── lib_tests.e             # Test suite
├── research/                   # This directory
└── specs/                      # Specification directory
```

## File Count Summary

| Category | Files |
|----------|-------|
| Core source | 4 |
| C library | 2 |
| Test files | 2 |
| Configuration | 1 |
| **Total** | **9** |

## External Dependencies

### C Libraries
- webview/webview (bundled)
- WebView2Loader.dll (Windows runtime)

### System Requirements
- Windows 10/11
- WebView2 Runtime (usually pre-installed)
- Edge Chromium (provides renderer)

### Optional
- EiffelVision2 (for SB_WIDGET)
