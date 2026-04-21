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
  elseif cmd == "search" then
    local query = table.concat(args, " ", 2)
    require("pkm.picker").search(query)
  elseif cmd == "tags" then
    local pattern = args[2] or ""
    require("pkm.picker").tags(pattern)
  elseif cmd == "links" then
    local title = table.concat(args, " ", 2)
    require("pkm.picker").links(title)
  else
    vim.notify("Pkm: Unknown subcommand '" .. cmd .. "'", vim.log.levels.ERROR)
  end
end

vim.api.nvim_create_user_command("Pkm", pkm_command, {
  nargs = "*",
  complete = function(_, line)
    local cmds = { "daily", "note", "search", "tags", "links" }
    local l = vim.split(line, "%s+")
    local n = #l - 2

    if n == 0 then
      return vim.tbl_filter(function(val)
        return vim.startswith(val, l[2])
      end, cmds)
    end
  end,
  desc = "PKM commands",
})

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

map("n", "<Leader>pd", function() require("pkm.capture").daily() end, "PKM Daily Note")
map("n", "<Leader>pn", function() require("pkm.capture").note() end, "PKM New Note")
map("n", "<Leader>ps", function() require("pkm.picker").search() end, "PKM Search")
map("n", "<Leader>pt", function() require("pkm.picker").tags() end, "PKM Tags")
map("n", "<Leader>pl", function() require("pkm.picker").links() end, "PKM Links")
