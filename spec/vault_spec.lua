require("spec_helper")

local json = require("dkjson")
local stub = require("spec.support.vim_stub")

describe("pkm.vault", function()
  local vim
  local state
  local vault
  local pkm

  before_each(function()
    vim, state = stub.new()
    _G.vim = vim
    package.loaded["pkm.util"] = nil
    package.loaded["pkm.cli"] = nil
    package.loaded["pkm.vault"] = nil
    package.loaded["pkm"] = nil
    pkm = require("pkm")
    vault = require("pkm.vault")
  end)

  it("resolves and caches the active vault", function()
    pkm.setup({ vault = "TEMP_VAULT_A" })
    state.system_handler = function(cmd)
      if table.concat(cmd, " ") == "pkm vault list" then
        return {
          code = 0,
          stdout = json.encode({
            vaults = {
              {
                name = "TEMP_VAULT_A",
                path = "/tmp/pkm-test-vaults/temp-vault-a",
                active = true,
              },
            },
            active = "TEMP_VAULT_A",
          }),
          stderr = "",
        }
      end
      if table.concat(cmd, " ") == "pkm vault where" then
        return { code = 0, stdout = "/tmp/pkm-test-vaults/temp-vault-a\n", stderr = "" }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    local current = vault.get()
    assert.are.equal("TEMP_VAULT_A", current.name)
    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-a", current.path)
    assert.are.equal(current, vault.get())
  end)

  it("switches vaults and falls back on path hints", function()
    pkm.setup({ vault_dir = "/tmp/pkm-test-vaults/temp-vault-a" })
    state.system_handler = function(cmd)
      local joined = table.concat(cmd, " ")
      if joined == "pkm vault list" then
        return {
          code = 0,
          stdout = json.encode({
            vaults = {
              {
                name = "TEMP_VAULT_A",
                path = "/tmp/pkm-test-vaults/temp-vault-a",
                active = false,
              },
            },
          }),
          stderr = "",
        }
      end
      if joined == "pkm vault open TEMP_VAULT_A" then
        return { code = 0, stdout = "", stderr = "" }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    local ok, target = vault.switch("/tmp/pkm-test-vaults/temp-vault-a")
    assert.is_true(ok)
    assert.are.equal("TEMP_VAULT_A", target.name)
    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-a", state.cwd)
    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-a", target.path)
    -- _switching must be false after switch completes
    assert.is_false(vault._switching)
  end)

  it("sets _switching=true during cd to suppress DirChanged invalidation", function()
    state.system_handler = function(cmd)
      local joined = table.concat(cmd, " ")
      if joined == "pkm vault list" then
        return {
          code = 0,
          stdout = json.encode({
            vaults = { { name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a", active = false } },
          }),
          stderr = "",
        }
      end
      if joined == "pkm vault open TEMP_VAULT_A" then
        return { code = 0, stdout = "", stderr = "" }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    local switching_during_cd = nil
    -- Override vim.cmd to capture _switching state at the moment of cd
    local orig_cmd = vim.cmd
    vim.cmd = function(c)
      if type(c) == "string" and c:match("^cd ") then
        switching_during_cd = vault._switching
      end
      return orig_cmd(c)
    end

    vault.switch("/tmp/pkm-test-vaults/temp-vault-a")

    vim.cmd = orig_cmd
    assert.is_true(switching_during_cd)
    assert.is_false(vault._switching)
  end)

  it("builds note paths and opens daily/sub notes", function()
    local today = os.date("%Y-%m-%d")
    local today_escaped = today:gsub("%-", "%%-")
    local current = { name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a" }
    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-a/daily/2026-04-25.md", vault.daily_path(current, "2026-04-25"))
    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-a/notes/foo-bar.md", vault.note_path(current, "Foo Bar"))
    assert.are.equal(
      "/tmp/pkm-test-vaults/temp-vault-a/daily/" .. today .. "-foo-bar.md",
      vault.sub_daily_path(current, "Foo Bar")
    )

    vault.open_file("/tmp/example.md")
    assert.are.equal("edit /tmp/example.md", state.commands[#state.commands])

    vault.open_daily(current)
    assert.is_true(state.commands[#state.commands]:match("daily/" .. today_escaped .. "%.md") ~= nil)

    vault.open_sub_daily(current, "Foo Bar")
    assert.is_true(state.commands[#state.commands]:match(today_escaped .. "%-foo%-bar%.md") ~= nil)
  end)

  it("resolves names, refreshes the cache, and reports missing daily paths", function()
    pkm.setup({ vault_dir = "/tmp/pkm-test-vaults/temp-vault-a" })
    state.system_handler = function(cmd)
      local joined = table.concat(cmd, " ")
      if joined == "pkm vault list" then
        return {
          code = 0,
          stdout = json.encode({
            vaults = {
              {
                name = "TEMP_VAULT_A",
                path = "/tmp/pkm-test-vaults/temp-vault-a",
                active = true,
              },
              {
                name = "TEMP_VAULT_B",
                path = "/tmp/pkm-test-vaults/temp-vault-b",
                active = false,
              },
            },
            active = "TEMP_VAULT_A",
          }),
          stderr = "",
        }
      end
      if joined == "pkm vault where" then
        return { code = 0, stdout = "/tmp/pkm-test-vaults/temp-vault-a\n", stderr = "" }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    assert.are.equal("TEMP_VAULT_A", vault.resolve_name("/tmp/pkm-test-vaults/temp-vault-a"))
    assert.are.equal("TEMP_VAULT_B", vault.resolve("TEMP_VAULT_B").name)

    vault.set({ name = "cached", path = "/cached" })
    assert.are.equal("cached", vault.get().name)

    vault.refresh()
    assert.are.equal("TEMP_VAULT_A", vault.get().name)

    vault.open_daily({ path = "" })
    assert.are.equal("Unable to resolve daily note path", state.notifications[#state.notifications].message)

    local existing = "/tmp/pkm-test-vaults/temp-vault-a/daily/" .. os.date("%Y-%m-%d") .. "-foo-bar.md"
    state.files[existing] = { "# note" }
    vault.open_sub_daily({ name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a" }, "Foo Bar")
    assert.are.equal("edit " .. existing, state.commands[#state.commands])
  end)

  it("covers fallback and error branches", function()
    pkm.setup({})
    state.system_handler = function(cmd)
      local joined = table.concat(cmd, " ")
      if joined == "pkm vault list" then
        return { code = 0, stdout = json.encode({ vaults = {} }), stderr = "" }
      end
      if joined == "pkm vault where" then
        return { code = 0, stdout = "/fallback/path\n", stderr = "" }
      end
      if joined == "pkm vault open missing" then
        return { code = 1, stdout = "", stderr = "boom" }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    vault.current = nil
    local current = vault.get()
    assert.are.equal("/fallback/path", current.path)
    assert.are.equal("path", current.name)

    vault.current = nil
    assert.are.same({}, vault.list())
    assert.are.equal("/fallback/path", vault.where())

    assert.is_nil(vault.resolve_name("/no/match"))
    assert.is_nil(vault.resolve("/no/match"))
    assert.are.equal("/fallback/path", vault.resolve(nil).path)

    local ok, err = vault.switch("missing")
    assert.is_false(ok)
    assert.are.equal("boom", err.stderr)

    state.system_handler = function(cmd)
      local joined = table.concat(cmd, " ")
      if joined == "pkm vault list" then
        return { code = 0, stdout = json.encode({ vaults = {} }), stderr = "" }
      end
      if joined == "pkm vault where" then
        return { code = 0, stdout = "\n", stderr = "" }
      end
      return { code = 0, stdout = "", stderr = "" }
    end
    vault.current = nil
    ok, err = vault.switch("")
    assert.is_false(ok)
    assert.are.equal("Unable to resolve vault name", err)

    assert.is_nil(vault.note_path({}, "Foo"))
    vault.open_file("")
    assert.are_not.equal("edit ", state.commands[#state.commands] or "")
  end)

  it("covers active-list selection when no hint is configured", function()
    pkm.setup({})
    state.system_handler = function(cmd)
      if table.concat(cmd, " ") == "pkm vault list" then
        return {
          code = 0,
          stdout = json.encode({
            vaults = {
              { name = "TEMP_VAULT_B", path = "/tmp/pkm-test-vaults/temp-vault-b", active = true },
              { name = "TEMP_VAULT_C", path = "/tmp/pkm-test-vaults/temp-vault-c", active = false },
            },
          }),
          stderr = "",
        }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    vault.current = nil
    local current = vault.get()
    assert.are.equal("TEMP_VAULT_B", current.name)
    assert.are.equal("TEMP_VAULT_B", vault.resolve_name(nil))
  end)
end)
