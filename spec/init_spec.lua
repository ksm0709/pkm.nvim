require("spec_helper")

local stub = require("spec.support.vim_stub")
local json = require("dkjson")

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

  describe("statusline", function()
    local state

    before_each(function()
      vim, state = stub.new()
      _G.vim = vim
      package.loaded["pkm"] = nil
      package.loaded["pkm.cli"] = nil
      package.loaded["pkm.vault"] = nil
      package.loaded["pkm.util"] = nil
      pkm = require("pkm")
    end)

    it("returns empty string and triggers async fetch on cold start", function()
      state.system_handler = function(cmd)
        if table.concat(cmd, " ") == "pkm vault list" then
          return {
            code = 0,
            stdout = json.encode({
              vaults = { { name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a", active = true } },
            }),
            stderr = "",
          }
        end
        return { code = 0, stdout = "", stderr = "" }
      end

      require("pkm.vault").current = nil
      pkm.statusline()
      -- stub calls callback synchronously, so vault.current should be set after the call
      assert.are.equal("TEMP_VAULT_A", require("pkm.vault").current and require("pkm.vault").current.name)
    end)

    it("returns vault name immediately when vault is cached", function()
      require("pkm.vault").current = { name = "TEMP_VAULT_B", path = "/tmp/pkm-test-vaults/temp-vault-b" }
      local result = pkm.statusline()
      assert.are.equal("󰠮 TEMP_VAULT_B", result)
    end)

    it("does not trigger multiple fetches within cooldown window", function()
      state.time = 10000
      require("pkm.vault").current = nil
      local call_count = 0
      state.system_handler = function(cmd)
        if table.concat(cmd, " ") == "pkm vault list" then
          call_count = call_count + 1
          return {
            code = 0,
            stdout = json.encode({
              vaults = { { name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a", active = true } },
            }),
            stderr = "",
          }
        end
        return { code = 0, stdout = "", stderr = "" }
      end

      -- First call triggers fetch; stub is sync so vault.current gets set immediately
      pkm.statusline()
      -- vault.current is now set, so second call returns name without fetching again
      state.time = 11000 -- only 1 second later, within cooldown
      pkm.statusline()
      -- Only 1 vault list call total
      assert.are.equal(1, call_count)
    end)

    it("updates vault.current with proper name from vault list, not path basename", function()
      state.system_handler = function(cmd)
        if table.concat(cmd, " ") == "pkm vault list" then
          return {
            code = 0,
            stdout = json.encode({
              vaults = {
                { name = "my-proper-name", path = "/tmp/pkm-test-vaults/different-dirname", active = true },
              },
            }),
            stderr = "",
          }
        end
        return { code = 0, stdout = "", stderr = "" }
      end

      require("pkm.vault").current = nil
      pkm.statusline()
      -- Should use "my-proper-name" from vault list, NOT "different-dirname" from path basename
      local current = require("pkm.vault").current
      assert.are.equal("my-proper-name", current and current.name)
    end)

    it("handles fetch failure gracefully", function()
      state.system_handler = function(_)
        return { code = 1, stdout = "", stderr = "error" }
      end

      require("pkm.vault").current = nil
      local result = pkm.statusline()
      assert.are.equal("", result)
      -- vault.current should still be nil
      assert.is_nil(require("pkm.vault").current)
    end)
  end)
end)
