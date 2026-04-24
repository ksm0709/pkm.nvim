require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.health", function()
  local vim
  local health

  before_each(function()
    vim = stub.new({ executables = { pkm = true, rg = true } })
    _G.vim = vim
    package.loaded["snacks"] = {}
    package.loaded["pkm.health"] = nil
    health = require("pkm.health")
  end)

  it("reports dependency status without error", function()
    health.check()
    assert.are.equal("start", vim._state.health[1].kind)
    assert.are.equal("ok", vim._state.health[2].kind)
    assert.are.equal("ok", vim._state.health[3].kind)
  end)

  it("reports warnings when dependencies are missing", function()
    vim = stub.new({ executables = {} })
    _G.vim = vim
    package.loaded["snacks"] = nil
    package.loaded["pkm.health"] = nil
    health = require("pkm.health")

    health.check()
    assert.are.equal("error", vim._state.health[2].kind)
    assert.are.equal("warn", vim._state.health[3].kind)
    assert.are.equal("warn", vim._state.health[4].kind)
  end)
end)
