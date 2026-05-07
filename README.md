# ✅ todoist.nvim

A Neovim plugin for managing [Todoist](https://todoist.com) tasks without leaving your editor.
Tasks are displayed in a floating window grouped by project, with priority coloring, task hierarchy,
inline descriptions, and full CRUD operations. No external dependencies beyond `curl`.

---

## ✨ Features

- **Project-grouped task view** — tasks organized under project headers, colored by priority
- **Task hierarchy** — subtasks indented beneath their parents
- **Inline descriptions** — toggle task descriptions in-place with `<CR>`
- **Create & edit tasks** — floating editor with project, parent task, due date, and description fields
- **Complete / reopen tasks** — toggle completion status; view completed tasks alongside active ones
- **Live search** — `/` to filter tasks; results persist after exiting search mode
- **Async API calls** — non-blocking `curl` requests, no UI freezes
- **Secure token storage** — stored at `stdpath('data')/todoist/token` with `0600` permissions
- **which-key integration** — `<leader>t` group registered automatically

---

## 📋 Requirements

- Neovim 0.9+
- `curl` in `PATH`
- A [Todoist API token](https://app.todoist.com/app/settings/integrations/developer)

---

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "arjun-shanmugam/todoist.nvim",
  config = function()
    require("todoist").setup({
      token = vim.env.TODOIST_API_TOKEN, -- or set via :TodoistLogin
      today_view_ui = "custom",
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use({
  "arjun-shanmugam/todoist.nvim",
  config = function()
    require("todoist").setup({
      token = vim.env.TODOIST_API_TOKEN,
      today_view_ui = "custom",
    })
  end,
})
```

---

## 🔑 Authentication

The plugin resolves your API token in this order:

1. **`token` option** in `setup()` — recommended for inline config
2. **`TODOIST_API_TOKEN` environment variable** — good for shell-level secrets
3. **Saved token file** — run `:TodoistLogin` to paste and save your token securely

To remove a saved token: `:TodoistLogout`

---

## ⚙️ Configuration

Pass options to `require("todoist").setup({})`. All keys are optional.

```lua
require("todoist").setup({
  -- Your Todoist API token (get from https://app.todoist.com/app/settings/integrations/developer)
  token = nil,

  -- Which UI to use for the task view: "custom" (recommended) or "fzf"
  today_view_ui = "custom",

  -- Default project ID to show on open (nil = all projects)
  default_project = nil,

  -- Override global keymaps (see Keymaps section)
  keymaps = {
    enable = true,
    mappings = {
      open_tasks = "<leader>to",
      login      = "<leader>tl",
      logout     = "<leader>tL",
    },
  },

  -- curl binary path override
  curl_bin = "curl",

  -- Custom notification handler (defaults to vim.notify)
  notify = vim.notify,
})
```

---

## 🗂️ Task View

Open the task view with `<leader>to` (or `:TodoistTasks`).

Tasks are displayed in a floating window grouped by project. Within each project, completed tasks appear first (strikethrough), followed by active tasks indented to reflect their parent–child hierarchy. Priority is indicated by line color.

### Navigation

| Key | Action |
|-----|--------|
| `j` / `k` | Move to next / previous task |
| `[count]j` / `[count]k` | Jump N tasks (e.g. `5j`) |
| `gg` | Jump to first task |
| `G` | Jump to last task |
| `<C-d>` / `<C-u>` | Scroll down / up 10 tasks |

### Task Actions

| Key | Action |
|-----|--------|
| `<CR>` | Toggle inline description for the task under cursor |
| `<leader>te` | Open edit window for the task under cursor |
| `<leader>tc` | Toggle task completion (complete ↔ reopen) |
| `<leader>tn` | Open create window for a new task |
| `<leader>td` | Delete task under cursor |
| `<leader>tr` | Refresh task list from API |
| `<leader>ts` | Toggle display of completed tasks |
| `/` | Search (native Vim search — type pattern, `n`/`N` to jump between matches) |
| `<leader>wx` | Close the task view |

### Search

Press `/` to use Vim's native search. Task content, descriptions, project headers, and due dates are all searchable since they are real buffer lines.

- **`/pattern<CR>`** — search and jump to first match
- **`n` / `N`** — jump to next / previous match
- **`:noh`** — clear search highlights

All task action keymaps work normally during and after search.

### Visual Mode & Yanking

Standard visual mode (`v`, `V`, `<C-v>`) and yanking (`y`) work normally in the task view — select and copy any text.

---

## ✏️ Create Task Window

Open with `<leader>tn` from the task view.

The window is a floating editor with labeled sections:

```
╭─ Create Task ──────────────────────────────────────╮
│  Project                                           │
│  Work                                              │
│  ────────────────────────────────────────────────  │
│  Parent Task                                       │
│  None                                              │
│  ────────────────────────────────────────────────  │
│  Title                                             │
│  [cursor here — type your task title]              │
│  ────────────────────────────────────────────────  │
│  Due Date                                          │
│  tomorrow                                          │
│  ────────────────────────────────────────────────  │
│  Description                                       │
│  Any extra notes here                              │
╰─ <leader>tw save · <leader>tp project · <leader>ta parent · <leader>tq close ─╯
```

| Key | Action |
|-----|--------|
| `<leader>tw` | Save and create the task |
| `<leader>tp` | Open project picker |
| `<leader>ta` | Open parent task picker (filters to tasks in the selected project) |
| `<leader>tq` | Discard and close |

**Due date** accepts any natural language string that Todoist understands (e.g. `today`, `tomorrow`, `next monday`, `Jan 15`). Leave blank to create a task with no due date.

---

## 📝 Edit Task Window

Open with `<leader>te` while the cursor is on a task.

The layout is identical to the create window, pre-populated with the task's current values.

| Key | Action |
|-----|--------|
| `<leader>tw` | Save changes |
| `<leader>tp` | Change project (uses Todoist move endpoint) |
| `<leader>ta` | Change parent task (or set to "None" for top-level) |
| `<leader>tq` | Discard and close |

**Clearing the due date**: erase the due date line and save — the plugin sends Todoist's magic string `"no date"` to remove it.

**Changing the project** automatically clears the selected parent (since the parent must belong to the same project).

---

## 🌐 Global Keymaps

Set automatically during `setup()`. Registered under `<leader>t` in which-key.

| Key | Action |
|-----|--------|
| `<leader>to` | Open task view |
| `<leader>tl` | Login (`:TodoistLogin`) |
| `<leader>tL` | Logout (`:TodoistLogout`) |

### Disabling / Customizing

```lua
require("todoist").setup({
  keymaps = { enable = false }, -- disable all automatic keymaps
})
```

```lua
require("todoist").setup({
  keymaps = {
    mappings = {
      open_tasks = "<leader>to", -- customize
      login      = false,        -- disable this specific keymap
      logout     = false,
    },
  },
})
```

---

## 📡 Commands

| Command | Description |
|---------|-------------|
| `:TodoistTasks [project_id]` | Open the task view (optional project filter) |
| `:TodoistLogin` | Prompt for API token and save to disk |
| `:TodoistLogout` | Delete the saved token file |
| `:TodoistComplete <task_id>` | Complete a task by ID |

---

## 🔒 Security

- `:TodoistLogin` uses `vim.ui.input` with `secret = true` — the token is never echoed
- Token file is written with `0600` permissions under `stdpath('data')/todoist/`
- Setting `TODOIST_API_TOKEN` in the environment avoids writing any file

---

## 🙏 Credits

Originally forked from [mshiyaf/todoist.nvim](https://github.com/mshiyaf/todoist.nvim).

---

## 📄 License

MIT
