note
	description: "[
		SB_PLATFORM (Windows) - makes this platform's browser engine, WEBVIEW_ENGINE.

		Each platform cluster has its own SB_PLATFORM (src/windows, src/macos, src/linux),
		chosen by the ECF's platform conditions; SIMPLE_BROWSER names only this class.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SB_PLATFORM

feature -- Factory

	new_engine (a_ephemeral, a_debug: BOOLEAN): BROWSER_ENGINE
			-- An engine with a window of its own.
		do
			create {WEBVIEW_ENGINE} Result.make (a_ephemeral, a_debug)
		end

	new_engine_in (a_parent: POINTER; a_ephemeral, a_debug: BOOLEAN): BROWSER_ENGINE
			-- An engine inside the window `a_parent' (an HWND).
		require
			parent_given: a_parent /= default_pointer
		do
			create {WEBVIEW_ENGINE} Result.make_with_window (a_parent, a_ephemeral, a_debug)
		end

end
