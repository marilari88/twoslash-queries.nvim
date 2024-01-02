local M = {}

M.config = {
  is_enabled = true,
  multi_line = false,
  highlight = "TypeVirtualText",
}

M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args)
end

local query_regex = vim.regex([[^\s*/\/\s*\^?]])

local virtual_types_ns = vim.api.nvim_create_namespace("virtual_types")
local get_buffer_number = function()
  return vim.api.nvim_get_current_buf()
end

local get_whitespaces_string = function(whitespaces)
  local str = ""
  local i = 0
  while i < whitespaces do
    str = str .. " "
    i = i + 1
  end
  return str
end

local set_virtual_text = function(buffer_nr, position, lines)
  local virt_text = {}
  local virt_lines = {}

  if M.config.multi_line == true then
    virt_text = { { lines[1], M.config.highlight } }
    for i = 2, #lines do
      virt_lines[i - 1] = { { get_whitespaces_string(position.character + 2) .. lines[i], M.config.highlight } }
    end
  else
    virt_text = { { lines, M.config.highlight } }
  end

  return vim.api.nvim_buf_set_extmark(buffer_nr, virtual_types_ns, position.line + 1, 0, {
    virt_text = virt_text,
    virt_lines = virt_lines,
  })
end

local get_response_limit_indexes = function(lines)
  local start = nil
  local result_limit = vim.regex([[```]])
  for index, line in pairs(lines) do
    local match = result_limit:match_str(line)

    if start ~= nil and match then
      return { start + 1, index - 1 }
    end
    if match then
      start = index
    end
  end
  return { 1, #lines }
end

local format_virtual_text = function(text)
  local converted = vim.lsp.util.convert_input_to_markdown_lines(text, {})
  local limits = get_response_limit_indexes(converted)
  if M.config.multi_line == true then
    local selected_lines = vim.list_slice(converted, limits[1], limits[2])
    return selected_lines
  end
  local joined_string = table.concat(converted, "", limits[1], limits[2])
  local escaped = string.gsub(joined_string, "  ", " ")
  return string.sub(escaped, 1, 120)
end

M.remove_queries = function()
  vim.api.nvim_buf_clear_namespace(0, virtual_types_ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local removed_lines = 0

  for index, line in pairs(lines) do
    local match = query_regex:match_str(line)

    if match then
      vim.api.nvim_buf_set_lines(0, index - 1 - removed_lines, index - removed_lines, true, {})
      removed_lines = removed_lines + 1
    end
  end
end

---@alias line integer
---@type Map<bufnr, Map<line, {column:integer, text:integer, extmark:integer}>>
local cache = {}

local clear_cache = function(buffer_nr)
  if cache[buffer_nr] then
    for _, line in pairs(cache[buffer_nr]) do
      if line.extmark then
        vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, line.extmark)
      end
    end
    cache[buffer_nr] = nil
  end
end

local update_hover_text = function(client, buffer_nr, line, column)
  local position = { line = line - 2, character = column }
  if not vim.api.nvim_buf_is_valid(buffer_nr) then
    return
  end
  local params = { textDocument = vim.lsp.util.make_text_document_params(buffer_nr), position = position }
  if client then
    client.request("textDocument/hover", params, function(_, result)
      if result and result.contents then
        -- if the text is cached already, don't update it
        if
          cache[buffer_nr]
          and cache[buffer_nr][line]
          and cache[buffer_nr][line].column == column
          and cache[buffer_nr][line].text == result.contents
        then
          return
        end
        if cache[buffer_nr] and cache[buffer_nr][line] and cache[buffer_nr][line].extmark then
          vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, cache[buffer_nr][line].extmark)
        end
        local formatted_text = format_virtual_text(result.contents.value or result.contents)
        local extmark = set_virtual_text(buffer_nr, position, formatted_text)
        cache[buffer_nr] = cache[buffer_nr] or {}
        cache[buffer_nr][line] = { column = column, text = formatted_text, extmark = extmark }
      end
    end)
  end
end

local update_types = function(client, buffer_nr)
  if not client.server_capabilities.hoverProvider then
    return
  end
  -- vim.api.nvim_buf_clear_namespace(buffer_nr, virtual_types_ns, 0, -1)

  if M.config.is_enabled == false then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buffer_nr, 0, -1, false)
  for index, line in pairs(lines) do
    local match = query_regex:match_str(line)

    if match then
      local column = string.find(lines[index], "%^")
      update_hover_text(client, buffer_nr, index, column)
    end
  end
end

M.disable = function()
  M.config.is_enabled = false
  vim.api.nvim_buf_clear_namespace(get_buffer_number(), virtual_types_ns, 0, -1)
end

M.enable = function()
  M.config.is_enabled = true
  vim.cmd([[doautocmd User EnableTwoslashQueries]])
end

local activate_types_augroup = vim.api.nvim_create_augroup("activateTypes", { clear = true })

---@alias client_id integer
---@alias bufnr integer

---@type Map<client_id, {client: lsp.Client, bufs: bufnr[]}>
local clients = {}

---@param client_id client_id
local function update_types_for_client(client_id)
  local cur = clients[client_id]
  if not cur then
    return
  end
  for _, bufnr in ipairs(cur.bufs) do
    update_types(cur.client, bufnr)
  end
end

M.attach = function(client, buffer_nr)
  buffer_nr = buffer_nr or get_buffer_number()

  if not clients[client.id] then
    clients[client.id] = { client = client, bufs = {} }
  end
  table.insert(clients[client.id].bufs, buffer_nr)

  clear_cache(buffer_nr)
  update_types_for_client(client.id)

  vim.api.nvim_create_autocmd({
    "BufWinEnter",
    "TabEnter",
    "InsertLeave",
    "TextChanged",
  }, {
    buffer = buffer_nr,
    group = activate_types_augroup,
    callback = function(ev)
      if ev.event == "TextChanged" then
        clear_cache(buffer_nr)
      end
      update_types_for_client(client.id)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "EnableTwoslashQueries",
    group = activate_types_augroup,
    callback = function()
      clear_cache(buffer_nr)
      update_types_for_client(client.id)
    end,
  })
end

return M
