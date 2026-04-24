require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("plugin/pkm.lua", function()
  local vim
  local state

  before_each(function()
    vim, state = stub.new()
    _G.vim = vim
    package.loaded["pkm.capture"] = {
      daily = function()
        state.capture_daily = true
      end,
      note = function()
        state.capture_note = true
      end,
    }
    package.loaded["pkm.chat"] = {
      toggle = function()
        state.chat_toggled = true
      end,
    }
    package.loaded["pkm.picker"] = {
      daily_open = function()
        state.daily_open = true
      end,
      daily_sub = function()
        state.daily_sub = true
      end,
      vaults = function()
        state.vaults = true
      end,
      search = function()
        state.search = true
      end,
      tags = function()
        state.tags = true
      end,
      links = function()
        state.links = true
      end,
      grep = function()
        state.grep = true
      end,
      files = function()
        state.files = true
      end,
      index = function()
        state.index = true
      end,
      workflows = function()
        state.workflows = true
      end,
      chat_toggle = function()
        state.chat_toggle = true
      end,
    }
    package.loaded["pkm"] = {
      config = {},
    }
    package.loaded["pkm.health"] = nil
    package.loaded["pkm.cli"] = nil
    package.loaded["pkm.util"] = nil
    package.loaded["pkm.vault"] = nil
    package.loaded["pkm.blink"] = nil
    package.loaded["pkm.capture"] = package.loaded["pkm.capture"]
    package.loaded["pkm.chat"] = package.loaded["pkm.chat"]
    package.loaded["pkm.picker"] = package.loaded["pkm.picker"]
    package.loaded["plugin.pkm"] = nil
    dofile("plugin/pkm.lua")
  end)

  it("registers user commands and keymaps", function()
    assert.is_not_nil(state.user_commands.Pkm)
    assert.is_true(#state.keymaps >= 10)
    assert.is_not_nil(state.keymaps[1].opts.desc)
    assert.is_true(vim.startswith(state.keymaps[1].lhs, "<Leader>p"))
  end)

  it("dispatches :Pkm subcommands and completion", function()
    local command = state.user_commands.Pkm.callback
    command({ fargs = { "daily" } })
    command({ fargs = { "note" } })
    command({ fargs = { "daily-open" } })
    command({ fargs = { "daily-sub" } })
    command({ fargs = { "vault" } })
    command({ fargs = { "search", "alpha" } })
    command({ fargs = { "tags", "topic" } })
    command({ fargs = { "links", "note" } })
    command({ fargs = { "grep", "needle" } })
    command({ fargs = { "files" } })
    command({ fargs = { "index" } })
    command({ fargs = { "workflows" } })
    command({ fargs = { "chat" } })

    assert.is_true(state.capture_daily)
    assert.is_true(state.capture_note)
    assert.is_true(state.daily_open)
    assert.is_true(state.daily_sub)
    assert.is_true(state.vaults)
    assert.is_true(state.search)
    assert.is_true(state.tags)
    assert.is_true(state.links)
    assert.is_true(state.grep)
    assert.is_true(state.files)
    assert.is_true(state.index)
    assert.is_true(state.workflows)
    assert.is_true(state.chat_toggle)

    local completions = state.user_commands.Pkm.opts.complete(nil, "Pkm d")
    assert.is_true(vim.startswith(completions[1], "daily"))
  end)
end)
