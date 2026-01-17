note
	description: "[
		SIMPLE_BROWSER - Main facade for embedded browser functionality.

		Provides a fluent API for browser operations:
		- Navigation (URL and HTML content)
		- Window configuration (title, size)
		- JavaScript execution and bindings
		- Lifecycle management

		Example usage:
			create browser.make
			browser.titled ("My App")
			       .size (1024, 768)
			       .navigate ("https://example.com")
			browser.run

		For HTMX/Alpine integration:
			browser.load_htmx_page ("<div x-data='{ count: 0 }'>...</div>")

		Threading:
			The `run` method blocks. For non-blocking operation:
			- Use SCOOP processor
			- Or use with simple_vision widget (SB_WIDGET)
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SIMPLE_BROWSER

inherit
	SB_ANY

create
	make,
	make_with_engine

feature {NONE} -- Initialization

	make
			-- Create with default WEBVIEW_ENGINE.
		local
			l_engine: WEBVIEW_ENGINE
		do
			create l_engine.make
			engine := l_engine
			if not l_engine.is_ready then
				last_error := l_engine.last_error
			end
		ensure
			engine_set: engine /= Void
		end

	make_with_engine (an_engine: BROWSER_ENGINE)
			-- Create with custom engine (for testing or alternative backends).
		require
			engine_not_void: an_engine /= Void
		do
			engine := an_engine
		ensure
			engine_set: engine = an_engine
		end

feature -- Status

	is_valid: BOOLEAN
			-- Is the browser ready for use?
		do
			Result := engine.is_ready
		end

	last_error: detachable STRING_32
			-- Last error message.

feature -- Access

	engine: BROWSER_ENGINE
			-- Underlying browser engine.

feature -- Navigation Commands

	navigate_to (a_url: READABLE_STRING_GENERAL)
			-- Navigate to URL (procedure).
		require
			valid: is_valid
		do
			engine.navigate (a_url)
		end

	set_html_content (a_html: READABLE_STRING_GENERAL)
			-- Set HTML content (procedure).
		require
			valid: is_valid
		do
			engine.set_html (a_html)
		end

	load_htmx_page (a_body_html: READABLE_STRING_GENERAL)
			-- Load HTML with HTMX and Alpine.js CDN scripts injected.
		require
			valid: is_valid
		local
			l_full_html: STRING_32
		do
			create l_full_html.make (a_body_html.count + 600)
			l_full_html.append ("<!DOCTYPE html>%N<html>%N<head>%N")
			l_full_html.append ("<meta charset=%"UTF-8%">%N")
			l_full_html.append ("<script src=%"https://unpkg.com/htmx.org@2%"></script>%N")
			l_full_html.append ("<script defer src=%"https://unpkg.com/alpinejs@3%"></script>%N")
			l_full_html.append ("</head>%N<body>%N")
			l_full_html.append (a_body_html.to_string_32)
			l_full_html.append ("%N</body>%N</html>")
			engine.set_html (l_full_html)
		end

feature -- Navigation Fluent

	navigate (a_url: READABLE_STRING_GENERAL): like Current
			-- Navigate to URL (fluent).
		require
			valid: is_valid
		do
			navigate_to (a_url)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	with_html (a_html: READABLE_STRING_GENERAL): like Current
			-- Set HTML content (fluent).
		require
			valid: is_valid
		do
			set_html_content (a_html)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	with_htmx (a_body_html: READABLE_STRING_GENERAL): like Current
			-- Load HTMX/Alpine page (fluent).
		require
			valid: is_valid
		do
			load_htmx_page (a_body_html)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

feature -- Window Configuration Commands

	set_title (a_title: READABLE_STRING_GENERAL)
			-- Set window title (procedure).
		do
			engine.set_title (a_title)
		end

	set_size (a_width, a_height: INTEGER)
			-- Set window size (procedure).
		do
			engine.set_size (a_width, a_height, engine.Size_hint_none)
		end

	set_min_size (a_width, a_height: INTEGER)
			-- Set minimum window size.
		do
			engine.set_size (a_width, a_height, engine.Size_hint_min)
		end

	set_max_size (a_width, a_height: INTEGER)
			-- Set maximum window size.
		do
			engine.set_size (a_width, a_height, engine.Size_hint_max)
		end

	set_fixed_size (a_width, a_height: INTEGER)
			-- Set fixed window size (non-resizable).
		do
			engine.set_size (a_width, a_height, engine.Size_hint_fixed)
		end

feature -- Window Configuration Fluent

	titled (a_title: READABLE_STRING_GENERAL): like Current
			-- Set window title (fluent).
		do
			set_title (a_title)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	size (a_width, a_height: INTEGER): like Current
			-- Set window size (fluent).
		do
			set_size (a_width, a_height)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	min_size (a_width, a_height: INTEGER): like Current
			-- Set minimum size (fluent).
		do
			set_min_size (a_width, a_height)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	fixed_size (a_width, a_height: INTEGER): like Current
			-- Set fixed size (fluent).
		do
			set_fixed_size (a_width, a_height)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

feature -- JavaScript Commands

	eval (a_script: READABLE_STRING_GENERAL)
			-- Execute JavaScript immediately.
		require
			valid: is_valid
		do
			engine.eval_js (a_script)
		end

	inject (a_script: READABLE_STRING_GENERAL)
			-- Inject JavaScript to run on every page load.
		require
			valid: is_valid
		do
			engine.init_js (a_script)
		end

feature -- JavaScript Bindings

	on_call (a_name: READABLE_STRING_GENERAL; a_handler: PROCEDURE [TUPLE [STRING_8, STRING_8]])
			-- Bind Eiffel procedure callable from JavaScript.
			-- Handler receives (sequence_id, json_args).
		require
			valid: is_valid
			name_not_empty: not a_name.is_empty
		do
			engine.bind (a_name, a_handler)
		end

	respond (a_seq: STRING_8; a_result: STRING_8)
			-- Send success result back to JavaScript caller.
		require
			valid: is_valid
		do
			engine.return_value (a_seq, 0, a_result)
		end

	respond_error (a_seq: STRING_8; a_error: STRING_8)
			-- Send error back to JavaScript caller.
		require
			valid: is_valid
		do
			engine.return_value (a_seq, 1, a_error)
		end

feature -- Lifecycle

	run
			-- Start browser event loop (blocking).
			-- Returns when window is closed.
		require
			valid: is_valid
		do
			engine.run
		end

	close
			-- Close browser window.
		do
			engine.terminate
		end

	dispose
			-- Release all resources.
		do
			engine.dispose
		end

feature -- Debug Control

	with_debug: like Current
			-- Enable debug mode (developer tools).
		do
			enable_debug_mode
			engine.set_debug_mode (True)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

invariant
	engine_exists: engine /= Void

end
