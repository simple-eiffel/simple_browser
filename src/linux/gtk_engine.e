note
	description: "[
		GTK_ENGINE - the Linux engine: WebKitGTK 6.0 on GTK 4 (Clib/linux/sb_gtk.h,
		SIMPLE_BROWSER_SPEC.md section 3).

		- The loop: C never calls Eiffel. WebKitGTK's signals queue events in C; `pump' runs
		  the default GMainContext (a `blocking' external), and `next_event' takes them.
		  gtk_main and GtkApplication are never used, so simple_gui's GTK backend can share
		  the process and the loop.
		- Calls from the page: the shared bridge (SB_SCRIPTS.Bridge_script) posts them through
		  `webkit.messageHandlers.sb' (script-message-received::sb).
		- `evaluate': webkit_web_view_call_async_javascript_function with the shared body, in
		  the page's world.
		- Navigation decisions: decide-policy holds the WebKitPolicyDecision (referenced) until
		  `decide', so an allowed form is WebKit's own request, POST and body. WebKitGTK 6.0's
		  navigation action has no frame or source frame (its frame name, the target's, is NULL
		  for the main frame and for unnamed and named iframes alike: measured), so the engine's
		  frame script, in every frame, tells sb_gtk.h which navigations an iframe starts itself
		  (asked, not main frame) and which a parent starts by setting an iframe's src (not
		  asked).
		- New windows: a NEW_WINDOW_ACTION decision is ignored and reported; `create' returns
		  NULL (window.open, which reaches only `create', is reported there).
		- The title: notify::title. The end of a load: load-changed and load-failed, with
		  cancellations quiet.
		- Size hints: GTK 4 has no maximum size, so a max hint clamps the program's own sizes
		  and the window opens within it; the user can still enlarge it (spec 4.8).
		- Ephemeral: webkit_network_session_new_ephemeral, one per engine.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	GTK_ENGINE

inherit
	BROWSER_ENGINE
		redefine
			set_debug_mode,
			test_sees_request_body,
			test_request_body_limit
		end

create
	make,
	make_with_window

feature {NONE} -- Initialization

	make (a_ephemeral, a_debug: BOOLEAN)
			-- A browser window of its own; in-memory data if `a_ephemeral', developer tools if
			-- `a_debug'.
		do
			start (default_pointer, a_ephemeral, a_debug)
		ensure
			ephemeral_set: is_ephemeral = a_ephemeral
			valid_or_error: is_valid or last_error /= Void
		end

	make_with_window (a_parent: POINTER; a_ephemeral, a_debug: BOOLEAN)
			-- A browser inside `a_parent', a GtkWindow (the view becomes its child, or joins the
			-- GtkBox that is its child) or a GtkBox (the view is appended).
		require
			parent_given: a_parent /= default_pointer
		do
			start (a_parent, a_ephemeral, a_debug)
		ensure
			ephemeral_set: is_ephemeral = a_ephemeral
			valid_or_error: is_valid or last_error /= Void
		end

	start (a_parent: POINTER; a_ephemeral, a_debug: BOOLEAN)
			-- Create the engine in `a_parent', or in a window of its own if it is null.
		do
			is_ephemeral := a_ephemeral
			is_debug_mode := a_debug
			id := c_create (a_ephemeral.to_integer, a_debug.to_integer, a_parent)
			if id = 0 then
				inspect c_last_error
				when 1 then
					last_error := {STRING_32} "GTK could not start: no display"
				when 2 then
					last_error := {STRING_32} "too many browser engines (16 at most)"
				when 3 then
					last_error := {STRING_32} "the parent is neither a GtkBox nor a GtkWindow whose child is none or a GtkBox"
				when 4 then
					last_error := {STRING_32} "GTK is in use on another thread"
				else
					last_error := {STRING_32} "WebKitGTK could not start"
				end
			end
		ensure
			ephemeral_set: is_ephemeral = a_ephemeral
			valid_or_error: is_valid or last_error /= Void
		end

feature -- Status

	is_valid: BOOLEAN
			-- <Precursor>
		do
			Result := id > 0
		end

	is_deciding: BOOLEAN
			-- <Precursor>

	is_ephemeral: BOOLEAN
			-- Do cookies, storage and cache live in memory only?

	last_error: detachable STRING_32
			-- Why the engine is not valid, if it is not.

	is_gui_thread: BOOLEAN
			-- Is the current thread the one GTK runs on (or is GTK not started yet)?
			-- Every engine call belongs on it.
		do
			Result := c_is_gui_thread
		end

feature -- Window access

	window_handle: POINTER
			-- <Precursor>
			-- The own GtkWindow, or the parent's root GtkWindow when embedded.
		do
			Result := c_window (id)
		end

feature -- Navigation

	navigate (a_url: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_url: C_STRING
		do
			create l_url.make (utf_8 (a_url))
			c_navigate (id, l_url.item)
		end

	set_html (a_html: READABLE_STRING_GENERAL)
			-- <Precursor>
			-- webkit_web_view_load_html with `new_set_html_base' as the base URI.
		local
			l_html, l_base: C_STRING
		do
			create l_html.make (utf_8 (a_html))
			create l_base.make (new_set_html_base)
			c_set_html_with_base (id, l_html.item, l_base.item)
		end

feature -- Window configuration

	set_title (a_title: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_title: C_STRING
		do
			create l_title.make (utf_8 (a_title))
			c_set_title (id, l_title.item)
		end

	set_size (a_width, a_height: INTEGER; a_hint: INTEGER)
			-- <Precursor>
		do
			c_set_size (id, a_width, a_height, a_hint)
		end

	show
			-- <Precursor>
		do
			c_show (id)
		end

feature -- Scripts

	eval_js (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_script: C_STRING
		do
			create l_script.make (utf_8 (a_script))
			c_eval (id, l_script.item)
		end

	init_js (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
			-- In every frame (WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES).
		local
			l_name, l_script: C_STRING
		do
			create l_name.make ("")
			create l_script.make (utf_8 (a_script))
			c_add_script (id, l_name.item, l_script.item, 0, 1)
		end

	set_bridge (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
			-- In the top frame only, as every binding.
		local
			l_name, l_script: C_STRING
		do
			create l_name.make ("")
			create l_script.make (utf_8 (a_script))
			c_add_script (id, l_name.item, l_script.item, 1, 0)
		end

	bind_name (a_name, a_line: STRING_8)
			-- <Precursor>
		local
			l_name, l_line: C_STRING
		do
			unbind_name (a_name)
			create l_name.make (a_name)
			create l_line.make (a_line)
			c_add_script (id, l_name.item, l_line.item, 1, 0)
		end

	unbind_name (a_name: STRING_8)
			-- <Precursor>
		local
			l_name: C_STRING
		do
			create l_name.make (a_name)
			c_remove_script (id, l_name.item)
		end

	answer (a_seq: STRING_8; a_status: INTEGER; a_json: STRING_8)
			-- <Precursor>
		local
			l_script: C_STRING
		do
			create l_script.make (scripts.answer_script (a_seq, a_status, a_json))
			c_eval (id, l_script.item)
		end

	evaluate (a_ticket: INTEGER; a_body: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_body: C_STRING
		do
			create l_body.make (utf_8 (a_body))
			c_evaluate (id, a_ticket, l_body.item)
		end

feature -- Navigation decisions

	set_deciding (a_on: BOOLEAN)
			-- <Precursor>
		do
			is_deciding := a_on
			c_set_deciding (id, a_on.to_integer)
		end

	decide (a_decision: INTEGER; a_allow: BOOLEAN)
			-- <Precursor>
		do
			c_decide (id, a_decision, a_allow.to_integer)
		end

feature -- The loop

	pump (a_ms: INTEGER)
			-- <Precursor>
		do
			c_pump (id, a_ms)
		end

	next_event: BOOLEAN
			-- <Precursor>
		local
			l_kind: INTEGER
		do
			if c_take (id) then
				l_kind := c_current_kind (id)
				if is_event_kind (l_kind) then
					set_event (l_kind, c_current_a (id), c_current_b (id), c_current_c (id),
						current_text (1), current_text (2), current_text (3))
					Result := True
				end
			end
		end

feature -- Lifecycle

	terminate
			-- <Precursor>
			-- Only wakes a waiting `pump'; `closed' comes only from the user closing the window.
		do
			c_wake
		end

	dispose
			-- <Precursor>
		do
			if id > 0 then
				c_dispose (id)
				id := 0
			end
		end

feature -- Debug control

	set_debug_mode (a_enabled: BOOLEAN)
			-- <Precursor>
			-- Also turn WebKit's inspector (enable-developer-extras) on or off.
		do
			Precursor (a_enabled)
			if is_valid then
				c_set_dev_tools (id, a_enabled.to_integer)
			end
		end

feature -- Test hooks

	test_window_count: INTEGER
			-- <Precursor>
			-- This engine's own window, if shown, plus any visible window holding a web view no
			-- engine made.
		do
			Result := c_window_count (id)
		end

	test_content_width: INTEGER
			-- <Precursor>
		do
			Result := c_content_size (id, 0)
		end

	test_content_height: INTEGER
			-- <Precursor>
		do
			Result := c_content_size (id, 1)
		end

	test_is_resizable: BOOLEAN
			-- <Precursor>
		do
			Result := c_is_resizable (id) /= 0
		end

	set_html_with_base (a_html, a_base_url: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_html, l_base: C_STRING
		do
			create l_html.make (utf_8 (a_html))
			create l_base.make (utf_8 (a_base_url))
			c_set_html_with_base (id, l_html.item, l_base.item)
		end

	test_sees_request_body: BOOLEAN
			-- <Precursor>
			-- No: measured on WebKitGTK 2.52, WebKitURIRequest has a method and headers but no
			-- body, and a URI scheme handler for https is refused. A held decision, once used,
			-- still sends WebKit's own request, body included.
		do
			Result := False
		end

	test_request_body_limit: STRING_8
			-- <Precursor>
		do
			Result := "WebKitGTK 2.52's WebKitURIRequest has no body, and https URI scheme handlers are refused"
		end

	test_echo_at (a_url: READABLE_STRING_GENERAL)
			-- <Precursor>
			-- A request for `a_url' is answered, at decide-policy, with the echo page loaded
			-- by webkit_web_view_load_html. WebKitGTK 6.0 (2.52) gives the request its method
			-- but not its body, so the body shown is empty.
		local
			l_url: C_STRING
		do
			create l_url.make (utf_8 (a_url))
			c_set_echo (id, l_url.item)
		end

feature {NONE} -- Implementation

	id: INTEGER
			-- The engine's number in C (sb_gtk.h); 0 when not valid.

	scripts: SB_SCRIPTS
			-- The shared script texts.
		once
			create Result
		end

	utf_8 (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' in UTF-8.
		local
			l_utf: UTF_CONVERTER
		do
			Result := l_utf.utf_32_string_to_utf_8_string_8 (a_text)
		end

	current_text (a_index: INTEGER): STRING_8
			-- Text `a_index' of the event `c_take' took, copied.
		require
			valid_index: a_index >= 1 and a_index <= 3
		do
			create Result.make_from_c (c_current_text (id, a_index))
		end

feature {NONE} -- C externals

	c_create (a_ephemeral, a_debug: INTEGER; a_parent: POINTER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_create ((int) $a_ephemeral, (int) $a_debug, (void *) $a_parent);"
		end

	c_last_error: INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_last_error ();"
		end

	c_is_gui_thread: BOOLEAN
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return (EIF_BOOLEAN) (sbg_is_gui_thread () != 0);"
		end

	c_window (a_id: INTEGER): POINTER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return (EIF_POINTER) sbg_window ((int) $a_id);"
		end

	c_navigate (a_id: INTEGER; a_url: POINTER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_navigate ((int) $a_id, (const char *) $a_url);"
		end

	c_set_echo (a_id: INTEGER; a_url: POINTER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_set_echo ((int) $a_id, (const char *) $a_url);"
		end

	c_set_html_with_base (a_id: INTEGER; a_html, a_base: POINTER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_set_html_with_base ((int) $a_id, (const char *) $a_html, (const char *) $a_base);"
		end

	c_set_title (a_id: INTEGER; a_title: POINTER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_set_title ((int) $a_id, (const char *) $a_title);"
		end

	c_set_size (a_id, a_width, a_height, a_hint: INTEGER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_set_size ((int) $a_id, (int) $a_width, (int) $a_height, (int) $a_hint);"
		end

	c_show (a_id: INTEGER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_show ((int) $a_id);"
		end

	c_eval (a_id: INTEGER; a_script: POINTER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_eval ((int) $a_id, (const char *) $a_script);"
		end

	c_add_script (a_id: INTEGER; a_name, a_script: POINTER; a_now, a_all_frames: INTEGER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_add_script ((int) $a_id, (const char *) $a_name, (const char *) $a_script, (int) $a_now, (int) $a_all_frames);"
		end

	c_remove_script (a_id: INTEGER; a_name: POINTER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_remove_script ((int) $a_id, (const char *) $a_name);"
		end

	c_evaluate (a_id, a_ticket: INTEGER; a_body: POINTER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_evaluate ((int) $a_id, (int) $a_ticket, (const char *) $a_body);"
		end

	c_set_deciding (a_id, a_on: INTEGER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_set_deciding ((int) $a_id, (int) $a_on);"
		end

	c_decide (a_id, a_decision, a_allow: INTEGER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_decide ((int) $a_id, (int) $a_decision, (int) $a_allow);"
		end

	c_set_dev_tools (a_id, a_on: INTEGER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_set_dev_tools ((int) $a_id, (int) $a_on);"
		end

	c_pump (a_id, a_ms: INTEGER)
			-- `blocking': the thread waits in the main loop here, and a thread the runtime counts
			-- as inside Eiffel code would make every other processor's collection wait for it.
			-- sb_gtk.h's signal handlers only queue C data; they never touch an Eiffel object.
		external
			"C blocking inline use %"sb_gtk.h%""
		alias
			"sbg_pump ((int) $a_id, (int) $a_ms);"
		end

	c_wake
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_wake ();"
		end

	c_take (a_id: INTEGER): BOOLEAN
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return (EIF_BOOLEAN) (sbg_take ((int) $a_id) != 0);"
		end

	c_current_kind (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_current_kind ((int) $a_id);"
		end

	c_current_a (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_current_a ((int) $a_id);"
		end

	c_current_b (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_current_b ((int) $a_id);"
		end

	c_current_c (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_current_c ((int) $a_id);"
		end

	c_current_text (a_id, a_index: INTEGER): POINTER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return (EIF_POINTER) sbg_current_text ((int) $a_id, (int) $a_index);"
		end

	c_window_count (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_window_count ((int) $a_id);"
		end

	c_content_size (a_id, a_height: INTEGER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_content_size ((int) $a_id, (int) $a_height);"
		end

	c_is_resizable (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_gtk.h%""
		alias
			"return sbg_is_resizable ((int) $a_id);"
		end

	c_dispose (a_id: INTEGER)
		external
			"C inline use %"sb_gtk.h%""
		alias
			"sbg_dispose ((int) $a_id);"
		end

invariant
	id_in_range: id >= 0 and id <= 16

end
