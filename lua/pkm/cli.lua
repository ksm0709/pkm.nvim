---@class PkmCli
local M = {}

local pkm = require("pkm")

---@class PkmCliResult
---@field code integer Exit code
---@field stdout string Standard output
---@field stderr string Standard error

---@param args string[] Arguments to pass to the pkm CLI
---@param opts? { notify_msg?: string, on_success?: fun(res: PkmCliResult), on_error?: fun(stderr: string, res: PkmCliResult) }
local function exec_async(args, opts)
  opts = opts or {}
  
  local cmd = { "pkm" }
  if pkm.config.vault_dir then
    table.insert(cmd, "--vault")
    table.insert(cmd, pkm.config.vault_dir)
  end
  
  vim.list_extend(cmd, args)

  local notify_id
  if opts.notify_msg then
    notify_id = vim.notify(opts.notify_msg, vim.log.levels.INFO, { title = "PKM", hide_from_history = true })
  end

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        if notify_id then
          vim.notify("Success", vim.log.levels.INFO, { title = "PKM", replace = notify_id })
        end
        if opts.on_success then
          opts.on_success(obj)
        end
      else
        if notify_id then
          vim.notify("Failed", vim.log.levels.ERROR, { title = "PKM", replace = notify_id })
        end
        if opts.on_error then
          opts.on_error(obj.stderr, obj)
        else
          vim.notify("PKM CLI Error:\n" .. obj.stderr, vim.log.levels.ERROR, { title = "PKM" })
        end
      end
    end)
  end)
end

---@param content string The content to add
---@param on_success? fun(res: PkmCliResult)
---@param on_error? fun(stderr: string, res: PkmCliResult)
function M.daily_add(content, on_success, on_error)
  exec_async({ "daily", "add", content }, {
    notify_msg = "Saving daily note...",
    on_success = on_success,
    on_error = on_error,
  })
end

---@param title string|nil The title of the note (can be nil)
---@param content string The content of the note
---@param on_success? fun(res: PkmCliResult)
---@param on_error? fun(stderr: string, res: PkmCliResult)
function M.note_add(title, content, on_success, on_error)
  local args = { "note", "add" }
  if title and title ~= "" then
    table.insert(args, "--title")
    table.insert(args, title)
  end
  table.insert(args, content)

  exec_async(args, {
    notify_msg = "Saving note...",
    on_success = on_success,
    on_error = on_error,
  })
end

---@param query string The search query
---@param on_success fun(res: PkmCliResult)
---@param on_error? fun(stderr: string, res: PkmCliResult)
function M.search(query, on_success, on_error)
  exec_async({ "search", query }, {
    notify_msg = "Searching...",
    on_success = on_success,
    on_error = on_error,
  })
end

---@param pattern string The tag pattern
---@param on_success fun(res: PkmCliResult)
---@param on_error? fun(stderr: string, res: PkmCliResult)
function M.tags_search(pattern, on_success, on_error)
  exec_async({ "tags", "search", pattern }, {
    notify_msg = "Searching tags...",
    on_success = on_success,
    on_error = on_error,
  })
end

---@param title string The note title or ID
---@param on_success fun(res: PkmCliResult)
---@param on_error? fun(stderr: string, res: PkmCliResult)
function M.note_links(title, on_success, on_error)
  exec_async({ "note", "links", title }, {
    notify_msg = "Finding links...",
    on_success = on_success,
    on_error = on_error,
  })
end

return M
