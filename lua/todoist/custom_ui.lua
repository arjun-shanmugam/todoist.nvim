local M = {}

-- Priority color codes
local priority_colors = {
  [4] = 196, -- urgent
  [3] = 208, -- high
  [2] = 39,  -- medium
  [1] = 245, -- normal
}

-- Project color map
local project_color_map = {
  berry_red = 161, red = 196, orange = 208, yellow = 226,
  olive_green = 100, lime_green = 118, green = 34, mint_green = 121,
  teal = 30, sky_blue = 81, light_blue = 39, blue = 27,
  grape = 171, violet = 135, lavender = 183, magenta = 201,
  salmon = 209, charcoal = 240, grey = 247, taupe = 244,
}

-- Module-local state
local state = nil

-- Path for the plain-text mirror file (used for ClaudeCode send)
local mirror_path = vim.fn.stdpath("data") .. "/todoist/tasks_mirror.txt"

local function project_color_to_ansi(color)
  if not color then return nil end
  if type(color) == "number" then return color end
  return project_color_map[color]
end

local function build_project_lookup(projects)
  local lookup = {}
  if projects then
    for _, project in ipairs(projects) do
      if project.id then
        lookup[tostring(project.id)] = {
          name = project.name or ("Project " .. project.id),
          color = project_color_to_ansi(project.color),
        }
      end
    end
  end
  lookup.inbox = lookup.inbox or { name = "Inbox", color = project_color_to_ansi("charcoal") }
  return lookup
end

local function resolve_project(task, lookup)
  local fallback = {
    name = task.project_id and ("Project " .. task.project_id) or "Inbox",
    color = project_color_to_ansi("charcoal"),
  }
  if not lookup then return fallback end
  local project = lookup[tostring(task.project_id)]
  if project then
    return { name = project.name or fallback.name, color = project.color or fallback.color }
  end
  if not task.project_id and lookup.inbox then
    return { name = lookup.inbox.name or fallback.name, color = lookup.inbox.color or fallback.color }
  end
  return fallback
end

local function ansi_to_hex(ansi_code)
  local map = {
    [196] = "#ff0000", [208] = "#ff8700", [39]  = "#00afff", [245] = "#8a8a8a",
    [161] = "#d7005f", [226] = "#ffff00", [100] = "#878700", [118] = "#87ff00",
    [34]  = "#00af00", [121] = "#87ffaf", [30]  = "#008787", [81]  = "#5fd7ff",
    [27]  = "#005fff", [171] = "#d75fff", [135] = "#af5fff", [183] = "#d7afff",
    [201] = "#ff00ff", [209] = "#ff875f", [240] = "#585858", [247] = "#9e9e9e",
    [244] = "#808080",
  }
  return map[ansi_code] or "#ffffff"
end

local function setup_highlights()
  local cfg = require("todoist.config").get()
  local hl_cfg = (cfg.custom_ui or {}).highlights or {}

  vim.api.nvim_set_hl(0, "TodoistP4", hl_cfg.priority_4 or { fg = "#ff5555", bold = true })
  vim.api.nvim_set_hl(0, "TodoistP3", hl_cfg.priority_3 or { fg = "#ffb86c", bold = true })
  vim.api.nvim_set_hl(0, "TodoistP2", hl_cfg.priority_2 or { fg = "#8be9fd" })
  vim.api.nvim_set_hl(0, "TodoistP1", hl_cfg.priority_1 or { fg = "#6272a4" })
  vim.api.nvim_set_hl(0, "TodoistDueTime",    hl_cfg.due_time or { fg = "#ff79c6" })
  vim.api.nvim_set_hl(0, "TodoistDescription", { fg = "#6272a4", italic = true })
  vim.api.nvim_set_hl(0, "TodoistSeparator",  { fg = "#44475a" })
  vim.api.nvim_set_hl(0, "TodoistCompleted",  { fg = "#44475a", strikethrough = true })
end

-- Write plain-text mirror of the buffer lines for ClaudeCode send
local function write_mirror_file(lines)
  vim.fn.mkdir(vim.fn.fnamemodify(mirror_path, ":h"), "p")
  local f = io.open(mirror_path, "w")
  if f then
    f:write(table.concat(lines, "\n"))
    f:close()
  end
end

-- Format a single task line; depth controls indentation for child tasks
local function format_task_entry(task, depth)
  local indent   = string.rep("  ", (depth or 0) + 1)
  local checkbox = task.checked and "[x] " or "[ ] "
  local due_suffix = ""
  if task.due and type(task.due) == "table" then
    local label = task.due.string or task.due.date
    if label and label ~= "" then
      due_suffix = " @" .. label
    end
  end
  return indent .. checkbox .. (task.content or "(no content)") .. due_suffix
end

-- Format project section header
local function format_project_header(name, count)
  return string.format("━━━ %s (%d tasks) ━━━", name, count)
end

-- Create a floating window centered on the screen; returns { buf, win }
local function create_window()
  local total_w = vim.o.columns
  local total_h = vim.o.lines
  local width  = math.floor(total_w * 0.78)
  local height = math.floor(total_h * 0.80)
  local row    = math.floor((total_h - height) / 2)
  local col    = math.floor((total_w - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  if not vim.api.nvim_buf_is_valid(buf) then
    vim.notify("Failed to create Todoist buffer", vim.log.levels.ERROR)
    return nil
  end

  pcall(function()
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'filetype', 'todoist')
  end)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
    title    = " Todoist ",
    title_pos = "center",
  })

  pcall(function()
    vim.api.nvim_win_set_option(win, 'number', false)
    vim.api.nvim_win_set_option(win, 'relativenumber', false)
    vim.api.nvim_win_set_option(win, 'cursorline', true)
    vim.api.nvim_win_set_option(win, 'wrap', true)
    vim.api.nvim_win_set_option(win, 'linebreak', true)
    vim.api.nvim_win_set_option(win, 'breakindent', true)
  end)

  return { buf = buf, win = win }
end

-- Build a tree (attach children to parents) within a flat task list.
-- Tasks whose parent is not in the list are treated as roots.
local function build_task_tree(tasks)
  local by_id = {}
  for _, task in ipairs(tasks) do
    task.children = {}
    by_id[tostring(task.id)] = task
  end

  local roots = {}
  for _, task in ipairs(tasks) do
    if task.parent_id then
      local parent = by_id[tostring(task.parent_id)]
      if parent then
        table.insert(parent.children, task)
      else
        table.insert(roots, task)
      end
    else
      table.insert(roots, task)
    end
  end

  local function sort_tree(nodes)
    table.sort(nodes, function(a, b)
      if (not a.checked) ~= (not b.checked) then return not a.checked end
      return (a.child_order or 0) < (b.child_order or 0)
    end)
    for _, t in ipairs(nodes) do
      if #t.children > 0 then sort_tree(t.children) end
    end
  end
  sort_tree(roots)

  return roots
end

-- Group tasks by project; returns ordered list of groups.
-- Each group has .roots built from ALL tasks (active + completed) in the tree.
local function group_tasks_by_project(tasks, project_lookup)
  local group_map = {}
  local group_order = {}

  for _, task in ipairs(tasks or {}) do
    local pid = tostring(task.project_id or "inbox")
    if not group_map[pid] then
      local project = project_lookup and project_lookup[pid]
      local name = project and project.name or (task.project_id and ("Project " .. task.project_id) or "Inbox")
      local color = project and project.color or project_color_to_ansi("charcoal")
      group_map[pid] = { project_name = name, project_color = color, all = {} }
      table.insert(group_order, pid)
    end
    table.insert(group_map[pid].all, task)
  end

  table.sort(group_order, function(a, b)
    return (group_map[a].project_name or ""):lower() < (group_map[b].project_name or ""):lower()
  end)

  local groups = {}
  for _, pid in ipairs(group_order) do
    local g = group_map[pid]
    g.roots = build_task_tree(g.all)
    table.insert(groups, g)
  end
  return groups
end

-- Recursively render a task tree into lines/line_map
-- expanded_tasks: set (table keyed by task id string) of tasks whose descriptions are visible
local function render_tree(nodes, depth, lines, line_map, line_num, task_map, expanded_tasks)
  for _, task in ipairs(nodes) do
    -- Task line
    local line = format_task_entry(task, depth)
    table.insert(lines, line)
    line_map[line_num] = { type = "task", task_id = task.id, task = task, depth = depth }
    if task.id then
      task_map[tostring(task.id)] = task
    end
    line_num = line_num + 1

    -- Inline description — only when task is expanded
    if task.description and task.description ~= ""
      and expanded_tasks and expanded_tasks[tostring(task.id)]
    then
      local base_indent = string.rep("  ", (depth or 0) + 2)
      local first_line = true
      for desc_line in (task.description .. "\n"):gmatch("([^\n]*)\n") do
        if desc_line ~= "" then
          local prefix = first_line and (base_indent .. "↳ ") or (base_indent .. "  ")
          table.insert(lines, prefix .. desc_line)
          line_map[line_num] = { type = "description" }
          line_num = line_num + 1
          first_line = false
        end
      end
    end

    -- Children (indented one level deeper)
    if task.children and #task.children > 0 then
      line_num = render_tree(task.children, depth + 1, lines, line_map, line_num, task_map, expanded_tasks)
    end
  end
  return line_num
end

-- Count all tasks in a group recursively (for header count)
local function count_tasks(nodes)
  local n = 0
  for _, task in ipairs(nodes) do
    n = n + 1
    if task.children then n = n + count_tasks(task.children) end
  end
  return n
end

-- Render all tasks into buf; returns line_map, task_map, lines
local function render_grouped_tasks(buf, tasks, project_lookup, expanded_tasks)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return {}, {}, {}
  end

  local lines    = {}
  local task_map = {}
  local line_map = {}
  local line_num = 1
  local has_tasks = false

  local groups = group_tasks_by_project(tasks, project_lookup)

  for _, group in ipairs(groups) do
    local n_total = count_tasks(group.roots)
    if n_total > 0 then
      has_tasks = true

      local header = format_project_header(group.project_name, n_total)
      table.insert(lines, header)
      line_map[line_num] = {
        type = "header",
        project_name  = group.project_name,
        project_color = group.project_color,
      }
      line_num = line_num + 1

      -- Render all tasks (active and completed) in their natural hierarchy
      line_num = render_tree(group.roots, 0, lines, line_map, line_num, task_map, expanded_tasks)

      table.insert(lines, "")
      line_map[line_num] = { type = "separator" }
      line_num = line_num + 1
    end
  end

  if not has_tasks then
    lines    = { "", "  No tasks found", "" }
    line_map = { [1] = { type = "empty" }, [2] = { type = "empty" }, [3] = { type = "empty" } }
  end

  local ok, err = pcall(function()
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  end)

  if not ok then
    vim.notify("Error rendering tasks: " .. tostring(err), vim.log.levels.ERROR)
    return {}, {}, {}
  end

  -- Keep plain-text mirror in sync for ClaudeCode send
  write_mirror_file(lines)

  return line_map, task_map, lines
end

-- Apply syntax highlights to the buffer
local function apply_highlights(buf, lines, line_map)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local ns = vim.api.nvim_create_namespace("todoist_custom_ui")
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)

  for line_num, line_info in pairs(line_map) do
    local line_idx = line_num - 1
    if line_idx >= 0 and line_idx < #lines then
      if line_info.type == "header" then
        local hex     = ansi_to_hex(line_info.project_color or 240)
        local hl_name = "TodoistProjectHeader_" .. hex:gsub("#", "")
        pcall(vim.api.nvim_set_hl, 0, hl_name, { fg = hex, bold = true })
        pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl_name, line_idx, 0, -1)

      elseif line_info.type == "task" then
        local task = line_info.task
        local line = lines[line_num]
        if not line then goto continue end

        if task.checked then
          pcall(vim.api.nvim_buf_add_highlight, buf, ns, "TodoistCompleted", line_idx, 0, -1)
        else
          local hl_group = "TodoistP" .. (task.priority or 1)
          pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl_group, line_idx, 0, -1)
          local ts, te = line:find("@[^%s]+")
          if ts then
            pcall(vim.api.nvim_buf_add_highlight, buf, ns, "TodoistDueTime", line_idx, ts - 1, te)
          end
        end

      elseif line_info.type == "description" then
        pcall(vim.api.nvim_buf_add_highlight, buf, ns, "TodoistDescription", line_idx, 0, -1)
      end
      ::continue::
    end
  end
end

-- Move cursor, skipping non-task lines (headers, separators, descriptions)
local function move_cursor(state_obj, delta)
  if not state_obj or not vim.api.nvim_win_is_valid(state_obj.win) then return end

  local cursor     = vim.api.nvim_win_get_cursor(state_obj.win)
  local current    = cursor[1]
  local line_count = vim.api.nvim_buf_line_count(state_obj.buf)

  local has_tasks = false
  for _, info in pairs(state_obj.line_map) do
    if info.type == "task" then has_tasks = true; break end
  end

  if not has_tasks then
    vim.api.nvim_win_set_cursor(state_obj.win, { math.max(1, math.min(2, line_count)), 0 })
    return
  end

  local target, scan_dir
  if delta == math.huge then
    target   = line_count
    scan_dir = -1  -- scan backwards from end to find last task
  elseif delta == -math.huge then
    target   = 1
    scan_dir = 1   -- scan forwards from start to find first task
  else
    target   = math.max(1, math.min(current + delta, line_count))
    scan_dir = delta > 0 and 1 or -1
  end

  local max_iter = line_count + 1
  local iter     = 0
  while target >= 1 and target <= line_count and iter < max_iter do
    local info = state_obj.line_map[target]
    if info and info.type == "task" then break end
    target = target + scan_dir
    iter   = iter + 1
  end

  if target >= 1 and target <= line_count then
    local info = state_obj.line_map[target]
    if info and info.type == "task" then
      vim.api.nvim_win_set_cursor(state_obj.win, { target, 0 })
    end
  end
end

local function setup_navigation(state_obj)
  local buf = state_obj.buf
  local o   = { buffer = buf, noremap = true, silent = true }

  vim.keymap.set('n', 'j',      function() move_cursor(state_obj,  vim.v.count1) end, vim.tbl_extend("force", o, { desc = "Next task"      }))
  vim.keymap.set('n', 'k',      function() move_cursor(state_obj, -vim.v.count1) end, vim.tbl_extend("force", o, { desc = "Prev task"      }))
  vim.keymap.set('n', '<Down>', function() move_cursor(state_obj,  vim.v.count1) end, vim.tbl_extend("force", o, { desc = "Next task"      }))
  vim.keymap.set('n', '<Up>',   function() move_cursor(state_obj, -vim.v.count1) end, vim.tbl_extend("force", o, { desc = "Prev task"      }))
  vim.keymap.set('n', 'gg',     function() move_cursor(state_obj, -math.huge) end, vim.tbl_extend("force", o, { desc = "First task"     }))
  vim.keymap.set('n', 'G',      function() move_cursor(state_obj,  math.huge) end, vim.tbl_extend("force", o, { desc = "Last task"      }))
  vim.keymap.set('n', '<C-d>',  function() move_cursor(state_obj,  10)        end, vim.tbl_extend("force", o, { desc = "Scroll down"    }))
  vim.keymap.set('n', '<C-u>',  function() move_cursor(state_obj, -10)        end, vim.tbl_extend("force", o, { desc = "Scroll up"      }))
end

local function refresh_ui(state_obj)
  if not state_obj or not vim.api.nvim_buf_is_valid(state_obj.buf) then return end

  local line_map, task_map, lines = render_grouped_tasks(state_obj.buf, state_obj.tasks, state_obj.project_lookup, state_obj.expanded_tasks)
  state_obj.line_map = line_map
  state_obj.task_map = task_map

  apply_highlights(state_obj.buf, lines, line_map)

  vim.schedule(function()
    move_cursor(state_obj, 0)
  end)
end

local function refresh_with_loader(state_obj)
  if state_obj.is_loading then
    vim.notify("Refresh already in progress...", vim.log.levels.INFO)
    return false
  end

  state_obj.is_loading = true

  local loader = require("todoist.loader")
  state_obj.loader_id = loader.create_loader({
    ui_type = "custom",
    buffer  = state_obj.buf,
    message = "Refreshing tasks...",
  })
  loader.start(state_obj.loader_id)

  local auth  = require("todoist.auth")
  local token = auth.load_token()
  if not token then
    loader.stop(state_obj.loader_id)
    state_obj.is_loading = false
    vim.notify("No token found", vim.log.levels.ERROR)
    return
  end

  local client = require("todoist.client")
  client.fetch_tasks(token, {}, function(err, tasks)
    if err then
      loader.stop(state_obj.loader_id)
      state_obj.is_loading = false
      vim.notify("Failed to fetch tasks: " .. err, vim.log.levels.ERROR)
      return
    end

    local function finish(completed)
      client.fetch_projects(token, function(project_err, projects)
        loader.stop(state_obj.loader_id)
        state_obj.is_loading = false

        if project_err then
          vim.notify("Warning: Failed to fetch projects: " .. project_err, vim.log.levels.WARN)
        end

        -- Merge completed tasks into the main list; deduplicate by ID so a task that
        -- was just reopened (still in /tasks/completed due to eventual consistency)
        -- doesn't appear twice with conflicting checked state.
        local seen = {}
        local all_tasks = {}
        for _, t in ipairs(tasks or {}) do
          seen[tostring(t.id)] = true
          table.insert(all_tasks, t)
        end
        for _, t in ipairs(completed or {}) do
          if not seen[tostring(t.id)] then
            table.insert(all_tasks, t)
          end
        end

        local project_lookup     = build_project_lookup(projects)
        state_obj.tasks          = all_tasks
        state_obj.project_lookup = project_lookup

        refresh_ui(state_obj)
        vim.notify("Tasks refreshed", vim.log.levels.INFO)
      end)
    end

    if state_obj.show_completed then
      client.fetch_completed_tasks(token, function(cerr, completed)
        finish(cerr and {} or completed)
      end)
    else
      finish(nil)
    end
  end)
  return true
end

local function setup_autocmds(state_obj)
  local augroup = vim.api.nvim_create_augroup("TodoistCustomUI", { clear = true })
  state_obj.augroup = augroup

  -- Resize floating window when terminal is resized
  vim.api.nvim_create_autocmd("VimResized", {
    group    = augroup,
    callback = function()
      if not vim.api.nvim_win_is_valid(state_obj.win) then return end
      local total_w = vim.o.columns
      local total_h = vim.o.lines
      local width   = math.floor(total_w * 0.78)
      local height  = math.floor(total_h * 0.80)
      local row     = math.floor((total_h - height) / 2)
      local col     = math.floor((total_w - width) / 2)
      pcall(vim.api.nvim_win_set_config, state_obj.win, {
        relative = "editor", width = width, height = height, row = row, col = col,
      })
    end,
  })

  -- Cleanup on buffer unload
  vim.api.nvim_create_autocmd("BufUnload", {
    group    = augroup,
    buffer   = state_obj.buf,
    callback = function()
      if state_obj.loader_id then
        local loader = require("todoist.loader")
        loader.stop(state_obj.loader_id)
      end
    end,
  })
end

-- Shared helper: sorted list of {id, name} from project_lookup for vim.ui.select
local function project_choices(project_lookup)
  local choices = {}
  if project_lookup then
    for pid, p in pairs(project_lookup) do
      if pid ~= "inbox" then
        table.insert(choices, { id = pid, name = p.name or pid })
      end
    end
  end
  table.sort(choices, function(a, b) return (a.name):lower() < (b.name):lower() end)
  return choices
end

-- Floating window to create a new task (same UI as edit, but blank)
local function open_create_window(state_obj)
  local total_w = vim.o.columns
  local total_h = vim.o.lines
  local width   = math.floor(total_w * 0.60)
  local height  = math.floor(total_h * 0.55)
  local row     = math.floor((total_h - height) / 2)
  local col     = math.floor((total_w - width) / 2)

  vim.api.nvim_set_hl(0, "TodoistEditTitle",       { bold = true })
  vim.api.nvim_set_hl(0, "TodoistEditSep",         { fg = "#44475a" })
  vim.api.nvim_set_hl(0, "TodoistEditLabel",       { fg = "#6272a4", italic = true })
  vim.api.nvim_set_hl(0, "TodoistEditProjectName", {})
  vim.api.nvim_set_hl(0, "TodoistEditDue",         { fg = "#ff79c6" })

  local cfg = require("todoist.config").get()
  local selected_project = { id = nil, name = "Inbox" }
  if cfg.default_project and state_obj.project_lookup then
    local p = state_obj.project_lookup[tostring(cfg.default_project)]
    if p then selected_project = { id = cfg.default_project, name = p.name } end
  end
  local selected_parent = nil  -- { id, content } or nil

  local buf = vim.api.nvim_create_buf(false, false)
  pcall(vim.api.nvim_buf_set_name, buf, "todoist://new-task")
  pcall(function()
    vim.api.nvim_buf_set_option(buf, 'buftype',  'acwrite')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  end)
  -- Layout: line 0 = "  Project" (header, ignored on save)
  --         line 1 = title
  --         line 2 = due date (free text, e.g. "today", "tomorrow", "2025-12-31")
  --         lines 3+ = description
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  Project", "", "", "" })

  local ns     = vim.api.nvim_create_namespace("todoist_create_ui")
  local sep    = string.rep("─", width - 2)
  local hdr_id = nil

  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { line_hl_group = "TodoistEditLabel" })

  local function render_header()
    local parent_name = selected_parent and selected_parent.content or "None"
    local opts = {
      virt_lines = {
        { { "  " .. selected_project.name, "TodoistEditProjectName" } },
        { { sep,                            "TodoistEditSep"         } },
        { { "  Parent Task",               "TodoistEditLabel"       } },
        { { "  " .. parent_name,           "TodoistEditProjectName" } },
        { { sep,                            "TodoistEditSep"         } },
        { { "  Title",                      "TodoistEditLabel"       } },
      },
      virt_lines_above = false,
    }
    if hdr_id then opts.id = hdr_id end
    hdr_id = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, opts)
  end

  render_header()

  -- Title line + Due Date section below it
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { line_hl_group = "TodoistEditTitle" })
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, {
    virt_lines       = { { { sep, "TodoistEditSep" } }, { { "  Due Date", "TodoistEditLabel" } } },
    virt_lines_above = false,
  })
  -- Due date line + Description section below it
  vim.api.nvim_buf_set_extmark(buf, ns, 2, 0, { line_hl_group = "TodoistEditDue" })
  vim.api.nvim_buf_set_extmark(buf, ns, 2, 0, {
    virt_lines       = { { { sep, "TodoistEditSep" } }, { { "  Description", "TodoistEditLabel" } } },
    virt_lines_above = false,
  })

  local win_opts = {
    relative  = "editor", width = width, height = height, row = row, col = col,
    style     = "minimal", border = "rounded", title = " New Task ", title_pos = "center",
  }
  pcall(function()
    win_opts.footer     = "  :w save  ·  <leader>tp project  ·  <leader>ta parent  ·  :q close  "
    win_opts.footer_pos = "center"
  end)

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  pcall(vim.api.nvim_win_set_option, win, 'wrap', true)
  pcall(vim.api.nvim_win_set_option, win, 'linebreak', true)
  pcall(vim.api.nvim_win_set_option, win, 'cursorline', true)

  vim.api.nvim_win_set_cursor(win, { 2, 0 })

  local function save_and_close()
    local lines       = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_content = vim.trim(lines[2] or "")
    if new_content == "" then
      vim.notify("Task title cannot be empty", vim.log.levels.WARN)
      return
    end
    local new_due = vim.trim(lines[3] or "")
    local desc_parts = {}
    for i = 4, #lines do table.insert(desc_parts, lines[i]) end
    while #desc_parts > 0 and vim.trim(desc_parts[#desc_parts]) == "" do
      table.remove(desc_parts)
    end
    local new_description = table.concat(desc_parts, "\n")
    pcall(vim.api.nvim_win_close, win, true)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(state_obj.win) then
        vim.api.nvim_set_current_win(state_obj.win)
      end
    end)
    local token = require("todoist.auth").load_token()
    if not token then vim.notify("No token found", vim.log.levels.ERROR); return end

    local payload = { content = new_content }
    if new_due ~= "" then payload.due_string = new_due end
    if new_description ~= "" then payload.description = new_description end
    if selected_project.id then payload.project_id = selected_project.id end
    if selected_parent then payload.parent_id = selected_parent.id end

    require("todoist.client").add_task(token, payload, function(err, task)
      if err then vim.notify("Failed to create task: " .. err, vim.log.levels.ERROR); return end
      vim.notify(string.format("Created: %s", task and task.content or new_content))
      refresh_with_loader(state_obj)
    end)
  end

  local function pick_project()
    local choices = project_choices(state_obj.project_lookup)
    local names   = vim.tbl_map(function(c) return c.name end, choices)
    vim.ui.select(names, { prompt = "Select project: " }, function(choice)
      if not choice then return end
      for _, c in ipairs(choices) do
        if c.name == choice then
          selected_project = c
          selected_parent  = nil  -- clear parent; it belongs to the old project
          render_header()
          return
        end
      end
    end)
  end

  local function pick_parent()
    -- Candidates: active tasks in the currently selected project
    local candidates = {}
    for _, task in ipairs(state_obj.tasks or {}) do
      if not task.checked
        and tostring(task.project_id or "") == tostring(selected_project.id or "")
      then
        table.insert(candidates, task)
      end
    end
    table.sort(candidates, function(a, b)
      return (a.content or ""):lower() < (b.content or ""):lower()
    end)
    local names = { "  None (top-level task)" }
    for _, t in ipairs(candidates) do
      table.insert(names, "  " .. (t.content or "(no content)"))
    end
    vim.ui.select(names, { prompt = "Select parent task: " }, function(_, idx)
      if not idx then return end
      selected_parent = idx == 1 and nil or candidates[idx - 1]
      render_header()
    end)
  end

  local o = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set('n', '<leader>tp', pick_project,   vim.tbl_extend("force", o, { desc = "Todoist: change project"   }))
  vim.keymap.set('n', '<leader>ta', pick_parent,    vim.tbl_extend("force", o, { desc = "Todoist: assign parent"    }))
  local function close()
    pcall(vim.api.nvim_win_close, win, true)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(state_obj.win) then
        vim.api.nvim_set_current_win(state_obj.win)
      end
    end)
  end
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer   = buf,
    callback = function() vim.bo[buf].modified = false; save_and_close() end,
  })
  vim.api.nvim_create_autocmd("QuitPre", {
    buffer   = buf,
    callback = function() vim.bo[buf].modified = false end,
  })
end

-- Floating editor for task title + description
local function open_edit_window(task, state_obj)
  local total_w = vim.o.columns
  local total_h = vim.o.lines
  local width   = math.floor(total_w * 0.60)
  local height  = math.floor(total_h * 0.55)
  local row     = math.floor((total_h - height) / 2)
  local col     = math.floor((total_w - width) / 2)

  vim.api.nvim_set_hl(0, "TodoistEditTitle",       { bold = true })
  vim.api.nvim_set_hl(0, "TodoistEditSep",         { fg = "#44475a" })
  vim.api.nvim_set_hl(0, "TodoistEditLabel",       { fg = "#6272a4", italic = true })
  vim.api.nvim_set_hl(0, "TodoistEditProjectName", {})
  vim.api.nvim_set_hl(0, "TodoistEditDue",         { fg = "#ff79c6" })

  local selected_project = { id = task.project_id, name = "Inbox" }
  if task.project_id and state_obj.project_lookup then
    local p = state_obj.project_lookup[tostring(task.project_id)]
    if p then selected_project = { id = task.project_id, name = p.name } end
  end

  local function do_open(real_parent_id)
  local selected_parent = nil
  if real_parent_id then
    for _, t in ipairs(state_obj.tasks or {}) do
      if tostring(t.id) == tostring(real_parent_id) then
        selected_parent = { id = t.id, content = t.content }
        break
      end
    end
    if not selected_parent then
      selected_parent = { id = real_parent_id, content = "(parent task)" }
    end
  end

  -- Resolve current due date string for display
  local original_due = ""
  if task.due and type(task.due) == "table" then
    original_due = task.due.string or task.due.date or ""
  end

  local buf = vim.api.nvim_create_buf(false, false)
  pcall(vim.api.nvim_buf_set_name, buf, string.format("todoist://edit-%s", task.id))
  pcall(function()
    vim.api.nvim_buf_set_option(buf, 'buftype',  'acwrite')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  end)
  -- Layout: line 0 = "  Project" (header, ignored on save)
  --         line 1 = title
  --         line 2 = due date
  --         lines 3+ = description
  local desc_text = (task.description or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local initial   = { "  Project", task.content or "", original_due }
  if desc_text ~= "" then
    for line in (desc_text .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(initial, line)
    end
  else
    table.insert(initial, "")
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial)

  local ns     = vim.api.nvim_create_namespace("todoist_edit_ui")
  local sep    = string.rep("─", width - 2)
  local hdr_id = nil

  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { line_hl_group = "TodoistEditLabel" })

  local function render_header()
    local parent_name = selected_parent and selected_parent.content or "None"
    local opts = {
      virt_lines = {
        { { "  " .. selected_project.name, "TodoistEditProjectName" } },
        { { sep,                            "TodoistEditSep"         } },
        { { "  Parent Task",               "TodoistEditLabel"       } },
        { { "  " .. parent_name,           "TodoistEditProjectName" } },
        { { sep,                            "TodoistEditSep"         } },
        { { "  Title",                      "TodoistEditLabel"       } },
      },
      virt_lines_above = false,
    }
    if hdr_id then opts.id = hdr_id end
    hdr_id = vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, opts)
  end

  render_header()

  -- Title line + Due Date section below it
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { line_hl_group = "TodoistEditTitle" })
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, {
    virt_lines       = { { { sep, "TodoistEditSep" } }, { { "  Due Date", "TodoistEditLabel" } } },
    virt_lines_above = false,
  })
  -- Due date line + Description section below it
  vim.api.nvim_buf_set_extmark(buf, ns, 2, 0, { line_hl_group = "TodoistEditDue" })
  vim.api.nvim_buf_set_extmark(buf, ns, 2, 0, {
    virt_lines       = { { { sep, "TodoistEditSep" } }, { { "  Description", "TodoistEditLabel" } } },
    virt_lines_above = false,
  })

  local win_opts = {
    relative  = "editor", width = width, height = height, row = row, col = col,
    style     = "minimal", border = "rounded", title = " Edit Task ", title_pos = "center",
  }
  pcall(function()
    win_opts.footer     = "  :w save  ·  <leader>tp project  ·  <leader>ta parent  ·  :q close  "
    win_opts.footer_pos = "center"
  end)

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  pcall(vim.api.nvim_win_set_option, win, 'wrap', true)
  pcall(vim.api.nvim_win_set_option, win, 'linebreak', true)
  pcall(vim.api.nvim_win_set_option, win, 'cursorline', true)

  vim.api.nvim_win_set_cursor(win, { 2, 0 })

  local function save_and_close()
    local lines       = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_content = vim.trim(lines[2] or "")
    if new_content == "" then
      vim.notify("Task title cannot be empty", vim.log.levels.WARN)
      return
    end
    local new_due = vim.trim(lines[3] or "")
    local desc_parts = {}
    for i = 4, #lines do table.insert(desc_parts, lines[i]) end
    while #desc_parts > 0 and vim.trim(desc_parts[#desc_parts]) == "" do
      table.remove(desc_parts)
    end
    local new_description = table.concat(desc_parts, "\n")
    pcall(vim.api.nvim_win_close, win, true)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(state_obj.win) then
        vim.api.nvim_set_current_win(state_obj.win)
      end
    end)

    local updates = {}
    if new_content ~= (task.content or "") then updates.content = new_content end
    if new_description ~= (task.description or "") then updates.description = new_description end
    if new_due ~= original_due then
      -- "no date" is the Todoist API magic string for removing a due date
      updates.due_string = new_due ~= "" and new_due or "no date"
      -- API requires content to be present when modifying due_string
      if not updates.content then updates.content = new_content end
    end

    local new_project_id = nil
    if tostring(selected_project.id or "") ~= tostring(task.project_id or "") then
      new_project_id = selected_project.id
    end

    -- parent_id goes through /move, not the update body
    -- nil = no change, false = clear parent, string = new parent id
    local new_parent_id = nil
    local clear_parent_project_id = nil  -- project to move to when clearing parent
    if tostring(selected_parent and selected_parent.id or "") ~= tostring(task.parent_id or "") then
      if selected_parent then
        new_parent_id = selected_parent.id
      else
        new_parent_id = false
        clear_parent_project_id = selected_project.id or task.project_id
      end
    end

    if not next(updates) and not new_project_id and new_parent_id == nil then
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(state_obj.win) then
          vim.api.nvim_set_current_win(state_obj.win)
        end
      end)
      return
    end
    update_task_field(task.id, updates, new_project_id, new_parent_id, clear_parent_project_id, state_obj)
  end

  local function pick_project()
    local choices = project_choices(state_obj.project_lookup)
    local names   = vim.tbl_map(function(c) return c.name end, choices)
    vim.ui.select(names, { prompt = "Select project: " }, function(choice)
      if not choice then return end
      for _, c in ipairs(choices) do
        if c.name == choice then
          selected_project = c
          selected_parent  = nil  -- clear parent; it belongs to the old project
          render_header()
          return
        end
      end
    end)
  end

  local function pick_parent()
    local candidates = {}
    for _, t in ipairs(state_obj.tasks or {}) do
      if not t.checked
        and tostring(t.project_id or "") == tostring(selected_project.id or "")
        and tostring(t.id) ~= tostring(task.id)
      then
        table.insert(candidates, t)
      end
    end
    table.sort(candidates, function(a, b)
      return (a.content or ""):lower() < (b.content or ""):lower()
    end)
    local names = { "  None (top-level task)" }
    for _, t in ipairs(candidates) do
      table.insert(names, "  " .. (t.content or "(no content)"))
    end
    vim.ui.select(names, { prompt = "Select parent task: " }, function(_, idx)
      if not idx then return end
      selected_parent = idx == 1 and nil or candidates[idx - 1]
      render_header()
    end)
  end

  local function refocus()
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(state_obj.win) then
        vim.api.nvim_set_current_win(state_obj.win)
      end
    end)
  end

  local o = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set('n', '<leader>tp', pick_project,   vim.tbl_extend("force", o, { desc = "Todoist: change project" }))
  vim.keymap.set('n', '<leader>ta', pick_parent,    vim.tbl_extend("force", o, { desc = "Todoist: assign parent"  }))
  local function close()
    pcall(vim.api.nvim_win_close, win, true)
    refocus()
  end
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer   = buf,
    callback = function() vim.bo[buf].modified = false; save_and_close() end,
  })
  vim.api.nvim_create_autocmd("QuitPre", {
    buffer   = buf,
    callback = function() vim.bo[buf].modified = false end,
  })
  end -- do_open

  if task.checked and not task.parent_id then
    local token = require("todoist.auth").load_token()
    if token then
      require("todoist.client").get_task(token, task.id, function(err, full_task)
        vim.schedule(function()
          do_open(not err and full_task and full_task.parent_id or nil)
        end)
      end)
    else
      do_open(nil)
    end
  else
    do_open(task.parent_id)
  end
end

local function handle_action(state_obj, action_type)
  if not state_obj or not vim.api.nvim_win_is_valid(state_obj.win) then return end

  local cursor   = vim.api.nvim_win_get_cursor(state_obj.win)
  local line_num = cursor[1]
  local line_info = state_obj.line_map[line_num]

  if not line_info or line_info.type ~= "task" then
    vim.notify("No task selected", vim.log.levels.WARN)
    return
  end

  local task = line_info.task

  if action_type == "complete" then
    local auth   = require("todoist.auth")
    local client = require("todoist.client")
    local token  = auth.load_token()
    if not token then vim.notify("No token found", vim.log.levels.ERROR); return end

    if task.checked then
      client.reopen_task(token, task.id, function(err)
        if err then vim.notify("Reopen failed: " .. err, vim.log.levels.ERROR); return end
        vim.notify(string.format("Reopened: %s", task.content))
        refresh_with_loader(state_obj)
      end)
    else
      client.close_task(token, task.id, function(err)
        if err then vim.notify("Complete failed: " .. err, vim.log.levels.ERROR); return end
        vim.notify(string.format("Completed: %s", task.content))
        refresh_with_loader(state_obj)
      end)
    end

  elseif action_type == "edit" then
    open_edit_window(task, state_obj)

  elseif action_type == "delete" then
    vim.ui.select({ "Yes, delete", "Cancel" },
      { prompt = string.format("Delete '%s'?", task.content or "this task") },
      function(choice)
        if choice ~= "Yes, delete" then return end
        local auth   = require("todoist.auth")
        local client = require("todoist.client")
        local token  = auth.load_token()
        if not token then vim.notify("No token found", vim.log.levels.ERROR); return end
        client.delete_task(token, task.id, function(err)
          if err then vim.notify("Delete failed: " .. err, vim.log.levels.ERROR); return end
          vim.notify("Task deleted", vim.log.levels.INFO)
          refresh_with_loader(state_obj)
        end)
      end)
  end
end

function update_task_field(task_id, updates, new_project_id, new_parent_id, clear_parent_project_id, state_obj)
  local auth   = require("todoist.auth")
  local client = require("todoist.client")
  local token  = auth.load_token()
  if not token then vim.notify("No token found", vim.log.levels.ERROR); return end

  local function do_move_then_refresh()
    if new_parent_id ~= nil then
      local move_body = new_parent_id and { parent_id = new_parent_id }
                                       or { project_id = new_project_id or clear_parent_project_id }
      client.move_task(token, task_id, move_body, function(err)
        if err then vim.notify("Move failed: " .. err, vim.log.levels.ERROR); return end
        vim.notify("Task updated", vim.log.levels.INFO)
        refresh_with_loader(state_obj)
      end)
    elseif new_project_id then
      client.move_task(token, task_id, { project_id = new_project_id }, function(err)
        if err then vim.notify("Move failed: " .. err, vim.log.levels.ERROR); return end
        vim.notify("Task updated", vim.log.levels.INFO)
        refresh_with_loader(state_obj)
      end)
    else
      vim.notify("Task updated", vim.log.levels.INFO)
      refresh_with_loader(state_obj)
    end
  end

  if next(updates) then
    client.update_task(token, task_id, updates, function(err)
      if err then vim.notify("Update failed: " .. err, vim.log.levels.ERROR); return end
      do_move_then_refresh()
    end)
  elseif new_project_id or new_parent_id ~= nil then
    do_move_then_refresh()
  end
end

function setup_actions(state_obj)
  local buf = state_obj.buf
  local o   = { buffer = buf, noremap = true, silent = true }

  vim.keymap.set('n', '<CR>', function()
    local cursor    = vim.api.nvim_win_get_cursor(state_obj.win)
    local line_info = state_obj.line_map[cursor[1]]
    if not line_info or line_info.type ~= "task" then return end
    local task = line_info.task

    local function toggle(t)
      if not t.description or t.description == "" then return end
      local id = tostring(t.id)
      if state_obj.expanded_tasks[id] then
        state_obj.expanded_tasks[id] = nil
      else
        state_obj.expanded_tasks[id] = true
      end
      refresh_ui(state_obj)
    end

    -- Completed tasks may not have descriptions loaded; fetch on demand
    if task.checked and (not task.description or task.description == "") then
      local auth   = require("todoist.auth")
      local client = require("todoist.client")
      local token  = auth.load_token()
      if not token then return end
      client.get_task(token, task.id, function(err, full_task)
        if err or not full_task then return end
        task.description = full_task.description or ""
        for _, t in ipairs(state_obj.tasks) do
          if tostring(t.id) == tostring(task.id) then
            t.description = task.description
            break
          end
        end
        toggle(task)
      end)
    else
      toggle(task)
    end
  end, vim.tbl_extend("force", o, { desc = "Todoist: toggle description"    }))
  vim.keymap.set('n', '<leader>te', function() handle_action(state_obj, "edit")     end, vim.tbl_extend("force", o, { desc = "Todoist: edit task"              }))
  vim.keymap.set('n', '<leader>tc', function() handle_action(state_obj, "complete") end, vim.tbl_extend("force", o, { desc = "Todoist: toggle complete"        }))
  vim.keymap.set('n', '<leader>td', function() handle_action(state_obj, "delete")   end, vim.tbl_extend("force", o, { desc = "Todoist: delete task"            }))
  vim.keymap.set('n', '<leader>tr', function() refresh_with_loader(state_obj)        end, vim.tbl_extend("force", o, { desc = "Todoist: refresh"                }))
  vim.keymap.set('n', '<leader>tn', function() open_create_window(state_obj)         end, vim.tbl_extend("force", o, { desc = "Todoist: new task"               }))
  vim.keymap.set('n', '<leader>ts', function()
    state_obj.show_completed = not state_obj.show_completed
    local msg = state_obj.show_completed and "Showing completed tasks" or "Hiding completed tasks"
    if not refresh_with_loader(state_obj) then
      -- refresh blocked (is_loading); revert the toggle so state stays consistent
      state_obj.show_completed = not state_obj.show_completed
      vim.notify("Refresh in progress, try again shortly", vim.log.levels.WARN)
    else
      vim.notify(msg)
    end
  end, vim.tbl_extend("force", o, { desc = "Todoist: toggle completed tasks" }))
end

-- Main entry point
function M.show_today(tasks, opts)
  opts = opts or {}

  setup_highlights()

  local project_lookup = build_project_lookup(opts.projects)

  local layout = create_window()
  if not layout then
    vim.notify("Failed to create Todoist window", vim.log.levels.ERROR)
    return
  end

  local line_map, task_map, lines = render_grouped_tasks(layout.buf, tasks, project_lookup, {})
  if not line_map then
    vim.notify("Failed to render task list", vim.log.levels.ERROR)
    return
  end

  apply_highlights(layout.buf, lines, line_map)

  state = {
    buf            = layout.buf,
    win            = layout.win,
    tasks          = tasks or {},
    line_map       = line_map,
    task_map       = task_map,
    project_lookup = project_lookup,
    show_completed  = false,
    expanded_tasks  = {},
    is_loading      = false,
    loader_id      = nil,
    on_refresh     = opts.on_refresh,
    on_complete    = opts.on_complete,
  }

  local timestamp = vim.fn.localtime()
  pcall(vim.api.nvim_buf_set_name, layout.buf, string.format("todoist://today-%d", timestamp))

  setup_navigation(state)
  setup_actions(state)
  setup_autocmds(state)

  -- Nil state when the window is closed by any means (:q, <leader>wx, etc.)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern  = tostring(layout.win),
    once     = true,
    callback = function() state = nil end,
  })

  -- <leader>as in visual mode: send selected lines from mirror file to ClaudeCode
  vim.keymap.set('v', '<leader>as', function()
    local s  = vim.fn.line("'<")
    local e  = vim.fn.line("'>")
    local ok, cc = pcall(require, "claudecode")
    if ok then
      cc.send_at_mention(mirror_path, s - 1, e - 1)
    else
      vim.notify("ClaudeCode not available", vim.log.levels.WARN)
    end
  end, { buffer = layout.buf, noremap = true, silent = true, desc = "Todoist: send to Claude" })

  -- Close
  vim.keymap.set('n', '<leader>wx', function()
    if state.augroup then
      pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    end
    if vim.api.nvim_win_is_valid(state.win) then
      pcall(vim.api.nvim_win_close, state.win, true)
    end
  end, { buffer = layout.buf, noremap = true, silent = true, desc = "Todoist: close" })

  vim.schedule(function()
    move_cursor(state, 0)
  end)
end

function M.is_open()
  return state ~= nil and vim.api.nvim_win_is_valid(state.win or -1)
end

function M.close()
  if not M.is_open() then return end
  if state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
  end
  pcall(vim.api.nvim_win_close, state.win, true)
  state = nil
end

return M
