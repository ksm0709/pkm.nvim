require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.blink", function()
  local vim
  local blink

  before_each(function()
    vim = stub.new()
    _G.vim = vim
    package.loaded["pkm.blink"] = nil
    blink = require("pkm.blink")
  end)

  it("returns a source object and empty completions", function()
    local source = blink.new()
    assert.is_table(source)
    assert.are.same({ "[" }, source:get_trigger_characters())

    local called = false
    source:get_completions({ line = "[[hello", cursor = { 1, 6 } }, function(result)
      called = true
      assert.is_table(result)
      assert.are.same({}, result.items)
    end)
    assert.is_true(called)
  end)

  it("skips completions when the trigger is absent", function()
    local source = blink.new()
    local called = false
    source:get_completions({ line = "plain text", cursor = { 1, 5 } }, function(result)
      called = true
      assert.is_nil(result)
    end)
    assert.is_true(called)
  end)
end)
