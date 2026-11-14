note
	description: "[
		BROWSER_ENGINE - the contract every platform's browser engine keeps.

		One engine per platform, chosen by the ECF's platform conditions through SB_PLATFORM:
		- WEBVIEW_ENGINE: Windows, webview.dll with WebView2 (src/windows);
		- APPKIT_ENGINE: macOS, WKWebView (src/macos);
		- GTK_ENGINE: Linux, WebKitGTK 6.0 (src/linux).

		The engine never calls Eiffel from C (SIMPLE_BROWSER_SPEC.md 4.1). Its toolkit's
		callbacks queue events; SIMPLE_BROWSER's loop calls `pump', then takes every queued
		event with `next_event' and dispatches it. Shared code supplies every script text
		(the bridge, each binding's line, the evaluate wrapper's body); the engine only places it.
	]"
	author: "Larry Rix"
	date: "$Date$"

deferred class
	BROWSER_ENGINE

inherit
	SB_ANY

feature -- Status

	is_valid: BOOLEAN
			-- Is the engine created and not yet disposed?
		deferred
		end

	is_deciding: BOOLEAN
			-- Are navigation decisions held for Eiffel (`set_deciding')?
		deferred
		end

feature -- Window access

	window_handle: POINTER
			-- The toolkit's window: HWND (Windows), NSWindow * (macOS), GtkWindow * (Linux).
		require
			valid: is_valid
		deferred
		end

feature -- Navigation

	navigate (a_url: READABLE_STRING_GENERAL)
			-- Load `a_url'. The program's own navigation is never asked (`set_deciding').
		require
			valid: is_valid
			url_not_empty: not a_url.is_empty
		deferred
		end

	set_html (a_html: READABLE_STRING_GENERAL)
			-- Load `a_html' as the page, at `new_set_html_base' (SB_SCRIPTS.set_html_base), so
			-- its origin is SB_SCRIPTS.Set_html_origin on every platform. The program's own load
			-- is never asked.
		require
			valid: is_valid
		deferred
		end

	new_set_html_base: STRING_8
			-- The URL for the next `set_html' page; each call numbers a new one.
		do
			set_html_pages := set_html_pages + 1
			Result := shared_scripts.set_html_base (set_html_pages)
		ensure
			numbered: set_html_pages = old set_html_pages + 1
		end

	set_html_pages: INTEGER
			-- How many `set_html' pages this engine has numbered.

feature -- Window configuration

	set_title (a_title: READABLE_STRING_GENERAL)
			-- Set the window's title.
		require
			valid: is_valid
		deferred
		end

	set_size (a_width, a_height: INTEGER; a_hint: INTEGER)
			-- Size the content to `a_width' by `a_height' logical pixels with `a_hint'
			-- (`Size_hint_none', `Size_hint_min', `Size_hint_max' or `Size_hint_fixed').
			-- A min, max or fixed hint holds against a later `set_size'.
		require
			valid: is_valid
			valid_width: a_width > 0
			valid_height: a_height > 0
			valid_hint: is_valid_size_hint (a_hint)
		deferred
		end

	show
			-- Put the window on screen without taking the focus.
		require
			valid: is_valid
		deferred
		end

feature -- Scripts

	eval_js (a_script: READABLE_STRING_GENERAL)
			-- Run `a_script' on the page now; its result is discarded.
		require
			valid: is_valid
		deferred
		end

	init_js (a_script: READABLE_STRING_GENERAL)
			-- Run `a_script' at the start of every page, before the page's own scripts.
		require
			valid: is_valid
		deferred
		end

	set_bridge (a_script: READABLE_STRING_GENERAL)
			-- Run the bridge script `a_script' (SB_SCRIPTS.Bridge_script) at the start of every
			-- page, and on the page shown now.
		require
			valid: is_valid
			script_not_empty: not a_script.is_empty
		deferred
		end

	bind_name (a_name, a_line: STRING_8)
			-- Run `a_line', the binding of `a_name' built by shared code
			-- (SB_SCRIPTS.binding_line), at the start of every page and on the page shown now.
		require
			valid: is_valid
			name_not_empty: not a_name.is_empty
			line_not_empty: not a_line.is_empty
		deferred
		end

	unbind_name (a_name: STRING_8)
			-- Stop adding the binding of `a_name' to new pages.
		require
			valid: is_valid
			name_not_empty: not a_name.is_empty
		deferred
		end

	answer (a_seq: STRING_8; a_status: INTEGER; a_json: STRING_8)
			-- Settle call `a_seq' on the page: resolve it with the JSON value `a_json' when
			-- `a_status' is 0, reject it otherwise (`window.__sb.answer').
		require
			valid: is_valid
			seq_not_empty: not a_seq.is_empty
			json: is_json_text (a_json)
		deferred
		end

	evaluate (a_ticket: INTEGER; a_body: READABLE_STRING_GENERAL)
			-- Run `a_body', shared code's evaluate wrapper with the script inside
			-- (SB_SCRIPTS.evaluate_body), and queue its result as an `evaluated' event
			-- carrying `a_ticket'.
		require
			valid: is_valid
			ticket_positive: a_ticket > 0
			body_not_empty: not a_body.is_empty
		deferred
		end

feature -- Navigation decisions

	set_deciding (a_on: BOOLEAN)
			-- Hold navigation decisions for Eiffel (`navigating' events)? Off, the engine
			-- allows every navigation at once, with no event.
		require
			valid: is_valid
		deferred
		ensure
			set: is_deciding = a_on
		end

	decide (a_decision: INTEGER; a_allow: BOOLEAN)
			-- Answer held decision `a_decision' (from a `navigating' event).
		require
			valid: is_valid
			decision_positive: a_decision > 0
		deferred
		end

feature -- The loop

	pump (a_ms: INTEGER)
			-- Handle toolkit events for up to `a_ms' milliseconds, or until an event is queued.
			-- A `blocking' external: other processors' collections do not wait for it.
		require
			valid: is_valid
			non_negative: a_ms >= 0
		deferred
		end

	next_event: BOOLEAN
			-- Take the oldest queued event for this engine into `event_kind', `event_a',
			-- `event_b', `event_c' and `event_text'; False if there is none.
		require
			valid: is_valid
		deferred
		ensure
			kind_known: Result implies is_event_kind (event_kind)
		end

	event_kind: INTEGER
			-- The kind of the event last taken (`Event_call' .. `Event_closed').

	event_a, event_b, event_c: INTEGER
			-- The event's numbers:
			-- evaluated: a ticket, b status; navigating: a decision, b kind, c main frame 0 or 1;
			-- loaded: a status.

	event_text (a_index: INTEGER): STRING_8
			-- Text `a_index' of the event last taken, UTF-8:
			-- call: 1 name, 2 seq, 3 args JSON; evaluated: 1 JSON; navigating, new_window: 1 url;
			-- title_changed: 1 title; loaded: 1 error.
		require
			valid_index: a_index >= 1 and a_index <= 3
		do
			Result := event_texts [a_index]
		end

	event_text_32 (a_index: INTEGER): STRING_32
			-- `event_text' decoded from UTF-8, for urls and titles.
		require
			valid_index: a_index >= 1 and a_index <= 3
		local
			l_utf: UTF_CONVERTER
		do
			Result := l_utf.utf_8_string_8_to_string_32 (event_texts [a_index])
		end

feature -- Lifecycle

	terminate
			-- The program's loop is ending (SIMPLE_BROWSER.close): wake `pump' if it waits.
		deferred
		end

	dispose
			-- Release everything: held decisions are answered Cancel, the window goes.
		deferred
		ensure
			not_valid: not is_valid
		end

feature -- Test hooks

	test_window_count: INTEGER
			-- How many browser windows this engine's process shows (new windows never open).
		require
			valid: is_valid
		deferred
		end

	test_content_width: INTEGER
			-- The window's content width, in logical pixels.
		require
			valid: is_valid
		deferred
		end

	test_content_height: INTEGER
			-- The window's content height, in logical pixels.
		require
			valid: is_valid
		deferred
		end

	test_is_resizable: BOOLEAN
			-- Can the user resize the window?
		require
			valid: is_valid
		deferred
		end

	set_html_with_base (a_html, a_base_url: READABLE_STRING_GENERAL)
			-- Load `a_html' as the document at `a_base_url', so pages share an origin.
			-- The program's own load: never asked.
		require
			valid: is_valid
			base_not_empty: not a_base_url.is_empty
		deferred
		end

	test_echo_at (a_url: READABLE_STRING_GENERAL)
			-- Answer every request for `a_url' with a page whose element `echo' shows the
			-- request's method, a line break, then its body (a form's fields, as sent).
		require
			valid: is_valid
			url_not_empty: not a_url.is_empty
		deferred
		end

feature -- Queries

	is_json_text (a_text: READABLE_STRING_8): BOOLEAN
			-- Is `a_text' (UTF-8) one JSON value?
		local
			l_json: SIMPLE_JSON
			l_utf: UTF_CONVERTER
		do
			if not a_text.is_empty then
				create l_json
				Result := attached l_json.parse (l_utf.utf_8_string_8_to_string_32 (a_text))
			end
		end

	is_valid_size_hint (a_hint: INTEGER): BOOLEAN
			-- Is `a_hint' one of the `Size_hint_*' constants?
		do
			Result := a_hint >= Size_hint_none and a_hint <= Size_hint_fixed
		end

	is_event_kind (a_kind: INTEGER): BOOLEAN
			-- Is `a_kind' one of the `Event_*' constants?
		do
			Result := a_kind >= Event_call and a_kind <= Event_closed
		end

feature -- Size hint constants

	Size_hint_none: INTEGER = 0
			-- No constraint.

	Size_hint_min: INTEGER = 1
			-- A minimum content size.

	Size_hint_max: INTEGER = 2
			-- A maximum content size.

	Size_hint_fixed: INTEGER = 3
			-- A fixed content size; the user cannot resize the window.

feature -- Event kinds

	Event_call: INTEGER = 1
			-- The page called a binding: text 1 name, 2 seq, 3 args JSON.

	Event_evaluated: INTEGER = 2
			-- An `evaluate' finished: a ticket, b status (0 ok); text 1 JSON.

	Event_navigating: INTEGER = 3
			-- A navigation waits for `decide': a decision, b kind, c main frame; text 1 url.

	Event_new_window: INTEGER = 4
			-- The page asked for a new window, which did not open: text 1 url.

	Event_title_changed: INTEGER = 5
			-- The page's title changed: text 1 title.

	Event_loaded: INTEGER = 6
			-- A main-frame load ended: a status (0 ok); text 1 error.

	Event_closed: INTEGER = 7
			-- The user closed the window.

feature {NONE} -- Implementation

	shared_scripts: SB_SCRIPTS
			-- The shared script texts and page URLs.
		once
			create Result
		end

	event_texts: ARRAY [STRING_8]
			-- The texts of the event last taken.
		attribute
			Result := <<create {STRING_8}.make_empty, create {STRING_8}.make_empty, create {STRING_8}.make_empty>>
		end

	set_event (a_kind, a_a, a_b, a_c: INTEGER; a_text_1, a_text_2, a_text_3: STRING_8)
			-- Make the event last taken (`a_kind', numbers `a_a', `a_b', `a_c', UTF-8 texts).
		require
			kind_known: is_event_kind (a_kind)
		do
			event_kind := a_kind
			event_a := a_a
			event_b := a_b
			event_c := a_c
			event_texts := <<a_text_1, a_text_2, a_text_3>>
		ensure
			kind_set: event_kind = a_kind
			a_set: event_a = a_a
			b_set: event_b = a_b
			c_set: event_c = a_c
			text_1_set: event_text (1) = a_text_1
			text_2_set: event_text (2) = a_text_2
			text_3_set: event_text (3) = a_text_3
		end

invariant
	three_texts: event_texts.count = 3 and event_texts.lower = 1
	pages_counted: set_html_pages >= 0

end
