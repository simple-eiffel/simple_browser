note
	description: "[
		SB_PLATFORM - this platform's browser engine. One class of this name is in each platform's
		cluster (src/windows, src/macos, src/linux), and the ECF's conditions pick one, so shared code
		names no platform class. This one: macOS, APPKIT_ENGINE.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SB_PLATFORM

feature -- Engines

	new_engine (a_ephemeral, a_debug: BOOLEAN): BROWSER_ENGINE
			-- A browser in a window of its own.
		do
			create {APPKIT_ENGINE} Result.make (a_ephemeral, a_debug)
		end

	new_engine_in (a_parent: POINTER; a_ephemeral, a_debug: BOOLEAN): BROWSER_ENGINE
			-- A browser filling `a_parent', an NSView or an NSWindow.
		require
			parent_given: a_parent /= default_pointer
		do
			create {APPKIT_ENGINE} Result.make_with_window (a_parent, a_ephemeral, a_debug)
		end

end
