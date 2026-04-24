require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.init", function()
  local vim
  local pkm

  before_each(function()
    vim = stub.new()
    _G.vim = vim
    package.loaded["pkm"] = nil
    pkm = require("pkm")
  end)

  it("merges setup options into the default config", function()
    pkm.setup({ vault = "TEMP_VAULT_B", auto_index = false })
    assert.are.equal("TEMP_VAULT_B", pkm.config.vault)
    assert.is_false(pkm.config.auto_index)
    assert.is_nil(pkm.config.vault_dir)
  end)

  it("lazy-loads child modules through __index", function()
    package.loaded["pkm.util"] = { loaded = true }
    assert.is_true(pkm.util.loaded)
    assert.are.equal(package.loaded["pkm.util"], pkm.util)
  end)
end)
