local lfs = require("lfs")

local root = lfs.currentdir()

package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  root .. "/lua/?.lua",
  root .. "/lua/?/init.lua",
  root .. "/spec/?.lua",
  root .. "/spec/?/init.lua",
  package.path,
}, ";")

package.cpath = table.concat({
  root .. "/.rocks/lib/lua/5.1/?.so",
  root .. "/.rocks/lib/lua/5.1/?.dylib",
  package.cpath,
}, ";")
