require("spec_helper")
local lfs = require("lfs")
local root = lfs.currentdir()

describe("pkm.nvim E2E Example", function()
  it("launches Neovim headlessly, loads pkm.nvim, runs a command, and asserts output", function()
    -- Construct the command to launch Neovim headlessly
    -- - --headless: Run in headless mode
    -- - --noplugin: Disable plugins (optional, but good for isolation)
    -- - -u NONE: Do not load init.lua/init.vim
    -- - -c 'set rtp+=...': Add the plugin to runtimepath
    -- - -c 'runtime plugin/pkm.lua': Load the plugin
    -- - -c 'lua ...': Run the command
    -- - -c 'q': Quit Neovim
    local cmd = "nvim --headless --noplugin -u NONE -c 'set rtp+="
      .. root
      .. "' -c 'runtime plugin/pkm.lua' -c 'lua print(\"hello\")' -c 'q'"

    -- Execute the command and capture output
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    handle:close()

    -- Assert the output
    assert.is_string(result)
    assert.is_true(result:find("hello", 1, true) ~= nil)
  end)
end)
