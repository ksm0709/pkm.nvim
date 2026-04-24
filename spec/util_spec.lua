require("spec_helper")

local stub = require("spec.support.vim_stub")

describe("pkm.util", function()
  local vim
  local state
  local util

  before_each(function()
    vim, state = stub.new()
    _G.vim = vim
    package.loaded["pkm.util"] = nil
    util = require("pkm.util")
  end)

  it("normalizes paths and strings", function()
    assert.are.equal("a/b/c", util.join_path("a", "b", "c"))
    assert.are.equal("hello", util.trim("  hello  "))
    assert.are.equal("abc", util.slugify("ABC"))
    assert.are.equal("foo-bar", util.slugify("Foo Bar"))
    assert.are.same({ "a", "b" }, util.split_lines("a\nb"))
    assert.are.same({ "a", "b" }, util.split_lines("a\r\nb"))
    assert.are.equal("hello\nworld", util.normalize_output("hello\r\nworld"))
  end)

  it("reads files and detects filesystem state", function()
    local path = "/tmp/pkm-util-test.txt"
    state.files[path] = { "line1", "line2" }

    assert.is_true(util.file_exists(path))
    assert.is_false(util.dir_exists(path))
    assert.are.same({ "line1", "line2" }, util.read_lines(path))
    assert.are.equal("line1\nline2", util.read_file(path))
    assert.are.equal("pkm-util-test", util.basename_without_ext("/tmp/pkm-util-test.txt"))
    assert.are.equal("pkm-util-test.txt", util.basename("/tmp/pkm-util-test.txt"))
  end)

  it("creates missing directories and notifies", function()
    util.ensure_dir("/tmp/pkm-util-dir")
    assert.is_true(state.dirs["/tmp/pkm-util-dir"])

    util.notify("hello")
    assert.are.equal("hello", state.notifications[1].message)
  end)
end)
