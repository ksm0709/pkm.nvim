require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.daily", function()
  local vim_s
  local state
  local daily
  local daily_add_args
  local daily_sub_args
  local daily_path

  before_each(function()
    daily_add_args = nil
    daily_sub_args = nil
    daily_path = "/tmp/pkm-test/vault/daily/2026-04-25.md"

    vim_s, state = stub.new({
      files = {
        [daily_path] = { "# 2026-04-25", "- 09:00 session start", "- 14:00 fixed bug" },
      },
    })
    _G.vim = vim_s

    package.loaded["pkm.daily"] = nil
    package.loaded["pkm.vault"] = {
      get = function()
        return { name = "TEMP_VAULT_A", path = "/tmp/pkm-test/vault" }
      end,
      daily_path = function()
        return daily_path
      end,
    }
    package.loaded["pkm.cli"] = {
      daily_add = function(content, on_success)
        daily_add_args = content
        if on_success then
          on_success({})
        end
      end,
      daily_sub = function(title, on_success)
        daily_sub_args = title
        if on_success then
          on_success({})
        end
      end,
    }

    daily = require("pkm.daily")
  end)

  local function find_keymap(lhs)
    for _, entry in ipairs(state.keymaps) do
      if entry.lhs == lhs then
        return entry
      end
    end
  end

  local function find_autocmd(event)
    for _, ac in ipairs(state.autocmds) do
      if ac.event == event then
        return ac
      end
    end
  end

  it("opens viewer and input windows on toggle", function()
    daily.toggle()

    assert.is_true(state.windows[2] ~= nil and state.windows[2].valid)
    assert.is_true(state.windows[3] ~= nil and state.windows[3].valid)
  end)

  it("loads daily file content into viewer buffer", function()
    daily.toggle()

    local lines = state.buffers[2].lines
    assert.are.equal("# 2026-04-25", lines[1])
    assert.are.equal("- 14:00 fixed bug", lines[3])
  end)

  it("places viewer cursor at last line after open", function()
    daily.toggle()

    assert.are.same({ 3, 0 }, state.windows[2].cursor)
  end)

  it("sets viewer buffer to readonly after open", function()
    daily.toggle()

    assert.is_true(state.buf_opts[2].readonly == true)
  end)

  it("registers <CR> keymap for submit", function()
    daily.toggle()

    assert.is_not_nil(find_keymap("<CR>"))
  end)

  it("submits plain text via cli.daily_add", function()
    daily.toggle()

    state.buffers[3].lines = { "wrote new feature" }
    find_keymap("<CR>").rhs()

    assert.are.equal("wrote new feature", daily_add_args)
    assert.is_nil(daily_sub_args)
  end)

  it("clears input buffer after submit", function()
    daily.toggle()

    state.buffers[3].lines = { "some log entry" }
    find_keymap("<CR>").rhs()

    assert.are.equal("", state.buffers[3].lines[1])
  end)

  it("refreshes viewer after successful submit", function()
    daily.toggle()

    state.buffers[3].lines = { "new entry" }
    find_keymap("<CR>").rhs()

    -- on_success triggered refresh_viewer which reloaded the file
    assert.are.equal("# 2026-04-25", state.buffers[2].lines[1])
  end)

  it("ignores empty input on submit", function()
    daily.toggle()

    state.buffers[3].lines = { "   " }
    find_keymap("<CR>").rhs()

    assert.is_nil(daily_add_args)
    assert.is_nil(daily_sub_args)
  end)

  it("/add-subnote <title> calls cli.daily_sub", function()
    daily.toggle()

    state.buffers[3].lines = { "/add-subnote My Research Note" }
    find_keymap("<CR>").rhs()

    assert.are.equal("My Research Note", daily_sub_args)
    assert.is_nil(daily_add_args)
  end)

  it("/add-subnote none calls vim.ui.input then cli.daily_sub", function()
    table.insert(state.inputs, "Prompted Title")
    daily.toggle()

    state.buffers[3].lines = { "/add-subnote none" }
    find_keymap("<CR>").rhs()

    assert.are.equal("Prompted Title", daily_sub_args)
  end)

  it("/add-subnote with no argument calls vim.ui.input", function()
    table.insert(state.inputs, "Input Title")
    daily.toggle()

    state.buffers[3].lines = { "/add-subnote" }
    find_keymap("<CR>").rhs()

    assert.are.equal("Input Title", daily_sub_args)
  end)

  it("closes both windows on q keymap", function()
    daily.toggle()

    find_keymap("q").rhs()

    assert.is_false(state.windows[2].valid)
    assert.is_false(state.windows[3].valid)
  end)

  it("restores prev_win focus on close", function()
    daily.toggle()

    find_keymap("q").rhs()

    assert.are.equal(1, state.current_win)
  end)

  it("toggle twice closes the panel", function()
    daily.toggle()
    assert.is_true(state.windows[2].valid)
    daily.toggle()
    assert.is_false(state.windows[2].valid)
    assert.is_false(state.windows[3].valid)
  end)

  it("WinClosed autocmd closes panel when viewer window is closed externally", function()
    daily.toggle()

    local ac = find_autocmd("WinClosed")
    assert.is_not_nil(ac)

    -- simulate external close of viewer_win (ID 2); vim.schedule is sync in stub
    ac.opts.callback({ match = "2" })

    assert.is_false(state.windows[2].valid)
    assert.is_false(state.windows[3].valid)
  end)

  it("WinClosed autocmd is a no-op when panel is already closed", function()
    daily.toggle()
    local ac = find_autocmd("WinClosed")

    daily.toggle() -- close manually
    assert.is_false(state.windows[2].valid)

    -- firing the autocmd again should not error
    ac.opts.callback({ match = "2" })
    assert.is_false(state.windows[2].valid)
  end)

  it("registers <C-c> close keymap on both viewer and input buffers", function()
    daily.toggle()

    -- viewer_buf=2, input_buf=3
    local viewer_cc, input_cc = false, false
    for _, entry in ipairs(state.keymaps) do
      if entry.lhs == "<C-c>" then
        if entry.opts and entry.opts.buffer == 2 then
          viewer_cc = true
        elseif entry.opts and entry.opts.buffer == 3 then
          input_cc = true
        end
      end
    end
    assert.is_true(viewer_cc, "viewer_buf should have <C-c> keymap")
    assert.is_true(input_cc, "input_buf should have <C-c> keymap")
  end)

  it("handles missing daily file without error", function()
    vim_s, state = stub.new({ files = {} })
    _G.vim = vim_s
    package.loaded["pkm.daily"] = nil
    package.loaded["pkm.vault"] = {
      get = function()
        return { name = "TEMP_VAULT_A", path = "/tmp/pkm-test/vault" }
      end,
      daily_path = function()
        return "/tmp/pkm-test/vault/daily/missing.md"
      end,
    }
    package.loaded["pkm.cli"] = {
      daily_add = function() end,
      daily_sub = function() end,
    }
    daily = require("pkm.daily")

    daily.toggle()

    assert.is_true(state.windows[2].valid)
    assert.are.same({}, state.buffers[2].lines)
  end)
end)
