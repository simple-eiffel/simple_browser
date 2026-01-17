note
	description: "[
		SB_ANY - Base class for all simple_browser classes.

		Provides common functionality including:
		- Version information
		- Debug mode control
		- Logging support
	]"
	author: "Larry Rix"
	date: "$Date$"

deferred class
	SB_ANY

feature -- Constants

	Sb_version: STRING = "0.1.0"
			-- Library version.

	Sb_library_name: STRING = "simple_browser"
			-- Library name.

feature -- Status

	is_debug_mode: BOOLEAN
			-- Is debug mode enabled?
			-- When True, browser shows developer tools.

feature -- Debug Control

	enable_debug_mode
			-- Enable debug mode.
		do
			is_debug_mode := True
		ensure
			debug_enabled: is_debug_mode
		end

	disable_debug_mode
			-- Disable debug mode.
		do
			is_debug_mode := False
		ensure
			debug_disabled: not is_debug_mode
		end

	set_debug_mode (a_enabled: BOOLEAN)
			-- Set debug mode.
		do
			is_debug_mode := a_enabled
		ensure
			debug_set: is_debug_mode = a_enabled
		end

feature {NONE} -- Logging

	debug_log (a_message: READABLE_STRING_GENERAL)
			-- Log debug message (only when debug mode enabled).
		do
			if is_debug_mode then
				io.put_string ("[simple_browser] ")
				io.put_string (a_message.to_string_8)
				io.put_new_line
			end
		end

	error_log (a_message: READABLE_STRING_GENERAL)
			-- Log error message (always logged).
		do
			io.error.put_string ("[simple_browser ERROR] ")
			io.error.put_string (a_message.to_string_8)
			io.error.put_new_line
		end

end
