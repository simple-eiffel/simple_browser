note
	description: "[
		DEMO_EMBEDDED - Embedded browser in Vision2 window.

		Demonstrates SB_WIDGET: a browser embedded inside
		a simple_vision window with native chrome.
	]"
	author: "Larry Rix"

class
	DEMO_EMBEDDED

create
	make

feature {NONE} -- Initialization

	make
			-- Run demo.
		local
			l_app: SV_APPLICATION
		do
			print ("simple_browser Embedded Demo%N")
			print ("=============================%N%N")

			create l_app.make
			prepare_main_window (l_app)
			l_app.launch

			-- Cleanup after window closed
			if attached browser as b then
				b.dispose
			end
			print ("Demo complete.%N")
		end

	prepare_main_window (a_app: SV_APPLICATION)
			-- Set up main window with embedded browser.
		local
			l_window: SV_WINDOW
			l_column: SV_COLUMN
			l_toolbar: SV_ROW
			l_url_field: SV_TEXT_FIELD
			l_go_button: SV_BUTTON
			l_browser: SB_WIDGET
			l_discard: SV_WIDGET
		do
			-- Create main window
			create l_window.make_with_title ("simple_browser Embedded Demo")
			l_discard := l_window.set_size (1024, 768)

			-- Create layout
			create l_column.make
			l_discard := l_window.add (l_column)

			-- Toolbar row
			create l_toolbar.make
			l_discard := l_column.add (l_toolbar)
			l_toolbar.set_expansion_prevented (True)

			-- URL field
			create l_url_field.make
			l_url_field.set_text ("https://example.com")
			l_discard := l_toolbar.add (l_url_field)
			url_field := l_url_field

			-- Go button
			create l_go_button.make_with_text ("Go")
			l_discard := l_go_button.compact
			l_go_button.on_click (agent on_navigate)
			l_discard := l_toolbar.add (l_go_button)

			-- Browser widget
			create l_browser.make
			browser := l_browser
			l_discard := l_column.add (l_browser)

			-- Navigate to initial page
			l_discard := l_browser.with_htmx (demo_html)

			-- Register and show window
			a_app.add_window (l_window)
			l_window.show_now
		end

feature -- Access

	browser: detachable SB_WIDGET
			-- Embedded browser widget.

	url_field: detachable SV_TEXT_FIELD
			-- URL input field.

feature {NONE} -- Events

	on_navigate
			-- Navigate to URL in field.
		do
			if attached url_field as f and then attached f.text as l_url then
				if not l_url.is_empty then
					if attached browser as b then
						b.navigate (l_url)
					end
				end
			end
		end

feature {NONE} -- Demo Content

	demo_html: STRING = "[
		<style>
			body {
				font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
				max-width: 800px;
				margin: 50px auto;
				padding: 20px;
				background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
				min-height: 100vh;
			}
			.card {
				background: white;
				border-radius: 16px;
				padding: 30px;
				box-shadow: 0 10px 40px rgba(0,0,0,0.2);
			}
			h1 { color: #333; margin-bottom: 10px; }
			.subtitle { color: #666; margin-bottom: 30px; }
			.counter {
				font-size: 72px;
				text-align: center;
				margin: 40px 0;
				color: #667eea;
				font-weight: bold;
			}
			button {
				padding: 15px 30px;
				font-size: 18px;
				cursor: pointer;
				margin: 5px;
				border: none;
				border-radius: 8px;
				background: #667eea;
				color: white;
				transition: transform 0.1s, box-shadow 0.1s;
			}
			button:hover {
				transform: translateY(-2px);
				box-shadow: 0 5px 20px rgba(102, 126, 234, 0.4);
			}
			button:active {
				transform: translateY(0);
			}
			.buttons { text-align: center; }
			.info {
				margin-top: 30px;
				padding-top: 20px;
				border-top: 1px solid #eee;
				color: #888;
				font-size: 14px;
			}
		</style>

		<div class="card">
			<h1>Embedded Browser Demo</h1>
			<p class="subtitle">Browser running inside a Vision2 window</p>

			<div x-data="{ count: 0 }">
				<div class="counter" x-text="count"></div>
				<div class="buttons">
					<button @click="count--">- Decrease</button>
					<button @click="count++">+ Increase</button>
					<button @click="count = 0">Reset</button>
				</div>
			</div>

			<div class="info">
				<p>This demonstrates:</p>
				<ul>
					<li>SB_WIDGET embedded in SV_WINDOW</li>
					<li>HTMX + Alpine.js for reactive UI</li>
					<li>Native toolbar with URL navigation</li>
				</ul>
			</div>
		</div>
	]"

end
