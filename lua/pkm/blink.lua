local M = {}

function M.new()
  local self = setmetatable({}, { __index = M })
  return self
end

function M:get_trigger_characters()
  return { "[" }
end

function M:get_completions(context, callback)
  local line = context.line
  local col = context.cursor[2]
  local before_cursor = line:sub(1, col)

  if not before_cursor:match("%[%[.*$") then
    callback()
    return
  end

  local items = {}
  
  callback({
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = items,
  })
end

return M
