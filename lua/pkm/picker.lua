local M = {}

local cli = require("pkm.cli")

local function get_vault_dir()
  local pkm = require("pkm")
  if pkm.config.vault_dir then
    return pkm.config.vault_dir
  end
  local obj = vim.system({ "pkm", "vault", "where" }, { text = true }):wait()
  if obj.code == 0 then
    return vim.trim(obj.stdout)
  end
  return nil
end

local function resolve_path(vault_dir, filename)
  if not vault_dir then
    return filename
  end
  if filename:sub(1, 1) == "/" then
    return filename
  end

  local notes_path = vault_dir .. "/notes/" .. filename
  local daily_path = vault_dir .. "/daily/" .. filename

  if vim.fn.filereadable(notes_path) == 1 then
    return notes_path
  elseif vim.fn.filereadable(daily_path) == 1 then
    return daily_path
  end

  return filename
end

local function open_picker(title, items)
  local snacks_ok, snacks = pcall(require, "snacks")
  if not snacks_ok then
    vim.notify("Snacks.nvim is required for pickers", vim.log.levels.ERROR)
    return
  end

  snacks.picker({
    title = title,
    items = items,
    format = function(item, picker)
      local ret = {}
      table.insert(ret, { item.text, "Normal" })
      if item.desc and item.desc ~= "" then
        table.insert(ret, { " " .. item.desc, "Comment" })
      end
      return ret
    end,
    actions = {
      confirm = function(picker, item)
        picker:close()
        if item and item.file then
          vim.cmd("e " .. vim.fn.fnameescape(item.file))
        end
      end,
    },
  })
end

function M.search(query)
  if not query or query == "" then
    vim.ui.input({ prompt = "PKM Search: " }, function(input)
      if input and input ~= "" then
        M.search(input)
      end
    end)
    return
  end

  cli.search(query, function(res)
    local ok, parsed = pcall(vim.json.decode, res.stdout)
    if not ok or not parsed.results then
      vim.notify("Failed to parse search results", vim.log.levels.ERROR)
      return
    end

    local items = {}
    for _, result in ipairs(parsed.results) do
      local file_path = nil
      if result.graph_context and result.graph_context.nodes then
        for _, node in ipairs(result.graph_context.nodes) do
          if node.id == result.note_id and node.path then
            file_path = node.path
            break
          end
        end
      end

      if not file_path then
        file_path = result.title .. ".md"
      end

      local desc = result.description or ""
      desc = desc:gsub("\n", " ")

      table.insert(items, {
        text = result.title,
        desc = desc,
        file = file_path,
      })
    end

    open_picker("PKM Search: " .. query, items)
  end)
end

function M.tags(pattern)
  if not pattern or pattern == "" then
    vim.ui.input({ prompt = "PKM Tags Search: " }, function(input)
      if input and input ~= "" then
        M.tags(input)
      end
    end)
    return
  end

  cli.tags_search(pattern, function(res)
    local ok, parsed = pcall(vim.json.decode, res.stdout)
    if not ok or not parsed.results then
      vim.notify("Failed to parse tags search results", vim.log.levels.ERROR)
      return
    end

    local vault_dir = get_vault_dir()
    local items = {}
    for _, result in ipairs(parsed.results) do
      local file_path = resolve_path(vault_dir, result.path or (result.title .. ".md"))
      local tags_str = table.concat(result.tags or {}, ", ")

      table.insert(items, {
        text = result.title,
        desc = "[" .. tags_str .. "]",
        file = file_path,
      })
    end

    open_picker("PKM Tags: " .. pattern, items)
  end)
end

function M.links(title)
  if not title or title == "" then
    local buf_name = vim.api.nvim_buf_get_name(0)
    if buf_name ~= "" then
      title = vim.fn.fnamemodify(buf_name, ":t:r")
    else
      vim.ui.input({ prompt = "PKM Links for Note: " }, function(input)
        if input and input ~= "" then
          M.links(input)
        end
      end)
      return
    end
  end

  cli.note_links(title, function(res)
    local ok, parsed = pcall(vim.json.decode, res.stdout)
    if not ok or not parsed.backlinks then
      vim.notify("Failed to parse note links results", vim.log.levels.ERROR)
      return
    end

    local vault_dir = get_vault_dir()
    local items = {}
    for _, result in ipairs(parsed.backlinks) do
      local file_path = resolve_path(vault_dir, result.path or (result.title .. ".md"))
      local desc = result.description or ""
      desc = desc:gsub("\n", " ")

      table.insert(items, {
        text = result.title,
        desc = desc,
        file = file_path,
      })
    end

    open_picker("PKM Links: " .. title, items)
  end)
end

return M
