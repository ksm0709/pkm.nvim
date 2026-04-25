require("spec_helper")

local json = require("dkjson")
local stub = require("spec.support.vim_stub")

describe("pkm.picker", function()
  local vim
  local state
  local picker

  before_each(function()
    vim, state = stub.new()
    _G.vim = vim

    package.loaded["pkm.util"] = nil
    package.loaded["pkm"] = {
      config = {
        workflows = {
          {
            name = "custom-workflow",
            description = "Custom workflow",
            prompt = "custom prompt",
          },
        },
      },
    }

    package.loaded["pkm.chat"] = {
      stream_workflow = function(name, prompt)
        state.workflow_name = name
        state.workflow_prompt = prompt
      end,
      toggle = function()
        state.chat_toggled = true
      end,
    }

    package.loaded["pkm.vault"] = {
      get = function()
        if state.current_vault then
          return state.current_vault
        end
        return { name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a" }
      end,
      list = function()
        return {
          { name = "TEMP_VAULT_A", path = "/tmp/pkm-test-vaults/temp-vault-a", active = true },
          { name = "TEMP_VAULT_B", path = "/tmp/pkm-test-vaults/temp-vault-b", active = false },
        }
      end,
      switch = function(name)
        state.switched_vault = name
        state.current_vault = { name = name, path = "/tmp/pkm-test-vaults/" .. name:lower() }
        return true, state.current_vault
      end,
      open_daily = function(target)
        state.open_daily_target = target
      end,
      sub_daily_path = function(_, title)
        return "/tmp/pkm-test-vaults/temp-vault-a/daily/2026-04-24-" .. title:lower():gsub("%s+", "-") .. ".md"
      end,
    }

    package.loaded["pkm.cli"] = {
      search = function(query, on_success)
        state.search_query = query
        on_success({
          stdout = json.encode({
            results = {
              {
                title = "Note A",
                description = "desc",
                score = 1.23,
                tags = { "one" },
                graph_context = {
                  nodes = {
                    { type = "note", path = "/tmp/note-a.md" },
                  },
                },
              },
              {
                title = "Note B",
                description = "fallback",
                score = 0.75,
                tags = { "two" },
                graph_context = nil,
              },
            },
          }),
        })
      end,
      tags_search = function(pattern, on_success)
        state.tags_query = pattern
        on_success({
          stdout = json.encode({
            results = {
              {
                title = "Tag Note",
                tags = { "a", "b" },
                graph_context = {
                  nodes = {
                    { type = "note", path = "/tmp/tag-note.md" },
                  },
                },
              },
            },
          }),
        })
      end,
      graph_neighbors = function(note_id, on_success)
        state.links_query = note_id
        on_success({
          stdout = json.encode({
            inbound = { { title = "Inbound", note_id = "inbound", type = "note" } },
            outbound = { { title = "Outbound", note_id = "outbound", type = "note" } },
            semantic = { { title = "Semantic", note_id = "semantic", type = "tag" } },
          }),
        })
      end,
      grep_backlinks = function(note_id, vault_path, on_success)
        on_success({ stdout = "", code = 1 })
      end,
      daily_sub = function(title, on_success)
        state.daily_sub_title = title
        if on_success then
          on_success({ stdout = "", stderr = "", code = 0 })
        end
      end,
      index = function(handlers)
        state.index_called = true
        if handlers.on_exit then
          handlers.on_exit(0)
        end
      end,
    }

    state.pickers = {}
    package.loaded["snacks"] = {
      picker = setmetatable({
        grep = function(config)
          table.insert(state.pickers, config)
        end,
      }, {
        __call = function(_, config)
          table.insert(state.pickers, config)
        end,
      }),
    }
    package.loaded["snacks.picker.util.async"] = {
      running = function()
        return {
          suspend = function() end,
          resume = function() end,
        }
      end,
    }

    state.system_handler = function(cmd)
      local line = table.concat(cmd, " ")
      if line:find("rg --files", 1, true) then
        return {
          code = 0,
          stdout = table.concat({
            "/tmp/pkm-test-vaults/temp-vault-a/notes/note-a.md",
            "/tmp/pkm-test-vaults/temp-vault-a/notes/note-b.md",
          }, "\n"),
          stderr = "",
        }
      end
      if line:find("rg --vimgrep", 1, true) then
        return {
          code = 0,
          stdout = "/tmp/pkm-test-vaults/temp-vault-a/notes/note-a.md:12:3:match one",
          stderr = "",
        }
      end
      return { code = 0, stdout = "", stderr = "" }
    end

    package.loaded["pkm.picker"] = nil
    picker = require("pkm.picker")
  end)

  local function last_picker()
    return state.pickers[#state.pickers]
  end

  local function confirm_last(item_index)
    local config = last_picker()
    local item = config.items[item_index or 1]
    config.actions.confirm({
      close = function()
        state.picker_closed = true
      end,
    }, item)
  end

  it("builds search, tags, links, file, and grep pickers", function()
    picker.search()
    assert.are.equal("PKM Search", last_picker().title)

    local cb_items = {}
    last_picker().finder({ filter = { search = "alpha" } })(function(item)
      table.insert(cb_items, item)
    end)

    assert.are.equal("/tmp/note-a.md", cb_items[1].file)
    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-a/notes/note-b.md", cb_items[2].file)

    last_picker().actions.confirm({
      close = function()
        state.picker_closed = true
      end,
    }, cb_items[1])
    assert.are.equal("edit /tmp/note-a.md", state.commands[#state.commands])

    picker.tags()
    assert.are.equal("PKM Tags", last_picker().title)
    cb_items = {}
    last_picker().finder({ filter = { search = "topic" } })(function(item)
      table.insert(cb_items, item)
    end)

    last_picker().actions.confirm({
      close = function()
        state.picker_closed = true
      end,
    }, cb_items[1])
    assert.are.equal("edit /tmp/tag-note.md", state.commands[#state.commands])

    picker.links("Some Title")
    assert.are.equal("PKM Links: Some Title", last_picker().title)
    assert.are.equal(3, #last_picker().items)
    assert.are.equal("Inbound", last_picker().items[1].text)
    assert.are.equal("Outbound", last_picker().items[2].text)
    assert.are.equal("Semantic", last_picker().items[3].text)

    last_picker().actions.confirm({
      close = function()
        state.picker_closed = true
      end,
    }, last_picker().items[1])
    -- The path for note is /tmp/pkm-test-vaults/temp-vault-a/notes/inbound.md
    assert.are.equal("edit /tmp/pkm-test-vaults/temp-vault-a/notes/inbound.md", state.commands[#state.commands])

    picker.files()
    assert.is_true(#last_picker().items >= 2)

    picker.grep("needle")
    assert.are.equal("needle", last_picker().search)
    assert.are.equal("/tmp/pkm-test-vaults/temp-vault-a", last_picker().dirs[1])
  end)

  it("covers prompt paths, daily actions, vault switching, workflows, and chat toggle", function()
    picker.daily_open()
    assert.are.equal("TEMP_VAULT_A", state.open_daily_target.name)

    state.inputs = { "Sub note" }
    picker.daily_sub()
    assert.are.equal("Sub note", state.daily_sub_title)
    assert.is_true(state.commands[#state.commands]:find("2026%-04%-24%-", 1, false) ~= nil)

    picker.index()
    assert.is_true(state.index_called)
    assert.are.equal("Index refreshed", state.notifications[#state.notifications].message)

    picker.vaults()
    confirm_last(2)
    assert.are.equal("TEMP_VAULT_B", state.switched_vault)
    local saw_cd = false
    for _, command in ipairs(state.commands) do
      if command:find("^cd ") then
        saw_cd = true
        break
      end
    end
    assert.is_true(saw_cd)
    assert.are.equal("TEMP_VAULT_B", state.open_daily_target.name)

    picker.workflows()
    assert.is_true(#last_picker().items >= 2)
    confirm_last(1)
    assert.are.equal("custom-workflow", state.workflow_name)
    assert.are.equal("custom prompt", state.workflow_prompt)

    picker.chat_toggle()
    assert.is_true(state.chat_toggled)
  end)
end)
