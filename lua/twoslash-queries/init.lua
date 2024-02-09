local M = {}

M.config = {
  is_enabled = true,
  multi_line = false,
  highlight = "TypeVirtualText",
}

local query_regex = vim.regex([[^\s*/\/\s*\^?]])
local virtual_types_ns = vim.api.nvim_create_namespace("virtual_types")
local activate_types_augroup = vim.api.nvim_create_augroup("activateTypes", { clear = true })

---@alias client_id integer
---@alias buffer_nr integer
---@type Map<client_id, {client: lsp.Client, buffers: buffer_nr[]}>
local clients = {}

---@alias extmark_id integer
---@alias line_nr integer
---@alias extmark_cache_item {column: integer, virtual_text: string, target_line_text: string, extmark_id: extmark_id, expired: boolean}
---@type Map<buffer_nr, Map<line_nr, extmark_cache_item>>
local extmark_cache = {}

---Mark all cached extmarks for a buffer as expired
---The extmarks won't be cleared until the next call to clear_expired_buffer_extmarks
---@param buffer_nr buffer_nr
local buf_expire_all_extmarks = function(buffer_nr)
  if extmark_cache[buffer_nr] then
    for _, cache_item in pairs(extmark_cache[buffer_nr]) do
      cache_item.expired = true
    end
  end
end

---Clear any cached extmarks that are marked as expired
---@param buffer_nr buffer_nr
local buf_clear_expired_extmarks = function(buffer_nr)
  for line_nr, cache_item in pairs(extmark_cache[buffer_nr] or {}) do
    if cache_item.expired then
      vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, cache_item.extmark_id)
      extmark_cache[buffer_nr][line_nr] = nil
    end
  end
end

---Clear any cached extmarks where the target line's text has changed since the extmark was created
---@param buffer_nr buffer_nr
local buf_clear_stale_extmarks = function(buffer_nr)
  for cache_line_nr, cache_item in pairs(extmark_cache[buffer_nr] or {}) do
    local extmark_id = cache_item.extmark_id
    local extmark = vim.api.nvim_buf_get_extmark_by_id(buffer_nr, virtual_types_ns, extmark_id, {})
    if not extmark then
      extmark_cache[buffer_nr][cache_line_nr] = nil
      return
    end
    local row = extmark[1]
    local line = row + 1
    local target_line_text = vim.api.nvim_buf_get_lines(buffer_nr, line, line + 1, false)[1]
    if cache_item.target_line_text ~= target_line_text then
      extmark_cache[buffer_nr][cache_line_nr] = nil
      vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, extmark_id)
    end
  end
end

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

---@param buffer_nr buffer_nr
---@param position {line: line_nr, character: integer}
---@param lines string[]|string
---@return extmark_id
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

local get_indent = function(line_num)
  local indentexpr = vim.bo.indentexpr
  if indentexpr ~= "" then
    vim.v.lnum = line_num
    local expr_indent_tbl = vim.api.nvim_exec2("echo " .. indentexpr, { output = true })
    local expr_indent_str = expr_indent_tbl.output
    local expr_indent = tonumber(expr_indent_str)
    return expr_indent
  end
  local prev_nonblank = vim.fn.prevnonblank(line_num - 1)
  local prev_nonblank_indent = vim.fn.indent(prev_nonblank)
  return prev_nonblank_indent
end

local update_extmark = function(client, buffer_nr, line, column, callback)
  local target_line_text = vim.api.nvim_buf_get_lines(buffer_nr, line, line + 1, false)[1]
  local position = { line = line - 2, character = column - 1 }
  if not client or not vim.api.nvim_buf_is_valid(buffer_nr) then
    callback()
    return
  end

  -- clears the cached extmark for this line, if it exists
  local clear_extmark = function()
    if
      extmark_cache[buffer_nr]
      and extmark_cache[buffer_nr][line]
      and extmark_cache[buffer_nr][line].extmark_id ~= nil
    then
      vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, extmark_cache[buffer_nr][line].extmark_id)
      extmark_cache[buffer_nr][line] = nil
    end
  end

  local finished = false
  local callback_wrapper = function(success)
    finished = true
    if not success then
      clear_extmark()
    end
    callback()
  end

  local params = { textDocument = vim.lsp.util.make_text_document_params(buffer_nr), position = position }
  local ok = client.request("textDocument/hover", params, function(_, result)
    if not result or not result.contents then
      callback_wrapper(false)
      return
    end
    -- if the virtual_text is cached already, don't update it
    -- this avoids flickering when the hover text is the same as before
    if
      extmark_cache[buffer_nr]
      and extmark_cache[buffer_nr][line]
      and extmark_cache[buffer_nr][line].column == column
      and extmark_cache[buffer_nr][line].virtual_text == result.contents
    then
      extmark_cache[buffer_nr][line].expired = false
      callback_wrapper(true)
      return
    end
    clear_extmark()
    local virtual_text = format_virtual_text(result.contents.value or result.contents)
    local extmark_id = set_virtual_text(buffer_nr, position, virtual_text)
    local cache_item = {
      column = column,
      virtual_text = virtual_text,
      target_line_text = target_line_text,
      extmark_id = extmark_id,
      expired = false,
    }
    extmark_cache[buffer_nr] = extmark_cache[buffer_nr] or {}
    extmark_cache[buffer_nr][line] = cache_item
    callback_wrapper(true)
  end)

  if not ok then
    callback_wrapper(false)
    return
  end

  -- When hovering over locations where there is no hover information,
  -- tsserver seems to not respond to the hover request at all.
  -- This means that the callback is not called, and the extmark is never cleared.
  -- As a workaround, clear the extmark after a timeout if the callback
  -- has not been called yet.
  -- If the response comes later, the callback will still be called, and the extmark
  -- will be created as expected.
  vim.defer_fn(function()
    if not finished then
      clear_extmark()
    end
  end, 250)
end

local buf_get_queries = function(buffer_nr)
  local lines = vim.api.nvim_buf_get_lines(buffer_nr, 0, -1, false)
  local matches = {}
  for index, line in pairs(lines) do
    local match = query_regex:match_str(line)
    if match then
      local column = string.find(lines[index], "%^")
      if column then
        table.insert(matches, { index, column })
      end
    end
  end
  return matches
end

local buf_update_extmarks = function(client, buffer_nr)
  if
    not client.server_capabilities.hoverProvider
    or M.config.is_enabled == false
    or not vim.api.nvim_buf_is_valid(buffer_nr)
  then
    return
  end

  buf_clear_stale_extmarks(buffer_nr)

  local matches = buf_get_queries(buffer_nr)
  if #matches == 0 then
    buf_clear_expired_extmarks(buffer_nr)
    return
  end

  local finished = 0
  for _, match in ipairs(matches) do
    local index, column = unpack(match)
    update_extmark(client, buffer_nr, index, column, function()
      finished = finished + 1
      if finished == #matches then
        buf_clear_expired_extmarks(buffer_nr)
      end
    end)
  end
end

---@param client_id client_id
local client_update_extmarks = function(client_id)
  local cur = clients[client_id]
  if not cur then
    return
  end
  for _, buffer_nr in ipairs(cur.buffers) do
    buf_update_extmarks(cur.client, buffer_nr)
  end
end

---- Public API

M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args)
end

M.disable = function()
  M.config.is_enabled = false
  vim.api.nvim_buf_clear_namespace(get_buffer_number(), virtual_types_ns, 0, -1)
end

M.enable = function()
  M.config.is_enabled = true
  vim.cmd([[doautocmd User EnableTwoslashQueries]])
end

M.attach = function(client, buffer_nr)
  buffer_nr = buffer_nr or get_buffer_number()

  if not clients[client.id] then
    clients[client.id] = { client = client, buffers = {} }
  end
  table.insert(clients[client.id].buffers, buffer_nr)

  buf_expire_all_extmarks(buffer_nr)
  client_update_extmarks(client.id)

  vim.api.nvim_clear_autocmds({
    buffer = buffer_nr,
    group = activate_types_augroup,
  })

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
        buf_expire_all_extmarks(buffer_nr)
      end
      client_update_extmarks(client.id)
    end,
  })

  vim.api.nvim_create_autocmd({
    "TextChangedI",
  }, {
    buffer = buffer_nr,
    group = activate_types_augroup,
    callback = function()
      buf_expire_all_extmarks(buffer_nr)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "EnableTwoslashQueries",
    group = activate_types_augroup,
    callback = function()
      buf_expire_all_extmarks(buffer_nr)
      client_update_extmarks(client.id)
    end,
  })
end

M.add_query = function(pos)
  local line, col = unpack(pos)
  local indent = math.max(get_indent(line), get_indent(line + 1))
  local two_slash_string = string.rep(" ", indent) .. "//"
  two_slash_string = two_slash_string .. string.rep(" ", col - #two_slash_string) .. "^?"
  vim.api.nvim_buf_set_lines(0, line, line, false, { two_slash_string })
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

return M
