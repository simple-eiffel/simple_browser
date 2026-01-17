note
	description: "[
		SB_WIDGET - Embedded browser widget for simple_vision.

		Embeds a webview browser inside a Vision2 container.
		Uses EV_DRAWING_AREA as the host widget and extracts its HWND
		to pass to the webview library for embedding.

		Usage:
			create browser_widget.make
			my_container.add (browser_widget.ev_widget)
			browser_widget.navigate ("https://example.com")

		Or fluent:
			create browser_widget.make
			browser_widget.url ("https://example.com")
			              .html_content ("<h1>Hello</h1>")

		IMPORTANT: The browser is created lazily when the widget is
		first displayed (realized). Navigation commands are queued
		until the browser is ready.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SB_WIDGET

inherit
	SV_WIDGET
		redefine
			apply_theme
		end

create
	make

feature {NONE} -- Initialization

	make
			-- Create browser widget.
		do
			create ev_drawing_area
			create pending_commands.make (5)

			-- Hook into realize event to create browser
			ev_drawing_area.expose_actions.extend (agent on_first_expose)

			-- Handle resize to keep browser sized correctly
			ev_drawing_area.resize_actions.extend (agent on_resize)

			apply_theme
			subscribe_to_theme
		ensure
			drawing_area_created: ev_drawing_area /= Void
		end

feature -- Access

	ev_drawing_area: EV_DRAWING_AREA
			-- Host widget for embedded browser.

	ev_widget: EV_WIDGET
			-- <Precursor>
		do
			Result := ev_drawing_area
		end

	engine: detachable WEBVIEW_ENGINE
			-- Browser engine (created on first display).

feature -- Status

	is_browser_ready: BOOLEAN
			-- Is the browser engine created and ready?
		do
			Result := attached engine as e and then e.is_ready
		end

	last_error: detachable STRING_32
			-- Last error message.

feature -- Navigation

	navigate (a_url: READABLE_STRING_GENERAL)
			-- Navigate to URL.
		require
			url_not_empty: not a_url.is_empty
		do
			if is_browser_ready and then attached engine as e then
				e.navigate (a_url)
			else
				queue_command (agent (eng: WEBVIEW_ENGINE; a_target_url: READABLE_STRING_GENERAL)
					do
						eng.navigate (a_target_url)
					end (?, a_url))
			end
		end

	set_html (a_html: READABLE_STRING_GENERAL)
			-- Set HTML content directly.
		require
			html_not_empty: not a_html.is_empty
		do
			if is_browser_ready and then attached engine as e then
				e.set_html (a_html)
			else
				queue_command (agent (eng: WEBVIEW_ENGINE; a_content: READABLE_STRING_GENERAL)
					do
						eng.set_html (a_content)
					end (?, a_html))
			end
		end

feature -- Fluent Navigation

	url (a_url: READABLE_STRING_GENERAL): like Current
			-- Navigate to URL (fluent).
		require
			url_not_empty: not a_url.is_empty
		do
			navigate (a_url)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	html_content (a_html: READABLE_STRING_GENERAL): like Current
			-- Set HTML content (fluent).
		require
			html_not_empty: not a_html.is_empty
		do
			set_html (a_html)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

	with_htmx (a_html: READABLE_STRING_GENERAL): like Current
			-- Load HTML with HTMX + Alpine.js CDN scripts injected.
		require
			html_not_empty: not a_html.is_empty
		local
			l_full_html: STRING_32
		do
			create l_full_html.make (a_html.count + 500)
			l_full_html.append ("<!DOCTYPE html><html><head>")
			l_full_html.append ("<meta charset=%"UTF-8%">")
			l_full_html.append ("<script src=%"https://unpkg.com/htmx.org@1.9.10%"></script>")
			l_full_html.append ("<script defer src=%"https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js%"></script>")
			l_full_html.append ("</head><body>")
			l_full_html.append_string_general (a_html)
			l_full_html.append ("</body></html>")
			set_html (l_full_html)
			Result := Current
		ensure
			result_is_current: Result = Current
		end

feature -- JavaScript

	eval_js (a_script: READABLE_STRING_GENERAL)
			-- Evaluate JavaScript in browser.
		require
			script_not_empty: not a_script.is_empty
		do
			if is_browser_ready and then attached engine as e then
				e.eval_js (a_script)
			else
				queue_command (agent (eng: WEBVIEW_ENGINE; a_js: READABLE_STRING_GENERAL)
					do
						eng.eval_js (a_js)
					end (?, a_script))
			end
		end

	init_js (a_script: READABLE_STRING_GENERAL)
			-- Inject JavaScript to run on every page load.
		require
			script_not_empty: not a_script.is_empty
		do
			if is_browser_ready and then attached engine as e then
				e.init_js (a_script)
			else
				queue_command (agent (eng: WEBVIEW_ENGINE; a_init_js: READABLE_STRING_GENERAL)
					do
						eng.init_js (a_init_js)
					end (?, a_script))
			end
		end

feature -- Lifecycle

	dispose
			-- Clean up browser resources.
		do
			if attached engine as e then
				e.dispose
				engine := Void
			end
		ensure
			disposed: engine = Void
		end

feature -- Theme

	apply_theme
			-- Apply theme to host widget.
		do
			ev_drawing_area.set_background_color (tokens.background.to_ev_color)
		end

feature {NONE} -- Implementation

	pending_commands: ARRAYED_LIST [PROCEDURE [WEBVIEW_ENGINE]]
			-- Commands queued before browser is ready.

	browser_created: BOOLEAN
			-- Has browser creation been attempted?

	queue_command (a_command: PROCEDURE [WEBVIEW_ENGINE])
			-- Queue a command to execute when browser is ready.
		require
			command_attached: a_command /= Void
		do
			pending_commands.extend (a_command)
		end

	execute_pending_commands
			-- Execute all queued commands.
		do
			if attached engine as e then
				across pending_commands as cmd loop
					cmd.call ([e])
				end
				pending_commands.wipe_out
			end
		end

	on_first_expose (a_x, a_y, a_width, a_height: INTEGER)
			-- Handle first expose event - create browser.
		do
			if not browser_created then
				browser_created := True
				-- Remove the expose handler after first call
				ev_drawing_area.expose_actions.wipe_out
				-- Create browser immediately
				create_browser
			end
		end

	on_resize (a_x, a_y, a_width, a_height: INTEGER)
			-- Handle resize - update browser size.
		do
			if is_browser_ready and then attached engine as e then
				-- Only resize if dimensions are valid (DbC compliance)
				if a_width > 0 and a_height > 0 then
					e.set_size (a_width, a_height, 0)
				end
			end
		end

	create_browser
			-- Create browser engine embedded in this widget.
		local
			l_hwnd: POINTER
		do
			-- Get native window handle from drawing area
			l_hwnd := get_widget_hwnd (ev_drawing_area)

			if l_hwnd /= default_pointer then
				create engine.make_with_window (l_hwnd)
				if attached engine as e and then e.is_ready then
					-- Set initial size (only if valid dimensions - DbC compliance)
					if ev_drawing_area.width > 0 and ev_drawing_area.height > 0 then
						e.set_size (ev_drawing_area.width, ev_drawing_area.height, 0)
					end
					-- Execute any pending commands
					execute_pending_commands
					debug_log ("Browser created in widget")
				else
					last_error := "Failed to create browser in widget"
					if attached engine as e and then attached e.last_error as err then
						last_error := err
					end
				end
			else
				last_error := "Failed to get native window handle"
			end
		end

	get_widget_hwnd (a_widget: EV_WIDGET): POINTER
			-- Extract native window handle (HWND) from Vision2 widget.
			-- Returns default_pointer if handle cannot be obtained.
			-- Uses GetActiveWindow to get the main window handle.
		require
			widget_attached: a_widget /= Void
		do
			-- Use the active window (main Vision2 window)
			Result := c_get_active_window
		end

feature {NONE} -- C Externals (Windows API)

	c_window_from_point (a_x, a_y: INTEGER): POINTER
			-- Find window at screen coordinates.
		external
			"C inline use <windows.h>"
		alias
			"[
				POINT pt;
				pt.x = (LONG)$a_x;
				pt.y = (LONG)$a_y;
				return (EIF_POINTER)WindowFromPoint(pt);
			]"
		end

	c_get_active_window: POINTER
			-- Get the active window.
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_POINTER)GetActiveWindow();"
		end

	c_get_foreground_window: POINTER
			-- Get the foreground window.
		external
			"C inline use <windows.h>"
		alias
			"return (EIF_POINTER)GetForegroundWindow();"
		end

invariant
	drawing_area_exists: ev_drawing_area /= Void
	pending_commands_exists: pending_commands /= Void

end
