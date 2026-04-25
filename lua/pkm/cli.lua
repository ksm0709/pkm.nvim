---@class PkmCli
local M = {}

local pkm = require("pkm")
local util = require("pkm.util")

---@class PkmCliResult
---@field code integer Exit code
---@field stdout string Standard output
---@field stderr string Standard error

---@class PkmCliOpts
---@field notify_msg? string
---@field on_success? fun(res: PkmCliResult)
---@field on_error? fun(stderr: string, res: PkmCliResult)

local function notify(message, level, replace)
  local opts = { title = "PKM", hide_from_history = true }
  if replace then
    opts.replace = replace
  end
  vim.notify(message, level or vim.log.levels.INFO, opts)
end

local function sync_exec(cmd)
  return vim.system(cmd, { text = true }):wait()
end

local function parse_json(value)
  return util.json_decode(value)
end

local function resolve_configured_vault_hint()
  local cfg = pkm.config or {}
  return cfg.vault or cfg.vault_dir
end

local function vault_list_sync()
  local obj = sync_exec({ "pkm", "vault", "list" })
  if obj.code ~= 0 then
    return nil, obj
  end

  local parsed = parse_json(obj.stdout)
  if not parsed then
    return nil, obj
  end

  return parsed, obj
end

local function vault_where_sync()
  local obj = sync_exec({ "pkm", "vault", "where" })
  if obj.code ~= 0 then
    return nil, obj
  end

  return util.trim(obj.stdout), obj
end

local function resolve_vault_name(hint)
  hint = hint or resolve_configured_vault_hint()
  if not hint or hint == "" then
    local parsed = vault_list_sync()
    if parsed and parsed.vaults then
      for _, vault in ipairs(parsed.vaults) do
        if vault.active then
          return vault.name
        end
      end
    end

    local where = vault_where_sync()
    if where and where ~= "" and parsed and parsed.vaults then
      for _, vault in ipairs(parsed.vaults) do
        if vault.path == where then
          return vault.name
        end
      end
    end

    return nil
  end

  if not hint:find("/") then
    return hint
  end

  local parsed = vault_list_sync()
  if parsed and parsed.vaults then
    for _, vault in ipairs(parsed.vaults) do
      if vault.path == hint then
        return vault.name
      end
    end
  end

  return nil
end

local function build_cmd(args, opts)
  opts = opts or {}

  local cmd = { "pkm" }
  if opts.vault ~= false then
    local vault_name = resolve_vault_name(opts.vault)
    if vault_name and vault_name ~= "" then
      table.insert(cmd, "--vault")
      table.insert(cmd, vault_name)
    end
  end

  vim.list_extend(cmd, args)
  return cmd
end

local function exec_async(args, opts)
  opts = opts or {}
  local cmd = build_cmd(args, opts)

  local notify_id
  if opts.notify_msg then
    notify_id = vim.notify(opts.notify_msg, vim.log.levels.INFO, { title = "PKM", hide_from_history = true })
  end

  vim.system(cmd, { text = true }, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        if notify_id then
          notify("Success", vim.log.levels.INFO, notify_id)
        end
        if opts.on_success then
          opts.on_success(obj)
        end
      else
        if notify_id then
          notify("Failed", vim.log.levels.ERROR, notify_id)
        end
        if opts.on_error then
          opts.on_error(obj.stderr, obj)
        else
          notify("PKM CLI Error:\n" .. obj.stderr, vim.log.levels.ERROR)
        end
      end
    end)
  end)
end

local function collect_stream(data)
  if not data or #data == 0 then
    return ""
  end
  local valid_data = {}
  for _, value in ipairs(data) do
    if value ~= nil then
      table.insert(valid_data, value)
    end
  end
  local text = table.concat(valid_data, "\n")
  return util.normalize_output(text)
end

local function exec_stream(args, opts)
  opts = opts or {}
  local cmd = build_cmd(args, opts)

  local job_id = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data, _)
      local text = collect_stream(data)
      if text ~= "" and opts.on_stdout then
        vim.schedule(function()
          opts.on_stdout(text)
        end)
      end
    end,
    on_stderr = function(_, data, _)
      local text = collect_stream(data)
      if text ~= "" and opts.on_stderr then
        vim.schedule(function()
          opts.on_stderr(text)
        end)
      end
    end,
    on_exit = function(_, code, _)
      vim.schedule(function()
        if code == 0 then
          if opts.on_exit then
            opts.on_exit(code, nil)
          end
        else
          if opts.on_exit then
            opts.on_exit(code, code)
          end
          if opts.on_error then
            opts.on_error("command exited with code " .. code, { code = code, stdout = "", stderr = "" })
          end
        end
      end)
    end,
  })

  if job_id <= 0 then
    if opts.on_error then
      opts.on_error("failed to start command", { code = job_id, stdout = "", stderr = "" })
    else
      notify("Failed to start command", vim.log.levels.ERROR)
    end
  end

  return job_id
end

function M.exec(args, opts)
  exec_async(args, opts)
end

function M.stream(args, opts)
  return exec_stream(args, opts)
end

function M.vault_list_sync()
  return vault_list_sync()
end

function M.vault_where_sync()
  return vault_where_sync()
end

function M.vault_list(on_success, on_error)
  exec_async({ "vault", "list" }, {
    vault = false,
    notify_msg = "Loading vaults...",
    on_success = function(res)
      local parsed = parse_json(res.stdout)
      if not parsed then
        if on_error then
          on_error("Failed to parse vault list", res)
        end
        return
      end
      if on_success then
        on_success(parsed, res)
      end
    end,
    on_error = on_error,
  })
end

function M.vault_where(on_success, on_error)
  exec_async({ "vault", "where" }, {
    vault = false,
    on_success = function(res)
      if on_success then
        on_success(util.trim(res.stdout), res)
      end
    end,
    on_error = on_error,
  })
end

function M.vault_open(name, on_success, on_error)
  exec_async({ "vault", "open", name }, {
    vault = false,
    notify_msg = "Switching vault...",
    on_success = on_success,
    on_error = on_error,
  })
end

function M.vault_open_sync(name)
  local obj = sync_exec({ "pkm", "vault", "open", name })
  if obj.code ~= 0 then
    return false, obj
  end

  return true, obj
end

function M.daily_add(content, on_success, on_error, opts)
  exec_async(
    { "daily", "add", "--", content },
    vim.tbl_extend("force", {
      notify_msg = "Saving daily note...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.daily_sub(title, on_success, on_error, opts)
  exec_async(
    { "daily", "add", "--sub", title },
    vim.tbl_extend("force", {
      notify_msg = "Creating daily sub-note...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.note_add(title, content, on_success, on_error, opts)
  local args = { "note", "add" }
  if title and title ~= "" then
    table.insert(args, "--")
    table.insert(args, title)
  end
  if content and content ~= "" then
    table.insert(args, "--content")
    table.insert(args, content)
  end

  exec_async(
    args,
    vim.tbl_extend("force", {
      notify_msg = "Saving note...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.search(query, on_success, on_error, opts)
  exec_async(
    { "search", "--", query },
    vim.tbl_extend("force", {
      notify_msg = "Searching...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.note_search(query, on_success, on_error, opts)
  exec_async(
    { "note", "search", "--", query },
    vim.tbl_extend("force", {
      notify_msg = "Searching notes...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.note_show(query, on_success, on_error, opts)
  exec_async(
    { "note", "show", "--", query },
    vim.tbl_extend("force", {
      notify_msg = "Loading note...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.tags_search(pattern, on_success, on_error, opts)
  exec_async(
    { "tags", "search", "--", pattern },
    vim.tbl_extend("force", {
      notify_msg = "Searching tags...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.note_links(title, on_success, on_error, opts)
  exec_async(
    { "note", "links", "--", title },
    vim.tbl_extend("force", {
      notify_msg = "Finding links...",
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.graph_neighbors(note_id, on_success, on_error, opts)
  exec_async(
    { "graph", "neighbors", "--semantic", "--format", "json", "--", note_id },
    vim.tbl_extend("force", {
      notify_msg = false,
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.ask_stream(query, handlers, opts)
  handlers = handlers or {}
  return exec_stream(
    { "ask", "--", query },
    vim.tbl_extend("force", {
      on_stdout = handlers.on_stdout,
      on_stderr = handlers.on_stderr,
      on_exit = handlers.on_exit,
      on_error = handlers.on_error,
    }, opts or {})
  )
end

function M.index(handlers, opts)
  handlers = handlers or {}
  return exec_stream(
    { "index" },
    vim.tbl_extend("force", {
      on_stdout = handlers.on_stdout,
      on_stderr = handlers.on_stderr,
      on_exit = handlers.on_exit,
      on_error = handlers.on_error,
    }, opts or {})
  )
end

function M.daemon_start(opts)
  exec_async(
    { "daemon", "start" },
    vim.tbl_extend("force", {
      notify_msg = "Starting daemon...",
    }, opts or {})
  )
end

function M.daemon_status(on_success, on_error, opts)
  exec_async(
    { "daemon", "status" },
    vim.tbl_extend("force", {
      on_success = on_success,
      on_error = on_error,
    }, opts or {})
  )
end

function M.daemon_logs(on_stdout, on_stderr, on_exit, opts)
  return exec_stream(
    { "daemon", "logs", "-f" },
    vim.tbl_extend("force", {
      on_stdout = on_stdout,
      on_stderr = on_stderr,
      on_exit = on_exit,
    }, opts or {})
  )
end

return M
