note
	description: "[
		SIMPLE_BROWSER - a browser window (or a browser inside a window), the same on Windows,
		macOS and Linux (SIMPLE_BROWSER_SPEC.md).

		Example:
			create browser.make
			browser.titled ("My App").size (1024, 768).navigate ("https://example.com").run

		Calls from the page:
			browser.on_call ("add", agent on_add)     -- JavaScript: await window.add (1, 2)
			on_add (a_seq, a_json_args: STRING_8) do browser.respond (a_seq, "3") end

		Results of a script, navigation decisions, new windows, the title, loads:
			browser.evaluate ("document.title", agent on_result)    -- on_result (ok, json)
			browser.on_navigation (agent allow)                      -- allow (n): BOOLEAN
			browser.on_new_window (agent on_new_window)              -- (url)
			browser.on_title (agent on_title)                        -- (title)
			browser.on_loaded (agent on_loaded)                      -- (ok, error)

		Every handler runs from `run', on the thread that made the browser. `run' is an Eiffel
		loop: the engine's `pump' (a blocking external, so other processors' collections never
		wait for it), then every queued event, until the window closes or `close' is called.

		htmx 2.0.4 and Alpine.js 3.14.8 are bundled (SB_BUNDLED_SCRIPTS): `load_htmx_page'
		writes them inline, so the page needs no network. A page Content Security Policy must
		allow inline scripts.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SIMPLE_BROWSER

inherit
	SB_ANY

create
	make,
	make_ephemeral,
	make_with_window,
	make_ephemeral_with_window,
	make_with_engine

feature {NONE} -- Initialization

	make
			-- A browser window of its own, with the persistent data store.
		do
			make_from_platform (False, default_pointer)
		ensure
			persistent: not is_ephemeral
		end

	make_ephemeral
			-- A browser window of its own whose cookies, storage and cache live in memory
			-- and go with it.
		do
			make_from_platform (True, default_pointer)
		ensure
			ephemeral: is_ephemeral
		end

	make_with_window (a_parent: POINTER)
			-- A browser inside the toolkit's `a_parent' (HWND, NSView * or NSWindow *, GtkWidget *).
		require
			parent_given: a_parent /= default_pointer
		do
			make_from_platform (False, a_parent)
		ensure
			persistent: not is_ephemeral
		end

	make_ephemeral_with_window (a_parent: POINTER)
			-- `make_with_window' with the in-memory data store of `make_ephemeral'.
		require
			parent_given: a_parent /= default_pointer
		do
			make_from_platform (True, a_parent)
		ensure
			ephemeral: is_ephemeral
		end

	make_with_engine (a_engine: BROWSER_ENGINE)
			-- A browser over `a_engine' (tests, other backends).
		do
			engine := a_engine
			start_engine
		ensure
			engine_set: engine = a_engine
		end

	make_from_platform (a_ephemeral: BOOLEAN; a_parent: POINTER)
			-- Make the platform's engine (SB_PLATFORM), in `a_parent' unless it is null.
		local
			l_platform: SB_PLATFORM
		do
			create l_platform
			is_ephemeral := a_ephemeral
			if a_parent = default_pointer then
				engine := l_platform.new_engine (a_ephemeral, False)
			else
				engine := l_platform.new_engine_in (a_parent, a_ephemeral, False)
			end
			start_engine
		ensure
			ephemeral_set: is_ephemeral = a_ephemeral
		end

	start_engine
			-- Give a valid engine the bridge; otherwise record why not.
		do
			if engine.is_valid then
				engine.set_bridge (scripts.Bridge_script)
			else
				last_error := {STRING_32} "the browser engine could not start"
			end
		ensure
			error_when_not_valid: not is_valid implies last_error /= Void
		end

feature -- Status

	is_valid: BOOLEAN
			-- Is the browser ready for use (created, not disposed)?
		do
			Result := engine.is_valid
		end

	is_ephemeral: BOOLEAN
			-- Do cookies, storage and cache live in memory only?

	is_closed: BOOLEAN
			-- Has the user closed the window?

	is_stopping: BOOLEAN
			-- Has `close' ended the current `run'?

	last_error: detachable STRING_32
			-- Why the browser is not valid, if it is not.

	pending_evaluations: INTEGER
			-- How many `evaluate' results have not come back yet?
		do
			Result := evaluations.count
		end

feature -- Access

	engine: BROWSER_ENGINE
			-- The platform's engine.

feature -- Navigation commands

	navigate_to (a_url: READABLE_STRING_GENERAL)
			-- Load `a_url'. Never asked of `on_navigation'.
		require
			valid: is_valid
			url_not_empty: not a_url.is_empty
		do
			engine.navigate (a_url)
		end

	set_html_content (a_html: READABLE_STRING_GENERAL)
			-- Load `a_html' as the page. Never asked of `on_navigation'.
		require
			valid: is_valid
		do
			engine.set_html (a_html)
		end

	load_htmx_page (a_body_html: READABLE_STRING_GENERAL)
			-- Load a page whose body is `a_body_html', with the bundled htmx inline in its head
			-- and the bundled Alpine.js inline at the end of its body (4.9).
		require
			valid: is_valid
		do
			engine.set_html (htmx_page (a_body_html))
		end

	htmx_page (a_body_html: READABLE_STRING_GENERAL): STRING_32
			-- The page `load_htmx_page' loads.
		local
			l_bundled: SB_BUNDLED_SCRIPTS
		do
			create l_bundled
			create Result.make (a_body_html.count + l_bundled.Htmx_script.count + l_bundled.Alpine_script.count + 200)
			Result.append ({STRING_32} "<!DOCTYPE html>%N<html>%N<head>%N<meta charset=%"UTF-8%">%N<script>")
			Result.append_string_general (l_bundled.Htmx_script)
			Result.append ({STRING_32} "</script>%N</head>%N<body>%N")
			Result.append_string_general (a_body_html)
			Result.append ({STRING_32} "%N<script>")
			Result.append_string_general (l_bundled.Alpine_script)
			Result.append ({STRING_32} "</script>%N</body>%N</html>%N")
		ensure
			holds_the_body: Result.has_substring (a_body_html.to_string_32)
		end

feature -- Navigation fluent

	navigate (a_url: READABLE_STRING_GENERAL): like Current
			-- Load `a_url' (fluent).
		require
			valid: is_valid
			url_not_empty: not a_url.is_empty
		do
			navigate_to (a_url)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	with_html (a_html: READABLE_STRING_GENERAL): like Current
			-- Load `a_html' (fluent).
		require
			valid: is_valid
		do
			set_html_content (a_html)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	with_htmx (a_body_html: READABLE_STRING_GENERAL): like Current
			-- `load_htmx_page' (fluent).
		require
			valid: is_valid
		do
			load_htmx_page (a_body_html)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

feature -- Window configuration commands

	set_title (a_title: READABLE_STRING_GENERAL)
			-- Set the window's title.
		require
			valid: is_valid
		do
			engine.set_title (a_title)
		end

	set_size (a_width, a_height: INTEGER)
			-- Size the content to `a_width' by `a_height' (within any min, max or fixed size).
		require
			valid: is_valid
			positive: a_width > 0 and a_height > 0
		do
			engine.set_size (a_width, a_height, engine.Size_hint_none)
		end

	set_min_size (a_width, a_height: INTEGER)
			-- The content is never smaller than `a_width' by `a_height'.
		require
			valid: is_valid
			positive: a_width > 0 and a_height > 0
		do
			engine.set_size (a_width, a_height, engine.Size_hint_min)
		end

	set_max_size (a_width, a_height: INTEGER)
			-- The content is never larger than `a_width' by `a_height'.
		require
			valid: is_valid
			positive: a_width > 0 and a_height > 0
		do
			engine.set_size (a_width, a_height, engine.Size_hint_max)
		end

	set_fixed_size (a_width, a_height: INTEGER)
			-- The content is `a_width' by `a_height', and the user cannot resize the window.
		require
			valid: is_valid
			positive: a_width > 0 and a_height > 0
		do
			engine.set_size (a_width, a_height, engine.Size_hint_fixed)
		end

feature -- Window configuration fluent

	titled (a_title: READABLE_STRING_GENERAL): like Current
			-- Set the window's title (fluent).
		require
			valid: is_valid
		do
			set_title (a_title)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	size (a_width, a_height: INTEGER): like Current
			-- `set_size' (fluent).
		require
			valid: is_valid
			positive: a_width > 0 and a_height > 0
		do
			set_size (a_width, a_height)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	min_size (a_width, a_height: INTEGER): like Current
			-- `set_min_size' (fluent).
		require
			valid: is_valid
			positive: a_width > 0 and a_height > 0
		do
			set_min_size (a_width, a_height)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	fixed_size (a_width, a_height: INTEGER): like Current
			-- `set_fixed_size' (fluent).
		require
			valid: is_valid
			positive: a_width > 0 and a_height > 0
		do
			set_fixed_size (a_width, a_height)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

feature -- Scripts

	eval (a_script: READABLE_STRING_GENERAL)
			-- Run `a_script' on the page now; its result is discarded.
		require
			valid: is_valid
		do
			engine.eval_js (a_script)
		end

	inject (a_script: READABLE_STRING_GENERAL)
			-- Run `a_script' at the start of every page, before the page's own scripts.
		require
			valid: is_valid
		do
			engine.init_js (a_script)
		end

	evaluate (a_script: READABLE_STRING_GENERAL; a_handler: PROCEDURE [TUPLE [ok: BOOLEAN; json: STRING_8]])
			-- Run the expression `a_script' on the page; `a_handler' gets its result from `run'
			-- as JSON text ("3", "%"Title%"", "null" for undefined), promises awaited. A thrown
			-- error gives `ok' False and its message as a JSON string. Statements go inside
			-- the program's own function expression.
		require
			valid: is_valid
			script_not_empty: not a_script.is_empty
		do
			last_ticket := last_ticket + 1
			evaluations.force (a_handler, last_ticket)
			engine.evaluate (last_ticket, scripts.evaluate_body (a_script))
		ensure
			ticket_advanced: last_ticket = old last_ticket + 1
			waiting: evaluations.has (last_ticket)
		end

feature -- Calls from the page

	on_call (a_name: READABLE_STRING_GENERAL; a_handler: PROCEDURE [TUPLE [STRING_8, STRING_8]])
			-- Make `window [a_name]' on every page call `a_handler' with (seq, JSON array of the
			-- arguments); answer with `respond' or `respond_error' and that seq.
		require
			valid: is_valid
			name_not_empty: not a_name.is_empty
		local
			l_name: STRING_8
			l_utf: UTF_CONVERTER
		do
			l_name := l_utf.utf_32_string_to_utf_8_string_8 (a_name)
			call_handlers.force (a_handler, l_name)
			engine.bind_name (l_name, scripts.binding_line (l_name))
		ensure
			bound: has_call (a_name)
		end

	remove_call (a_name: READABLE_STRING_GENERAL)
			-- Undo `on_call (a_name, ...)', on new pages and the page shown now.
		require
			valid: is_valid
			name_not_empty: not a_name.is_empty
		local
			l_name: STRING_8
			l_utf: UTF_CONVERTER
		do
			l_name := l_utf.utf_32_string_to_utf_8_string_8 (a_name)
			call_handlers.remove (l_name)
			engine.unbind_name (l_name)
			engine.eval_js ("delete window[" + scripts.json_string_8 (l_name) + "];")
		ensure
			unbound: not has_call (a_name)
		end

	has_call (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_name' bound by `on_call'?
		local
			l_utf: UTF_CONVERTER
		do
			Result := call_handlers.has (l_utf.utf_32_string_to_utf_8_string_8 (a_name))
		end

	respond (a_seq: STRING_8; a_result: STRING_8)
			-- Resolve call `a_seq' with the JSON value `a_result'. Text that is not JSON
			-- rejects it instead, with the parse error as a JSON string.
		require
			valid: is_valid
			seq_not_empty: not a_seq.is_empty
		do
			if attached scripts.json_error (a_result) as al_error then
				engine.answer (a_seq, 1, scripts.json_string (al_error))
			else
				engine.answer (a_seq, 0, a_result)
			end
		end

	respond_error (a_seq: STRING_8; a_error: STRING_8)
			-- Reject call `a_seq' with the JSON value `a_error' (or, if it is not JSON, with
			-- the parse error as a JSON string).
		require
			valid: is_valid
			seq_not_empty: not a_seq.is_empty
		do
			if attached scripts.json_error (a_error) as al_error then
				engine.answer (a_seq, 1, scripts.json_string (al_error))
			else
				engine.answer (a_seq, 1, a_error)
			end
		end

feature -- Page events

	on_navigation (a_handler: FUNCTION [SB_NAVIGATION, BOOLEAN])
			-- Ask `a_handler' about every navigation the page starts (True allows). The
			-- program's own `navigate' and `set_html' are never asked.
		require
			valid: is_valid
		do
			navigation_handler := a_handler
			engine.set_deciding (True)
		ensure
			set: navigation_handler = a_handler
			deciding: engine.is_deciding
		end

	on_new_window (a_handler: PROCEDURE [TUPLE [url: STRING_32]])
			-- Tell `a_handler' each url the page asks to open in a new window; none opens.
		require
			valid: is_valid
		do
			new_window_handler := a_handler
		ensure
			set: new_window_handler = a_handler
		end

	on_title (a_handler: PROCEDURE [TUPLE [title: STRING_32]])
			-- Tell `a_handler' each new title of the page.
		require
			valid: is_valid
		do
			title_handler := a_handler
		ensure
			set: title_handler = a_handler
		end

	on_loaded (a_handler: PROCEDURE [TUPLE [ok: BOOLEAN; error: STRING_32]])
			-- Tell `a_handler' the end of each main-frame load (not of one `on_navigation'
			-- cancelled).
		require
			valid: is_valid
		do
			loaded_handler := a_handler
		ensure
			set: loaded_handler = a_handler
		end

feature -- Lifecycle

	run
			-- Show the window, then pump and dispatch every event until the user closes the
			-- window or `close' is called.
		require
			valid: is_valid
		do
			is_stopping := False
			if not is_closed then
				engine.show
				from
					dispatch_events
				until
					is_closed or is_stopping or not engine.is_valid
				loop
					engine.pump (Pump_wait_ms)
					dispatch_events
				end
			end
		ensure
			ended: is_closed or is_stopping or not is_valid
		end

	close
			-- End `run' (the window stays until `dispose').
		do
			is_stopping := True
			if engine.is_valid then
				engine.terminate
			end
		ensure
			stopping: is_stopping
		end

	dispose
			-- Release everything; the browser is unusable after.
		do
			if engine.is_valid then
				engine.dispose
			end
			evaluations.wipe_out
			call_handlers.wipe_out
		ensure
			not_valid: not is_valid
		end

feature -- Debug control

	with_debug: like Current
			-- Turn the developer tools on (fluent).
		do
			enable_debug_mode
			engine.set_debug_mode (True)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

feature -- Constants

	Pump_wait_ms: INTEGER = 50
			-- How long one `pump' in `run' waits for an event.

feature {NONE} -- Dispatch

	dispatch_events
			-- Dispatch every event queued for the engine.
		do
			from
			until
				not engine.is_valid or else not engine.next_event
			loop
				dispatch_event
			end
		end

	dispatch_event
			-- Dispatch the engine's event last taken.
		require
			valid: is_valid
		local
			l_kind, l_a, l_b, l_c: INTEGER
			l_text_1, l_text_2, l_text_3: STRING_8
			l_text_32: STRING_32
			l_navigation: SB_NAVIGATION
			l_allow: BOOLEAN
		do
			l_kind := engine.event_kind
			l_a := engine.event_a
			l_b := engine.event_b
			l_c := engine.event_c
			l_text_1 := engine.event_text (1)
			l_text_2 := engine.event_text (2)
			l_text_3 := engine.event_text (3)
			l_text_32 := engine.event_text_32 (1)
			if l_kind = engine.Event_call then
				if attached call_handlers.item (l_text_1) as al_handler then
					al_handler.call ([l_text_2, l_text_3])
				end
			elseif l_kind = engine.Event_evaluated then
				if attached evaluations.item (l_a) as al_handler then
					evaluations.remove (l_a)
					al_handler.call ([l_b = 0, l_text_1])
				end
			elseif l_kind = engine.Event_navigating then
				create l_navigation.make (l_text_32, navigation_kind (l_b), l_c /= 0)
				l_allow := True
				if attached navigation_handler as al_handler then
					l_allow := al_handler.item ([l_navigation])
				end
				if engine.is_valid and l_a > 0 then
					engine.decide (l_a, l_allow)
				end
			elseif l_kind = engine.Event_new_window then
				if attached new_window_handler as al_handler then
					al_handler.call ([l_text_32])
				end
			elseif l_kind = engine.Event_title_changed then
				if attached title_handler as al_handler then
					al_handler.call ([l_text_32])
				end
			elseif l_kind = engine.Event_loaded then
				if attached loaded_handler as al_handler then
					al_handler.call ([l_a = 0, l_text_32])
				end
			elseif l_kind = engine.Event_closed then
				is_closed := True
			end
		end

	navigation_kind (a_kind: INTEGER): INTEGER
			-- `a_kind' if it is an SB_NAVIGATION kind, else `Kind_other'.
		do
			if a_kind >= 0 and a_kind <= 4 then
				Result := a_kind
			end
		ensure
			in_range: Result >= 0 and Result <= 4
		end

feature {NONE} -- Implementation

	scripts: SB_SCRIPTS
			-- The shared script texts.
		once
			create Result
		end

	last_ticket: INTEGER
			-- The ticket of the last `evaluate'.

	evaluations: HASH_TABLE [PROCEDURE [TUPLE [ok: BOOLEAN; json: STRING_8]], INTEGER]
			-- Handlers of the `evaluate' results still to come, by ticket.
		attribute
			create Result.make (8)
		end

	call_handlers: HASH_TABLE [PROCEDURE [TUPLE [STRING_8, STRING_8]], STRING_8]
			-- `on_call' handlers, by name (UTF-8).
		attribute
			create Result.make (8)
		end

	navigation_handler: detachable FUNCTION [SB_NAVIGATION, BOOLEAN]
			-- `on_navigation''s handler.

	new_window_handler: detachable PROCEDURE [TUPLE [url: STRING_32]]
			-- `on_new_window''s handler.

	title_handler: detachable PROCEDURE [TUPLE [title: STRING_32]]
			-- `on_title''s handler.

	loaded_handler: detachable PROCEDURE [TUPLE [ok: BOOLEAN; error: STRING_32]]
			-- `on_loaded''s handler.

invariant
	tickets_positive: last_ticket >= 0

end
