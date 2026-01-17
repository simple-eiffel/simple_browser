note
	description: "[
		WEBVIEW_ENGINE - Browser engine using webview/webview C library.

		Wraps the webview C API to provide embedded browser functionality.
		Uses WebView2 on Windows, WebKit on Linux/macOS.

		Pattern follows WHISPER_ENGINE from simple_speech:
		- Opaque pointer (ctx) to C context
		- Inline C externals for all API calls
		- C_STRING for string marshalling

		Threading: The event loop (run) is blocking. For non-blocking
		operation, run the engine in a separate SCOOP processor.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	WEBVIEW_ENGINE

inherit
	BROWSER_ENGINE

create
	make,
	make_with_window

feature {NONE} -- Initialization

	make
			-- Create standalone browser window.
		local
			l_err: INTEGER
		do
			initialize_callbacks
			-- Debug=1 enables DevTools (required for stable operation)
			ctx := c_webview_create (1, default_pointer)
			if ctx = default_pointer then
				l_err := c_get_last_error
				last_error := "Failed to create webview context (GetLastError=" + l_err.out + ")"
			end
		ensure
			ctx_set_or_error: is_ready or last_error /= Void
		end

	make_with_window (a_window_handle: POINTER)
			-- Create browser embedded in existing window.
		require
			valid_handle: a_window_handle /= default_pointer
		do
			initialize_callbacks
			parent_window := a_window_handle
			ctx := c_webview_create (1, a_window_handle)
			if ctx = default_pointer then
				last_error := "Failed to create webview in parent window"
			end
		ensure
			ctx_set_or_error: is_ready or last_error /= Void
		end

feature -- Status

	is_ready: BOOLEAN
			-- <Precursor>
		do
			Result := ctx /= default_pointer
		end

	last_error: detachable STRING_32
			-- <Precursor>

feature -- Window Access

	window_handle: POINTER
			-- <Precursor>
		do
			if ctx /= default_pointer then
				Result := c_webview_get_window (ctx)
			end
		end

feature -- Navigation

	navigate (a_url: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_url: C_STRING
			l_result: INTEGER
		do
			create l_url.make (a_url.to_string_8)
			l_result := c_webview_navigate (ctx, l_url.item)
		end

	set_html (a_html: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_html: C_STRING
			l_result: INTEGER
		do
			create l_html.make (a_html.to_string_8)
			l_result := c_webview_set_html (ctx, l_html.item)
		end

feature -- Window Configuration

	set_title (a_title: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_title: C_STRING
			l_result: INTEGER
		do
			create l_title.make (a_title.to_string_8)
			l_result := c_webview_set_title (ctx, l_title.item)
		end

	set_size (a_width, a_height: INTEGER; a_hints: INTEGER)
			-- <Precursor>
		local
			l_result: INTEGER
		do
			l_result := c_webview_set_size (ctx, a_width, a_height, a_hints)
		end

feature -- JavaScript Execution

	eval_js (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_script: C_STRING
			l_result: INTEGER
		do
			create l_script.make (a_script.to_string_8)
			l_result := c_webview_eval (ctx, l_script.item)
		end

	init_js (a_script: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_script: C_STRING
			l_result: INTEGER
		do
			create l_script.make (a_script.to_string_8)
			l_result := c_webview_init (ctx, l_script.item)
		end

feature -- JavaScript Bindings

	bind (a_name: READABLE_STRING_GENERAL; a_callback: PROCEDURE [TUPLE [seq: STRING_8; req: STRING_8]])
			-- <Precursor>
		local
			l_name: C_STRING
			l_result: INTEGER
			l_binding_index: INTEGER
		do
			create l_name.make (a_name.to_string_8)
			-- Store callback for dispatch
			register_callback (a_name.to_string_8, a_callback)
			-- Register binding in C with trampoline
			l_binding_index := c_register_binding (l_name.item, $Current, $dispatch_callback)
			if l_binding_index >= 0 then
				-- Bind with trampoline callback, passing index as arg
				l_result := c_webview_bind_with_trampoline (ctx, l_name.item, l_binding_index)
			end
		end

	unbind (a_name: READABLE_STRING_GENERAL)
			-- <Precursor>
		local
			l_name: C_STRING
			l_result: INTEGER
		do
			create l_name.make (a_name.to_string_8)
			l_result := c_webview_unbind (ctx, l_name.item)
			c_unregister_binding (l_name.item)
			unregister_callback (a_name.to_string_8)
		end

	return_value (a_seq: STRING_8; a_status: INTEGER; a_result: STRING_8)
			-- <Precursor>
		local
			l_seq, l_json_result: C_STRING
			l_result: INTEGER
		do
			create l_seq.make (a_seq)
			create l_json_result.make (a_result)
			l_result := c_webview_return (ctx, l_seq.item, a_status, l_json_result.item)
		end

feature {NONE} -- Callback Dispatch

	dispatch_callback (a_name, a_seq, a_req: POINTER)
			-- Dispatch callback from C trampoline to registered Eiffel callback.
			-- Called from C code via function pointer.
			-- Note: In finalized Eiffel, Current is passed implicitly by runtime.
			-- a_name: Binding name
			-- a_seq: JavaScript sequence ID
			-- a_req: JSON request arguments
		local
			l_name, l_seq, l_req: STRING_8
			l_file: PLAIN_TEXT_FILE
		do
			create l_name.make_from_c (a_name)
			create l_seq.make_from_c (a_seq)
			create l_req.make_from_c (a_req)

			-- Debug: log to file
			create l_file.make_open_append ("eiffel_dispatch.log")
			l_file.put_string ("EIFFEL dispatch_callback: name=" + l_name + " seq=" + l_seq + "%N")

			l_file.put_string ("  Registry has " + callback_registry.count.out + " entries%N")
			if attached callback_registry.item (l_name) as cb then
				l_file.put_string ("  FOUND callback, calling...%N")
				l_file.close
				cb.call ([l_seq, l_req])
			else
				l_file.put_string ("  NOT FOUND in registry%N")
				l_file.close
			end
		end

feature -- Lifecycle

	run
			-- <Precursor>
		local
			l_result: INTEGER
		do
			l_result := c_webview_run (ctx)
		end

	terminate
			-- <Precursor>
		local
			l_result: INTEGER
		do
			if ctx /= default_pointer then
				l_result := c_webview_terminate (ctx)
			end
		end

	dispose
			-- <Precursor>
		local
			l_result: INTEGER
		do
			if ctx /= default_pointer then
				l_result := c_webview_destroy (ctx)
				ctx := default_pointer
			end
			callback_registry.wipe_out
		ensure then
			disposed: ctx = default_pointer
		end

feature {NONE} -- Implementation

	ctx: POINTER
			-- Opaque webview_t pointer.

	parent_window: POINTER
			-- Parent window handle (if embedded).

	callback_registry: HASH_TABLE [PROCEDURE [TUPLE [STRING_8, STRING_8]], STRING_8]
			-- Registered JavaScript callbacks (global/static via once).
		once
			create Result.make (20)
		end

	debug_flag: INTEGER
			-- Debug flag for webview_create.
		do
			if is_debug_mode then
				Result := 1
			else
				Result := 0
			end
		end

	initialize_callbacks
			-- Initialize callback registry (no-op, registry is once).
		do
			-- Registry is created on first access via once
		end

	register_callback (a_name: STRING_8; a_callback: PROCEDURE [TUPLE [STRING_8, STRING_8]])
			-- Register callback for JavaScript binding.
		do
			callback_registry.force (a_callback, a_name)
		end

	unregister_callback (a_name: STRING_8)
			-- Unregister callback.
		do
			callback_registry.remove (a_name)
		end

feature {NONE} -- C Externals

	c_webview_create (a_debug: INTEGER; a_window: POINTER): POINTER
			-- Create webview instance.
			-- Returns webview_t (opaque pointer) or NULL on failure.
		external
			"C (int, void*): void* | %"webview_wrapper.h%""
		alias
			"webview_create"
		end

	c_get_last_error: INTEGER
			-- Get Windows GetLastError.
		external
			"C inline use <windows.h>"
		alias
			"return (int)GetLastError();"
		end

	c_webview_destroy (a_w: POINTER): INTEGER
			-- Destroy webview instance.
			-- Returns 0 on success.
		external
			"C (void*): int | %"webview_wrapper.h%""
		alias
			"webview_destroy"
		end

	c_webview_run (a_w: POINTER): INTEGER
			-- Run event loop.
			-- Returns 0 on success.
		external
			"C (void*): int | %"webview_wrapper.h%""
		alias
			"webview_run"
		end

	c_webview_terminate (a_w: POINTER): INTEGER
			-- Stop event loop.
			-- Returns 0 on success.
		external
			"C (void*): int | %"webview_wrapper.h%""
		alias
			"webview_terminate"
		end

	c_webview_get_window (a_w: POINTER): POINTER
			-- Get native window handle.
		external
			"C (void*): void* | %"webview_wrapper.h%""
		alias
			"webview_get_window"
		end

	c_webview_set_title (a_w, a_title: POINTER): INTEGER
			-- Set window title.
			-- Returns 0 on success.
		external
			"C (void*, const char*): int | %"webview_wrapper.h%""
		alias
			"webview_set_title"
		end

	c_webview_set_size (a_w: POINTER; a_width, a_height, a_hints: INTEGER): INTEGER
			-- Set window size.
			-- Returns 0 on success.
		external
			"C (void*, int, int, int): int | %"webview_wrapper.h%""
		alias
			"webview_set_size"
		end

	c_webview_navigate (a_w, a_url: POINTER): INTEGER
			-- Navigate to URL.
			-- Returns 0 on success.
		external
			"C (void*, const char*): int | %"webview_wrapper.h%""
		alias
			"webview_navigate"
		end

	c_webview_set_html (a_w, a_html: POINTER): INTEGER
			-- Set HTML content.
			-- Returns 0 on success.
		external
			"C (void*, const char*): int | %"webview_wrapper.h%""
		alias
			"webview_set_html"
		end

	c_webview_init (a_w, a_js: POINTER): INTEGER
			-- Inject JavaScript for page load.
			-- Returns 0 on success.
		external
			"C (void*, const char*): int | %"webview_wrapper.h%""
		alias
			"webview_init"
		end

	c_webview_eval (a_w, a_js: POINTER): INTEGER
			-- Evaluate JavaScript.
			-- Returns 0 on success.
		external
			"C (void*, const char*): int | %"webview_wrapper.h%""
		alias
			"webview_eval"
		end

	c_webview_bind (a_w, a_name, a_fn, a_arg: POINTER): INTEGER
			-- Bind native function to JavaScript.
			-- Returns 0 on success.
		external
			"C (void*, const char*, void*, void*): int | %"webview_wrapper.h%""
		alias
			"webview_bind"
		end

	c_webview_unbind (a_w, a_name: POINTER): INTEGER
			-- Unbind function.
			-- Returns 0 on success.
		external
			"C (void*, const char*): int | %"webview_wrapper.h%""
		alias
			"webview_unbind"
		end

	c_webview_return (a_w, a_seq: POINTER; a_status: INTEGER; a_result: POINTER): INTEGER
			-- Return value to JavaScript.
			-- Returns 0 on success.
		external
			"C (void*, const char*, int, const char*): int | %"webview_wrapper.h%""
		alias
			"webview_return"
		end

	c_register_binding (a_name, a_eiffel_obj, a_callback: POINTER): INTEGER
			-- Register binding in C trampoline registry.
			-- Returns binding index or -1 on failure.
		external
			"C inline use %"webview_wrapper.h%""
		alias
			"return webview_register_binding((const char*)$a_name, $a_eiffel_obj, (eiffel_callback_t)$a_callback);"
		end

	c_unregister_binding (a_name: POINTER)
			-- Unregister binding from C trampoline registry.
		external
			"C inline use %"webview_wrapper.h%""
		alias
			"webview_unregister_binding((const char*)$a_name);"
		end

	c_webview_bind_with_trampoline (a_w, a_name: POINTER; a_index: INTEGER): INTEGER
			-- Bind using the C callback trampoline.
			-- Returns 0 on success.
		external
			"C inline use %"webview_wrapper.h%""
		alias
			"return webview_bind($a_w, (const char*)$a_name, webview_callback_trampoline, (void*)(intptr_t)$a_index);"
		end

invariant
	valid_when_ready: is_ready implies ctx /= default_pointer
	callback_registry_exists: callback_registry /= Void

end
