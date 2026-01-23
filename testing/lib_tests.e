note
	description: "Test cases for simple_browser"
	date: "$Date$"
	revision: "$Revision$"

class
	LIB_TESTS

inherit
	TEST_SET_BASE

feature -- Tests

	test_creation
			-- Test that library can be used.
		do
			assert ("placeholder", True)
		end

end
