if vim.g.loaded_pkm == 1 then
  return
end
vim.g.loaded_pkm = 1

local function pkm_command(opts)
  local args = opts.fargs
  local cmd = args[1]

  if not cmd then
    vim.notify("Pkm: Missing subcommand", vim.log.levels.ERROR)
    return
  end

  if cmd == "daily" then
    require("pkm.capture").daily()
  elseif cmd == "note" then
    require("pkm.capture").note()
  elseif cmd == "daily-open" then
    require("pkm.picker").daily_open()
  elseif cmd == "daily-sub" then
    require("pkm.picker").daily_sub()
  elseif cmd == "vault" then
    require("pkm.picker").vaults()
  elseif cmd == "search" then
    local query = table.concat(args, " ", 2)
    require("pkm.picker").search(query)
  elseif cmd == "tags" then
    local pattern = args[2] or ""
    require("pkm.picker").tags(pattern)
  elseif cmd == "links" then
    local title = table.concat(args, " ", 2)
    require("pkm.picker").links(title)
  elseif cmd == "grep" then
    local query = table.concat(args, " ", 2)
    require("pkm.picker").grep(query)
  elseif cmd == "files" then
    require("pkm.picker").files()
  elseif cmd == "index" then
    require("pkm.picker").index()
  elseif cmd == "workflows" then
    require("pkm.picker").workflows()
  elseif cmd == "chat" then
    require("pkm.picker").chat_toggle()
  else
    vim.notify("Pkm: Unknown subcommand '" .. cmd .. "'", vim.log.levels.ERROR)
  end
end

vim.api.nvim_create_user_command("Pkm", pkm_command, {
  nargs = "*",
  complete = function(_, line)
    local cmds = {
      "chat",
      "daily",
      "daily-open",
      "daily-sub",
      "files",
      "grep",
      "index",
      "links",
      "note",
      "search",
      "tags",
      "vault",
      "workflows",
    }
    local l = vim.split(line, "%s+")
    local n = #l - 2

    if n == 0 then
      return vim.tbl_filter(function(val)
        return vim.startswith(val, l[2] or "")
      end, cmds)
    end
  end,
  desc = "PKM commands",
})

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

map("n", "<Leader>pd", function()
  require("pkm.picker").daily_open()
end, "PKM Daily Note")
map("n", "<Leader>pD", function()
  require("pkm.picker").daily_sub()
end, "PKM New Daily Sub-note")
map("n", "<Leader>pv", function()
  require("pkm.picker").vaults()
end, "PKM Vault Picker")
map("n", "<Leader>pa", function()
  require("pkm.chat").toggle()
end, "PKM Chat")
map("n", "<Leader>pw", function()
  require("pkm.picker").workflows()
end, "PKM Workflows")
map("n", "<Leader>pg", function()
  require("pkm.picker").grep()
end, "PKM Grep")
map("n", "<Leader>pf", function()
  require("pkm.picker").files()
end, "PKM Files")
map("n", "<Leader>pi", function()
  require("pkm.picker").index()
end, "PKM Reindex")
map("n", "<Leader>ps", function()
  local word = vim.fn.expand("<cword>")
  require("pkm.picker").search(word)
end, "PKM Search")

map("v", "<Leader>ps", function()
  vim.cmd('noau normal! "vy"')
  local text = vim.fn.getreg("v")
  vim.fn.setreg("v", {})
  text = text:gsub("\n", " ")
  require("pkm.picker").search(text)
end, "PKM Search")
map("n", "<Leader>pt", function()
  require("pkm.picker").tags()
end, "PKM Tags")
map("n", "<Leader>pl", function()
  require("pkm.picker").links()
end, "PKM Links")
