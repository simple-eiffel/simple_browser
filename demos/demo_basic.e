note
	description: "[
		DEMO_BASIC - Basic browser demonstration.

		Shows fundamental simple_browser usage:
		- Creating a browser window
		- Loading HTML content
		- Running the event loop
	]"
	author: "Larry Rix"

class
	DEMO_BASIC

create
	make

feature {NONE} -- Initialization

	make
			-- Run demo.
		local
			l_browser: SIMPLE_BROWSER
		do
			print ("simple_browser Demo%N")
			print ("==================%N%N")

			create l_browser.make
			if l_browser.is_valid then
				l_browser := l_browser.titled ("simple_browser Demo")
				                       .size (800, 600)
				                       .with_htmx (demo_html)

				print ("Browser window opened. Close window to exit.%N")
				l_browser.run
				l_browser.dispose
				print ("Demo complete.%N")
			else
				print ("ERROR: Failed to create browser%N")
				if attached l_browser.last_error as err then
					print ("  " + err.to_string_8 + "%N")
				end
			end
		end

feature {NONE} -- Demo Content

	demo_html: STRING = "[
		<style>
			body {
				font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
				max-width: 600px;
				margin: 50px auto;
				padding: 20px;
			}
			h1 { color: #333; }
			.counter {
				font-size: 48px;
				text-align: center;
				margin: 40px 0;
			}
			button {
				padding: 10px 20px;
				font-size: 18px;
				cursor: pointer;
				margin: 5px;
			}
			.buttons { text-align: center; }
		</style>

		<h1>simple_browser Demo</h1>
		<p>This is an embedded browser powered by WebView2.</p>

		<div x-data="{ count: 0 }">
			<div class="counter" x-text="count"></div>
			<div class="buttons">
				<button @click="count--">-</button>
				<button @click="count++">+</button>
				<button @click="count = 0">Reset</button>
			</div>
		</div>

		<hr>
		<p><small>Built with simple_browser + HTMX + Alpine.js</small></p>
	]"

end
