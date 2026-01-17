note
	description: "[
		BROWSER_ENGINE - Abstract interface for browser implementations.

		This deferred class defines the contract for all browser backends.
		Current implementations:
		- WEBVIEW_ENGINE: Uses webview/webview C library (WebView2 on Windows)

		Future potential backends:
		- ULTRALIGHT_ENGINE: Ultralight HTML renderer
		- SCITER_ENGINE: Sciter embeddable HTML engine

		The abstraction allows switching browser backends without changing
		application code that uses SIMPLE_BROWSER facade.
	]"
	author: "Larry Rix"
	date: "$Date$"

deferred class
	BROWSER_ENGINE

inherit
	SB_ANY

feature -- Status

	is_ready: BOOLEAN
			-- Is the browser engine initialized and ready?
		deferred
		end

	last_error: detachable STRING_32
			-- Last error message, if any.
		deferred
		end

feature -- Window Access

	window_handle: POINTER
			-- Native window handle (HWND on Windows).
			-- Use for embedding in parent windows.
		deferred
		end

feature -- Navigation

	navigate (a_url: READABLE_STRING_GENERAL)
			-- Navigate to URL.
			-- Supports http://, https://, file://, and data: URLs.
		require
			ready: is_ready
			url_not_empty: not a_url.is_empty
		deferred
		end

	set_html (a_html: READABLE_STRING_GENERAL)
			-- Set HTML content directly.
			-- Replaces current page with provided HTML.
		require
			ready: is_ready
		deferred
		end

feature -- Window Configuration

	set_title (a_title: READABLE_STRING_GENERAL)
			-- Set window title.
		require
			ready: is_ready
		deferred
		end

	set_size (a_width, a_height: INTEGER; a_hints: INTEGER)
			-- Set window size with hints.
			-- Use Size_hint_* constants for `a_hints`.
		require
			ready: is_ready
			valid_width: a_width > 0
			valid_height: a_height > 0
			valid_hints: a_hints >= Size_hint_none and a_hints <= Size_hint_fixed
		deferred
		end

feature -- JavaScript Execution

	eval_js (a_script: READABLE_STRING_GENERAL)
			-- Execute JavaScript code immediately.
			-- Result is discarded; use bindings for return values.
		require
			ready: is_ready
		deferred
		end

	init_js (a_script: READABLE_STRING_GENERAL)
			-- Inject JavaScript to run on every page load.
			-- Called before window.onload.
		require
			ready: is_ready
		deferred
		end

feature -- JavaScript Bindings

	bind (a_name: READABLE_STRING_GENERAL; a_callback: PROCEDURE [TUPLE [seq: STRING_8; req: STRING_8]])
			-- Bind native function callable from JavaScript.
			-- JavaScript: await window.`a_name`(args...) returns Promise.
			-- Callback receives (sequence_id, json_args).
			-- Must call `return_value` or `return_error` with sequence_id.
		require
			ready: is_ready
			name_not_empty: not a_name.is_empty
			callback_attached: a_callback /= Void
		deferred
		end

	unbind (a_name: READABLE_STRING_GENERAL)
			-- Remove JavaScript binding.
		require
			ready: is_ready
		deferred
		end

	return_value (a_seq: STRING_8; a_status: INTEGER; a_result: STRING_8)
			-- Return value to JavaScript caller.
			-- `a_seq`: Sequence ID from callback.
			-- `a_status`: 0 for success, non-zero for error.
			-- `a_result`: JSON-encoded result.
		require
			ready: is_ready
			seq_not_empty: not a_seq.is_empty
		deferred
		end

feature -- Lifecycle

	run
			-- Run the browser event loop (blocking).
			-- Returns when window is closed or `terminate` is called.
			-- For non-blocking operation, run in SCOOP processor.
		require
			ready: is_ready
		deferred
		end

	terminate
			-- Stop the browser event loop.
			-- Causes `run` to return.
		deferred
		end

	dispose
			-- Release all resources.
			-- Engine becomes unusable after this call.
		deferred
		ensure
			not_ready: not is_ready
		end

feature -- Size Hint Constants

	Size_hint_none: INTEGER = 0
			-- No size constraints.

	Size_hint_min: INTEGER = 1
			-- Minimum size constraint.

	Size_hint_max: INTEGER = 2
			-- Maximum size constraint.

	Size_hint_fixed: INTEGER = 3
			-- Fixed size (non-resizable).

end
