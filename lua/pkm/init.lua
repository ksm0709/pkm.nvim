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
local _statusline_last_try = 0

function M.vault_invalidate()
  require("pkm.vault").current = nil
  _statusline_fetching = false
  _statusline_last_try = 0
end

function M.statusline()
  local vault = require("pkm.vault").current
  if vault and vault.name then
    return "󰠮 " .. vault.name
  end

  local now = vim.loop.now()
  if not _statusline_fetching and (now - _statusline_last_try > 5000) then
    _statusline_fetching = true
    _statusline_last_try = now

    require("pkm.cli").exec({ "vault", "list" }, {
      vault = false,
      on_success = function(res)
        local parsed = require("pkm.util").json_decode(res.stdout)
        if parsed and parsed.vaults then
          for _, v in ipairs(parsed.vaults) do
            if v.active and v.name and v.name ~= "" then
              require("pkm.vault").set({ name = v.name, path = v.path })
              vim.cmd("redrawstatus")
              break
            end
          end
        end
        _statusline_fetching = false
      end,
      on_error = function()
        _statusline_fetching = false
      end,
    })
  end

  return ""
end

return M
