local M = {}

local chat = require("pkm.chat")
local cli = require("pkm.cli")
local util = require("pkm.util")
local vault = require("pkm.vault")

local workflow_roots = {
  vim.fn.expand("~/.claude/skills/pkm/workflows"),
}

local function snacks_picker(title, items, actions, format)
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    util.notify("Snacks.nvim is required for pickers", vim.log.levels.ERROR)
    return
  end

  snacks.picker({
    title = title,
    items = items,
    format = format or function(item)
      local text = { { item.text or "", "Normal" } }
      if item.desc and item.desc ~= "" then
        table.insert(text, { " " .. item.desc, "Comment" })
      end
      return text
    end,
    actions = actions or {
      confirm = function(picker, item)
        picker:close()
        if item and item.file then
          if item.line then
            vim.cmd("edit " .. vim.fn.fnameescape(item.file))
            vim.api.nvim_win_set_cursor(0, { item.line, math.max((item.col or 1) - 1, 0) })
          else
            vim.cmd("edit " .. vim.fn.fnameescape(item.file))
          end
        end
      end,
    },
  })
end

local function prompt(title, cb)
  vim.ui.input({ prompt = title .. ": " }, function(input)
    if input and input ~= "" then
      cb(input)
    end
  end)
end

local function open_path(path, line, col)
  if not path or path == "" then
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))
  if line and line > 0 then
    vim.api.nvim_win_set_cursor(0, { line, math.max((col or 1) - 1, 0) })
  end
end

local function current_vault()
  return vault.get()
end

local function vault_from_path(path)
  if not path or path == "" then
    return nil
  end
  local vaults = vault.list()
  for _, v in ipairs(vaults) do
    if v.path and path:sub(1, #v.path) == v.path then
      return v
    end
  end
  return nil
end

local function ensure_vault_path()
  local current = current_vault()
  if current and current.path then
    return current.path
  end

  local where = cli.vault_where_sync()
  if where and where ~= "" then
    local resolved = vault.refresh()
    if resolved and resolved.path then
      return resolved.path
    end
    return where
  end

  return nil
end

local function note_path_from_result(result)
  if result.graph_context and result.graph_context.nodes then
    for _, node in ipairs(result.graph_context.nodes) do
      if node.type == "note" and node.path then
        return node.path
      end
    end
  end

  local current = current_vault()
  if current and current.path and result.title then
    local daily_candidate = util.join_path(current.path, "daily", result.title .. ".md")
    if util.file_exists(daily_candidate) then
      return daily_candidate
    end

    local note_candidate = util.join_path(current.path, "notes", util.slugify(result.title) .. ".md")
    if util.file_exists(note_candidate) then
      return note_candidate
    end
    return note_candidate
  end

  return result.path
end

local function build_result_items(results)
  local items = {}
  for _, result in ipairs(results or {}) do
    local tags = result.tags or {}
    if tags == vim.NIL then
      tags = {}
    end
    local tag_text = #tags > 0 and ("[" .. table.concat(tags, ", ") .. "]") or ""
    local desc = result.description
    if desc == vim.NIL then
      desc = ""
    end
    desc = util.normalize_output(desc or ""):gsub("\n", " ")
    local meta = {}
    if result.score then
      table.insert(meta, string.format("score=%.3f", result.score))
    end
    if tag_text ~= "" then
      table.insert(meta, tag_text)
    end
    if desc ~= "" then
      table.insert(meta, desc)
    end
    table.insert(items, {
      text = result.title or result.note_id or "(untitled)",
      desc = table.concat(meta, "  "),
      file = note_path_from_result(result),
    })
  end
  return items
end

function M.search(query)
  local snacks = require("snacks")
  local current = current_vault()
  local vault_name = current and current.name or nil
  snacks.picker({
    title = "PKM Search",
    search = query,
    supports_live = true,
    live = true,
    finder = function(opts, ctx)
      local filter = (ctx and ctx.filter) or (opts and opts.filter) or {}
      local pattern = filter.search
        or filter.pattern
        or (type(opts) == "table" and opts.search)
        or (type(opts) == "table" and opts.pattern)
        or ""
      if type(pattern) ~= "string" then
        pattern = ""
      end
      return function(cb)
        if pattern == "" then
          return
        end

        local async = require("snacks.picker.util.async").running()
        local results = nil

        cli.search(pattern, function(res)
          results = res
          if async then
            async:resume()
          end
        end, function(err)
          results = { error = true }
          if async then
            async:resume()
          end
        end, { notify_msg = false, vault = vault_name })

        if async then
          async:suspend()
        end

        if results and not results.error then
          local parsed = util.json_decode(results.stdout)
          if parsed and parsed.results then
            for _, item in ipairs(build_result_items(parsed.results)) do
              cb(item)
            end
          end
        end
      end
    end,
    format = function(item)
      local text = { { item.text or "", "Normal" } }
      if item.desc and item.desc ~= "" then
        table.insert(text, { " " .. item.desc, "Comment" })
      end
      return text
    end,
    actions = {
      confirm = function(picker, item)
        picker:close()
        if item and item.file then
          open_path(item.file)
        end
      end,
    },
  })
end

function M.tags()
  local snacks = require("snacks")
  local current = current_vault()
  local vault_name = current and current.name or nil
  snacks.picker({
    title = "PKM Tags",
    supports_live = true,
    live = true,
    finder = function(opts, ctx)
      local filter = (ctx and ctx.filter) or (opts and opts.filter) or {}
      local pattern = filter.search
        or filter.pattern
        or (type(opts) == "table" and opts.search)
        or (type(opts) == "table" and opts.pattern)
        or ""
      if type(pattern) ~= "string" then
        pattern = ""
      end
      return function(cb)
        if pattern == "" then
          return
        end

        local async = require("snacks.picker.util.async").running()
        local results = nil

        cli.tags_search(pattern, function(res)
          results = res
          if async then
            async:resume()
          end
        end, function(err)
          results = { error = true }
          if async then
            async:resume()
          end
        end, { notify_msg = false, vault = vault_name })

        if async then
          async:suspend()
        end

        if results and not results.error then
          local parsed = util.json_decode(results.stdout)
          if parsed and parsed.results then
            for _, result in ipairs(parsed.results) do
              local tags_str = table.concat(result.tags or {}, ", ")
              cb({
                text = result.title or result.note_id or "(untitled)",
                desc = "[" .. tags_str .. "]",
                file = note_path_from_result(result),
              })
            end
          end
        end
      end
    end,
    actions = {
      confirm = function(picker, item)
        picker:close()
        if item and item.file then
          open_path(item.file)
        end
      end,
    },
  })
end

function M.links(title)
  local snacks = require("snacks")
  local buf_name = vim.api.nvim_buf_get_name(0)
  local current = vault_from_path(buf_name) or current_vault()
  local vault_name = current and current.name or nil
  local v_path = (current and current.path) or ensure_vault_path()

  local target_note = title
  if not target_note or target_note == "" then
    if buf_name ~= "" then
      target_note = vim.fn.fnamemodify(buf_name, ":t:r")
    else
      util.notify("No active note to get links for", vim.log.levels.ERROR)
      return
    end
  end

  local graph_res = nil
  local grep_res = nil
  local pending = 2

  local function node_file_path(name, node_type)
    if node_type == "tag" then
      return util.join_path(v_path, "tags", name .. ".md")
    end
    local daily = util.join_path(v_path, "daily", name .. ".md")
    if util.file_exists(daily) then
      return daily
    end
    return util.join_path(v_path, "notes", util.slugify(name) .. ".md")
  end

  local function open_item(item)
    if item.node_type == "tag" then
      local path = util.join_path(v_path, "tags", item.text .. ".md")
      if not util.file_exists(path) then
        vim.schedule(function()
          vim.system(
            { "pkm", "tags", "edit", item.text },
            { text = true, env = vim.tbl_extend("force", vim.fn.environ(), { EDITOR = "true" }) }
          ):wait()
          open_path(path)
        end)
      else
        open_path(path)
      end
    elseif item.file and item.file ~= "" and util.file_exists(item.file) then
      open_path(item.file)
    else
      local daily = util.join_path(v_path, "daily", item.text .. ".md")
      if util.file_exists(daily) then
        open_path(daily)
      else
        open_path(util.join_path(v_path, "notes", util.slugify(item.text) .. ".md"))
      end
    end
  end

  local function launch_picker()
    local items = {}
    local graph_inbound_ids = {}

    local parsed = graph_res and util.json_decode(graph_res.stdout)
    if parsed then
      for _, node in ipairs(parsed.inbound or {}) do
        local name = (node.title or node.note_id):gsub("^tag:", "")
        graph_inbound_ids[node.note_id] = true
        table.insert(items, {
          text = name,
          desc = "[inbound] " .. node.type,
          node_type = node.type,
          node_id = node.note_id,
          direction = "inbound",
          file = node_file_path(name, node.type),
        })
      end
      for _, node in ipairs(parsed.outbound or {}) do
        local name = (node.title or node.note_id):gsub("^tag:", "")
        table.insert(items, {
          text = name,
          desc = "[outbound] " .. node.type,
          node_type = node.type,
          node_id = node.note_id,
          direction = "outbound",
          file = node_file_path(name, node.type),
        })
      end
      for _, node in ipairs(parsed.semantic or {}) do
        local name = (node.title or node.note_id):gsub("^tag:", "")
        table.insert(items, {
          text = name,
          desc = "[semantic] " .. node.type,
          node_type = node.type,
          node_id = node.note_id,
          direction = "semantic",
          file = node_file_path(name, node.type),
        })
      end
    end

    -- Wikilink-based inbound: fill in what graph hasn't indexed yet
    if grep_res and grep_res.stdout and grep_res.stdout ~= "" then
      for _, filepath in ipairs(vim.split(vim.trim(grep_res.stdout), "\n")) do
        if filepath ~= "" then
          local stem = vim.fn.fnamemodify(filepath, ":t:r")
          if stem ~= target_note and not graph_inbound_ids[stem] then
            table.insert(items, {
              text = stem,
              desc = "[inbound] wikilink",
              node_type = "note",
              node_id = stem,
              direction = "inbound",
              file = filepath,
            })
          end
        end
      end
    end

    snacks.picker({
      title = "PKM Links: " .. target_note,
      items = items,
      format = function(item)
        return { { item.text, "Normal" }, { " " .. item.desc, "Comment" } }
      end,
      actions = {
        confirm = function(picker, item)
          picker:close()
          if item then
            open_item(item)
          end
        end,
      },
    })
  end

  local function on_done()
    pending = pending - 1
    if pending == 0 then
      launch_picker()
    end
  end

  cli.graph_neighbors(target_note, function(res)
    graph_res = res
    on_done()
  end, function(_)
    graph_res = nil
    on_done()
  end, { notify_msg = false, vault = vault_name })

  if v_path and v_path ~= "" then
    cli.grep_backlinks(target_note, v_path, function(res)
      grep_res = res
      on_done()
    end, function(_)
      grep_res = nil
      on_done()
    end)
  else
    on_done()
  end
end

function M.vaults()
  local items = {}
  for _, item in ipairs(vault.list()) do
    local prefix = item.active and "● " or "  "
    table.insert(items, {
      text = prefix .. item.name,
      desc = item.path,
      vault = item,
    })
  end

  snacks_picker("PKM Vaults", items, {
    confirm = function(picker, item)
      picker:close()
      if not item or not item.vault then
        return
      end

      local ok, result = vault.switch(item.vault.name)
      if not ok then
        util.notify("Failed to switch vault: " .. tostring(result), vim.log.levels.ERROR)
        return
      end

      local target = vault.get()
      if target and target.path then
        vim.cmd("cd " .. vim.fn.fnameescape(target.path))
      end
      vault.open_daily(target)
    end,
  })
end

function M.files()
  local vault_path = ensure_vault_path()
  if not vault_path then
    util.notify("No active vault found", vim.log.levels.ERROR)
    return
  end

  local obj = vim.system({ "rg", "--files", vault_path }, { text = true }):wait()
  if obj.code ~= 0 then
    util.notify("Failed to list files in vault", vim.log.levels.ERROR)
    return
  end

  local items = {}
  for _, file in ipairs(vim.split(util.trim(obj.stdout), "\n", { plain = true, trimempty = true })) do
    if file ~= "" then
      table.insert(items, {
        text = vim.fn.fnamemodify(file, ":t"),
        desc = vim.fn.fnamemodify(file, ":."),
        file = file,
      })
    end
  end

  snacks_picker("PKM Files", items, {
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        open_path(item.file)
      end
    end,
  })
end

function M.grep(query)
  local vault_path = ensure_vault_path()
  if not vault_path then
    util.notify("No active vault found", vim.log.levels.ERROR)
    return
  end
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    util.notify("Snacks.nvim is required for pickers", vim.log.levels.ERROR)
    return
  end
  snacks.picker.grep({
    dirs = { vault_path },
    search = query or "",
  })
end

function M.daily_open()
  vault.open_daily(vault.get())
end

function M.daily_sub()
  prompt("Daily sub-note title", function(title)
    local current = vault.get()
    local target_path = vault.sub_daily_path(current, title)

    cli.daily_sub(title, function()
      if target_path then
        open_path(target_path)
      end
    end, function(stderr)
      util.notify("Failed to create daily sub-note:\n" .. stderr, vim.log.levels.ERROR)
    end, {
      vault = current and current.name or nil,
    })
  end)
end

function M.index()
  util.notify("Refreshing index...", vim.log.levels.INFO)
  cli.index({
    on_exit = function(code)
      if code == 0 then
        util.notify("Index refreshed", vim.log.levels.INFO)
      else
        util.notify("Index refresh failed", vim.log.levels.ERROR)
      end
    end,
  }, {
    vault = current_vault() and current_vault().name or nil,
  })
end

local function workflow_files()
  local files = {}
  local seen = {}
  for _, root in ipairs(workflow_roots) do
    if util.dir_exists(root) then
      local obj = vim.system({ "rg", "--files", root }, { text = true }):wait()
      if obj.code == 0 then
        for _, file in ipairs(vim.split(util.trim(obj.stdout), "\n", { plain = true, trimempty = true })) do
          local name = util.basename(file)
          if file:sub(-3) == ".md" and name ~= "AGENTS.md" and not seen[file] then
            seen[file] = true
            table.insert(files, file)
          end
        end
      end
    end
  end
  return files
end

local function workflow_prompt(file)
  return util.read_file(file) or ""
end

local function workflow_summary(file)
  local lines = util.read_lines(file)
  if #lines == 0 then
    return ""
  end

  if lines[1] == "---" then
    for index = 2, #lines do
      local line = lines[index]
      if line == "---" then
        break
      end
      local value = line:match("^description:%s*(.+)$")
      if value and value ~= "" then
        return value
      end
    end
  end

  for _, line in ipairs(lines) do
    local trimmed = util.trim(line)
    if trimmed ~= "" and trimmed ~= "---" and not trimmed:match("^#") then
      return trimmed
    end
  end

  for _, line in ipairs(lines) do
    local trimmed = util.trim(line)
    if trimmed:match("^#") then
      return trimmed:gsub("^#+%s*", "")
    end
  end

  return util.trim(lines[1])
end

local function configured_workflows()
  local pkm = require("pkm")
  local config = pkm.config or {}
  local result = {}

  for _, workflow in ipairs(config.workflows or {}) do
    if type(workflow) == "table" then
      local workflow_text = workflow.prompt or ""
      if workflow_text == "" and workflow.file then
        workflow_text = util.read_file(workflow.file) or ""
      end

      table.insert(result, {
        text = workflow.name or workflow.title or workflow.label or util.basename_without_ext(
          workflow.file or "workflow"
        ),
        desc = workflow.description or workflow.summary or "",
        file = workflow.file,
        prompt = workflow_text,
      })
    end
  end

  return result
end

function M.workflows()
  local items = {}
  for _, item in ipairs(configured_workflows()) do
    table.insert(items, item)
  end
  for _, file in ipairs(workflow_files()) do
    local name = util.basename_without_ext(file)
    local workflow_text = workflow_prompt(file)
    table.insert(items, {
      text = name,
      desc = workflow_summary(file),
      file = file,
      prompt = workflow_text,
    })
  end

  if #items == 0 then
    util.notify("No workflows found", vim.log.levels.WARN)
    return
  end

  snacks_picker("PKM Workflows", items, {
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      local workflow_text = item.prompt or workflow_prompt(item.file)
      if workflow_text == "" then
        util.notify("Workflow prompt is empty", vim.log.levels.ERROR)
        return
      end
      chat.stream_workflow(item.text, workflow_text)
    end,
  })
end

function M.daemon_workflows()
  local obj = vim.system({ "pkm", "workflow", "list" }, { text = true }):wait()
  if obj.code ~= 0 then
    util.notify("Failed to list workflows: " .. (obj.stderr or ""), vim.log.levels.ERROR)
    return
  end

  local parsed = util.json_decode(obj.stdout)
  if not parsed or #parsed == 0 then
    util.notify("No daemon workflows found", vim.log.levels.WARN)
    return
  end

  local items = {}
  for _, wf in ipairs(parsed) do
    table.insert(items, {
      text = wf.id,
      desc = wf.schedule_hour and ("hour: " .. wf.schedule_hour) or "",
      id = wf.id,
    })
  end

  snacks_picker("PKM Daemon Workflows", items, {
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end
      chat.stream_cmd("workflow: " .. item.id, { "workflow", "run", item.id })
    end,
  })
end

function M.chat_toggle()
  chat.toggle()
end

return M
