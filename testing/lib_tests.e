note
	description: "[
		Tests for simple_browser: today's tests (`test_creation', `test_binding_round_trip',
		`test_gc_runs_while_the_window_loop_runs') and the shared tests of
		SIMPLE_BROWSER_SPEC.md section 5, the same on Windows, macOS and Linux.

		Every shared test starts from a local HTML string, needs no network and uses an
		ephemeral browser. Each page has a watchdog: after `Watchdog_ms' it calls the binding
		`sb_watchdog', which records `timed_out' and closes the browser, so one stuck test
		fails instead of hanging the run.
	]"
	date: "$Date$"
	revision: "$Revision$"

class
	LIB_TESTS

inherit
	TEST_SET_BASE

feature -- Tests

	test_creation
			-- Test that library can be used.
		do
			assert ("placeholder", True)
		end

feature -- Tests (live WebView2 window)

	test_binding_round_trip
			-- JavaScript calls a bound Eiffel routine three times, and each call runs
			-- a full collection: the C trampoline must re-enter Eiffel code and reach
			-- the bound object through its protected handle every time.
		local
			l_browser: SIMPLE_BROWSER
		do
			create l_browser.make
			assert ("WebView2 available", l_browser.is_valid)
			ping_count := 0
			l_browser.on_call ("ping", agent on_ping (l_browser, ?, ?))
			l_browser.set_html_content ("<script>(async () => { for (let i = 0; i < 3; i++) { await window.ping(i); } })();</script>")
			l_browser.run
			assert_integers_equal ("three pings answered", 3, ping_count)
		end

	test_gc_runs_while_the_window_loop_runs
			-- Another processor collects garbage while the root sits in the window's
			-- message loop. `run' is a blocking external, so the collector does not
			-- wait for the root: the page starts the worker from inside the loop and
			-- asks two seconds later, by when 20 collections are long done. Before
			-- the fix every collection waited for the next callback.
		local
			l_browser: SIMPLE_BROWSER
			l_worker: separate GC_CHURN_WORKER
		do
			create l_browser.make
			assert ("WebView2 available", l_browser.is_valid)
			create l_worker
			churn_rounds := 0
			churn_ms := 0
			l_browser.on_call ("go", agent on_go (l_browser, l_worker, ?, ?))
			l_browser.on_call ("check", agent on_check (l_browser, l_worker, ?, ?))
			l_browser.set_html_content ("<script>window.go().then(() => setTimeout(() => window.check(), 2000));</script>")
			l_browser.run
			print ("    worker: " + churn_rounds.out + " collections in " + churn_ms.out + " ms%N")
			assert_integers_equal ("all 20 collections ran", 20, churn_rounds)
			assert ("20 collections took under a second (" + churn_ms.out + " ms)", churn_ms < 1000)
		end

feature -- Tests (shared, SIMPLE_BROWSER_SPEC.md section 5)

	test_a_page_loads_and_tells_its_title
			-- `on_loaded' reports ok once and `on_title' reports "One"; then
			-- `evaluate ("document.title = 'Two'")' and `on_title' reports "Two".
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_loaded (agent on_title_page_loaded (l_browser, ?, ?))
			l_browser.on_title (agent on_title_page_title (l_browser, ?))
			l_browser.set_html_content ("<html><head><title>One</title></head><body>one</body></html>")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_integers_equal ("loaded once", 1, loads_ok)
			assert_integers_equal ("no failed load", 0, loads_failed)
			assert ("title One reported", titles.has ({STRING_32} "One"))
			assert ("title Two reported last", not titles.is_empty and then titles.last.same_string ("Two"))
			assert ("One before Two", titles.index_of ({STRING_32} "One", 1) < titles.index_of ({STRING_32} "Two", 1))
		end

	test_evaluate_returns_json
			-- Results come back as JSON text; promises are awaited; a thrown error gives
			-- ok False and its message.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_loaded (agent on_evaluate_page_loaded (l_browser, ?, ?))
			l_browser.set_html_content ("<html><head><title>Tee</title></head><body></body></html>")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_equal ("1 + 2", "ok 3", results.item ("sum"))
			assert_equal ("document.title", "ok %"Tee%"", results.item ("title"))
			assert_equal ("undefined", "ok null", results.item ("undefined"))
			assert_equal ("Promise.resolve (42)", "ok 42", results.item ("promise"))
			if attached results.item ("throw") as al_thrown then
				assert_string_starts_with ("throw gives ok False", al_thrown, "error ")
				assert_string_contains ("the message holds x", al_thrown, "x")
			else
				assert ("throw answered", False)
			end
		end

	test_a_binding_round_trip
			-- Three awaited calls, each with a full collection in the handler; `respond'
			-- resolves with the value, which the page echoes back through a second binding;
			-- `respond_error' rejects; an answer that is not JSON rejects with a string.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			ping_count := 0
			l_browser.on_call ("ping", agent on_round_trip_ping (l_browser, ?, ?))
			l_browser.on_call ("fail", agent on_round_trip_fail (l_browser, ?, ?))
			l_browser.on_call ("bad", agent on_round_trip_bad (l_browser, ?, ?))
			l_browser.on_call ("echo", agent on_round_trip_echo (l_browser, ?, ?))
			l_browser.set_html_content ("[
				<script>
				(async () => {
				  for (let i = 0; i < 3; i++) { const v = await window.ping (i); await window.echo (v); }
				  try { await window.fail (); await window.echo ("not rejected"); }
				  catch (e) { await window.echo ({rejected: e}); }
				  try { await window.bad (); await window.echo ("not rejected"); }
				  catch (e) { await window.echo ({bad: typeof e}); }
				  await window.echo ("done");
				}) ();
				</script>
			]")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_integers_equal ("three pings", 3, ping_count)
			assert_integers_equal ("six echoes", 6, echoes.count)
			if echoes.count = 6 then
				assert_equal ("first value", "[{%"got%":[0]}]", echoes [1])
				assert_equal ("second value", "[{%"got%":[1]}]", echoes [2])
				assert_equal ("third value", "[{%"got%":[2]}]", echoes [3])
				assert_equal ("respond_error rejects", "[{%"rejected%":%"nope%"}]", echoes [4])
				assert_equal ("not JSON rejects with a string", "[{%"bad%":%"string%"}]", echoes [5])
			end
		end

	test_inject_runs_before_the_page
			-- `inject ("window.early = 1")': a page script reads it and calls a binding with it.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.inject ("window.early = 1;")
			l_browser.on_call ("report", agent on_report (l_browser, ?, ?))
			l_browser.set_html_content ("<html><body><script>window.report (window.early);</script></body></html>")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_equal ("the page saw 1", "[1]", reported)
		end

	test_a_navigation_is_held_and_answered
			-- The handler cancels about:blank#blocked and allows about:blank#allowed; the page
			-- clicks a link to each; `location.hash' is then "#allowed"; both were links in the
			-- main frame. A link inside an iframe is asked too, not in the main frame; the parent
			-- page setting an iframe's srcdoc or src is not asked.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_navigation (agent on_hold_navigation (l_browser, ?))
			l_browser.on_loaded (agent on_hold_loaded (l_browser, ?, ?))
			l_browser.set_html_content ("[
				<html><body>
				<a id="blocked" href="about:blank#blocked">blocked</a>
				<a id="allowed" href="about:blank#allowed">allowed</a>
				<iframe id="frame" srcdoc="<a id=&quot;inner&quot; href=&quot;about:blank#inner&quot;>inner</a>"></iframe>
				<iframe id="plain" src="about:blank"></iframe>
				<script>
				setTimeout (() => {
				  document.getElementById ("frame").contentDocument.getElementById ("inner").click ();
				  setTimeout (() => {
				    document.getElementById ("frame").srcdoc = "<p>second</p>";
				    document.getElementById ("plain").src = "about:blank#parent";
				  }, 500);
				  setTimeout (() => document.getElementById ("blocked").click (), 1000);
				  setTimeout (() => document.getElementById ("allowed").click (), 1500);
				}, 300);
				</script>
				</body></html>
			]")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_equal ("#blocked: a link in the main frame", "1 main", asked.item ("about:blank#blocked"))
			assert_equal ("#allowed: a link in the main frame", "1 main", asked.item ("about:blank#allowed"))
			if attached asked.item ("about:blank#inner") as al_inner then
				assert_string_ends_with ("#inner: not in the main frame", al_inner, " iframe")
			else
				assert ("asked about the iframe's #inner", False)
			end
			refute ("the parent setting srcdoc is not asked", asked.has ("about:srcdoc"))
			refute ("the parent setting src is not asked", asked.has ("about:blank#parent"))
			assert_equal ("location.hash", "ok %"#allowed%"", results.item ("hash"))
		end

	test_a_form_is_held_and_submitted
			-- A form with method POST, held then allowed, reaches the page it posts to with its
			-- fields: the replay is the real request, not a GET of its URL.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.engine.test_echo_at (Echo_url)
			l_browser.on_navigation (agent on_form_navigation)
			l_browser.on_loaded (agent on_form_loaded (l_browser, ?, ?))
			l_browser.set_html_content ("[
				<html><body>
				<form id="form" method="post" action="https://simple-browser.invalid/echo">
				<input name="a" value="1"><input name="b" value="two words">
				<button id="send" type="submit">send</button>
				</form>
				<script>setTimeout (() => document.getElementById ("send").click (), 300);</script>
				</body></html>
			]")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_equal ("the form was asked about, as a form in the main frame", "2 main", asked.item (Echo_url))
			assert_equal ("the page got POST and the fields", "ok %"POST\na=1&b=two+words%"", results.item ("echo"))
		end

	test_a_set_html_page_has_the_shared_origin
			-- Every `set_html' page loads at https://simple-browser.invalid/page-N, on every
			-- platform (SB_SCRIPTS.set_html_base).
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_loaded (agent on_store_loaded (l_browser, "location.origin", "origin", ?, ?))
			l_browser.set_html_content ("<html><body>origin</body></html>")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_equal ("location.origin", "ok %"https://simple-browser.invalid%"", results.item ("origin"))
		end

	test_a_new_window_is_reported_not_opened
			-- `window.open' and a target=_blank link each report their url to
			-- `on_new_window'; the engine's window count stays 1.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_new_window (agent on_new_window_request (l_browser, ?))
			l_browser.set_html_content ("[
				<html><body>
				<a id="link" target="_blank" href="about:blank#link">link</a>
				<script>
				setTimeout (() => {
				  window.open ("about:blank#new");
				  document.getElementById ("link").click ();
				}, 200);
				</script>
				</body></html>
			]")
			l_browser.run
			refute ("no timeout", timed_out)
			assert ("window.open reported", new_windows.has ({STRING_32} "about:blank#new"))
			assert ("target=_blank reported", new_windows.has ({STRING_32} "about:blank#link"))
			assert_integers_equal ("one window", 1, window_count)
			l_browser.dispose
		end

	test_the_ephemeral_store_forgets
			-- One ephemeral engine sets localStorage.k, then is disposed; a second, at the same
			-- origin, reads it as null.
		local
			l_first, l_second: SIMPLE_BROWSER
		do
			l_first := new_browser
			l_first.on_loaded (agent on_store_loaded (l_first, "(localStorage.k = 'v', localStorage.k)", "first", ?, ?))
			l_first.engine.set_html_with_base ("<html><body>first</body></html>", Store_origin)
			l_first.run
			l_first.dispose
			refute ("no timeout (first)", timed_out)
			assert_equal ("the first engine stores v", "ok %"v%"", results.item ("first"))
			l_second := new_browser
			l_second.on_loaded (agent on_store_loaded (l_second, "localStorage.k", "second", ?, ?))
			l_second.engine.set_html_with_base ("<html><body>second</body></html>", Store_origin)
			l_second.run
			l_second.dispose
			refute ("no timeout (second)", timed_out)
			assert_equal ("the second engine finds nothing", "ok null", results.item ("second"))
		end

	test_the_program_navigation_is_not_asked
			-- With a handler that cancels everything, `set_html' and `navigate ("about:blank")'
			-- still load, and the handler is never asked.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_navigation (agent on_cancel_everything)
			l_browser.on_loaded (agent on_own_load (l_browser, ?, ?))
			l_browser.set_html_content ("<html><body>own</body></html>")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_integers_equal ("both loads ended ok", 2, loads_ok)
			assert_integers_equal ("never asked", 0, navigations.count)
		end

	test_close_ends_run
			-- `close' from a handler ends `run'; `dispose' with a decision held answers it.
		local
			l_browser: SIMPLE_BROWSER
			l_tries: INTEGER
			l_held: BOOLEAN
		do
			l_browser := new_browser
			l_browser.on_navigation (agent on_cancel_everything)
			l_browser.on_call ("stop", agent on_stop (l_browser, ?, ?))
			l_browser.set_html_content ("[
				<html><body><a id="away" href="about:blank#away">away</a>
				<script>
				window.stop ().then (() => setTimeout (() => document.getElementById ("away").click (), 100));
				</script>
				</body></html>
			]")
			l_browser.run
			refute ("no timeout", timed_out)
			assert ("run ended by close", l_browser.is_stopping and not l_browser.is_closed)
				-- Pump without dispatching until the page's navigation is held.
			from
			until
				l_held or l_tries >= 100
			loop
				l_browser.engine.pump (50)
				from
				until
					l_held or else not l_browser.engine.next_event
				loop
					l_held := l_browser.engine.event_kind = l_browser.engine.Event_navigating
				end
				l_tries := l_tries + 1
			end
			assert ("a decision is held", l_held)
			assert_integers_equal ("the handler was not asked", 0, navigations.count)
			l_browser.dispose
			refute ("disposed", l_browser.is_valid)
		end

	test_htmx_and_alpine_load_without_the_network
			-- `load_htmx_page' with an Alpine counter: htmx and Alpine are there, at their
			-- pinned versions, and clicking the button makes the counter 1.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_loaded (agent on_htmx_loaded (l_browser, ?, ?))
			l_browser.load_htmx_page ("[
				<div x-data="{ n: 0 }">
				<button id="add" @click="n = n + 1">add</button>
				<span id="count" x-text="n"></span>
				</div>
			]")
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_equal ("typeof htmx", "ok %"object%"", results.item ("htmx"))
			assert_equal ("Alpine.version", "ok %"3.14.8%"", results.item ("alpine"))
			assert_equal ("htmx.version", "ok %"2.0.4%"", results.item ("htmx_version"))
			assert_equal ("the counter after a click", "ok %"1%"", results.item ("counter"))
		end

	test_size_hints_hold
			-- `fixed_size (400, 300)': not resizable, content 400 by 300, and a later `set_size'
			-- holds to it. A min hint clamps a later `set_size' and grows a smaller window; a
			-- max hint shrinks a larger one.
		local
			l_browser: SIMPLE_BROWSER
		do
			l_browser := new_browser
			l_browser.on_loaded (agent on_size_loaded (l_browser, ?, ?))
			l_browser.set_html_content ("<html><body>sizes</body></html>")
			size_step := 0
			l_browser.run
			l_browser.dispose
			refute ("no timeout", timed_out)
			assert_equal ("fixed 400 by 300, not resizable", "400x300 fixed", size_at (1))
			assert_equal ("fixed holds against set_size (800, 600)", "400x300 fixed", size_at (2))
			assert_equal ("min 500 by 400 grows the window", "500x400 resizable", size_at (3))
			assert_equal ("min holds against set_size (300, 200)", "500x400 resizable", size_at (4))
			assert_equal ("max 600 by 450 holds against set_size (900, 900)", "600x450 resizable", size_at (5))
			assert_equal ("max 550 by 420 shrinks the window", "550x420 resizable", size_at (6))
		end

feature -- Tests (beyond the spec's list)

	test_a_browser_inside_a_window
			-- `make_ephemeral_with_window': a browser inside another browser's window loads a
			-- page and answers `evaluate'.
		local
			l_outer, l_inner: SIMPLE_BROWSER
		do
			l_outer := new_browser
			l_outer.set_html_content ("<html><body>outer</body></html>")
			create l_inner.make_ephemeral_with_window (l_outer.engine.window_handle)
			assert ("inner browser available", l_inner.is_valid)
			l_inner.on_loaded (agent on_store_loaded (l_inner, "6 * 7", "inner", ?, ?))
			l_inner.set_html_content ("<html><body>inner</body></html>")
			l_inner.run
			l_inner.dispose
			l_outer.dispose
			assert_equal ("the inner page answers", "ok 42", results.item ("inner"))
		end

feature {NONE} -- Shared test support

	new_browser: SIMPLE_BROWSER
			-- An ephemeral browser with the watchdog, the per-test state cleared.
		do
			create Result.make_ephemeral
			assert ("browser engine available", Result.is_valid)
			timed_out := False
			loads_ok := 0
			loads_failed := 0
			create titles.make (4)
			create results.make (8)
			create echoes.make (8)
			create navigations.make (4)
			create asked.make (4)
			create new_windows.make (4)
			create sizes.make (8)
			titles.compare_objects
			echoes.compare_objects
			navigations.compare_objects
			new_windows.compare_objects
			sizes.compare_objects
			reported := Void
			window_count := 0
			allowed_seen := False
			hash_checks := 0
			Result.on_call ("sb_watchdog", agent on_watchdog (Result, ?, ?))
			Result.inject ("setTimeout (() => { if (window.sb_watchdog) { window.sb_watchdog (); } }, " + Watchdog_ms.out + ");")
		end

	Watchdog_ms: INTEGER = 20000
			-- How long a page may run before its test gives up.

	Store_origin: STRING_8 = "https://simple-browser.test/"
			-- The origin both engines of `test_the_ephemeral_store_forgets' load.

	Echo_url: STRING_32 = "https://simple-browser.invalid/echo"
			-- Where `test_a_form_is_held_and_submitted' posts (answered by `test_echo_at').

	timed_out: BOOLEAN
	loads_ok, loads_failed: INTEGER
	titles: ARRAYED_LIST [STRING_32] attribute create Result.make (0) end
	results: HASH_TABLE [STRING_8, STRING_8] attribute create Result.make (0) end
	echoes: ARRAYED_LIST [STRING_8] attribute create Result.make (0) end
	reported: detachable STRING_8
	navigations: ARRAYED_LIST [STRING_32] attribute create Result.make (0) end
	asked: HASH_TABLE [STRING_8, STRING_32] attribute create Result.make (0) end
	new_windows: ARRAYED_LIST [STRING_32] attribute create Result.make (0) end
	window_count: INTEGER
	sizes: ARRAYED_LIST [STRING_8] attribute create Result.make (0) end
	size_step: INTEGER

	on_watchdog (a_browser: SIMPLE_BROWSER; a_seq, a_args: STRING_8)
		do
			timed_out := True
			print ("    watchdog: the page ran " + Watchdog_ms.out + " ms%N")
			a_browser.respond (a_seq, "null")
			a_browser.close
		end

	record_result (a_label: STRING_8; a_ok: BOOLEAN; a_json: STRING_8)
			-- Keep "ok <json>" or "error <json>" under `a_label'.
		do
			if a_ok then
				results.force ("ok " + a_json, a_label)
			else
				results.force ("error " + a_json, a_label)
			end
		end

	on_result_then (a_browser: SIMPLE_BROWSER; a_label: STRING_8; a_then: detachable PROCEDURE; a_ok: BOOLEAN; a_json: STRING_8)
			-- Record a result, then run `a_then' (or close if there is none).
		do
			record_result (a_label, a_ok, a_json)
			if attached a_then as al_then then
				al_then.call (Void)
			else
				a_browser.close
			end
		end

	size_at (a_index: INTEGER): detachable STRING_8
			-- The size recorded by step `a_index', if it ran.
		do
			if sizes.valid_index (a_index) then
				Result := sizes [a_index]
			end
		end


feature {NONE} -- Title test

	on_title_page_loaded (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_error: STRING_32)
		do
			if a_ok then
				loads_ok := loads_ok + 1
				a_browser.evaluate ("document.title = 'Two'", agent record_result ("set", ?, ?))
			else
				loads_failed := loads_failed + 1
			end
		end

	on_title_page_title (a_browser: SIMPLE_BROWSER; a_title: STRING_32)
		do
			titles.extend (a_title)
			if a_title.same_string ("Two") then
				a_browser.close
			end
		end

feature {NONE} -- Evaluate test

	on_evaluate_page_loaded (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_error: STRING_32)
		do
			a_browser.evaluate ("1 + 2", agent on_evaluated (a_browser, "sum", ?, ?))
			a_browser.evaluate ("document.title", agent on_evaluated (a_browser, "title", ?, ?))
			a_browser.evaluate ("undefined", agent on_evaluated (a_browser, "undefined", ?, ?))
			a_browser.evaluate ("Promise.resolve (42)", agent on_evaluated (a_browser, "promise", ?, ?))
			a_browser.evaluate ("(() => { throw new Error ('x'); }) ()", agent on_evaluated (a_browser, "throw", ?, ?))
		end

	on_evaluated (a_browser: SIMPLE_BROWSER; a_label: STRING_8; a_ok: BOOLEAN; a_json: STRING_8)
		do
			record_result (a_label, a_ok, a_json)
			if a_browser.pending_evaluations = 0 then
				a_browser.close
			end
		end

feature {NONE} -- Binding test

	on_round_trip_ping (a_browser: SIMPLE_BROWSER; a_seq, a_args: STRING_8)
		do
			ping_count := ping_count + 1;
			(create {MEMORY}).full_collect
			a_browser.respond (a_seq, "{%"got%":" + a_args + "}")
		end

	on_round_trip_fail (a_browser: SIMPLE_BROWSER; a_seq, a_args: STRING_8)
		do
			a_browser.respond_error (a_seq, "%"nope%"")
		end

	on_round_trip_bad (a_browser: SIMPLE_BROWSER; a_seq, a_args: STRING_8)
		do
			a_browser.respond (a_seq, "{this is not json")
		end

	on_round_trip_echo (a_browser: SIMPLE_BROWSER; a_seq, a_args: STRING_8)
		do
			echoes.extend (a_args)
			a_browser.respond (a_seq, "null")
			if a_args.same_string ("[%"done%"]") then
				a_browser.close
			end
		end

feature {NONE} -- Inject test

	on_report (a_browser: SIMPLE_BROWSER; a_seq, a_args: STRING_8)
		do
			reported := a_args
			a_browser.respond (a_seq, "null")
			a_browser.close
		end

feature {NONE} -- Navigation tests

	on_hold_navigation (a_browser: SIMPLE_BROWSER; a_navigation: SB_NAVIGATION): BOOLEAN
		do
			record_asked (a_navigation)
			Result := not a_navigation.url.same_string ("about:blank#blocked")
			if a_navigation.url.same_string ("about:blank#allowed") then
				allowed_seen := True
				check_hash (a_browser)
			end
		end

	on_hold_loaded (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_error: STRING_32)
			-- A navigation allowed may make a new document (Windows) or keep the page
			-- (a fragment): read the hash after either.
		do
			if a_ok then
				loads_ok := loads_ok + 1
				if allowed_seen then
					check_hash (a_browser)
				end
			end
		end

	allowed_seen: BOOLEAN
			-- Has the handler allowed about:blank#allowed?

	hash_checks: INTEGER
			-- How many times the hash has been read.

	check_hash (a_browser: SIMPLE_BROWSER)
			-- Read `location.hash' a moment from now; a document that goes away on the
			-- navigation never answers, so the new one's load reads it again.
		do
			a_browser.evaluate ("new Promise ((r) => setTimeout (() => r (location.hash), 300))",
				agent on_hash (a_browser, ?, ?))
		end

	on_hash (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_json: STRING_8)
		do
			hash_checks := hash_checks + 1
			if a_ok and a_json.same_string ("%"#allowed%"") then
				record_result ("hash", a_ok, a_json)
				a_browser.close
			elseif hash_checks < 10 then
				check_hash (a_browser)
			else
				record_result ("hash", a_ok, a_json)
				a_browser.close
			end
		end

	record_asked (a_navigation: SB_NAVIGATION)
			-- Keep "<kind> main" or "<kind> iframe" under the navigation's url.
		do
			navigations.extend (a_navigation.url)
			asked.force (a_navigation.kind.out + (if a_navigation.is_main_frame then " main" else " iframe" end),
				a_navigation.url)
		end

	on_form_navigation (a_navigation: SB_NAVIGATION): BOOLEAN
		do
			record_asked (a_navigation)
			Result := True
		end

	on_form_loaded (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_error: STRING_32)
		do
			loads_ok := loads_ok + 1
			if loads_ok = 2 then
				a_browser.evaluate ("document.getElementById ('echo').textContent",
					agent on_result_then (a_browser, "echo", Void, ?, ?))
			end
		end

	on_cancel_everything (a_navigation: SB_NAVIGATION): BOOLEAN
		do
			navigations.extend (a_navigation.url)
			Result := False
		end

	on_own_load (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_error: STRING_32)
		do
			if a_ok then
				loads_ok := loads_ok + 1
				if loads_ok = 1 then
					a_browser.navigate_to ("about:blank")
				else
					a_browser.close
				end
			else
				loads_failed := loads_failed + 1
				a_browser.close
			end
		end

	on_new_window_request (a_browser: SIMPLE_BROWSER; a_url: STRING_32)
		do
			new_windows.extend (a_url)
			if new_windows.count = 2 then
					-- Give a window that should not open the time to appear, then count.
				a_browser.evaluate ("new Promise ((r) => setTimeout (() => r (1), 500))",
					agent on_count_windows (a_browser, ?, ?))
			end
		end

	on_count_windows (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_json: STRING_8)
		do
			window_count := a_browser.engine.test_window_count
			a_browser.close
		end

	on_stop (a_browser: SIMPLE_BROWSER; a_seq, a_args: STRING_8)
		do
			a_browser.respond (a_seq, "null")
			a_browser.close
		end

feature {NONE} -- Store test

	on_store_loaded (a_browser: SIMPLE_BROWSER; a_script, a_label: STRING_8; a_ok: BOOLEAN; a_error: STRING_32)
		do
			a_browser.evaluate (a_script, agent on_result_then (a_browser, a_label, Void, ?, ?))
		end

feature {NONE} -- htmx test

	on_htmx_loaded (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_error: STRING_32)
		do
			a_browser.evaluate ("typeof htmx", agent record_result ("htmx", ?, ?))
			a_browser.evaluate ("Alpine.version", agent record_result ("alpine", ?, ?))
			a_browser.evaluate ("htmx.version", agent record_result ("htmx_version", ?, ?))
			a_browser.evaluate ("[
				(async () => {
				  document.getElementById ("add").click ();
				  await new Promise ((r) => setTimeout (r, 100));
				  return document.getElementById ("count").textContent;
				}) ()
			]", agent on_result_then (a_browser, "counter", Void, ?, ?))
		end

feature {NONE} -- Size test

	on_size_loaded (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_error: STRING_32)
		do
			next_size_step (a_browser, True, "1")
		end

	next_size_step (a_browser: SIMPLE_BROWSER; a_ok: BOOLEAN; a_json: STRING_8)
			-- Read the size the last step left (after a turn of the loop), then take the next.
		do
			if size_step > 0 then
				sizes.extend (a_browser.engine.test_content_width.out + "x" + a_browser.engine.test_content_height.out
					+ (if a_browser.engine.test_is_resizable then " resizable" else " fixed" end))
			end
			size_step := size_step + 1
			inspect size_step
			when 1 then a_browser.set_fixed_size (400, 300)
			when 2 then a_browser.set_size (800, 600)
			when 3 then a_browser.set_min_size (500, 400)
			when 4 then a_browser.set_size (300, 200)
			when 5 then
				a_browser.set_max_size (600, 450)
				a_browser.set_size (900, 900)
			when 6 then a_browser.set_max_size (550, 420)
			else
				a_browser.close
			end
			if size_step <= 6 then
				a_browser.evaluate ("new Promise ((r) => setTimeout (() => r (1), 100))", agent next_size_step (a_browser, ?, ?))
			end
		end

feature {NONE} -- Callbacks

	ping_count: INTEGER

	on_ping (a_browser: SIMPLE_BROWSER; a_seq, a_req: STRING_8)
		do
			ping_count := ping_count + 1;
			(create {MEMORY}).full_collect
			a_browser.respond (a_seq, "null")
			if ping_count = 3 then
				a_browser.close
			end
		end

	churn_rounds: INTEGER
	churn_ms: NATURAL_64

	on_go (a_browser: SIMPLE_BROWSER; a_worker: separate GC_CHURN_WORKER; a_seq, a_req: STRING_8)
			-- Start the worker (asynchronously) and hand control back to the loop.
		do
			start_churn (a_worker)
			a_browser.respond (a_seq, "null")
		end

	on_check (a_browser: SIMPLE_BROWSER; a_worker: separate GC_CHURN_WORKER; a_seq, a_req: STRING_8)
			-- Read the worker's result and close the window.
		do
			read_churn (a_worker)
			a_browser.respond (a_seq, "null")
			a_browser.close
		end

	start_churn (a_worker: separate GC_CHURN_WORKER)
		do
			a_worker.churn (20)
		end

	read_churn (a_worker: separate GC_CHURN_WORKER)
		do
			churn_rounds := a_worker.rounds
			churn_ms := a_worker.elapsed_ms
		end

end
