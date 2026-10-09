note
	description: "[
		A processor that allocates and runs full garbage collections, for
		LIB_TESTS.test_gc_runs_while_the_window_loop_runs. It times its own
		work, so a stall (a collection waiting for the root's message loop)
		shows up as elapsed time rather than as a hang.
	]"

class
	GC_CHURN_WORKER

feature -- Access

	rounds: INTEGER
			-- Collections completed by `churn'.

	elapsed_ms: NATURAL_64
			-- Wall time `churn' took, in milliseconds.

feature -- Basic operations

	churn (a_rounds: INTEGER)
			-- Allocate a little garbage and run a full collection, `a_rounds' times.
		require
			positive: a_rounds > 0
		local
			l_memory: MEMORY
			l_list: ARRAYED_LIST [STRING_8]
			l_start: NATURAL_64
			i, j: INTEGER
		do
			l_start := tick_ms
			create l_memory
			from i := 1 until i > a_rounds loop
				create l_list.make (1000)
				from j := 1 until j > 1000 loop
					l_list.extend (j.out)
					j := j + 1
				end
				l_memory.full_collect
				rounds := i
				i := i + 1
			end
			elapsed_ms := tick_ms - l_start
		ensure
			all_rounds: rounds = a_rounds
		end

feature {NONE} -- Implementation

	tick_ms: NATURAL_64
			-- Milliseconds since system start.
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_NATURAL_64) GetTickCount64();"
		end

end
