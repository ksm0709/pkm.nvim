require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.cli", function()
  local vim
  local state
  local pkm
  local cli

  before_each(function()
    vim, state = stub.new()
    _G.vim = vim
    package.loaded["pkm.util"] = nil
    package.loaded["pkm"] = nil
    package.loaded["pkm.cli"] = nil
    pkm = require("pkm")
    cli = require("pkm.cli")
  end)

  local function join(cmd)
    return table.concat(cmd, " ")
  end

  local function non_lookup_commands()
    local out = {}
    for _, call in ipairs(state.system_calls) do
      if join(call.cmd) ~= "pkm vault list" then
        table.insert(out, call)
      end
    end
    return out
  end

  it("resolves vault names and builds async commands", function()
    pkm.setup({ vault_dir = "/tmp/pkm-test-vaults/temp-vault-a" })
    state.system_handler = function(cmd)
      local line = join(cmd)
      if line == "pkm vault list" then
        return {
          code = 0,
          stdout = [[{"vaults":[{"name":"TEMP_VAULT_A","path":"/tmp/pkm-test-vaults/temp-vault-a","active":true}]}]],
          stderr = "",
        }
      end
      if line == "pkm vault where" then
        return { code = 0, stdout = "/tmp/pkm-test-vaults/temp-vault-a\n", stderr = "" }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    cli.daily_add("entry")
    cli.daily_sub("sub")
    cli.note_add("Title", "body")
    cli.search("query")
    cli.note_search("query")
    cli.note_show("query")
    cli.tags_search("tag")
    cli.note_links("note")
    cli.vault_open("vault")
    cli.daemon_start()
    cli.daemon_status()

    local calls = non_lookup_commands()
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "daily", "add", "entry" }, calls[1].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "daily", "add", "--sub", "sub" }, calls[2].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "note", "add", "Title", "--content", "body" }, calls[3].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "search", "query" }, calls[4].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "note", "search", "query" }, calls[5].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "note", "show", "query" }, calls[6].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "tags", "search", "tag" }, calls[7].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "note", "links", "note" }, calls[8].cmd)
    assert.are.same({ "pkm", "vault", "open", "vault" }, calls[9].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "daemon", "start" }, calls[10].cmd)
    assert.are.same({ "pkm", "--vault", "TEMP_VAULT_A", "daemon", "status" }, calls[11].cmd)
  end)

  it("exposes sync vault helpers and async error paths", function()
    state.system_handler = function(cmd)
      local line = join(cmd)
      if line == "pkm vault list" then
        return {
          code = 0,
          stdout = [[{"vaults":[{"name":"TEMP_VAULT_B","path":"/tmp/pkm-test-vaults/temp-vault-b","active":false}]}]],
          stderr = "",
        }
      end
      if line == "pkm vault where" then
        return { code = 0, stdout = "/tmp/pkm-test-vaults/temp-vault-b\n", stderr = "" }
      end
      return { code = 1, stdout = "", stderr = "nope" }
    end

    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-b", cli.vault_where_sync())
    local parsed = cli.vault_list_sync()
    assert.are.equal("TEMP_VAULT_B", parsed.vaults[1].name)

    local error_seen = false
    cli.vault_open("broken", nil, function(stderr)
      error_seen = true
      assert.is_true(stderr:find("nope", 1, true) ~= nil or stderr ~= nil)
    end)
    assert.is_true(error_seen)
  end)

  it("streams commands and handles job failures", function()
    state.job_handler = function(cmd, opts)
      if join(cmd) == "pkm ask hello" then
        if opts.on_stdout then
          opts.on_stdout(nil, { "chunk" }, nil)
        end
        if opts.on_stderr then
          opts.on_stderr(nil, { "warn" }, nil)
        end
        if opts.on_exit then
          opts.on_exit(nil, 0, nil)
        end
        return 7
      end
      if opts.on_exit then
        opts.on_exit(nil, 1, nil)
      end
      return 0
    end

    local stdout = {}
    local stderr = {}
    local exits = {}
    cli.ask_stream("hello", {
      on_stdout = function(text)
        table.insert(stdout, text)
      end,
      on_stderr = function(text)
        table.insert(stderr, text)
      end,
      on_exit = function(code)
        table.insert(exits, code)
      end,
    })

    local error_seen = false
    cli.stream({ "broken" }, {
      on_error = function(message)
        error_seen = true
        assert.is_true(message:find("failed", 1, true) ~= nil or message:find("exited", 1, true) ~= nil)
      end,
    })

    assert.are.same({ "chunk" }, stdout)
    assert.are.same({ "warn" }, stderr)
    assert.are.same({ 0 }, exits)
    assert.is_true(error_seen)
    assert.are.same({ "pkm", "ask", "hello" }, state.job_calls[1].cmd)
  end)
end)
