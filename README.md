# todoist.nvim

A Neovim plugin for managing [Todoist](https://todoist.com) tasks without leaving your editor.
Tasks are displayed in a floating window grouped by project, with priority coloring, task hierarchy,
inline descriptions, and full CRUD operations. No external dependencies beyond `curl`.

---

## Features

- **Project-grouped task view** — tasks organized under project headers, ordered to match the Todoist app
- **Task hierarchy** — subtasks indented beneath their parents
- **Priority coloring** — tasks colored by Todoist priority (urgent → high → medium → normal)
- **Inline descriptions** — toggle task descriptions in-place with `<CR>`
- **Create & edit tasks** — floating editor with title, project, parent task, due date, and description fields
- **Complete / reopen tasks** — toggle completion status with `<leader>tc`
- **Completed task view** — toggle display of completed tasks with `<leader>ts`; completed subtasks appear under their parents
- **Native Vim search** — `/` to search across all task content, project headers, and due dates
- **Full pagination** — fetches all tasks across all pages (Todoist paginates at 50)
- **Async API calls** — non-blocking `curl` requests; no UI freezes
- **Secure token storage** — stored at `stdpath('data')/todoist/token` with `0600` permissions
- **which-key integration** — `<leader>t` group registered automatically if which-key is installed

---

## Requirements

- Neovim 0.9+
- `curl` in `PATH`
- A [Todoist API token](https://app.todoist.com/app/settings/integrations/developer)

---

## Installation

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

## Authentication

The plugin resolves your API token in this priority order:

1. **`token` option** in `setup()` — simplest for inline config
2. **`TODOIST_API_TOKEN` environment variable** — good for shell-level secrets management
3. **Saved token file** — run `:TodoistLogin` to paste and save your token securely to disk

To remove a saved token: `:TodoistLogout`

---

## Configuration

Pass options to `require("todoist").setup({})`. All keys are optional.

```lua
require("todoist").setup({
  -- Your Todoist API token
  -- Get from: https://app.todoist.com/app/settings/integrations/developer
  token = nil,

  -- Which UI to use: "custom" (recommended floating window) or "fzf"
  today_view_ui = "custom",

  -- Default project ID to filter on open (nil = show all projects)
  default_project = nil,

  -- Global keymaps registered on setup() (see Keymaps section)
  keymaps = {
    enable = true,
    mappings = {
      open_tasks = "<leader>to",
      login      = "<leader>tl",
      logout     = "<leader>tL",
    },
  },

  -- curl binary to use for API requests
  curl_bin = "curl",

  -- Override the notification handler (defaults to vim.notify)
  notify = vim.notify,
})
```

---

## Task View

Toggle the task view with `<leader>to` (or `:TodoistTasks`). Pressing `<leader>to` again closes it.

Tasks are displayed in a floating window grouped by project, ordered to match the Todoist app's
`child_order` field. Within each project, active tasks are shown first, indented to reflect their
parent–child hierarchy. Completed tasks appear at the bottom of each project section when
`<leader>ts` is toggled on.

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
| `<leader>td` | Delete task under cursor (with confirmation) |
| `<leader>tr` | Refresh task list from API |
| `<leader>ts` | Toggle display of completed tasks |
| `<leader>tmu` | Move task up within its siblings (respects parent boundary) |
| `<leader>tmd` | Move task down within its siblings (respects parent boundary) |
| `<leader>wx` | Close the task view |

### Search

Press `/` to use Vim's native search. Task content, descriptions, project headers, and due dates
are all searchable since they are real buffer lines.

| Key | Action |
|-----|--------|
| `/pattern<CR>` | Search and jump to first match |
| `n` / `N` | Jump to next / previous match |
| `:noh` | Clear search highlights |

All task action keymaps work normally during and after search.

### Visual Mode & Yanking

Standard visual mode (`v`, `V`, `<C-v>`) and yanking (`y`) work normally in the task view.

---

## Create Task Window

Open with `<leader>tn` from the task view.

```
╭─────────────────────── New Task ───────────────────────╮
│  Project                                               │
│  Work                                                  │
│  ─────────────────────────────────────────────────     │
│  Parent Task                                           │
│  None                                                  │
│  ─────────────────────────────────────────────────     │
│  Title                                                 │
│  ▎                                                     │
│  ─────────────────────────────────────────────────     │
│  Due Date                                              │
│                                                        │
│  ─────────────────────────────────────────────────     │
│  Description                                           │
│                                                        │
╰── :w save · <leader>tp project · <leader>ta parent · :q close ──╯
```

| Key | Action |
|-----|--------|
| `:w` | Save and create the task |
| `<leader>tp` | Open project picker |
| `<leader>ta` | Open parent task picker (filtered to the selected project) |
| `:q` | Discard and close |

**Due date** accepts any natural-language string Todoist understands: `today`, `tomorrow`,
`next monday`, `Jan 15`, `every day`, etc. Leave the field blank to create a task with no due date.

---

## Edit Task Window

Open with `<leader>te` while the cursor is on a task. The window is pre-populated with the task's
current title, due date, and description.

```
╭─────────────────────── Edit Task ───────────────────────────────╮
│  Project                                                        │
│  Work                                                           │
│  ────────────────────────────────────────────────────────────── │
│  Parent Task                                                    │
│  Q3 planning                                                    │
│  ────────────────────────────────────────────────────────────── │
│  Title                                                          │
│  Write weekly update                                            │
│  ────────────────────────────────────────────────────────────── │
│  Due Date                                                       │
│  friday                                                         │
│  ────────────────────────────────────────────────────────────── │
│  Description                                                    │
│  Include metrics from last sprint                               │
╰── :w save · <leader>tp project · <leader>ta parent · :q close ──╯
```

| Key | Action |
|-----|--------|
| `:w` | Save changes |
| `<leader>tp` | Change project (uses the Todoist move endpoint) |
| `<leader>ta` | Change parent task, or pick "None" for top-level |
| `:q` | Discard and close |

**Clearing the due date**: erase the due date line and save — the plugin sends Todoist's `"no date"`
magic string to remove it.

**Changing the project** automatically clears the selected parent task, since the parent must belong
to the same project.

**Editing a completed task**: if the task was completed and its parent is not locally cached,
the plugin fetches the parent from the API to show it correctly in the editor.

---

## Global Keymaps

Set automatically during `setup()`. Registered under `<leader>t` in which-key (if installed).

| Key | Action |
|-----|--------|
| `<leader>to` | Toggle task view (open if closed, close if open) |
| `<leader>tl` | Login (`:TodoistLogin`) |
| `<leader>tL` | Logout (`:TodoistLogout`) |

### Disabling / Customizing

Disable all automatic keymaps:

```lua
require("todoist").setup({
  keymaps = { enable = false },
})
```

Disable or remap individual keys:

```lua
require("todoist").setup({
  keymaps = {
    mappings = {
      open_tasks = "<leader>to",
      login      = false,  -- disable this keymap
      logout     = false,
    },
  },
})
```

---

## Commands

| Command | Description |
|---------|-------------|
| `:TodoistTasks [project_id]` | Open the task view (optional project ID filter) |
| `:TodoistLogin` | Prompt for API token and save it securely to disk |
| `:TodoistLogout` | Delete the saved token file |
| `:TodoistComplete <task_id>` | Complete a task by its ID |

---

## API

The plugin targets the [Todoist REST API v1](https://developer.todoist.com/rest/v1/) and uses
cursor-based pagination to fetch all tasks regardless of how many you have.

All requests are made asynchronously via `vim.fn.jobstart` + `curl`. The UI stays responsive
during loads; a spinner appears in the task buffer while a refresh is in progress.

---

## Security

- `:TodoistLogin` uses `vim.ui.input` with `secret = true` — the token is never echoed to the screen
- The token file is written with `0600` permissions under `stdpath('data')/todoist/`
- Setting `TODOIST_API_TOKEN` in the environment avoids writing any file at all
- The inline `token = "..."` config option is convenient but stores the secret in your config file;
  use the env var or `:TodoistLogin` to avoid committing it

---

## Credits

Originally forked from [mshiyaf/todoist.nvim](https://github.com/mshiyaf/todoist.nvim).

---

## License

MIT
