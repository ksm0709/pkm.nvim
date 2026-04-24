---@class PkmConfig
---@field vault? string Vault name or path override for CLI calls.
---@field vault_dir? string Path to the PKM vault. If nil, uses the CLI default.
---@field auto_index? boolean Whether to auto-index on certain actions.
---@field workflows? table[] Optional workflow definitions for picker launches.

---@class Pkm
---@field config PkmConfig
local M = {}

setmetatable(M, {
  __index = function(t, k)
    ---@diagnostic disable-next-line: no-unknown
    t[k] = require("pkm." .. k)
    return t[k]
  end,
})

---@type PkmConfig
local default_config = {
  vault = nil,
  vault_dir = nil,
  auto_index = true,
  workflows = nil,
}

M.config = default_config

---@param opts? PkmConfig
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", default_config, opts or {})
end

local _statusline_fetching = false

function M.statusline()
  local vault = require("pkm.vault").current
  if vault and vault.name then
    return "󰠮 " .. vault.name
  end

  if not _statusline_fetching then
    _statusline_fetching = true
    vim.schedule(function()
      require("pkm.vault").get()
      vim.cmd("redrawstatus")
    end)
  end

  return ""
end

return M
