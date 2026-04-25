local M = {}

local cli = require("pkm.cli")
local util = require("pkm.util")

M.current = nil
M._switching = false

local function resolve_from_list(vaults, hint)
  if not vaults then
    return nil
  end

  if not hint or hint == "" then
    for _, vault in ipairs(vaults) do
      if vault.active then
        return vault
      end
    end
    return nil
  end

  for _, vault in ipairs(vaults) do
    if vault.name == hint or vault.path == hint then
      return vault
    end
  end

  return nil
end

local function configured_hint()
  local pkm = require("pkm")
  local cfg = pkm.config or {}
  return cfg.vault or cfg.vault_dir
end

function M.list()
  local result = cli.vault_list_sync()
  if not result then
    return {}
  end
  return result.vaults or {}
end

function M.where()
  local value = cli.vault_where_sync()
  return util.trim(value)
end

function M.get()
  if M.current then
    return M.current
  end

  local vaults = M.list()
  local resolved = resolve_from_list(vaults, configured_hint())
  if resolved then
    M.current = resolved
    return resolved
  end

  local where = M.where()
  if where ~= "" then
    resolved = resolve_from_list(vaults, where)
    if resolved then
      M.current = resolved
      return resolved
    end
    M.current = { path = where, name = util.basename(where) }
    return M.current
  end

  return nil
end

function M.set(vault)
  M.current = vault
  return vault
end

function M.refresh()
  M.current = nil
  return M.get()
end

function M.resolve_name(vault)
  if not vault or vault == "" then
    local current = M.get()
    return current and current.name or nil
  end

  if not vault:find("/") then
    return vault
  end

  for _, item in ipairs(M.list()) do
    if item.path == vault then
      return item.name
    end
  end

  return nil
end

function M.resolve(vault)
  if not vault or vault == "" then
    return M.get()
  end

  local name = M.resolve_name(vault)
  if not name then
    return nil
  end

  for _, item in ipairs(M.list()) do
    if item.name == name then
      return item
    end
  end

  return { name = name, path = vault }
end

function M.switch(name)
  local target = M.resolve(name)
  if not target then
    if name and name:find("/") then
      target = { name = util.basename(name), path = name }
    else
      target = { name = name, path = nil }
    end
  end

  local open_name = target.name or util.basename(target.path or "")
  if not open_name or open_name == "" then
    return false, "Unable to resolve vault name"
  end

  local ok, res = cli.vault_open_sync(open_name)
  if not ok then
    return false, res
  end

  M._switching = true
  if target.path then
    vim.cmd("cd " .. vim.fn.fnameescape(target.path))
  end
  M.set(target)
  M._switching = false
  return true, target
end

function M.daily_path(vault, date)
  local root = vault and vault.path or (M.get() and M.get().path)
  if not root or root == "" then
    return nil
  end

  return util.join_path(root, "daily", (date or os.date("%Y-%m-%d")) .. ".md")
end

function M.note_path(vault, title)
  local root = vault and vault.path or (M.get() and M.get().path)
  if not root or root == "" then
    return nil
  end

  return util.join_path(root, "notes", util.slugify(title) .. ".md")
end

function M.sub_daily_path(vault, title)
  local root = vault and vault.path or (M.get() and M.get().path)
  if not root or root == "" then
    return nil
  end
  local current_date = os.date("%Y-%m-%d")
  return util.join_path(root, "daily", current_date .. "-" .. util.slugify(title) .. ".md")
end

function M.open_file(path)
  if not path or path == "" then
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
end

function M.open_daily(vault)
  local path = M.daily_path(vault)
  if not path then
    util.notify("Unable to resolve daily note path", vim.log.levels.ERROR)
    return
  end

  M.open_file(path)
end

function M.open_sub_daily(vault, title)
  local path = M.sub_daily_path(vault, title)
  if path and util.file_exists(path) then
    M.open_file(path)
    return path
  end

  if path then
    M.open_file(path)
  end
  return path
end

return M
