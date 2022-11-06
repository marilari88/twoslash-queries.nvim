--[[ hi TypeVirtualText guifg=#CCCC00 ]]
vim.api.nvim_set_hl(0, "TypeVirtualText", { fg = "#CCCC00" })

vim.api.nvim_create_user_command("EnableTwoslashQueries", function()
	require("twoslash-queries").enable()
end, {})
vim.api.nvim_create_user_command("DisableTwoslashQueries", function()
	require("twoslash-queries").disable()
end, {})
