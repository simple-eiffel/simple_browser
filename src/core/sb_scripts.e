note
	description: "[
		SB_SCRIPTS - the script texts every engine runs, the same on all three platforms
		(SIMPLE_BROWSER_SPEC.md 4.2 and 4.3), and the JSON helpers shared code uses on them.

		- `Bridge_script': `window.__sb', with `call (name, args)' answering a Promise and
		  `answer (seq, status, json)' settling it. A call posts {name, seq, args} to the
		  platform's channel, `args' already JSON text (JSON.stringify of the arguments).
		- `binding_line': `window["NAME"] = (...a) => window.__sb.call ("NAME", a)'.
		- `answer_script': `window.__sb.answer ("SEQ", STATUS, JSON)'.
		- `evaluate_body': the evaluate wrapper's function body with the script inside.
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SB_SCRIPTS

feature -- Constants

	Bridge_script: STRING_8 = "[
(() => {
  if (window.__sb) { return; }
  const post = (message) => {
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage (message);
    } else {
      window.webkit.messageHandlers.sb.postMessage (message);
    }
  };
  const pending = new Map ();
  let next = 0;
  const bridge = {
    call (name, args) {
      next = next + 1;
      const seq = String (next);
      return new Promise ((resolve, reject) => {
        pending.set (seq, {resolve: resolve, reject: reject});
        post ({name: String (name), seq: seq, args: JSON.stringify (args)});
      });
    },
    answer (seq, status, json) {
      const waiting = pending.get (String (seq));
      if (waiting !== undefined) {
        pending.delete (String (seq));
        if (status === 0) { waiting.resolve (json); } else { waiting.reject (json); }
      }
    }
  };
  Object.defineProperty (window, "__sb", {value: Object.freeze (bridge), writable: false, configurable: false});
}) ();
]"
			-- The bridge (4.3): run at the start of every page, in the page's world.

	Evaluate_wrapper: STRING_8 = "[
const r = await (async () => (
@SCRIPT@
)) ();
const s = JSON.stringify (r);
return s === undefined ? "null" : s;
]"
			-- The body every engine runs for `evaluate' (4.2), as an async function's body;
			-- `@SCRIPT@' stands for the script. The script sits on lines of its own, so a
			-- trailing line comment in it cannot swallow the closing parentheses.

	Script_placeholder: STRING_8 = "@SCRIPT@"
			-- Where `Evaluate_wrapper' takes the script.

	Set_html_origin: STRING_8 = "https://simple-browser.invalid"
			-- The origin of every page `set_html' loads, on every platform. The name is reserved
			-- (RFC 2606), so it never reaches the network: each engine answers it itself.

feature -- Pages

	set_html_base (a_page: INTEGER): STRING_8
			-- The URL of `set_html''s page number `a_page': `Set_html_origin' + "/page-N".
		require
			page_positive: a_page > 0
		do
			Result := Set_html_origin + "/page-" + a_page.out
		ensure
			at_the_origin: Result.starts_with (Set_html_origin + "/")
		end

feature -- Script texts

	binding_line (a_name: READABLE_STRING_8): STRING_8
			-- The line that binds `a_name' (UTF-8) on the page.
		require
			name_not_empty: not a_name.is_empty
		local
			l_name: STRING_8
		do
			l_name := json_string_8 (a_name)
			create Result.make (a_name.count * 2 + 50)
			Result.append ("window[")
			Result.append (l_name)
			Result.append ("] = (...a) => window.__sb.call (")
			Result.append (l_name)
			Result.append (", a);")
		ensure
			calls_the_bridge: Result.has_substring ("window.__sb.call (")
		end

	answer_script (a_seq: READABLE_STRING_8; a_status: INTEGER; a_json: READABLE_STRING_8): STRING_8
			-- The script that settles call `a_seq' with the JSON value `a_json'.
		require
			seq_not_empty: not a_seq.is_empty
			json_not_empty: not a_json.is_empty
		do
			create Result.make (a_json.count + a_seq.count + 40)
			Result.append ("window.__sb.answer (")
			Result.append (json_string_8 (a_seq))
			Result.append (", ")
			Result.append_integer (a_status)
			Result.append (", ")
			Result.append (a_json)
			Result.append (");")
		ensure
			answers: Result.starts_with ("window.__sb.answer (")
		end

	evaluate_body (a_script: READABLE_STRING_GENERAL): STRING_32
			-- `Evaluate_wrapper' with `a_script' in it.
		require
			script_not_empty: not a_script.is_empty
		do
			create Result.make_from_string (Evaluate_wrapper)
			Result.replace_substring_all (Script_placeholder, a_script.to_string_32)
		ensure
			holds_the_script: Result.has_substring (a_script.to_string_32)
			placeholder_gone: not a_script.has_substring (Script_placeholder) implies not Result.has_substring (Script_placeholder)
		end

feature -- JSON

	json_string (a_text: READABLE_STRING_GENERAL): STRING_8
			-- `a_text' as a JSON string literal, quoted, in ASCII (\u escapes beyond it).
		local
			i: INTEGER
			l_code: NATURAL_32
		do
			create Result.make (a_text.count + 2)
			Result.append_character ('"')
			from i := 1 until i > a_text.count loop
				l_code := a_text.code (i)
				inspect l_code
				when 34 then Result.append ("\%"")
				when 92 then Result.append ("\\")
				when 8 then Result.append ("\b")
				when 9 then Result.append ("\t")
				when 10 then Result.append ("\n")
				when 12 then Result.append ("\f")
				when 13 then Result.append ("\r")
				else
					if l_code < 32 or (l_code >= 127 and l_code < 65536) then
						append_unicode_escape (Result, l_code)
					elseif l_code >= 65536 then
							-- A surrogate pair.
						append_unicode_escape (Result, ((l_code - 65536) |>> 10) + 0xD800)
						append_unicode_escape (Result, ((l_code - 65536) & 0x3FF) + 0xDC00)
					else
						Result.append_code (l_code)
					end
				end
				i := i + 1
			end
			Result.append_character ('"')
		ensure
			quoted: Result.count >= 2 and Result [1] = '"' and Result [Result.count] = '"'
		end

	json_string_8 (a_utf_8: READABLE_STRING_8): STRING_8
			-- The UTF-8 text `a_utf_8' as a JSON string literal.
		local
			l_utf: UTF_CONVERTER
		do
			Result := json_string (l_utf.utf_8_string_8_to_string_32 (a_utf_8))
		ensure
			quoted: Result.count >= 2 and Result [1] = '"' and Result [Result.count] = '"'
		end

	json_error (a_text: READABLE_STRING_8): detachable STRING_32
			-- Why `a_text' (UTF-8) is not one JSON value, or Void if it is.
		local
			l_json: SIMPLE_JSON
			l_utf: UTF_CONVERTER
		do
			if a_text.is_empty then
				Result := {STRING_32} "empty text is not JSON"
			else
				create l_json
				if not attached l_json.parse (l_utf.utf_8_string_8_to_string_32 (a_text)) then
					if l_json.has_errors then
						Result := l_json.errors_as_string
					end
					if not attached Result or else Result.is_empty then
						Result := {STRING_32} "not one JSON value"
					end
				end
			end
		ensure
			empty_is_not_json: a_text.is_empty implies Result /= Void
		end

feature {NONE} -- Implementation

	append_unicode_escape (a_target: STRING_8; a_code: NATURAL_32)
			-- Append `\uXXXX' for `a_code' (at most 0xFFFF) to `a_target'.
		require
			sixteen_bits: a_code <= 0xFFFF
		local
			l_hex: STRING_8
		do
			l_hex := a_code.to_hex_string
			a_target.append ("\u")
			a_target.append (l_hex.substring (l_hex.count - 3, l_hex.count).as_lower)
		ensure
			six_more: a_target.count = old a_target.count + 6
		end

end
