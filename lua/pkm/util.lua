local M = {}

function M.join_path(...)
  local parts = { ... }
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(unpack(parts))
  end

  local path = table.concat(parts, "/")
  path = path:gsub("/+", "/")
  return path
end

function M.trim(value)
  return vim.trim(value or "")
end

function M.json_decode(value)
  if not value or value == "" then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, value)
  if ok then
    return decoded
  end

  return nil
end

function M.read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return nil
  end

  return table.concat(lines, "\n")
end

function M.read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    return {}
  end

  return lines
end

function M.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

function M.dir_exists(path)
  return vim.fn.isdirectory(path) == 1
end

function M.ensure_dir(path)
  if not M.dir_exists(path) then
    vim.fn.mkdir(path, "p")
  end
end

function M.basename(path)
  return vim.fn.fnamemodify(path, ":t")
end

function M.basename_without_ext(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

function M.slugify(value)
  value = (value or ""):lower()
  value = value:gsub("[^%w%s%-_]", "")
  value = value:gsub("[%s_]+", "-")
  value = value:gsub("%-+", "-")
  value = value:gsub("^%-+", "")
  value = value:gsub("%-+$", "")
  return value
end

function M.normalize_output(value)
  value = value or ""
  value = value:gsub("\27%[[%d;]*[A-Za-z]", "")
  value = value:gsub("\r\n", "\n")
  value = value:gsub("\r", "\n")
  return value
end

function M.split_lines(value)
  value = M.normalize_output(value)
  local lines = {}
  for line in (value .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  return lines
end

function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "PKM" })
end

return M
