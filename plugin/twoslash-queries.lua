vim.api.nvim_set_hl(0, "TypeVirtualText", { fg = "#CCCC00" })

vim.api.nvim_create_user_command("TwoslashQueriesEnable", function()
	require("twoslash-queries").enable()
end, { nargs = 0, desc = "Enable two slash queries" })

vim.api.nvim_create_user_command("TwoslashQueriesDisable", function()
	require("twoslash-queries").disable()
end, { nargs = 0, desc = "Disable two slash queries" })

vim.api.nvim_create_user_command("TwoslashQueriesInspect", function()
	-- get cursor position
	local r, c = unpack(vim.api.nvim_win_get_cursor(0))

	-- create a string line //
	local two_slash_string = "//"
	local i = 2
	while i < c do
		two_slash_string = two_slash_string .. " "
		i = i + 1
	end
	two_slash_string = two_slash_string .. "^?"

	-- write string line
	vim.api.nvim_buf_set_lines(0, r, r, false, { two_slash_string })
end, { nargs = 0, desc = "Inspect variable under the cursor" })

vim.api.nvim_create_user_command("TwoslashQueriesRemove", function()
	require("twoslash-queries").remove_queries()
end, { nargs = 0, desc = "Remove all two slash queries in the current buffer" })

-- Fallback command for backward compatibility
vim.api.nvim_create_user_command("EnableTwoslashQueries", function()
	print("EnableTwoslashQueries commad is obsolete. Use TwoslashQueriesEnable")
	vim.api.nvim_command("EnableTwoslashQueries")
end, { nargs = 0, desc = "[Deprecated] Enable two slash queries" })

vim.api.nvim_create_user_command("DisableTwoslashQueries", function()
	print("DisableTwoslashQueries commad is obsolete. Use TwoslashQueriesDisable")
	vim.api.nvim_command("DisableTwoslashQueries")
end, { nargs = 0, desc = "[Deprecated] Disable two slash queries" })

vim.api.nvim_create_user_command("InspectTwoslashQueries", function()
	print("InspectTwoslashQueries commad is obsolete. Use TwoslashQueriesInspect")
	vim.api.nvim_command("InspectTwoslashQueries")
end, { nargs = 0, desc = "[Deprecated] Inspect two slash queries" })

vim.api.nvim_create_user_command("RemoveTwoslashQueries", function()
	print("RemoveTwoslashQueries commad is obsolete. Use TwoslashQueriesRemove")
	require("twoslash-queries").remove_queries()
end, { nargs = 0, desc = "[Deprecated] Remove two slash queries" })
