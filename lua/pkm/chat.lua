local M = {}

local cli = require("pkm.cli")
local util = require("pkm.util")
local vault = require("pkm.vault")

local state = {
  open = false,
  stdout_buf = nil,
  stdout_win = nil,
  input_buf = nil,
  input_win = nil,
  thinking = false,
  separator_inserted = false,
}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function set_buf_common(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
end

local function append_text(buf, text)
  if not valid_buf(buf) or not text or text == "" then
    return
  end

  vim.bo[buf].modifiable = true

  if state.thinking and not state.separator_inserted then
    local is_work = text:match("%s*↳") or text:match("%[thinking%]") or text:match("Asking daemon")
    if not is_work and text:match("%S") then
      state.separator_inserted = true
      state.thinking = false

      local line_count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { "", "---", "" })
    end
  end

  local segments = vim.split(text, "\r", { plain = true })

  for i, segment in ipairs(segments) do
    local line_count = vim.api.nvim_buf_line_count(buf)

    if i > 1 then
      vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, { "" })
    end

    if segment ~= "" then
      local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1]
      local last_col = #last_line
      local lines = vim.split(segment, "\n", { plain = true })
      vim.api.nvim_buf_set_text(buf, line_count - 1, last_col, line_count - 1, last_col, lines)
    end
  end

  if valid_win(state.stdout_win) then
    vim.api.nvim_win_set_cursor(state.stdout_win, { vim.api.nvim_buf_line_count(buf), 0 })
  end

  vim.bo[buf].modifiable = false
end

local function clear_input()
  if valid_buf(state.input_buf) then
    vim.bo[state.input_buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
    vim.bo[state.input_buf].modifiable = true
  end
end

local function close()
  if valid_win(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end
  if valid_win(state.stdout_win) then
    vim.api.nvim_win_close(state.stdout_win, true)
  end

  state.open = false
  state.stdout_buf = nil
  state.stdout_win = nil
  state.input_buf = nil
  state.input_win = nil
end

local function run_stream(args, title)
  local current = vault.get()
  local vault_name = current and current.name or nil

  state.thinking = true
  state.separator_inserted = false
  append_text(state.stdout_buf, ("\n$ pkm %s\n"):format(table.concat(args, " ")))

  cli.stream(args, {
    vault = vault_name,
    on_stdout = function(text)
      append_text(state.stdout_buf, text)
    end,
    on_stderr = function(text)
      append_text(state.stdout_buf, "[stderr] " .. text)
    end,
    on_exit = function(code, _)
      append_text(state.stdout_buf, ("\n[%s exit=%d]\n"):format(title, code))
    end,
  })
end

function M.open()
  if state.open and valid_win(state.stdout_win) and valid_win(state.input_win) then
    vim.api.nvim_set_current_win(state.input_win)
    return state
  end

  vim.cmd("botright vsplit")
  state.stdout_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(state.stdout_win, math.max(44, math.floor(vim.o.columns * 0.36)))

  state.stdout_buf = vim.api.nvim_create_buf(false, true)
  set_buf_common(state.stdout_buf)
  vim.api.nvim_win_set_buf(state.stdout_win, state.stdout_buf)
  vim.bo[state.stdout_buf].filetype = "markdown"
  vim.bo[state.stdout_buf].modifiable = false
  vim.bo[state.stdout_buf].readonly = true

  vim.wo[state.stdout_win].wrap = true
  vim.wo[state.stdout_win].winfixwidth = true
  vim.wo[state.stdout_win].number = false
  vim.wo[state.stdout_win].relativenumber = false
  vim.wo[state.stdout_win].signcolumn = "no"

  vim.cmd("belowright split")
  state.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(state.input_win, 4)

  state.input_buf = vim.api.nvim_create_buf(false, true)
  set_buf_common(state.input_buf)
  vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
  vim.bo[state.input_buf].filetype = "markdown"
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  vim.wo[state.input_win].wrap = true
  vim.wo[state.input_win].winfixwidth = true
  vim.wo[state.input_win].winfixheight = true
  vim.wo[state.input_win].number = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn = "no"

  vim.keymap.set("n", "q", close, { buffer = state.stdout_buf, silent = true, desc = "Close PKM chat" })
  vim.keymap.set("n", "q", close, { buffer = state.input_buf, silent = true, desc = "Close PKM chat" })
  vim.keymap.set("n", "<Esc>", close, { buffer = state.stdout_buf, silent = true, desc = "Close PKM chat" })
  vim.keymap.set("n", "<Esc>", close, { buffer = state.input_buf, silent = true, desc = "Close PKM chat" })

  local function submit()
    if not valid_buf(state.input_buf) then
      return
    end

    local line = util.trim(vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1])
    if line == "" then
      return
    end

    clear_input()
    append_text(state.stdout_buf, ("\n> %s\n"):format(line))
    run_stream({ "ask", line }, "ask")
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert")
  end

  vim.keymap.set({ "n", "i" }, "<CR>", submit, { buffer = state.input_buf, silent = true, desc = "Submit PKM ask" })
  vim.keymap.set({ "n", "i" }, "<C-c>", close, { buffer = state.input_buf, silent = true, desc = "Close PKM chat" })
  vim.keymap.set({ "n", "i" }, "<C-c>", close, { buffer = state.stdout_buf, silent = true, desc = "Close PKM chat" })

  state.open = true
  vim.api.nvim_set_current_win(state.input_win)
  vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
  vim.cmd("startinsert")

  append_text(state.stdout_buf, "PKM chat ready\n")
  return state
end

function M.toggle()
  if state.open and valid_win(state.stdout_win) and valid_win(state.input_win) then
    close()
    return
  end

  M.open()
end

function M.stream_prompt(title, prompt)
  M.open()
  append_text(state.stdout_buf, ("\n[%s]\n"):format(title))
  run_stream({ "ask", prompt }, title)
end

function M.stream_workflow(name, prompt)
  M.open()
  append_text(state.stdout_buf, ("\n[workflow] %s\n"):format(name))
  cli.daemon_start({
    vault = vault.get() and vault.get().name or nil,
    on_success = function()
      run_stream({ "ask", prompt }, name)
    end,
    on_error = function(stderr)
      append_text(state.stdout_buf, "[daemon error] " .. stderr)
      run_stream({ "ask", prompt }, name)
    end,
  })
end

function M.append(text)
  M.open()
  append_text(state.stdout_buf, text)
end

return M
