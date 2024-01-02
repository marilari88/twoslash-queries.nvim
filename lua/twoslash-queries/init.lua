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
---@alias cache_item {column:integer,text:string,extmark:integer,clear:boolean,target:string}
---@type Map<bufnr, Map<line, cache_item>>
local cache = {}

local clear_cache = function(buffer_nr)
  if cache[buffer_nr] then
    for _, line in pairs(cache[buffer_nr]) do
      line.clear = true
    end
  end
end

local update_hover_text = function(client, buffer_nr, line, column, cb)
  local target = vim.api.nvim_buf_get_lines(buffer_nr, line, line + 1, false)[1]
  local position = { line = line - 2, character = column }
  if not vim.api.nvim_buf_is_valid(buffer_nr) then
    cb()
    return
  end
  local params = { textDocument = vim.lsp.util.make_text_document_params(buffer_nr), position = position }
  if not client then
    cb()
    return
  end
  client.request("textDocument/hover", params, function(_, result)
    if result and result.contents then
      -- if the text is cached already, don't update it
      if
        cache[buffer_nr]
        and cache[buffer_nr][line]
        and cache[buffer_nr][line].column == column
        and cache[buffer_nr][line].text == result.contents
      then
        cache[buffer_nr][line].clear = false
        cb()
        return
      end
      if cache[buffer_nr] and cache[buffer_nr][line] and cache[buffer_nr][line].extmark then
        vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, cache[buffer_nr][line].extmark)
        cache[buffer_nr][line] = nil
      end
      local formatted_text = format_virtual_text(result.contents.value or result.contents)
      local extmark = set_virtual_text(buffer_nr, position, formatted_text)
      cache[buffer_nr] = cache[buffer_nr] or {}
      cache[buffer_nr][line] = {
        column = column,
        text = formatted_text,
        extmark = extmark,
        clear = false,
        target = target,
      }
    end
    cb()
  end)
end

local _clear_cache = function(buffer_nr)
  for line, data in pairs(cache[buffer_nr] or {}) do
    if data.clear then
      vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, data.extmark)
      cache[buffer_nr][line] = nil
    end
  end
end

local update_types = function(client, buffer_nr)
  if not client.server_capabilities.hoverProvider or M.config.is_enabled == false then
    return
  end

  -- update cache in case extmark positions have changed
  local extmarks = vim.api.nvim_buf_get_extmarks(buffer_nr, virtual_types_ns, 0, -1, {})
  for _, extmark in ipairs(extmarks) do
    local extmark_id = extmark[1]
    local row = extmark[2]
    local line = row + 1
    for cache_line, cache_item in pairs(cache[buffer_nr] or {}) do
      if cache_item.extmark == extmark_id then
        if cache_line ~= line then
          local target = vim.api.nvim_buf_get_lines(buffer_nr, line, line + 1, false)[1]
          if cache_item.target ~= target then
            cache[buffer_nr][cache_line] = nil
            vim.api.nvim_buf_del_extmark(buffer_nr, virtual_types_ns, extmark_id)
          end
        end
        break
      end
    end
  end

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

  local finished = 0
  local cb = function()
    finished = finished + 1
    if finished == #matches then
      _clear_cache(buffer_nr)
    end
  end
  if #matches == 0 then
    _clear_cache(buffer_nr)
  else
    for _, match in ipairs(matches) do
      local index = match[1]
      local column = match[2]
      update_hover_text(client, buffer_nr, index, column, cb)
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

  vim.api.nvim_create_autocmd({
    "TextChangedI",
  }, {
    buffer = buffer_nr,
    group = activate_types_augroup,
    callback = function()
      clear_cache(buffer_nr)
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
