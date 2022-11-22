M = {}

local isEnabled = false

local virtual_types_ns = vim.api.nvim_create_namespace("virtual_types")
local get_buffer_number = function()
	return vim.api.nvim_get_current_buf()
end

local add_virtual_text = function(buffer_nr, line, text)
	vim.api.nvim_buf_set_extmark(buffer_nr, virtual_types_ns, line - 1, 0, {
		virt_text = { { text, "TypeVirtualText" } },
	})
end

local format_virtual_text = function(text)
	local converted = vim.lsp.util.convert_input_to_markdown_lines(text)
	local joined_string = table.concat(converted, "", 3, #converted - 2)
	local escaped = string.gsub(joined_string, "  ", " ")
	return string.sub(escaped, 1, 120)
end

local get_hover_text = function(client, buffer_nr, line, column)
	local position = { line = line - 2, character = column }
	if not vim.api.nvim_buf_is_valid(buffer_nr) then
		return
	end
	local params = { textDocument = vim.lsp.util.make_text_document_params(buffer_nr), position = position }
	if client then
		client.request("textDocument/hover", params, function(_, result)
			if result and result.contents and result.contents.value then
				add_virtual_text(buffer_nr, line, format_virtual_text(result.contents.value))
			end
		end)
	end
end

local get_types = function(client, buffer_nr)
	vim.api.nvim_buf_clear_namespace(buffer_nr, virtual_types_ns, 0, -1)
	local lines = vim.api.nvim_buf_get_lines(buffer_nr, 0, -1, false)
	local regex = vim.regex([[^\s*\/\/\s*\^\?]])

	for index, line in pairs(lines) do
		local match = regex:match_str(line)

		if match then
			local column = string.find(lines[index], "%^")
			get_hover_text(client, buffer_nr, index, column)
		end
	end
end

M.disable = function()
	isEnabled = false
	vim.api.nvim_buf_clear_namespace(get_buffer_number(), virtual_types_ns, 0, -1)
end

M.enable = function()
	isEnabled = true
end

local activate_types_augroup = vim.api.nvim_create_augroup("activateTypes", { clear = true })

M.attach = function(client, buffer_nr)
	isEnabled = true
	get_types(client, buffer_nr or 0)

	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "TabEnter", "InsertLeave", "TextChanged" }, {
		pattern = "*",
		group = activate_types_augroup,
		callback = function()
			if isEnabled == false then
				return
			end
			if client and client.server_capabilities.hoverProvider then
				get_types(client, buffer_nr or 0)
			end
		end,
	})
end

return M
