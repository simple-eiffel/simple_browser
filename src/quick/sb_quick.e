note
	description: "[
		SB_QUICK - Zero-configuration browser facade.

		Provides simple one-liner patterns for common use cases:
		- Standalone app window with HTML
		- localhost connection for web server integration
		- Quick JavaScript bindings

		Example:
			create quick.make
			quick.app_window ("My App", 800, 600, "<h1>Hello</h1>")

		With server:
			quick.localhost_app ("VoxCraft", 8080)
			quick.start
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SB_QUICK

inherit
	SB_ANY

create
	make

feature {NONE} -- Initialization

	make
			-- Create quick facade.
		do
			port := 8080
		end

feature -- Quick Setup

	app_window (a_title: STRING; a_width, a_height: INTEGER; a_html: STRING)
			-- Create standalone app window with HTML content.
			-- Blocking call - returns when window closes.
		local
			l_browser: SIMPLE_BROWSER
		do
			create l_browser.make
			if l_browser.is_valid then
				l_browser.set_title (a_title)
				l_browser.set_size (a_width, a_height)
				l_browser.load_htmx_page (a_html)
				browser := l_browser
				l_browser.run
			end
		end

	localhost_app (a_title: STRING; a_port: INTEGER)
			-- Create app that connects to localhost server.
			-- Call `start` to run (non-blocking setup).
		local
			l_browser: SIMPLE_BROWSER
		do
			port := a_port
			create l_browser.make
			if l_browser.is_valid then
				l_browser.set_title (a_title)
				l_browser.navigate_to ("http://localhost:" + a_port.out)
				browser := l_browser
			end
		end

feature -- Access

	browser: detachable SIMPLE_BROWSER
			-- Browser instance.

	port: INTEGER
			-- Server port for localhost_app.

feature -- Execution

	start
			-- Start app (runs browser event loop).
		require
			browser_exists: browser /= Void
		do
			if attached browser as b then
				b.run
			end
		end

	close
			-- Close app.
		do
			if attached browser as b then
				b.close
			end
		end

feature -- Quick Bindings

	on (a_name: STRING; a_handler: PROCEDURE [TUPLE [STRING_8]])
			-- Quick handler registration (no return value, simplified args).
		require
			browser_exists: browser /= Void
		do
			if attached browser as b then
				b.on_call (a_name, agent wrap_simple_handler (?, ?, a_handler))
			end
		end

feature {NONE} -- Implementation

	wrap_simple_handler (a_seq: STRING_8; a_req: STRING_8; a_handler: PROCEDURE [TUPLE [STRING_8]])
			-- Wrap simple handler to full signature.
		do
			a_handler.call ([a_req])
			-- Auto-respond with null
			if attached browser as b then
				b.respond (a_seq, "null")
			end
		end

end
