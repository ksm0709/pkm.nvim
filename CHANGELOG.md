# Changelog

All notable changes to pkm.nvim are documented here.
Versions follow [Semantic Versioning](https://semver.org). Release notes are auto-generated from [Conventional Commits](https://www.conventionalcommits.org).

---

## [Unreleased]

### Features
- `<Leader>pD` remapped to open daily note and cd to vault root; subnote picker moved to `<Leader>pS`
- Statusline: detect active vault from buffer path, refresh on `BufEnter`
- Links picker: wikilink grep fallback for un-indexed notes
- Daily sub-note: open created buffer immediately after creation; rename `/subnote` slash command; fix Tab/CR completion keys
- Chat: stream daemon workflow output in right panel
- `<Leader>pw` replaced with pkm daemon workflow list/run picker
- `<Leader>pd` replaced with vsplit daily panel (viewer + chat input)
- Search: prepopulate query with cursor word or visual selection
- Links picker: upgraded to show interactive graph neighbors (inbound, outbound, semantic)

### Fixes
- Statusline: use `vault list` name field instead of path basename; use vault icon `󱓧`
- Statusline: detect vault from CWD path fallback; refresh vault on directory change
- CI: resolve stylua check failures on full repo scope
- Picker: handle CLI errors cleanly in async finders
- Picker: attach file paths to links picker items to fix preview crash
- Picker: resolve E5560 fast event crash by caching vault synchronously
- Picker: prevent async deadlock by correctly ordering coroutine suspend/resume
- Picker: ensure compatibility with all snacks.picker finder signatures
- Picker: use `filter.search` for live typing queries
- Picker: disable notifications in snacks finders to prevent fast event crashes
- Picker: ensure text fallback to avoid nil str crash in snacks mappers
- Picker: detect vault from buffer path for links picker
- Picker: remove deprecated `.bak` workflow roots
- CLI: use `--` separator to prevent flag misinterpretation for positional arguments
- CLI: update `daily_sub` to use `pkm daily subnote` command

---

## [v0.3.6] — 2026-04-24

### Fixes
- Picker: correct variable shadowing in async finders

---

## [v0.3.5] — 2026-04-24

### Fixes
- Picker: update async finder signature for snacks.nvim

---

## [v0.3.4] — 2026-04-24

### Fixes
- Statusline: make active vault fetching non-blocking and lazy-loaded

---

## [v0.3.3] — 2026-04-24

### Style
- Chat UI: refine rendering and disable line numbers and sign columns

---

## [v0.3.2] — 2026-04-24

### Fixes
- Chat: handle carriage returns in streamed output; fix interactive snacks pickers

---

## [v0.3.1] — 2026-04-24

### Chores
- Ignore local context, agent files, and node_modules in gitignore

---

## [v0.3.0] — 2026-04-24

### Features
- Complete implementation of statusline API, search fixes, and chat streaming

---

## [v0.2.0] — 2026-04-24

### Features
- Add statusline API, fix search issues, and chat streaming improvements

---

## [v0.1.0] — 2026-04-24

### Features
- Initial release: vault-aware PKM UI with codex quality gate
