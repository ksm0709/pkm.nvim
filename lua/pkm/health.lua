local M = {}

local health = vim.health or require("health")

local function report(kind, message, advice)
  local fn = health["report_" .. kind] or health[kind]
  if fn then
    if advice then
      fn(message, advice)
    else
      fn(message)
    end
  end
end

function M.check()
  report("start", "pkm.nvim")

  if vim.fn.executable("pkm") == 1 then
    report("ok", "pkm CLI is installed and executable.")
  else
    report(
      "error",
      "pkm CLI is not found in $PATH.",
      { "Install the pkm CLI tool.", "Ensure it is available in your $PATH." }
    )
  end

  if pcall(require, "snacks") then
    report("ok", "snacks.nvim is available.")
  else
    report("warn", "snacks.nvim is not available.", { "Picker-based features will not work." })
  end

  if vim.fn.executable("rg") == 1 then
    report("ok", "ripgrep is installed and executable.")
  else
    report("warn", "ripgrep is not found in $PATH.", { "Grep and file picker features will be degraded." })
  end
end

return M
