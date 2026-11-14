note
	description: "Test application for SIMPLE_BROWSER"

class
	TEST_APP

create
	make

feature {NONE} -- Initialization

	make
			-- Run the tests.
		do
			print ("Running SIMPLE_BROWSER tests...%N%N")
			passed := 0
			failed := 0

			run_lib_tests

			print ("%N========================%N")
			print ("Results: " + passed.out + " passed, " + failed.out + " failed%N")

			if failed > 0 then
				print ("TESTS FAILED%N")
			else
				print ("ALL TESTS PASSED%N")
			end
		end

feature {NONE} -- Test Runners

	run_lib_tests
		do
			create lib_tests
			run_test (agent lib_tests.test_creation, "test_creation")
			run_test (agent lib_tests.test_binding_round_trip, "test_binding_round_trip")
			run_test (agent lib_tests.test_gc_runs_while_the_window_loop_runs, "test_gc_runs_while_the_window_loop_runs")
				-- The shared tests (SIMPLE_BROWSER_SPEC.md section 5)
			run_test (agent lib_tests.test_a_page_loads_and_tells_its_title, "test_a_page_loads_and_tells_its_title")
			run_test (agent lib_tests.test_evaluate_returns_json, "test_evaluate_returns_json")
			run_test (agent lib_tests.test_a_binding_round_trip, "test_a_binding_round_trip")
			run_test (agent lib_tests.test_inject_runs_before_the_page, "test_inject_runs_before_the_page")
			run_test (agent lib_tests.test_a_navigation_is_held_and_answered, "test_a_navigation_is_held_and_answered")
			run_test (agent lib_tests.test_a_new_window_is_reported_not_opened, "test_a_new_window_is_reported_not_opened")
			run_test (agent lib_tests.test_the_ephemeral_store_forgets, "test_the_ephemeral_store_forgets")
			run_test (agent lib_tests.test_the_program_navigation_is_not_asked, "test_the_program_navigation_is_not_asked")
			run_test (agent lib_tests.test_close_ends_run, "test_close_ends_run")
			run_test (agent lib_tests.test_htmx_and_alpine_load_without_the_network, "test_htmx_and_alpine_load_without_the_network")
			run_test (agent lib_tests.test_size_hints_hold, "test_size_hints_hold")
				-- Beyond the spec's list
			run_test (agent lib_tests.test_a_browser_inside_a_window, "test_a_browser_inside_a_window")
		end

feature {NONE} -- Implementation

	lib_tests: LIB_TESTS

	passed: INTEGER
	failed: INTEGER

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run a single test and update counters; with an argument, only the tests whose
			-- names hold it.
		local
			l_retried: BOOLEAN
			l_arguments: ARGUMENTS_32
		do
			create l_arguments
			if not l_retried and (l_arguments.argument_count = 0 or else a_name.has_substring (l_arguments.argument (1))) then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				io.output.flush
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			if attached (create {EXCEPTION_MANAGER}).last_exception as al_exception then
				print ("        " + al_exception.generating_type.name + ": ")
				if attached al_exception.description as al_description then
					print (al_description)
				end
				print ("%N")
			end
			io.output.flush
			failed := failed + 1
			l_retried := True
			retry
		end

end
