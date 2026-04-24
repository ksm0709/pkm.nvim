require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.chat", function()
  local vim
  local state
  local chat

  before_each(function()
    vim, state = stub.new()
    _G.vim = vim
    package.loaded["pkm.chat"] = nil
    package.loaded["pkm.vault"] = {
      get = function()
        return { name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a" }
      end,
    }
    package.loaded["pkm.cli"] = {
      stream = function(args, handlers)
        state.stream_args = args
        state.stream_handlers = handlers
        return 1
      end,
      daemon_start = function(opts)
        state.daemon_started = true
        if opts.on_success then
          opts.on_success()
        end
      end,
    }
    chat = require("pkm.chat")
  end)

  local function find_keymap(lhs)
    for _, entry in ipairs(state.keymaps) do
      if entry.lhs == lhs then
        return entry
      end
    end
  end

  it("opens, submits, and streams ask output", function()
    chat.toggle()
    local buffer_ids = {}
    for id in pairs(state.buffers) do
      if id ~= 1 then
        table.insert(buffer_ids, id)
      end
    end
    table.sort(buffer_ids)
    local stdout_buf = buffer_ids[1]
    local input_buf = buffer_ids[2]
    assert.is_not_nil(stdout_buf)
    assert.is_not_nil(input_buf)
    state.buffers[input_buf].lines = { "hello world" }

    local submit = find_keymap("<CR>")
    assert.is_not_nil(submit)
    submit.rhs()

    assert.are.same({ "ask", "hello world" }, state.stream_args)

    if state.stream_handlers.on_stdout then
      state.stream_handlers.on_stdout("answer")
    end

    local stdout_text = table.concat(state.buffers[stdout_buf].lines, "\n")
    assert.is_true(stdout_text:find("answer", 1, true) ~= nil)
  end)

  it("handles chunked streaming and newlines correctly", function()
    chat.open()
    local buffer_ids = {}
    for id in pairs(state.buffers) do
      if id ~= 1 then
        table.insert(buffer_ids, id)
      end
    end
    table.sort(buffer_ids)
    local stdout_buf = buffer_ids[1]

    chat.stream_prompt("test", "test prompt")

    local on_stdout = state.stream_handlers.on_stdout
    on_stdout("Asking daemon using model 'gemini'...\n")
    on_stdout("  ↳ vault_stats()\n")
    on_stdout("  ↳ list_orphans()\n")
    on_stdout("Hello! ")
    on_stdout("I found ")
    on_stdout("some things.\n\n")
    on_stdout("Here they are.")

    local lines = state.buffers[stdout_buf].lines
    local text = table.concat(lines, "\n")

    assert.is_true(text:find("Asking daemon using model 'gemini'...\n", 1, true) ~= nil)
    assert.is_true(text:find("  ↳ list_orphans()\n", 1, true) ~= nil)
    assert.is_true(text:find("Hello! I found some things.\n\nHere they are.", 1, true) ~= nil)
  end)

  it("toggling twice closes the chat", function()
    chat.toggle()
    local win_ids = {}
    for id in pairs(state.windows) do
      if id ~= 1 then
        table.insert(win_ids, id)
      end
    end
    table.sort(win_ids)
    assert.is_true(state.windows[win_ids[1]].valid)
    chat.toggle()
    for _, id in ipairs(win_ids) do
      assert.is_true(state.windows[id].valid == false)
    end
  end)

  it("starts workflows through the daemon and stream bridge", function()
    chat.stream_workflow("zettelkasten-maintenance", "run workflow")
    assert.is_true(state.daemon_started)
    assert.are.same({ "ask", "run workflow" }, state.stream_args)
  end)
end)
