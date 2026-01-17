<p align="center">
  <img src="https://raw.githubusercontent.com/simple-eiffel/.github/main/profile/assets/logo.png" alt="simple_ library logo" width="400">
</p>

# simple_browser

**[Documentation](https://simple-eiffel.github.io/simple_browser/)** | **[GitHub](https://github.com/simple-eiffel/simple_browser)**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Eiffel](https://img.shields.io/badge/Eiffel-25.02-blue.svg)](https://www.eiffel.org/)
[![Design by Contract](https://img.shields.io/badge/DbC-enforced-orange.svg)]()

Embedded browser widget using webview/webview for Eiffel applications.

Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

**Development** - Core functionality with WebView2 backend on Windows

## Overview

SIMPLE_BROWSER provides embedded browser functionality for Eiffel applications using the webview library. Create desktop apps with HTML/CSS/JS interfaces, integrate with HTMX and Alpine.js, or build hybrid applications.

## Features

- **Embedded Browser** - Native WebView2 on Windows, WebKit on Linux/macOS
- **Fluent API** - Chainable configuration methods
- **JavaScript Bindings** - Call Eiffel from JavaScript and vice versa
- **HTMX/Alpine Ready** - Built-in support for modern web frameworks
- **Vision2 Widget** - Embeddable in simple_vision applications
- **Design by Contract** - Full preconditions, postconditions, invariants
- **Void Safe** - Fully void-safe implementation

## Installation

1. Set the ecosystem environment variable (one-time setup for all simple_* libraries):
```bash
export SIMPLE_EIFFEL=D:\prod
```

2. Add to your ECF:
```xml
<library name="simple_browser" location="$SIMPLE_EIFFEL/simple_browser/simple_browser.ecf"/>
```

## Quick Start

### Basic Browser Window

```eiffel
local
    browser: SIMPLE_BROWSER
do
    create browser.make
    browser.titled ("My App")
           .size (1024, 768)
           .navigate ("https://example.com")
    browser.run
end
```

### Load HTML Content

```eiffel
local
    browser: SIMPLE_BROWSER
do
    create browser.make
    browser.titled ("Dashboard")
           .size (800, 600)
           .load_html ("<h1>Hello from Eiffel!</h1>")
    browser.run
end
```

### HTMX/Alpine Integration

```eiffel
local
    browser: SIMPLE_BROWSER
do
    create browser.make
    browser.titled ("Interactive App")
           .load_htmx_page ("[
               <div x-data="{ count: 0 }">
                   <button @click="count++">Count: <span x-text="count"></span></button>
               </div>
           ]")
    browser.run
end
```

## API Reference

### SIMPLE_BROWSER

| Feature | Description |
|---------|-------------|
| `make` | Create browser with default WebView engine |
| `titled (name)` | Set window title (fluent) |
| `size (w, h)` | Set window size (fluent) |
| `navigate (url)` | Navigate to URL |
| `load_html (content)` | Load HTML content directly |
| `load_htmx_page (html)` | Load HTML with HTMX/Alpine includes |
| `run` | Run the browser event loop (blocking) |
| `eval (js)` | Execute JavaScript code |
| `bind (name, callback)` | Bind Eiffel callback to JavaScript |

## Targets

| Target | Description |
|--------|-------------|
| `simple_browser` | Core browser library |
| `simple_browser_vision` | Vision2 widget integration |
| `simple_browser_web` | Full stack with simple_web/htmx/alpine |
| `lib_tests` | Test suite |

## Dependencies

- simple_json
- webview library (bundled)
- WebView2 runtime (Windows)

## License

MIT License - Copyright (c) 2024-2025, Larry Rix
