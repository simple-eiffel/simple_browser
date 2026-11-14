note
	description: "[
		WEBVIEW_ENGINE - the Windows engine: webview.dll (WebView2 inside), with WebView2
		reached through webview_get_native_handle for what webview.dll does not offer
		(Clib/windows/sb_win.h).

		- The loop: C never calls Eiffel. WebView2's callbacks queue events in C; `pump'
		  handles this thread's messages (a `blocking' external), and `next_event' takes them.
		- Calls from the page: the shared bridge (SB_SCRIPTS.Bridge_script) posts them through
		  `window.chrome.webview.postMessage'; webview.dll's own bind is not used.
		- `evaluate': ExecuteScript takes neither a function body nor a promise, so the shared
		  body runs inside an async function expression that posts its string back through the
		  same channel, tagged with the ticket (`Evaluate_wrapper_windows').
		- Navigation decisions: NavigationStarting takes no deferral, so sb_win.h cancels a
		  navigation the page starts at once and, if `decide' allows it, starts it again with
		  ICoreWebView2::Navigate (let through as the engine's own load). WebView2 reports no
		  fragment navigation within a page; `Hint_script' holds those through the Navigation
		  API. WebView2 1.0.1150's arguments do not tell a link from a form, so `Hint_script'
		  also reports link clicks and form submissions just before the navigation they start.
		- New windows: NewWindowRequested, Handled = TRUE, reported.
		- The title: DocumentTitleChanged. The end of a load: NavigationCompleted.
		- Ephemeral: webview.dll makes the controller itself, without options, so an
		  InPrivate controller is out of reach; an ephemeral engine gets a fresh user-data
		  folder in the temporary directory (WEBVIEW2_USER_DATA_FOLDER while webview_create
		  runs), deleted on `dispose' once WebView2's processes let go of it (spec 4.6).
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	WEBVIEW_ENGINE

inherit
	BROWSER_ENGINE
		redefine
			set_debug_mode
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
			-- A browser inside the window `a_parent' (an HWND).
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
		local
			l_script: C_STRING
			l_name: C_STRING
		do
			is_ephemeral := a_ephemeral
			is_debug_mode := a_debug
			id := c_create (a_ephemeral.to_integer, a_debug.to_integer, a_parent)
			if id = 0 then
				last_error := {STRING_32} "WebView2 could not start (error " + c_last_error.out + ")"
			else
				create l_name.make ("")
				create l_script.make (Hint_script)
				c_add_script (id, l_name.item, l_script.item)
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
			-- Does the engine keep its data in a temporary folder deleted on `dispose'?

	last_error: detachable STRING_32
			-- Why the engine is not valid, if it is not.

feature -- Window access

	window_handle: POINTER
			-- <Precursor>
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
		local
			l_script: C_STRING
		do
			create l_script.make (utf_8 (a_script))
			c_init_js (id, l_script.item)
		end

	set_bridge (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_name, l_script: C_STRING
		do
			create l_name.make ("")
			create l_script.make (main_frame_only (utf_8 (a_script)))
			c_add_script (id, l_name.item, l_script.item)
		end

	bind_name (a_name, a_line: STRING_8)
			-- <Precursor>
		local
			l_name, l_line: C_STRING
		do
			unbind_name (a_name)
			create l_name.make (a_name)
			create l_line.make (main_frame_only (a_line))
			c_add_script (id, l_name.item, l_line.item)
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
			l_text: STRING_8
			l_script: C_STRING
		do
			create l_text.make_from_string (Evaluate_wrapper_windows)
			l_text.replace_substring_all (Ticket_placeholder, a_ticket.out)
			l_text.replace_substring_all (Body_placeholder, utf_8 (a_body))
			create l_script.make (l_text)
			c_evaluate (id, a_ticket, l_script.item)
		end

feature -- Navigation decisions

	set_deciding (a_on: BOOLEAN)
			-- <Precursor>
			-- Also tell `Hint_script' on every page whether to hold fragment navigations.
		local
			l_name, l_script: C_STRING
		do
			is_deciding := a_on
			c_set_deciding (id, a_on.to_integer)
			create l_name.make (Asks_name)
			c_remove_script (id, l_name.item)
			if a_on then
				create l_script.make ("window.__sb_win_asks = true;")
				c_add_script (id, l_name.item, l_script.item)
			else
				create l_script.make ("window.__sb_win_asks = false;")
				c_eval (id, l_script.item)
			end
		end

	decide (a_decision: INTEGER; a_allow: BOOLEAN)
			-- <Precursor>
			-- A navigation `Hint_script' held on the page (a fragment, a form) is replayed there,
			-- in its own frame, if allowed; any other is replayed by sb_win.h.
		local
			l_script: C_STRING
		do
			if a_decision >= Page_decision_base then
				if attached page_decisions.item (a_decision) as al_held then
					page_decisions.remove (a_decision)
					if a_allow then
						if al_held.pass then
							c_pass_next (id, al_held.frame)
						end
						create l_script.make (al_held.replay)
					else
						create l_script.make (al_held.drop)
					end
					c_eval_in (id, al_held.frame, l_script.item)
				end
			else
				c_decide (id, a_decision, a_allow.to_integer)
			end
		end

feature -- The loop

	pump (a_ms: INTEGER)
			-- <Precursor>
		do
			c_pump (id, a_ms)
		end

	next_event: BOOLEAN
			-- <Precursor>
			-- Web messages become `call' and `evaluated' events here; navigation-kind hints are
			-- kept for the navigation they precede.
		local
			l_done: BOOLEAN
			l_kind: INTEGER
		do
			from
			until
				l_done
			loop
				if c_take (id) then
					l_kind := c_current_kind (id)
					if l_kind = Message_kind then
						Result := take_message (current_text (1), c_current_c (id))
						l_done := Result
					elseif is_event_kind (l_kind) then
						if l_kind = Event_navigating then
							set_event (l_kind, c_current_a (id), navigation_kind (current_text (1)), c_current_c (id),
								current_text (1), current_text (2), current_text (3))
						else
							set_event (l_kind, c_current_a (id), c_current_b (id), c_current_c (id),
								current_text (1), current_text (2), current_text (3))
						end
						Result := True
						l_done := True
					end
				else
					l_done := True
				end
			end
		end

feature -- Lifecycle

	terminate
			-- <Precursor>
		do
		end

	dispose
			-- <Precursor>
		do
			if id > 0 then
				c_dispose (id)
				id := 0
			end
			page_decisions.wipe_out
		end

feature -- Debug control

	set_debug_mode (a_enabled: BOOLEAN)
			-- <Precursor>
			-- Also turn WebView2's developer tools on or off.
		do
			Precursor (a_enabled)
			if is_valid then
				c_set_dev_tools (id, a_enabled.to_integer)
			end
		end

feature -- Test hooks

	test_window_count: INTEGER
			-- <Precursor>
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

	test_echo_at (a_url: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_url: C_STRING
		do
			create l_url.make (utf_8 (a_url))
			c_set_echo (id, l_url.item)
		end

feature {NONE} -- Web messages

	take_message (a_json: STRING_8; a_frame: INTEGER): BOOLEAN
			-- Make the web message `a_json' from frame `a_frame' (0 the main frame) the event last
			-- taken, if it is a call or a result (main frame only, as the bridge is) or a
			-- navigation held on the page; keep it as `hint_url' and `hint_kind' if it is a
			-- navigation-kind hint.
		local
			l_json: SIMPLE_JSON
			l_utf: UTF_CONVERTER
			l_ticket, l_status: INTEGER
			l_result, l_url: STRING_8
		do
			create l_json
			if not a_json.is_empty and then attached l_json.parse (l_utf.utf_8_string_8_to_string_32 (a_json)) as al_value
				and then al_value.is_object
			then
				if attached al_value.as_object as al_object then
					if a_frame = 0 and attached al_object.string_item ("name") as al_name
						and attached al_object.string_item ("seq") as al_seq
						and attached al_object.string_item ("args") as al_args
					then
						set_event (Event_call, 0, 0, 0, l_utf.utf_32_string_to_utf_8_string_8 (al_name),
							l_utf.utf_32_string_to_utf_8_string_8 (al_seq), l_utf.utf_32_string_to_utf_8_string_8 (al_args))
						Result := True
					elseif a_frame = 0 and attached al_object.item ("sb_ticket") as al_ticket and then al_ticket.is_number then
						l_ticket := al_ticket.as_integer.to_integer_32
						l_status := 1
						if attached al_object.item ("status") as al_status and then al_status.is_number then
							l_status := al_status.as_integer.to_integer_32
						end
						if attached al_object.string_item ("json") as al_result then
							l_result := l_utf.utf_32_string_to_utf_8_string_8 (al_result)
						else
							l_result := "null"
						end
						set_event (Event_evaluated, l_ticket, l_status, 0, l_result, create {STRING_8}.make_empty,
							create {STRING_8}.make_empty)
						Result := True
					elseif attached al_object.string_item ("sb_fragment") as al_fragment then
						l_url := l_utf.utf_32_string_to_utf_8_string_8 (al_fragment)
						Result := take_page_decision (l_url, al_object.integer_32_item ("kind"), a_frame,
							"window.__sb_win_replay = " + scripts.json_string_8 (l_url) + "; location.href = "
								+ scripts.json_string_8 (l_url) + ";",
							"", False)
					elseif attached al_object.item ("sb_form") as al_form and then al_form.is_number
						and attached al_object.string_item ("url") as al_form_url
					then
						l_url := l_utf.utf_32_string_to_utf_8_string_8 (al_form_url)
						Result := take_page_decision (l_url, {SB_NAVIGATION}.Kind_form, a_frame,
							"window.__sb_win_replay_form (" + al_form.as_integer.out + ");",
							"window.__sb_win_drop_form (" + al_form.as_integer.out + ");", True)
					elseif attached al_object.item ("sb_hint") as al_hint and then al_hint.is_number
						and attached al_object.string_item ("url") as al_url
					then
						hint_kind := al_hint.as_integer.to_integer_32
						hint_url := al_url
					end
				end
			end
		end

	take_page_decision (a_url: STRING_8; a_kind, a_frame: INTEGER; a_replay, a_drop: STRING_8; a_pass: BOOLEAN): BOOLEAN
			-- Make the navigation to `a_url' that `Hint_script' held in frame `a_frame' a
			-- `navigating' event, under a decision number of this engine's own. `decide' runs
			-- `a_replay' there if allowed (after letting the frame's next navigation through
			-- if `a_pass'), else `a_drop'.
		local
			l_kind: INTEGER
		do
			if is_deciding then
				last_page_decision := last_page_decision.max (Page_decision_base - 1) + 1
				page_decisions.force ([a_replay, a_drop, a_frame, a_pass], last_page_decision)
				l_kind := navigation_kind (a_url)
				if l_kind = 0 and a_kind >= 0 and a_kind <= 4 then
					l_kind := a_kind
				end
				set_event (Event_navigating, last_page_decision, l_kind, (a_frame = 0).to_integer, a_url,
					create {STRING_8}.make_empty, create {STRING_8}.make_empty)
				Result := True
			elseif not a_replay.is_empty then
					-- Asked while no handler was set (the flag was late): allow at once.
				if a_pass then
					c_pass_next (id, a_frame)
				end
				c_eval_in (id, a_frame, (create {C_STRING}.make (a_replay)).item)
			end
		end

	page_decisions: HASH_TABLE [TUPLE [replay, drop: STRING_8; frame: INTEGER; pass: BOOLEAN], INTEGER]
			-- Navigations held on the page, by decision number: what allowing and refusing run.
		attribute
			create Result.make (4)
		end

	last_page_decision: INTEGER
			-- The last decision number given to a navigation held on the page (0 before the
			-- first; numbers start at `Page_decision_base').

	Page_decision_base: INTEGER = 1_000_000_000
			-- Decision numbers of navigations held on the page start here (sb_win.h's stay below).

	main_frame_only (a_script: STRING_8): STRING_8
			-- `a_script' run only in the main frame (as WKWebView's and WebKitGTK's user scripts
			-- are): WebView2 runs document-start scripts in every frame.
		do
			Result := "if (window === window.top) {%N" + a_script + "%N}"
		ensure
			holds_the_script: Result.has_substring (a_script)
		end

	Asks_name: STRING_8 = "__sb_win_asks"
			-- The name of the document-start script that sets `window.__sb_win_asks'.

	hint_kind: INTEGER
			-- The kind of the last link click or form submission the page reported.

	hint_url: detachable STRING_32
			-- Where that link or form goes.

	navigation_kind (a_url: STRING_8): INTEGER
			-- The kind of a navigation to `a_url' (UTF-8): the hint's, if the hint is for it.
		local
			l_url: STRING_32
			l_utf: UTF_CONVERTER
		do
			if attached hint_url as al_hint then
				l_url := l_utf.utf_8_string_8_to_string_32 (a_url)
				if l_url.same_string (al_hint) or else (hint_kind = 2 and l_url.starts_with (al_hint)) then
					if hint_kind >= 1 and hint_kind <= 4 then
						Result := hint_kind
					end
				end
				hint_url := Void
			end
		ensure
			known: Result >= 0 and Result <= 4
		end

feature {NONE} -- Implementation

	id: INTEGER
			-- The engine's number in C (sb_win.h); 0 when not valid.

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

	Message_kind: INTEGER = 100
			-- A raw web message (sb_win.h's SBW_EVENT_MESSAGE).

	Ticket_placeholder: STRING_8 = "@TICKET@"
			-- Where `Evaluate_wrapper_windows' takes the ticket.

	Body_placeholder: STRING_8 = "@BODY@"
			-- Where `Evaluate_wrapper_windows' takes the shared evaluate body.

	Evaluate_wrapper_windows: STRING_8 = "[
(async () => {
@BODY@
}) ().then (
  (s) => window.chrome.webview.postMessage ({sb_ticket: @TICKET@, status: 0, json: s}),
  (e) => window.chrome.webview.postMessage ({sb_ticket: @TICKET@, status: 1,
    json: JSON.stringify (String ((e !== null && typeof e === "object" && "message" in e) ? e.message : e))}));
"sb-evaluating";
]"
			-- ExecuteScript's script for `evaluate': the shared body in an async function
			-- expression whose string goes back through the bridge's channel with the ticket.
			-- Its own value tells sb_win.h that the script compiled and started.

	Hint_script: STRING_8 = "[
(() => {
  if (window.__sb_hints) { return; }
  Object.defineProperty (window, "__sb_hints", {value: true});
  const post = (message) => {
    if (window.chrome && window.chrome.webview) { window.chrome.webview.postMessage (message); }
  };
  window.addEventListener ("click", (event) => {
    if (event.defaultPrevented || !event.target || !event.target.closest) { return; }
    const link = event.target.closest ("a[href]");
    if (link && typeof link.href === "string") { post ({sb_hint: 1, url: link.href}); }
  });
  const forms = new Map ();
  let form_serial = 0;
  const native_submit = HTMLFormElement.prototype.submit;
  const form_target = (form, submitter) => {
    const target = (submitter && submitter.formTarget) || form.target || "";
    return target === "" || target === "_self";
  };
  const form_method = (form, submitter) =>
    String ((submitter && submitter.hasAttribute ("formmethod") && submitter.formMethod) || form.method || "get").toLowerCase ();
  const form_url = (form, submitter) => {
    const action = (submitter && submitter.hasAttribute ("formaction")) ? submitter.formAction : form.action;
    if (form_method (form, submitter) !== "get") { return action; }
    const url = new URL (action);
    url.search = new URLSearchParams (submitter ? new FormData (form, submitter) : new FormData (form)).toString ();
    return url.href;
  };
  const holds = (form, submitter) =>
    window.__sb_win_asks === true && form_target (form, submitter) && form_method (form, submitter) !== "dialog";
  const hold_form = (form, submitter, native) => {
    form_serial = form_serial + 1;
    forms.set (form_serial, {form: form, submitter: submitter, native: native});
    post ({sb_form: form_serial, url: form_url (form, submitter)});
  };
  Object.defineProperty (window, "__sb_win_replay_form", {value: (serial) => {
    const held = forms.get (serial);
    if (held === undefined) { return; }
    forms.delete (serial);
    held.form.__sb_win_pass = true;
    if (held.native) {
      native_submit.call (held.form);
      held.form.__sb_win_pass = false;
    } else if (held.submitter && held.submitter.isConnected) {
      held.form.requestSubmit (held.submitter);
    } else {
      held.form.requestSubmit ();
    }
  }});
  Object.defineProperty (window, "__sb_win_drop_form", {value: (serial) => { forms.delete (serial); }});
  HTMLFormElement.prototype.submit = function () {
    if (this.__sb_win_pass !== true && holds (this, null)) { hold_form (this, null, true); return; }
    return native_submit.call (this);
  };
  window.addEventListener ("submit", (event) => {
    if (event.defaultPrevented || !event.target) { return; }
    const form = event.target;
    if (form.__sb_win_pass === true) { form.__sb_win_pass = false; return; }
    if (holds (form, event.submitter)) {
      event.preventDefault ();
      hold_form (form, event.submitter || null, false);
    } else if (typeof form.action === "string") {
      post ({sb_hint: 2, url: form.action});
    }
  });
  if (window.navigation && window.navigation.addEventListener) {
    window.navigation.addEventListener ("navigate", (event) => {
      if (window.__sb_win_asks !== true || !event.hashChange || !event.cancelable || event.formData) { return; }
      const url = event.destination.url;
      if (window.__sb_win_replay === url) { window.__sb_win_replay = undefined; return; }
      event.preventDefault ();
      post ({sb_fragment: url, kind: event.navigationType === "traverse" ? 3 : 0});
    });
  }
}) ();
]"
			-- This engine's own document-start script:
			-- - a link click or form submission the page did not cancel, reported before the
			--   navigation it starts (WebView2 1.0.1150 does not tell a link from a form);
			-- - while `window.__sb_win_asks' (`set_deciding'), a fragment navigation within the
			--   page, which WebView2 does not report, held through the Navigation API and
			--   reported for `decide';
			-- - while `window.__sb_win_asks', a form submission (the submit event, or
			--   HTMLFormElement.submit), held on the page and submitted again exactly (POST and
			--   body included) if `decide' allows it, since a replay by URL would lose the body.
			-- It runs in every frame; the bridge and the bindings run in the main frame only.

feature {NONE} -- C externals

	c_create (a_ephemeral, a_debug: INTEGER; a_parent: POINTER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_create ((int) $a_ephemeral, (int) $a_debug, (void *) $a_parent);"
		end

	c_last_error: INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_last_error ();"
		end

	c_window (a_id: INTEGER): POINTER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_window ((int) $a_id);"
		end

	c_navigate (a_id: INTEGER; a_url: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_navigate ((int) $a_id, (const char *) $a_url);"
		end

	c_set_echo (a_id: INTEGER; a_url: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_set_echo ((int) $a_id, (const char *) $a_url);"
		end

	c_pass_next (a_id, a_frame: INTEGER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_pass_next ((int) $a_id, (int) $a_frame);"
		end

	c_eval_in (a_id, a_frame: INTEGER; a_script: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_eval_in ((int) $a_id, (int) $a_frame, (const char *) $a_script);"
		end

	c_set_html_with_base (a_id: INTEGER; a_html, a_base: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_set_html_with_base ((int) $a_id, (const char *) $a_html, (const char *) $a_base);"
		end

	c_set_title (a_id: INTEGER; a_title: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"[
				sbw_engine_t *l_engine = sbw_engine ((int) $a_id);
				if (l_engine) { webview_set_title (l_engine->w, (const char *) $a_title); }
			]"
		end

	c_set_size (a_id, a_width, a_height, a_hint: INTEGER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_set_size ((int) $a_id, (int) $a_width, (int) $a_height, (int) $a_hint);"
		end

	c_show (a_id: INTEGER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_show ((int) $a_id);"
		end

	c_eval (a_id: INTEGER; a_script: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_eval ((int) $a_id, (const char *) $a_script);"
		end

	c_init_js (a_id: INTEGER; a_script: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"[
				sbw_engine_t *l_engine = sbw_engine ((int) $a_id);
				if (l_engine) { webview_init (l_engine->w, (const char *) $a_script); }
			]"
		end

	c_add_script (a_id: INTEGER; a_name, a_script: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_add_script ((int) $a_id, (const char *) $a_name, (const char *) $a_script);"
		end

	c_remove_script (a_id: INTEGER; a_name: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_remove_script ((int) $a_id, (const char *) $a_name);"
		end

	c_evaluate (a_id, a_ticket: INTEGER; a_script: POINTER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_evaluate ((int) $a_id, (int) $a_ticket, (const char *) $a_script);"
		end

	c_set_deciding (a_id, a_on: INTEGER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_set_deciding ((int) $a_id, (int) $a_on);"
		end

	c_decide (a_id, a_decision, a_allow: INTEGER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_decide ((int) $a_id, (int) $a_decision, (int) $a_allow);"
		end

	c_set_dev_tools (a_id, a_on: INTEGER)
		external
			"C inline use %"sb_win.h%""
		alias
			"sbw_set_dev_tools ((int) $a_id, (int) $a_on);"
		end

	c_pump (a_id, a_ms: INTEGER)
			-- `blocking': the thread waits for messages here, and a thread the runtime counts
			-- as inside Eiffel code would make every other processor's collection wait for it.
			-- sb_win.h's callbacks only queue C data; they never touch an Eiffel object.
		external
			"C blocking inline use %"sb_win.h%""
		alias
			"sbw_pump ((int) $a_id, (int) $a_ms);"
		end

	c_take (a_id: INTEGER): BOOLEAN
		external
			"C inline use %"sb_win.h%""
		alias
			"return (EIF_BOOLEAN) (sbw_take ((int) $a_id) != 0);"
		end

	c_current_kind (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_current_kind ((int) $a_id);"
		end

	c_current_a (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_current_a ((int) $a_id);"
		end

	c_current_b (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_current_b ((int) $a_id);"
		end

	c_current_c (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_current_c ((int) $a_id);"
		end

	c_current_text (a_id, a_index: INTEGER): POINTER
		external
			"C inline use %"sb_win.h%""
		alias
			"return (EIF_POINTER) sbw_current_text ((int) $a_id, (int) $a_index);"
		end

	c_window_count (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_window_count ((int) $a_id);"
		end

	c_content_size (a_id, a_height: INTEGER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_content_size ((int) $a_id, (int) $a_height);"
		end

	c_is_resizable (a_id: INTEGER): INTEGER
		external
			"C inline use %"sb_win.h%""
		alias
			"return sbw_is_resizable ((int) $a_id);"
		end

	c_dispose (a_id: INTEGER)
			-- `blocking': disposing an ephemeral engine waits (up to 15 seconds) for WebView2's
			-- processes to let go of its data folder before deleting it.
		external
			"C blocking inline use %"sb_win.h%""
		alias
			"sbw_dispose ((int) $a_id);"
		end

invariant
	id_in_range: id >= 0 and id <= 16

end
