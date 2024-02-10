vim.api.nvim_set_hl(0, "TypeVirtualText", { fg = "#CCCC00", default = true })

vim.api.nvim_create_user_command("TwoslashQueriesEnable", function()
  require("twoslash-queries").enable()
end, { nargs = 0, desc = "Enable two slash queries" })

vim.api.nvim_create_user_command("TwoslashQueriesDisable", function()
  require("twoslash-queries").disable()
end, { nargs = 0, desc = "Disable two slash queries" })

vim.api.nvim_create_user_command("TwoslashQueriesInspect", function()
  require("twoslash-queries").add_query(vim.api.nvim_win_get_cursor(0))
end, { nargs = 0, desc = "Inspect variable under the cursor" })

vim.api.nvim_create_user_command("TwoslashQueriesRemove", function()
  require("twoslash-queries").remove_queries()
end, { nargs = 0, desc = "Remove all two slash queries in the current buffer" })

-- Fallback command for backward compatibility
vim.api.nvim_create_user_command("EnableTwoslashQueries", function()
  print("EnableTwoslashQueries commad is obsolete. Use TwoslashQueriesEnable")
  vim.api.nvim_command("TwoslashQueriesEnable")
end, { nargs = 0, desc = "[Deprecated] Enable two slash queries" })

vim.api.nvim_create_user_command("DisableTwoslashQueries", function()
  print("DisableTwoslashQueries commad is obsolete. Use TwoslashQueriesDisable")
  vim.api.nvim_command("TwoslashQueriesDisable")
end, { nargs = 0, desc = "[Deprecated] Disable two slash queries" })

vim.api.nvim_create_user_command("InspectTwoslashQueries", function()
  print("InspectTwoslashQueries commad is obsolete. Use TwoslashQueriesInspect")
  vim.api.nvim_command("TwoslashQueriesInspect")
end, { nargs = 0, desc = "[Deprecated] Inspect two slash queries" })

vim.api.nvim_create_user_command("RemoveTwoslashQueries", function()
  print("RemoveTwoslashQueries commad is obsolete. Use TwoslashQueriesRemove")
  vim.api.nvim_command("TwoslashQueriesRemove")
end, { nargs = 0, desc = "[Deprecated] Remove two slash queries" })
