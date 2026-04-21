local M = {}
local cli = require("pkm.cli")

---@param title string
---@param on_save fun(content: string, lines: string[])
---@param initial_lines? string[]
local function open_capture_buffer(title, on_save, initial_lines)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "markdown"

  vim.api.nvim_buf_set_name(buf, "pkm-capture://" .. title:gsub("%s+", "-") .. "-" .. os.time())

  if initial_lines and #initial_lines > 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  end

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.4)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " PKM: " .. title .. " ",
    title_pos = "center",
  })

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(lines, "\n")

      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end

      on_save(content, lines)
    end,
  })

  vim.keymap.set(
    "n",
    "<C-c><C-c>",
    "<Cmd>w<CR>",
    { buffer = buf, silent = true, desc = "Save and close capture buffer" }
  )
  vim.keymap.set(
    "i",
    "<C-c><C-c>",
    "<Esc><Cmd>w<CR>",
    { buffer = buf, silent = true, desc = "Save and close capture buffer" }
  )

  vim.keymap.set(
    "n",
    "<Esc>",
    "<Cmd>q<CR>",
    { buffer = buf, silent = true, desc = "Close capture buffer without saving" }
  )
  vim.keymap.set("n", "q", "<Cmd>q<CR>", { buffer = buf, silent = true, desc = "Close capture buffer without saving" })
end

---@param initial_lines? string[]
function M.daily(initial_lines)
  open_capture_buffer("Daily Note", function(content, lines)
    if content:match("^%s*$") then
      vim.notify("Empty content, not saving.", vim.log.levels.WARN, { title = "PKM" })
      return
    end

    cli.daily_add(content, nil, function(stderr, res)
      vim.schedule(function()
        vim.notify("Failed to save daily note:\n" .. stderr, vim.log.levels.ERROR, { title = "PKM Error" })
        M.daily(lines)
      end)
    end)
  end, initial_lines)
end

---@param initial_lines? string[]
function M.note(initial_lines)
  open_capture_buffer("Atomic Note", function(content, lines)
    if content:match("^%s*$") then
      vim.notify("Empty content, not saving.", vim.log.levels.WARN, { title = "PKM" })
      return
    end

    cli.note_add(nil, content, nil, function(stderr, res)
      vim.schedule(function()
        vim.notify("Failed to save note:\n" .. stderr, vim.log.levels.ERROR, { title = "PKM Error" })
        M.note(lines)
      end)
    end)
  end, initial_lines)
end

return M
