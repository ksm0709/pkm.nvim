local M = {}

local health = vim.health or require("health")

function M.check()
  health.report_start("pkm.nvim")

  if vim.fn.executable("pkm") == 1 then
    health.report_ok("pkm CLI is installed and executable.")
  else
    health.report_error(
      "pkm CLI is not found in $PATH.",
      { "Install the pkm CLI tool.", "Ensure it is available in your $PATH." }
    )
  end
end

return M
