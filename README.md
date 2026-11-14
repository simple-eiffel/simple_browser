<p align="center">
  <img src="docs/images/logo.svg" alt="simple_browser logo" width="400">
</p>

# simple_browser

**[Documentation](https://simple-eiffel.github.io/simple_browser/)** | **[GitHub](https://github.com/simple-eiffel/simple_browser)**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Eiffel](https://img.shields.io/badge/Eiffel-25.02-blue.svg)](https://www.eiffel.org/)
[![Design by Contract](https://img.shields.io/badge/DbC-enforced-orange.svg)]()
![Windows: tests pass](https://img.shields.io/badge/Windows-tests%20pass-0078D6?logo=windows&logoColor=white) ![Linux and macOS: in progress](https://img.shields.io/badge/Linux%20%7C%20macOS-in%20progress-lightgrey)

A browser window for Eiffel programs: HTML, CSS and JavaScript interfaces, calls between the page
and Eiffel, htmx and Alpine.js bundled.

Part of the [Simple Eiffel](https://github.com/simple-eiffel) ecosystem.

## Status

**Development.** Windows (WebView2) passes the shared tests. macOS (WKWebView) and Linux (WebKitGTK 6.0)
engines are being written against the same contract (`BROWSER_ENGINE`) and the same tests.

## Engines

| Platform | Engine | Cluster |
|----------|--------|---------|
| Windows | `WEBVIEW_ENGINE`: webview.dll with WebView2, reached directly for what webview.dll lacks | `src/windows` |
| macOS | `APPKIT_ENGINE`: WKWebView | `src/macos` |
| Linux | `GTK_ENGINE`: WebKitGTK 6.0 on GTK 4 (needs the `libwebkitgtk-6.0-dev` package) | `src/linux` |

The ECF picks the cluster by platform; each has an `SB_PLATFORM` that makes its engine, so programs never
name an engine.

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

### A window

```eiffel
local
    browser: SIMPLE_BROWSER
do
    create browser.make
    browser.titled ("My App").size (1024, 768).navigate ("https://example.com").run
end
```

### Calls from the page

```eiffel
    browser.on_call ("add", agent on_add)   -- JavaScript: const sum = await window.add (1, 2)
    ...
on_add (a_seq, a_json_args: STRING_8)
    do
        browser.respond (a_seq, "3")          -- or respond_error (a_seq, "%"why%"")
    end
```

`respond` and `respond_error` check their text with simple_json: text that is not JSON rejects the call with
the parse error as a JSON string.

### Results, navigation, new windows, the title, loads

```eiffel
    browser.evaluate ("document.title", agent on_result)          -- on_result (ok: BOOLEAN; json: STRING_8)
    browser.on_navigation (agent allow)                            -- allow (n: SB_NAVIGATION): BOOLEAN
    browser.on_new_window (agent on_new_window)                    -- (url: STRING_32); nothing opens
    browser.on_title (agent on_title)                              -- (title: STRING_32)
    browser.on_loaded (agent on_loaded)                            -- (ok: BOOLEAN; error: STRING_32)
```

- `evaluate` takes one expression; promises are awaited; `undefined` gives `"null"`; a thrown error gives
  `ok` False and its message as a JSON string.
- `on_navigation` is asked about navigations the page starts, never about the program's own `navigate` and
  `set_html_content`.
- `make_ephemeral` keeps cookies, storage and cache in memory, gone with the browser (the tests use it).

### htmx and Alpine.js

```eiffel
    browser.load_htmx_page ("[
        <div x-data="{ count: 0 }">
            <button @click="count++">Count: <span x-text="count"></span></button>
        </div>
    ]")
```

`load_htmx_page` writes the bundled **htmx 2.0.4** inline in the page's head and the bundled
**Alpine.js 3.14.8** inline at the end of its body, so the page needs no network. A Content Security Policy
set by the page must allow inline scripts.

The files are in `assets/` with their licenses (`LICENSE-htmx`: Zero-Clause BSD; `LICENSE-alpinejs`: MIT).
`SB_BUNDLED_SCRIPTS` holds them as constants and is generated: after replacing a file in `assets/`, run
`python3 tools/generate_bundled_scripts.py` from the library's folder.

## The loop

`run` is an Eiffel loop: the engine's `pump` (a `blocking` external, so other SCOOP processors' garbage
collections never wait for the window), then every queued event, until the user closes the window or the
program calls `close`. The C side of every engine only queues events; it never calls Eiffel. Handlers run in
Eiffel, on the thread that made the browser.

## Windows notes

- WebView2's NavigationStarting takes no deferral, so a navigation the page starts is canceled at once and,
  if `on_navigation` allows it, started again with the same URL (a GET; a form's POST body is not replayed).
  Fragment-only navigations within a page are not reported by WebView2 and are not asked.
- `set_html_content` serves the page at `https://simple-browser.invalid/page-N` (a reserved name that never
  reaches the network) instead of webview.dll's data: URL, from which WebView2 cannot follow a link to
  `about:blank`.
- An ephemeral browser gets a fresh WebView2 user-data folder in the temporary directory, deleted on
  `dispose` (webview.dll makes the controller itself, without the options an InPrivate controller needs).

## Targets

| Target | Description |
|--------|-------------|
| `simple_browser` | The library |
| `simple_browser_web` | With simple_web, simple_htmx and simple_alpine |
| `lib_tests` | Test suite |

## Dependencies

- simple_json
- Windows: webview.dll (bundled in `lib/`) and the WebView2 runtime; WebView2.h (BSD, in `Clib/windows`)
- macOS: WebKit and Cocoa frameworks
- Linux: WebKitGTK 6.0

## License

MIT License - Copyright (c) 2024-2026, Larry Rix
