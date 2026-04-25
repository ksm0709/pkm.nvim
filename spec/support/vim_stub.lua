local json = require("dkjson")
local lfs = require("lfs")

local M = {}

local function deepcopy(value)
  if type(value) ~= "table" then
    return value
  end

  local copy = {}
  for key, item in pairs(value) do
    copy[deepcopy(key)] = deepcopy(item)
  end
  return copy
end

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function split_words(value)
  local out = {}
  for word in value:gmatch("%S+") do
    table.insert(out, word)
  end
  return out
end

local function split_text(value, sep, opts)
  opts = opts or {}
  if value == "" then
    return opts.trimempty and {} or { "" }
  end

  if sep == "%s+" and not opts.plain then
    return split_words(value)
  end

  local out = {}
  local pattern = opts.plain and sep or sep
  local start = 1
  while true do
    local s, e = value:find(pattern, start, opts.plain)
    if not s then
      local tail = value:sub(start)
      if tail ~= "" or not opts.trimempty then
        table.insert(out, tail)
      end
      break
    end
    local chunk = value:sub(start, s - 1)
    if chunk ~= "" or not opts.trimempty then
      table.insert(out, chunk)
    end
    start = e + 1
  end

  return out
end

local function join_path(...)
  local parts = { ... }
  return table.concat(parts, "/"):gsub("/+", "/")
end

local function basename(path)
  return path:match("([^/]+)$") or path
end

local function basename_without_ext(path)
  local name = basename(path)
  return name:gsub("%.[^%.]+$", "")
end

local function relative_path(cwd, path)
  if starts_with(path, cwd .. "/") then
    return path:sub(#cwd + 2)
  end
  return path
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local lines = {}
  for line in file:lines() do
    table.insert(lines, line)
  end
  file:close()
  return lines
end

function M.new(opts)
  opts = opts or {}

  local state = {
    cwd = opts.cwd or lfs.currentdir(),
    next_buf = 2,
    next_win = 2,
    buffers = {},
    windows = {},
    buf_opts = {},
    win_opts = {},
    notifications = {},
    commands = {},
    keymaps = {},
    user_commands = {},
    autocmds = {},
    system_calls = {},
    job_calls = {},
    inputs = deepcopy(opts.inputs or {}),
    executables = deepcopy(opts.executables or {}),
    files = deepcopy(opts.files or {}),
    dirs = deepcopy(opts.dirs or {}),
    system_handler = opts.system_handler,
    job_handler = opts.job_handler,
    health = {},
    current_win = 1,
    current_buf = 1,
    time = opts.time or 10000,
  }

  state.buffers[1] = { valid = true, name = "", lines = { "" } }
  state.windows[1] = { valid = true, buf = 1, width = nil, height = nil, config = {} }

  local vim = {
    g = {},
    o = { columns = opts.columns or 120, lines = opts.lines or 40 },
    log = { levels = { INFO = 1, WARN = 2, ERROR = 3 } },
    loop = {
      now = function()
        return state.time
      end,
    },
  }

  function vim.notify(message, level, notify_opts)
    table.insert(state.notifications, {
      message = message,
      level = level,
      opts = notify_opts,
    })
    return #state.notifications
  end

  function vim.schedule(fn)
    fn()
  end

  function vim.trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  end

  function vim.split(value, sep, split_opts)
    return split_text(value or "", sep or "%s+", split_opts or {})
  end

  function vim.startswith(value, prefix)
    return starts_with(value, prefix)
  end

  function vim.tbl_filter(predicate, list)
    local out = {}
    for _, item in ipairs(list or {}) do
      if predicate(item) then
        table.insert(out, item)
      end
    end
    return out
  end

  function vim.tbl_extend(mode, dst, src)
    local out = deepcopy(dst or {})
    for key, value in pairs(src or {}) do
      if mode == "force" or out[key] == nil then
        out[key] = value
      end
    end
    return out
  end

  function vim.tbl_deep_extend(mode, ...)
    local out = {}
    local tables = { ... }
    for _, tbl in ipairs(tables) do
      for key, value in pairs(tbl or {}) do
        if type(value) == "table" and type(out[key]) == "table" then
          out[key] = vim.tbl_deep_extend(mode, out[key], value)
        elseif mode == "force" or out[key] == nil then
          out[key] = deepcopy(value)
        end
      end
    end
    return out
  end

  function vim.list_extend(dst, src)
    for _, item in ipairs(src or {}) do
      table.insert(dst, item)
    end
    return dst
  end

  vim.fs = {}

  function vim.fs.joinpath(...)
    return join_path(...)
  end

  vim.json = {
    decode = function(value)
      local decoded, _, err = json.decode(value)
      if err then
        error(err)
      end
      return decoded
    end,
  }

  local ensure_buffer

  function vim.cmd(command)
    table.insert(state.commands, command)
    local cd_target = command:match("^cd%s+(.+)$")
    if cd_target then
      state.cwd = cd_target:gsub([[\ ]], " ")
      return
    end

    local edit_target = command:match("^edit%s+(.+)$")
    if edit_target then
      ensure_buffer(state.current_buf).name = edit_target
      return
    end

    if command:find("vsplit", 1, true) or command:find("split", 1, true) then
      local id = state.next_win
      state.next_win = id + 1
      state.windows[id] = {
        valid = true,
        buf = state.current_buf,
        width = nil,
        height = nil,
        config = {},
      }
      state.win_opts[id] = {}
      state.current_win = id
      return
    end
  end

  vim.ui = {
    input = function(_, callback)
      callback(table.remove(state.inputs, 1))
    end,
  }

  vim.health = {
    report_start = function(message)
      table.insert(state.health, { kind = "start", message = message })
    end,
    report_ok = function(message)
      table.insert(state.health, { kind = "ok", message = message })
    end,
    report_warn = function(message, advice)
      table.insert(state.health, { kind = "warn", message = message, advice = advice })
    end,
    report_error = function(message, advice)
      table.insert(state.health, { kind = "error", message = message, advice = advice })
    end,
  }

  local function ensure_buffer_impl(buf)
    if not state.buffers[buf] then
      state.buffers[buf] = { valid = true, name = "", lines = { "" } }
    end
    if not state.buf_opts[buf] then
      state.buf_opts[buf] = {}
    end
    return state.buffers[buf]
  end
  ensure_buffer = ensure_buffer_impl

  local function ensure_window(win)
    if win == 0 then
      win = state.current_win
    end
    if not state.windows[win] then
      state.windows[win] = { valid = true, buf = 1, width = nil, height = nil, config = {} }
    end
    if not state.win_opts[win] then
      state.win_opts[win] = {}
    end
    return state.windows[win]
  end

  local function normalize_buf(buf)
    if buf == 0 then
      return state.current_buf
    end
    return buf
  end

  vim.keymap = {}
  vim.bo = setmetatable({}, {
    __index = function(t, buf)
      ensure_buffer(buf)
      local proxy = setmetatable({}, {
        __index = function(_, key)
          return state.buf_opts[buf][key]
        end,
        __newindex = function(_, key, value)
          state.buf_opts[buf][key] = value
        end,
      })
      rawset(t, buf, proxy)
      return proxy
    end,
  })

  vim.wo = setmetatable({}, {
    __index = function(t, win)
      ensure_window(win)
      local proxy = setmetatable({}, {
        __index = function(_, key)
          return state.win_opts[win][key]
        end,
        __newindex = function(_, key, value)
          state.win_opts[win][key] = value
        end,
      })
      rawset(t, win, proxy)
      return proxy
    end,
  })

  vim.fn = {}

  function vim.fn.pumvisible()
    return 0
  end

  function vim.fn.executable(name)
    return state.executables[name] and 1 or 0
  end

  function vim.fn.filereadable(path)
    if state.files[path] ~= nil then
      return 1
    end
    local stat = lfs.attributes(path)
    return stat and stat.mode == "file" and 1 or 0
  end

  function vim.fn.isdirectory(path)
    if state.dirs[path] then
      return 1
    end
    local stat = lfs.attributes(path)
    return stat and stat.mode == "directory" and 1 or 0
  end

  function vim.fn.readfile(path)
    local value = state.files[path]
    if type(value) == "table" then
      return deepcopy(value)
    elseif type(value) == "string" then
      local lines = {}
      for line in value:gmatch("([^\n]*)\n?") do
        if line ~= "" or #lines == 0 then
          table.insert(lines, line)
        end
      end
      if #lines > 0 and lines[#lines] == "" then
        table.remove(lines, #lines)
      end
      return lines
    end

    local lines = read_file(path)
    if not lines then
      error("file not found: " .. path)
    end
    return lines
  end

  function vim.fn.mkdir(path)
    state.dirs[path] = true
  end

  function vim.fn.fnameescape(path)
    return path
  end

  function vim.fn.fnamemodify(path, modifier)
    if modifier == ":t" then
      return basename(path)
    elseif modifier == ":t:r" then
      return basename_without_ext(path)
    elseif modifier == ":." then
      return relative_path(state.cwd, path)
    elseif modifier == ":h" then
      return path:gsub("/[^/]+$", "")
    elseif modifier == ":p" then
      return path
    end
    return path
  end

  function vim.fn.getcwd()
    return state.cwd
  end

  function vim.fn.expand(expr)
    if expr == "~" or expr:sub(1, 2) == "~/" then
      return join_path(os.getenv("HOME") or state.cwd, expr:sub(3))
    end
    return expr
  end

  function vim.fn.jobstart(cmd, job_opts)
    table.insert(state.job_calls, { cmd = deepcopy(cmd), opts = job_opts })
    if state.job_handler then
      return state.job_handler(cmd, job_opts, state)
    end
    return 1
  end

  function vim.system(cmd, system_opts, callback)
    local result = { code = 0, stdout = "", stderr = "" }
    if state.system_handler then
      result = state.system_handler(cmd, system_opts, state) or result
    end
    table.insert(state.system_calls, { cmd = deepcopy(cmd), opts = deepcopy(system_opts), result = deepcopy(result) })
    if callback then
      callback(result)
    end
    return {
      wait = function()
        return result
      end,
    }
  end

  vim.api = {}

  function vim.api.nvim_create_user_command(name, callback, command_opts)
    state.user_commands[name] = { callback = callback, opts = command_opts }
  end

  function vim.api.nvim_create_autocmd(event, autocmd_opts)
    table.insert(state.autocmds, { event = event, opts = autocmd_opts })
  end

  function vim.api.nvim_create_buf(_, _)
    local id = state.next_buf
    state.next_buf = id + 1
    state.buffers[id] = { valid = true, name = "", lines = { "" } }
    state.buf_opts[id] = {}
    return id
  end

  function vim.api.nvim_open_win(buf, enter, config)
    local id = state.next_win
    state.next_win = id + 1
    state.windows[id] =
      { valid = true, buf = buf, width = config.width, height = config.height, config = deepcopy(config) }
    state.win_opts[id] = {}
    if enter then
      state.current_win = id
      state.current_buf = buf
    end
    return id
  end

  function vim.api.nvim_win_is_valid(win)
    if win == 0 then
      win = state.current_win
    end
    return state.windows[win] and state.windows[win].valid or false
  end

  function vim.api.nvim_win_close(win, _)
    if win == 0 then
      win = state.current_win
    end
    if state.windows[win] then
      state.windows[win].valid = false
    end
  end

  function vim.api.nvim_win_set_width(win, width)
    ensure_window(win).width = width
  end

  function vim.api.nvim_win_set_height(win, height)
    ensure_window(win).height = height
  end

  function vim.api.nvim_set_current_win(win)
    if win == 0 then
      win = state.current_win
    end
    state.current_win = win
    if state.windows[win] then
      state.current_buf = state.windows[win].buf
    end
  end

  function vim.api.nvim_get_current_win()
    return state.current_win
  end

  function vim.api.nvim_win_set_buf(win, buf)
    if win == 0 then
      win = state.current_win
    end
    ensure_window(win).buf = buf
    state.current_buf = buf
  end

  function vim.api.nvim_win_set_cursor(win, pos)
    if win == 0 then
      win = state.current_win
    end
    ensure_window(win).cursor = deepcopy(pos)
  end

  function vim.api.nvim_buf_is_valid(buf)
    buf = normalize_buf(buf)
    return state.buffers[buf] and state.buffers[buf].valid or false
  end

  function vim.api.nvim_buf_set_name(buf, name)
    buf = normalize_buf(buf)
    ensure_buffer(buf).name = name
  end

  function vim.api.nvim_buf_get_name(buf)
    buf = normalize_buf(buf)
    return state.buffers[buf] and state.buffers[buf].name or ""
  end

  function vim.api.nvim_buf_set_text(buf, start_row, start_col, end_row, end_col, replacement)
    buf = normalize_buf(buf)
    local lines = ensure_buffer(buf).lines
    if start_row == end_row and start_row == #lines - 1 then
      local current = lines[start_row + 1] or ""
      local new_line = current:sub(1, start_col) .. replacement[1]
      lines[start_row + 1] = new_line
      for i = 2, #replacement do
        table.insert(lines, replacement[i])
      end
    end
  end

  function vim.api.nvim_buf_get_lines(buf, start_idx, end_idx, _)
    buf = normalize_buf(buf)
    local lines = ensure_buffer(buf).lines
    local s = start_idx + 1
    local e = end_idx == -1 and #lines or end_idx
    local out = {}
    for i = s, e do
      table.insert(out, lines[i] or "")
    end
    return out
  end

  function vim.api.nvim_buf_set_lines(buf, start_idx, end_idx, _, new_lines)
    buf = normalize_buf(buf)
    local lines = ensure_buffer(buf).lines
    if start_idx == 0 and end_idx == -1 then
      state.buffers[buf].lines = deepcopy(new_lines)
      return
    end
    if start_idx >= #lines then
      for _, line in ipairs(new_lines) do
        table.insert(lines, line)
      end
      return
    end
    local before = {}
    for i = 1, start_idx do
      table.insert(before, lines[i])
    end
    local after = {}
    for i = end_idx + 1, #lines do
      table.insert(after, lines[i])
    end
    state.buffers[buf].lines = {}
    vim.list_extend(state.buffers[buf].lines, before)
    vim.list_extend(state.buffers[buf].lines, new_lines)
    vim.list_extend(state.buffers[buf].lines, after)
  end

  function vim.api.nvim_buf_line_count(buf)
    buf = normalize_buf(buf)
    return #ensure_buffer(buf).lines
  end

  function vim.api.nvim_get_commands()
    return state.user_commands
  end

  function vim.keymap.set(mode, lhs, rhs, key_opts)
    table.insert(state.keymaps, { mode = mode, lhs = lhs, rhs = rhs, opts = key_opts })
  end

  vim._state = state
  return vim, state
end

return M
