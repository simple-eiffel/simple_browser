note
	description: "Test cases for simple_browser"
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
