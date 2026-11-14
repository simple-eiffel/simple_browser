note
	description: "[
		SB_NAVIGATION - a navigation the page started, held for SIMPLE_BROWSER.on_navigation's
		handler to allow or cancel (SIMPLE_BROWSER_SPEC.md 4.4).
	]"
	author: "Larry Rix"
	date: "$Date$"

class
	SB_NAVIGATION

create
	make

feature {NONE} -- Initialization

	make (a_url: READABLE_STRING_GENERAL; a_kind: INTEGER; a_is_main_frame: BOOLEAN)
			-- A navigation to `a_url' of kind `a_kind', in the main frame or not.
		require
			valid_kind: is_valid_kind (a_kind)
		do
			url := a_url.to_string_32
			kind := a_kind
			is_main_frame := a_is_main_frame
		ensure
			url_set: url.same_string_general (a_url)
			kind_set: kind = a_kind
			main_frame_set: is_main_frame = a_is_main_frame
		end

feature -- Access

	url: STRING_32
			-- Where the navigation goes, in full (fragment included).

	kind: INTEGER
			-- `Kind_other', `Kind_link', `Kind_form', `Kind_back_or_forward' or `Kind_reload'.

	is_main_frame: BOOLEAN
			-- Is it the main frame's navigation (not an iframe's)?

feature -- Status

	is_link: BOOLEAN
			-- Did a link start it?
		do
			Result := kind = Kind_link
		ensure
			definition: Result = (kind = Kind_link)
		end

	is_valid_kind (a_kind: INTEGER): BOOLEAN
			-- Is `a_kind' one of the `Kind_*' constants?
		do
			Result := a_kind >= Kind_other and a_kind <= Kind_reload
		end

feature -- Kinds

	Kind_other: INTEGER = 0
			-- A script, the address, or anything else.

	Kind_link: INTEGER = 1
			-- A link.

	Kind_form: INTEGER = 2
			-- A form submitted (or resubmitted).

	Kind_back_or_forward: INTEGER = 3
			-- Back or forward through the history.

	Kind_reload: INTEGER = 4
			-- A reload.

invariant
	valid_kind: is_valid_kind (kind)

end
