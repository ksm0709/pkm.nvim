local M = {}

local cli = require("pkm.cli")
local vault = require("pkm.vault")

local SLASH_COMMANDS = {
  { word = "/subnote ", menu = "create a linked sub-note" },
}

local state = {
  open = false,
  prev_win = nil,
  viewer_buf = nil,
  viewer_win = nil,
  input_buf = nil,
  input_win = nil,
  autocmd_id = nil,
}

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_state()
  return valid_win(state.viewer_win) and valid_win(state.input_win)
end

local function refresh_viewer()
  if not valid_buf(state.viewer_buf) or not valid_win(state.viewer_win) then
    return
  end

  local path = vault.daily_path(vault.get())
  local lines = (path and vim.fn.filereadable(path) == 1) and vim.fn.readfile(path) or {}

  vim.bo[state.viewer_buf].readonly = false
  vim.bo[state.viewer_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.viewer_buf, 0, -1, false, lines)
  vim.bo[state.viewer_buf].modifiable = false
  vim.bo[state.viewer_buf].readonly = true

  vim.api.nvim_win_set_cursor(state.viewer_win, { math.max(1, #lines), 0 })
end

local function close()
  if state.autocmd_id then
    pcall(vim.api.nvim_del_autocmd, state.autocmd_id)
    state.autocmd_id = nil
  end

  if valid_win(state.input_win) then
    vim.api.nvim_win_close(state.input_win, true)
  end
  if valid_win(state.viewer_win) then
    vim.api.nvim_win_close(state.viewer_win, true)
  end

  local prev = state.prev_win
  state.open = false
  state.prev_win = nil
  state.viewer_buf = nil
  state.viewer_win = nil
  state.input_buf = nil
  state.input_win = nil

  if prev and vim.api.nvim_win_is_valid(prev) then
    vim.api.nvim_set_current_win(prev)
  end
end

function M.open()
  if state.open and valid_state() then
    vim.api.nvim_set_current_win(state.input_win)
    vim.cmd("startinsert")
    return
  end

  state.prev_win = vim.api.nvim_get_current_win()

  vim.cmd("botright vsplit")
  state.viewer_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(state.viewer_win, math.max(44, math.floor(vim.o.columns * 0.36)))

  state.viewer_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.viewer_buf].buftype = "nofile"
  vim.bo[state.viewer_buf].bufhidden = "wipe"
  vim.bo[state.viewer_buf].swapfile = false
  vim.bo[state.viewer_buf].filetype = "markdown"
  vim.bo[state.viewer_buf].modifiable = false
  vim.bo[state.viewer_buf].readonly = true
  vim.api.nvim_win_set_buf(state.viewer_win, state.viewer_buf)

  vim.wo[state.viewer_win].wrap = true
  vim.wo[state.viewer_win].winfixwidth = true
  vim.wo[state.viewer_win].number = false
  vim.wo[state.viewer_win].relativenumber = false
  vim.wo[state.viewer_win].signcolumn = "no"

  vim.cmd("belowright split")
  state.input_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(state.input_win, 3)

  state.input_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.input_buf].buftype = "nofile"
  vim.bo[state.input_buf].bufhidden = "wipe"
  vim.bo[state.input_buf].swapfile = false
  vim.bo[state.input_buf].modifiable = true
  vim.api.nvim_win_set_buf(state.input_win, state.input_buf)
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

  vim.wo[state.input_win].wrap = true
  vim.wo[state.input_win].winfixwidth = true
  vim.wo[state.input_win].winfixheight = true
  vim.wo[state.input_win].number = false
  vim.wo[state.input_win].relativenumber = false
  vim.wo[state.input_win].signcolumn = "no"
  vim.wo[state.input_win].statusline = "  PKM Daily  │  /subnote <title> "

  local vbuf = state.viewer_buf
  local ibuf = state.input_buf

  vim.keymap.set("n", "q", close, { buffer = vbuf, silent = true, desc = "Close PKM daily" })
  vim.keymap.set("n", "<Esc>", close, { buffer = vbuf, silent = true, desc = "Close PKM daily" })
  vim.keymap.set({ "n", "i" }, "<C-c>", close, { buffer = vbuf, silent = true, desc = "Close PKM daily" })
  vim.keymap.set("n", "q", close, { buffer = ibuf, silent = true, desc = "Close PKM daily" })
  vim.keymap.set("n", "<Esc>", close, { buffer = ibuf, silent = true, desc = "Close PKM daily" })
  vim.keymap.set({ "n", "i" }, "<C-c>", close, { buffer = ibuf, silent = true, desc = "Close PKM daily" })

  local function submit()
    if not valid_buf(state.input_buf) then
      return
    end

    local raw = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
    local content = vim.trim(table.concat(raw, " "))
    if content == "" then
      return
    end

    vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })

    local function on_error(stderr)
      vim.notify("PKM: " .. (stderr or "error"), vim.log.levels.ERROR, { title = "PKM" })
    end

    local cmd, arg = content:match("^/(%S+)%s*(.*)")
    if cmd then
      arg = vim.trim(arg or "")
      if cmd == "subnote" then
        local function open_subnote(title)
          cli.daily_sub(title, function()
            local path = vault.sub_daily_path(vault.get(), title)
            close()
            if path and vim.fn.filereadable(path) == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(path))
            end
          end, on_error)
        end
        if arg == "" then
          vim.ui.input({ prompt = "Sub-note title: " }, function(title)
            if title and vim.trim(title) ~= "" then
              open_subnote(vim.trim(title))
            end
          end)
        else
          open_subnote(arg)
        end
      else
        vim.notify("Unknown command: /" .. cmd, vim.log.levels.WARN, { title = "PKM" })
      end
      return
    end

    cli.daily_add(content, refresh_viewer, on_error)
  end

  vim.keymap.set({ "n", "i" }, "<CR>", function()
    if vim.fn.pumvisible() == 1 then
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
      return
    end
    submit()
  end, { buffer = ibuf, silent = true, desc = "Submit PKM daily or accept completion" })

  vim.keymap.set("i", "<Tab>", function()
    if vim.fn.pumvisible() == 1 then
      return "<C-y>"
    end
    return "<Tab>"
  end, { buffer = ibuf, expr = true, silent = true, desc = "Accept completion" })

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = ibuf,
    callback = function()
      local line = vim.api.nvim_get_current_line()
      if not line:match("^/") then
        return
      end
      local col = vim.fn.col(".")
      local typed = line:sub(1, col - 1)
      local matches = {}
      for _, cmd in ipairs(SLASH_COMMANDS) do
        if cmd.word:sub(1, #typed) == typed then
          matches[#matches + 1] = cmd
        end
      end
      if #matches > 0 then
        vim.fn.complete(1, matches)
      end
    end,
    desc = "PKM daily slash command completion",
  })

  state.autocmd_id = vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(ev)
      if not state.open then
        return
      end
      local closed = tonumber(ev.match)
      if closed == state.viewer_win or closed == state.input_win then
        vim.schedule(close)
      end
    end,
    desc = "PKM daily panel cleanup",
  })

  state.open = true

  refresh_viewer()

  vim.api.nvim_set_current_win(state.input_win)
  vim.cmd("startinsert")
end

M.close = close

function M.toggle()
  if state.open and valid_state() then
    close()
    return
  end
  M.open()
end

return M
