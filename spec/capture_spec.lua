require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.capture", function()
  local vim
  local state
  local capture

  before_each(function()
    vim, state = stub.new()
    _G.vim = vim
    package.loaded["pkm.capture"] = nil
    package.loaded["pkm.cli"] = {
      daily_add = function(content, on_success, on_error)
        state.daily_content = content
        state.daily_on_success = on_success
        state.daily_on_error = on_error
      end,
      note_add = function(title, content, on_success, on_error)
        state.note_title = title
        state.note_content = content
        state.note_on_success = on_success
        state.note_on_error = on_error
      end,
    }
    capture = require("pkm.capture")
  end)

  local function trigger_write()
    local autocmd = state.autocmds[#state.autocmds]
    autocmd.opts.callback()
  end

  it("captures and saves a daily note", function()
    capture.daily({ "alpha", "beta" })
    trigger_write()
    assert.are.equal("alpha\nbeta", state.daily_content)
    assert.are.equal(" PKM: Daily Note ", state.windows[state.current_win].config.title)
  end)

  it("captures and saves a note", function()
    capture.note({ "body" })
    trigger_write()
    assert.are.equal("body", state.note_content)
  end)

  it("skips empty writes", function()
    capture.daily({})
    trigger_write()
    assert.are.equal(nil, state.daily_content)
    assert.are.equal("Empty content, not saving.", state.notifications[1].message)
  end)

  it("skips empty note writes", function()
    capture.note({})
    trigger_write()
    assert.are.equal(nil, state.note_content)
    assert.are.equal("Empty content, not saving.", state.notifications[1].message)
  end)
end)
