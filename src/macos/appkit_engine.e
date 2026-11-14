note
	description: "[
		APPKIT_ENGINE - simple_browser's engine on macOS: a WKWebView in a window of its own, or
		filling a parent view (docs/SIMPLE_BROWSER_SPEC.md, section 2).

		The C side (Clib/macos/sb_appkit.m) never calls Eiffel: what the page and the toolkit say is
		queued, and the shared loop takes it with `next_event' after `pump' (section 4.1). Every text
		the page sees (the bridge, a binding's line, `evaluate''s wrapper) comes from shared code;
		this engine only places it.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	APPKIT_ENGINE

inherit
	BROWSER_ENGINE

create
	make,
	make_with_window

feature {NONE} -- Initialization

	make (a_ephemeral, a_debug: BOOLEAN)
			-- A browser in a window of its own; `a_ephemeral': an in-memory data store (4.6);
			-- `a_debug': Safari's Web Inspector can attach.
		require
			on_the_gui_thread: is_gui_thread
		do
			engine_id := c_create (default_pointer, a_ephemeral, a_debug)
		end

	make_with_window (a_parent: POINTER; a_ephemeral, a_debug: BOOLEAN)
			-- A browser filling `a_parent', an NSView (or an NSWindow: its content view).
		require
			on_the_gui_thread: is_gui_thread
			parent_given: a_parent /= default_pointer
		do
			engine_id := c_create (a_parent, a_ephemeral, a_debug)
		end

feature -- Status

	is_valid: BOOLEAN
			-- <Precursor>
		do
			Result := engine_id /= 0
		end

	is_deciding: BOOLEAN
			-- <Precursor>

	is_gui_thread: BOOLEAN
			-- Is this the main thread, the only one AppKit may be used from?
		external
			"C inline use %"sb_appkit.h%""
		alias
			"return (EIF_BOOLEAN) sb_is_gui_thread();"
		end

feature -- Window access

	window_handle: POINTER
			-- <Precursor>: the NSWindow, or the WKWebView when embedded.
		do
			Result := c_window (engine_id)
		end

feature -- Navigation

	navigate (a_url: READABLE_STRING_GENERAL)
			-- <Precursor>
		do
			c_navigate (engine_id, utf_8 (a_url).item)
		end

	set_html (a_html: READABLE_STRING_GENERAL)
			-- <Precursor>
		do
			c_set_html (engine_id, utf_8 (a_html).item, utf_8 (new_set_html_base).item)
		end

	set_html_with_base (a_html, a_base_url: READABLE_STRING_GENERAL)
			-- Tests: `a_html' with `a_base_url' as its origin.
		do
			c_set_html (engine_id, utf_8 (a_html).item, utf_8 (a_base_url).item)
		end

feature -- Window configuration

	set_title (a_title: READABLE_STRING_GENERAL)
			-- <Precursor>
		do
			c_set_title (engine_id, utf_8 (a_title).item)
		end

	set_size (a_width, a_height: INTEGER; a_hints: INTEGER)
			-- <Precursor>: points (logical pixels); a minimum or maximum also holds against later sizes.
		do
			c_set_size (engine_id, a_width, a_height, a_hints)
		end

	show
			-- Put the window on screen, without taking the keyboard focus from the user.
		do
			c_show (engine_id)
		end

feature -- Scripts

	eval_js (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
		do
			c_eval (engine_id, utf_8 (a_script).item)
		end

	init_js (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
		do
			c_add_script (engine_id, utf_8 (a_script).item)
		end

	set_bridge (a_script: READABLE_STRING_GENERAL)
			-- The shared bridge script (4.3): first at every document start, and on the page shown now.
		do
			c_set_bridge (engine_id, utf_8 (a_script).item)
		end

	bind_name (a_name, a_line: STRING_8)
			-- Binding `a_name', whose page-side line shared code wrote.
		do
			c_bind (engine_id, utf_8 (a_name).item, utf_8 (a_line).item)
		end

	unbind_name (a_name: STRING_8)
			-- Binding `a_name' gone from this page and the next.
		do
			c_unbind (engine_id, utf_8 (a_name).item)
		end

	answer (a_seq: STRING_8; a_status: INTEGER; a_json: STRING_8)
			-- Resolve (status 0) or reject the page's call `a_seq' with `a_json', valid JSON text that
			-- shared code checked (4.3).
		do
			c_answer (engine_id, utf_8 (a_seq).item, a_status, utf_8 (a_json).item)
		end

	evaluate (a_ticket: INTEGER; a_body: READABLE_STRING_GENERAL)
			-- Run `a_body', a function body that returns JSON text (shared code's wrapper, 4.2); its
			-- result comes back as event 2 with `a_ticket'.
		do
			c_evaluate (engine_id, a_ticket, utf_8 (a_body).item)
		end

feature -- Navigation decisions

	set_deciding (a_on: BOOLEAN)
			-- Hold the page's navigations for the program (`a_on'), or allow them at once.
		do
			c_set_deciding (engine_id, a_on)
			is_deciding := a_on
		end

	decide (a_decision: INTEGER; a_allow: BOOLEAN)
			-- Answer held navigation `a_decision'.
		do
			c_decide (engine_id, a_decision, a_allow)
		end

feature -- The loop

	pump (a_ms: INTEGER)
			-- Handle the toolkit's events for up to `a_ms' milliseconds, or until one of ours is queued.
		do
			c_pump (a_ms).do_nothing
		end

	next_event: BOOLEAN
			-- <Precursor>
		local
			l_kind, l_a, l_b, l_c: INTEGER
		do
			if c_next_for (engine_id, $l_kind, $l_a, $l_b, $l_c) then
				Result := True
				set_event (l_kind, l_a, l_b, l_c, text_of (1), text_of (2), text_of (3))
			end
		end

	terminate
			-- <Precursor>: the loop ends at its next event.
		do
			c_terminate (engine_id)
		end

	dispose
			-- <Precursor>: held decisions are refused, the window closes.
		do
			if engine_id /= 0 then
				c_destroy (engine_id)
				engine_id := 0
			end
		end

feature -- Tests

	test_window_count: INTEGER
			-- <Precursor>: this engine's window and any web-view window no engine made.
		do
			Result := c_window_count (engine_id)
		end

	test_echo_at (a_url: READABLE_STRING_GENERAL)
			-- <Precursor>: the request itself is refused, and a page at its URL shows what it carried.
		do
			c_echo_at (engine_id, utf_8 (a_url).item)
		end

	test_content_width: INTEGER
		do
			Result := c_content_width (engine_id)
		end

	test_content_height: INTEGER
		do
			Result := c_content_height (engine_id)
		end

	test_is_resizable: BOOLEAN
		do
			Result := c_is_resizable (engine_id)
		end

feature {NONE} -- Implementation

	engine_id: INTEGER
			-- The C side's engine; 0 none.

	utf_8 (a_text: READABLE_STRING_GENERAL): C_STRING
			-- `a_text' as NUL-terminated UTF-8.
		do
			create Result.make ({UTF_CONVERTER}.string_32_to_utf_8_string_8 (a_text.to_string_32))
		end

	text_of (i: INTEGER): STRING_8
			-- Text `i' of the event taken last, as its UTF-8 bytes.
		do
			create Result.make_from_c_substring (c_text (i), 1, c_text_length (i))
		end

feature {NONE} -- C

	c_create (a_parent: POINTER; a_ephemeral, a_debug: BOOLEAN): INTEGER
		external "C inline use %"sb_appkit.h%"" alias "return sb_create($a_parent, $a_ephemeral, $a_debug);" end

	c_destroy (e: INTEGER)
		external "C inline use %"sb_appkit.h%"" alias "sb_destroy($e);" end

	c_window (e: INTEGER): POINTER
		external "C inline use %"sb_appkit.h%"" alias "return sb_window($e);" end

	c_set_title (e: INTEGER; a_title: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_set_title($e, (const char *) $a_title);" end

	c_set_size (e, w, h, a_hint: INTEGER)
		external "C inline use %"sb_appkit.h%"" alias "sb_set_size($e, $w, $h, $a_hint);" end

	c_show (e: INTEGER)
		external "C inline use %"sb_appkit.h%"" alias "sb_show($e);" end

	c_navigate (e: INTEGER; a_url: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_navigate($e, (const char *) $a_url);" end

	c_set_html (e: INTEGER; a_html, a_base: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_set_html($e, (const char *) $a_html, (const char *) $a_base);" end

	c_eval (e: INTEGER; a_script: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_eval($e, (const char *) $a_script);" end

	c_add_script (e: INTEGER; a_script: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_add_script($e, (const char *) $a_script);" end

	c_set_bridge (e: INTEGER; a_script: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_set_bridge($e, (const char *) $a_script);" end

	c_bind (e: INTEGER; a_name, a_line: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_bind($e, (const char *) $a_name, (const char *) $a_line);" end

	c_unbind (e: INTEGER; a_name: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_unbind($e, (const char *) $a_name);" end

	c_answer (e: INTEGER; a_seq: POINTER; a_status: INTEGER; a_json: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_answer($e, (const char *) $a_seq, $a_status, (const char *) $a_json);" end

	c_evaluate (e, a_ticket: INTEGER; a_body: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_evaluate($e, $a_ticket, (const char *) $a_body);" end

	c_set_deciding (e: INTEGER; a_on: BOOLEAN)
		external "C inline use %"sb_appkit.h%"" alias "sb_set_deciding($e, $a_on);" end

	c_decide (e, a_decision: INTEGER; a_allow: BOOLEAN)
		external "C inline use %"sb_appkit.h%"" alias "sb_decide($e, $a_decision, $a_allow);" end

	c_pump (a_ms: INTEGER): INTEGER
			-- `blocking': while AppKit waits, this thread is outside Eiffel code, so other processors'
			-- garbage collection doesn't wait for it (test_gc_runs_while_the_window_loop_runs).
		external "C blocking signature (int): int use %"sb_appkit.h%"" alias "sb_pump" end

	c_next_for (e: INTEGER; a_kind, a, b, c: TYPED_POINTER [INTEGER]): BOOLEAN
		external "C inline use %"sb_appkit.h%"" alias "return (EIF_BOOLEAN) sb_next_for($e, (int *) $a_kind, (int *) $a, (int *) $b, (int *) $c);" end

	c_text (i: INTEGER): POINTER
		external "C inline use %"sb_appkit.h%"" alias "return (void *) sb_text($i);" end

	c_text_length (i: INTEGER): INTEGER
		external "C inline use %"sb_appkit.h%"" alias "return sb_text_length($i);" end

	c_terminate (e: INTEGER)
		external "C inline use %"sb_appkit.h%"" alias "sb_terminate($e);" end

	c_window_count (e: INTEGER): INTEGER
		external "C inline use %"sb_appkit.h%"" alias "return sb_test_window_count($e);" end

	c_echo_at (e: INTEGER; a_url: POINTER)
		external "C inline use %"sb_appkit.h%"" alias "sb_test_echo_at($e, (const char *) $a_url);" end

	c_content_width (e: INTEGER): INTEGER
		external "C inline use %"sb_appkit.h%"" alias "return sb_test_content_width($e);" end

	c_content_height (e: INTEGER): INTEGER
		external "C inline use %"sb_appkit.h%"" alias "return sb_test_content_height($e);" end

	c_is_resizable (e: INTEGER): BOOLEAN
		external "C inline use %"sb_appkit.h%"" alias "return (EIF_BOOLEAN) sb_test_is_resizable($e);" end

end
