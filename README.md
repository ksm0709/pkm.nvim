# pkm.nvim

Neovim plugin for [pkm](https://github.com/ksm0709/pkm) — a personal knowledge management CLI. Browse notes, capture daily entries, search semantically, manage backlinks, and run AI-powered workflows directly from your editor.

## Requirements

- Neovim ≥ 0.10
- [pkm CLI](https://github.com/ksm0709/pkm) installed and on `$PATH`
- [snacks.nvim](https://github.com/folke/snacks.nvim) (picker UI)

## Installation

### lazy.nvim

```lua
{
  "ksm0709/pkm.nvim",
  opts = {},
}
```

### With options

```lua
{
  "ksm0709/pkm.nvim",
  opts = {
    vault = "my-vault",      -- explicit vault name or path override
    vault_dir = "~/notes",   -- path to vault root
    auto_index = true,       -- re-index on capture actions
  },
}
```

## Configuration

`require("pkm").setup(opts)` accepts:

| Option | Type | Default | Description |
|---|---|---|---|
| `vault` | `string` | `nil` | Vault name or path override for CLI calls |
| `vault_dir` | `string` | `nil` | Path to the PKM vault root |
| `auto_index` | `boolean` | `true` | Auto-index vault on certain actions |
| `workflows` | `table[]` | `nil` | Optional workflow definitions for the picker |

## Keymaps

All keymaps use the `<Leader>p` prefix and are set automatically on load.

| Keymap | Mode | Description |
|---|---|---|
| `<Leader>pd` | `n` | Toggle daily note panel (vsplit viewer + input) |
| `<Leader>pD` | `n` | Open daily note and cd to vault root |
| `<Leader>pS` | `n` | Create new daily sub-note |
| `<Leader>pa` | `n` | Toggle AI chat panel |
| `<Leader>ps` | `n` | Semantic search (uses word under cursor) |
| `<Leader>ps` | `v` | Semantic search (uses visual selection) |
| `<Leader>pt` | `n` | Browse notes by tag |
| `<Leader>pl` | `n` | Browse backlinks / graph neighbors |
| `<Leader>pf` | `n` | Browse vault files |
| `<Leader>pg` | `n` | Full-text grep across vault |
| `<Leader>pv` | `n` | Switch vault |
| `<Leader>pw` | `n` | List and run daemon workflows |
| `<Leader>pi` | `n` | Re-index vault |

## Commands

`:Pkm <subcommand>` (tab-completable):

| Subcommand | Description |
|---|---|
| `daily` | Capture entry to today's daily note |
| `note` | Capture a new standalone note |
| `daily-open` | Open the daily note picker |
| `daily-sub` | Create a daily sub-note |
| `vault` | Switch active vault |
| `search [query]` | Semantic search |
| `tags [pattern]` | Browse notes by tag |
| `links [title]` | Browse backlinks and graph neighbors |
| `grep [query]` | Full-text grep |
| `files` | File browser |
| `index` | Re-index the vault |
| `workflows` | List and run daemon workflows |
| `chat` | Toggle AI chat panel |

## Statusline

Display the active vault name in your statusline:

```lua
-- lualine example
require("lualine").setup({
  sections = {
    lualine_x = { require("pkm").statusline },
  },
})
```

Returns `"󱓧 vault-name"` when inside a known vault, `""` otherwise. The lookup is non-blocking — the component renders empty on the first call and updates asynchronously.

## Health check

```
:checkhealth pkm
```

Verifies that the `pkm` CLI is installed and reachable.

## Structure

```
lua/pkm/
├── init.lua      setup(), statusline(), vault_invalidate()
├── cli.lua       async pkm CLI wrapper
├── picker.lua    snacks.nvim picker integrations
├── daily.lua     daily note panel (vsplit viewer + input)
├── capture.lua   note/daily capture helpers
├── chat.lua      AI chat panel with streamed output
├── vault.lua     vault detection, caching, and switching
├── blink.lua     blink.cmp completion source
├── util.lua      shared utilities (json, paths, slugify)
└── health.lua    :checkhealth pkm

plugin/
└── pkm.lua       user commands (:Pkm) and keymaps
```

## License

ISC
