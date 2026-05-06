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
  local indent = string.rep("  ", (depth or 0) + 1)
  local due_suffix = ""
  if task.due and type(task.due) == "table" then
    local label = task.due.string or task.due.date
    if label and label ~= "" then
      due_suffix = " @" .. label
    end
  end
  return indent .. (task.content or "(no content)") .. due_suffix
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
    vim.api.nvim_win_set_option(win, 'wrap', false)
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
    table.sort(nodes, function(a, b) return (a.priority or 1) > (b.priority or 1) end)
    for _, t in ipairs(nodes) do
      if #t.children > 0 then sort_tree(t.children) end
    end
  end
  sort_tree(roots)

  return roots
end

-- Group tasks by project; returns ordered list of groups with .roots (tree)
local function group_tasks_by_project(tasks, project_lookup)
  local group_map = {}
  local group_order = {}

  for _, task in ipairs(tasks or {}) do
    local pid = tostring(task.project_id or "inbox")
    if not group_map[pid] then
      local project = project_lookup and project_lookup[pid]
      local name, color
      if project then
        name  = project.name
        color = project.color
      else
        name  = task.project_id and ("Project " .. task.project_id) or "Inbox"
        color = project_color_to_ansi("charcoal")
      end
      group_map[pid] = { project_name = name, project_color = color, tasks = {} }
      table.insert(group_order, pid)
    end
    table.insert(group_map[pid].tasks, task)
  end

  table.sort(group_order, function(a, b)
    return (group_map[a].project_name or ""):lower() < (group_map[b].project_name or ""):lower()
  end)

  local groups = {}
  for _, pid in ipairs(group_order) do
    local g = group_map[pid]
    g.roots = build_task_tree(g.tasks)
    table.insert(groups, g)
  end
  return groups
end

-- Recursively render a task tree into lines/line_map
local function render_tree(nodes, depth, lines, line_map, line_num, task_map)
  for _, task in ipairs(nodes) do
    -- Task line
    local line = format_task_entry(task, depth)
    table.insert(lines, line)
    line_map[line_num] = { type = "task", task_id = task.id, task = task, depth = depth }
    if task.id then
      task_map[tostring(task.id)] = task
    end
    line_num = line_num + 1

    -- Inline description (non-empty, non-blank lines only)
    if task.description and task.description ~= "" then
      local desc_indent = string.rep("  ", (depth or 0) + 2) .. "↳ "
      for desc_line in (task.description .. "\n"):gmatch("([^\n]*)\n") do
        if desc_line ~= "" then
          table.insert(lines, desc_indent .. desc_line)
          line_map[line_num] = { type = "description" }
          line_num = line_num + 1
        end
      end
    end

    -- Children (indented one level deeper)
    if task.children and #task.children > 0 then
      line_num = render_tree(task.children, depth + 1, lines, line_map, line_num, task_map)
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
local function render_grouped_tasks(buf, tasks, project_lookup)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return {}, {}, {}
  end

  local lines    = {}
  local task_map = {}
  local line_map = {}
  local line_num = 1

  local groups   = group_tasks_by_project(tasks, project_lookup)
  local has_tasks = false

  for _, group in ipairs(groups) do
    if #group.tasks > 0 then
      has_tasks = true

      local header = format_project_header(group.project_name, count_tasks(group.roots))
      table.insert(lines, header)
      line_map[line_num] = {
        type = "header",
        project_name  = group.project_name,
        project_color = group.project_color,
      }
      line_num = line_num + 1

      line_num = render_tree(group.roots, 0, lines, line_map, line_num, task_map)

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
        local task     = line_info.task
        local line     = lines[line_num]
        if not line then goto continue end

        local priority = task.priority or 1
        local hl_group = "TodoistP" .. priority

        -- Whole line gets the priority color
        pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl_group, line_idx, 0, -1)

        -- Due time overrides with its own color
        local ts, te = line:find("@[^%s]+")
        if ts then
          pcall(vim.api.nvim_buf_add_highlight, buf, ns, "TodoistDueTime", line_idx, ts - 1, te)
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
  local target     = current + delta
  local line_count = vim.api.nvim_buf_line_count(state_obj.buf)

  target = math.max(1, math.min(target, line_count))

  local has_tasks = false
  for _, info in pairs(state_obj.line_map) do
    if info.type == "task" then has_tasks = true; break end
  end

  if not has_tasks then
    vim.api.nvim_win_set_cursor(state_obj.win, { math.max(1, math.min(2, line_count)), 0 })
    return
  end

  local max_iter  = line_count + 1
  local iter      = 0
  while target >= 1 and target <= line_count and iter < max_iter do
    local info = state_obj.line_map[target]
    if info and info.type == "task" then break end
    target = target + (delta > 0 and 1 or -1)
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

  vim.keymap.set('n', 'j',      function() move_cursor(state_obj,  1)          end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', 'k',      function() move_cursor(state_obj, -1)          end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<Down>', function() move_cursor(state_obj,  1)          end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<Up>',   function() move_cursor(state_obj, -1)          end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', 'gg',     function() move_cursor(state_obj, -math.huge)  end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', 'G',      function() move_cursor(state_obj,  math.huge)  end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<C-d>',  function() move_cursor(state_obj,  10)         end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<C-u>',  function() move_cursor(state_obj, -10)         end, { buffer = buf, noremap = true, silent = true })
end

local function fuzzy_match(query, text)
  if not query or query == "" then return true, 1000 end
  query = query:lower()
  text  = text:lower()
  local pos = text:find(query, 1, true)
  if pos then return true, 1000 - pos end
  return false, 0
end

local function search_tasks(tasks, query, project_lookup)
  if not query or query == "" then return tasks end

  local results = {}
  for _, task in ipairs(tasks) do
    local project = resolve_project(task, project_lookup)
    local searchable = table.concat({
      task.content or "",
      task.description or "",
      project.name or "",
      "P" .. (task.priority or 1),
      (task.due and type(task.due) == "table" and task.due.string) or "",
    }, " ")
    local matches, score = fuzzy_match(query, searchable)
    if matches then table.insert(results, { task = task, score = score }) end
  end

  table.sort(results, function(a, b) return a.score > b.score end)

  local filtered = {}
  for _, item in ipairs(results) do table.insert(filtered, item.task) end
  return filtered
end

local function refresh_ui(state_obj)
  if not state_obj or not vim.api.nvim_buf_is_valid(state_obj.buf) then return end

  local tasks_to_display = state_obj.search_mode and state_obj.filtered_tasks or state_obj.tasks

  local line_map, task_map, lines = render_grouped_tasks(state_obj.buf, tasks_to_display, state_obj.project_lookup)
  state_obj.line_map = line_map
  state_obj.task_map = task_map

  apply_highlights(state_obj.buf, lines, line_map)

  if state_obj.search_mode then
    local search_line = string.format("Search: %s_", state_obj.search_query)
    vim.api.nvim_buf_set_option(state_obj.buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(state_obj.buf, 0, 1, false, { search_line })
    vim.api.nvim_buf_set_option(state_obj.buf, 'modifiable', false)

    local new_map = { [1] = { type = "search_prompt" } }
    for n, info in pairs(line_map) do new_map[n + 1] = info end
    state_obj.line_map = new_map
  end

  vim.schedule(function()
    move_cursor(state_obj, state_obj.search_mode and 1 or 0)
  end)
end

local function refresh_with_loader(state_obj)
  if state_obj.is_loading then
    vim.notify("Refresh already in progress...", vim.log.levels.INFO)
    return
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
  client.fetch_tasks(token, { filter = "today" }, function(err, tasks)
    if err then
      loader.stop(state_obj.loader_id)
      state_obj.is_loading = false
      vim.notify("Failed to fetch tasks: " .. err, vim.log.levels.ERROR)
      return
    end

    client.fetch_projects(token, function(project_err, projects)
      loader.stop(state_obj.loader_id)
      state_obj.is_loading = false

      if project_err then
        vim.notify("Warning: Failed to fetch projects: " .. project_err, vim.log.levels.WARN)
      end

      local project_lookup = build_project_lookup(projects)
      state_obj.tasks          = tasks or {}
      state_obj.filtered_tasks = tasks or {}
      state_obj.project_lookup = project_lookup

      refresh_ui(state_obj)
      vim.notify("Tasks refreshed", vim.log.levels.INFO)
    end)
  end)
end

local function enter_search_mode(state_obj)
  state_obj.search_mode    = true
  state_obj.search_query   = ""
  state_obj.filtered_tasks = state_obj.tasks

  refresh_ui(state_obj)

  local buf = state_obj.buf

  for i = 32, 126 do
    local char = string.char(i)
    vim.keymap.set('n', char, function()
      state_obj.search_query   = state_obj.search_query .. char
      state_obj.filtered_tasks = search_tasks(state_obj.tasks, state_obj.search_query, state_obj.project_lookup)
      refresh_ui(state_obj)
    end, { buffer = buf, noremap = true, silent = true })
  end

  vim.keymap.set('n', '<BS>', function()
    if #state_obj.search_query > 0 then
      state_obj.search_query   = state_obj.search_query:sub(1, -2)
      state_obj.filtered_tasks = search_tasks(state_obj.tasks, state_obj.search_query, state_obj.project_lookup)
      refresh_ui(state_obj)
    end
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set('n', '<Esc>', function()
    exit_search_mode(state_obj)
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set('n', '<CR>', function()
    state_obj.search_mode = false
    refresh_ui(state_obj)
    setup_navigation(state_obj)
    setup_actions(state_obj)
  end, { buffer = buf, noremap = true, silent = true })
end

function exit_search_mode(state_obj)
  state_obj.search_mode    = false
  state_obj.search_query   = ""
  state_obj.filtered_tasks = state_obj.tasks
  refresh_ui(state_obj)
  setup_navigation(state_obj)
  setup_actions(state_obj)
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

-- Floating editor for task title + description
local function open_edit_window(task, state_obj)
  local total_w = vim.o.columns
  local total_h = vim.o.lines
  local width   = math.floor(total_w * 0.60)
  local height  = math.floor(total_h * 0.55)
  local row     = math.floor((total_h - height) / 2)
  local col     = math.floor((total_w - width) / 2)

  -- Edit window highlight groups
  vim.api.nvim_set_hl(0, "TodoistEditTitle", { fg = "#f8f8f2", bold = true })
  vim.api.nvim_set_hl(0, "TodoistEditSep",   { fg = "#44475a" })
  vim.api.nvim_set_hl(0, "TodoistEditLabel", { fg = "#6272a4", italic = true })

  local buf = vim.api.nvim_create_buf(false, true)
  pcall(function()
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
  end)

  -- Layout: line 1 = title, lines 2+ = description (no blank separator)
  local desc_text = (task.description or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  local initial = { task.content or "" }
  if desc_text ~= "" then
    for line in (desc_text .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(initial, line)
    end
  else
    table.insert(initial, "")
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial)

  local ns = vim.api.nvim_create_namespace("todoist_edit_ui")

  -- Highlight entire title line
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    line_hl_group = "TodoistEditTitle",
  })
  -- "Title" label right-aligned on line 1
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    virt_text     = { { "  Title  ", "TodoistEditLabel" } },
    virt_text_pos = "right_align",
    priority      = 100,
  })
  -- Visual separator + Description label between title and description (virtual lines, not real)
  local sep_text = string.rep("─", width - 2)
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    virt_lines = {
      { { sep_text,          "TodoistEditSep"   } },
      { { "  Description",   "TodoistEditLabel" } },
    },
    virt_lines_above = false,
  })

  local win_opts = {
    relative  = "editor",
    width     = width, height = height, row = row, col = col,
    style     = "minimal", border = "rounded",
    title     = " Edit Task ", title_pos = "center",
  }
  pcall(function()
    win_opts.footer     = "  <leader>w  save    q  discard  "
    win_opts.footer_pos = "center"
  end)

  local win = vim.api.nvim_open_win(buf, true, win_opts)
  pcall(vim.api.nvim_win_set_option, win, 'wrap', true)
  pcall(vim.api.nvim_win_set_option, win, 'linebreak', true)
  pcall(vim.api.nvim_win_set_option, win, 'cursorline', true)

  -- Cursor at end of title, enter insert mode
  vim.api.nvim_win_set_cursor(win, { 1, #initial[1] })
  vim.cmd("startinsert!")

  local function save_and_close()
    local lines       = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_content = vim.trim(lines[1] or "")
    if new_content == "" then
      vim.notify("Task title cannot be empty", vim.log.levels.WARN)
      return
    end

    -- Description = lines 2+ (no blank separator line to skip)
    local desc_parts = {}
    for i = 2, #lines do table.insert(desc_parts, lines[i]) end
    while #desc_parts > 0 and vim.trim(desc_parts[#desc_parts]) == "" do
      table.remove(desc_parts)
    end
    local new_description = table.concat(desc_parts, "\n")

    pcall(vim.api.nvim_win_close, win, true)

    local updates = {}
    if new_content ~= (task.content or "") then
      updates.content = new_content
    end
    if new_description ~= (task.description or "") then
      updates.description = new_description
    end

    if not next(updates) then return end
    update_task_field(task.id, updates, state_obj)
  end

  -- Normal mode only — no insert-mode <leader>w to prevent accidental save while typing
  vim.keymap.set('n', '<leader>w', save_and_close,
    { buffer = buf, noremap = true, silent = true })
  -- q closes without saving; <Esc> is intentionally NOT mapped so it just exits insert mode
  vim.keymap.set('n', 'q', function()
    pcall(vim.api.nvim_win_close, win, true)
  end, { buffer = buf, noremap = true, silent = true })
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
    local init = require("todoist.init")
    init.complete_task(task.id, function(close_err)
      if close_err then
        vim.notify(close_err, vim.log.levels.ERROR)
        return
      end
      vim.notify(string.format("Completed task %s", task.content))
      refresh_with_loader(state_obj)
    end)

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

function update_task_field(task_id, updates, state_obj)
  local auth   = require("todoist.auth")
  local client = require("todoist.client")
  local token  = auth.load_token()
  if not token then vim.notify("No token found", vim.log.levels.ERROR); return end
  client.update_task(token, task_id, updates, function(err)
    if err then vim.notify("Update failed: " .. err, vim.log.levels.ERROR); return end
    vim.notify("Task updated", vim.log.levels.INFO)
    refresh_with_loader(state_obj)
  end)
end

function setup_actions(state_obj)
  local buf = state_obj.buf

  vim.keymap.set('n', '<CR>',        function() handle_action(state_obj, "complete") end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<leader>te', function() handle_action(state_obj, "edit")     end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<leader>tx', function() handle_action(state_obj, "delete")   end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '<leader>tr', function() refresh_with_loader(state_obj)        end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set('n', '/',          function() enter_search_mode(state_obj)          end, { buffer = buf, noremap = true, silent = true })
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

  local line_map, task_map, lines = render_grouped_tasks(layout.buf, tasks, project_lookup)
  if not line_map then
    vim.notify("Failed to render task list", vim.log.levels.ERROR)
    return
  end

  apply_highlights(layout.buf, lines, line_map)

  state = {
    buf            = layout.buf,
    win            = layout.win,
    tasks          = tasks or {},
    filtered_tasks = tasks or {},
    line_map       = line_map,
    task_map       = task_map,
    project_lookup = project_lookup,
    search_mode    = false,
    search_query   = "",
    is_loading     = false,
    loader_id      = nil,
    on_refresh     = opts.on_refresh,
    on_complete    = opts.on_complete,
  }

  local timestamp = vim.fn.localtime()
  pcall(vim.api.nvim_buf_set_name, layout.buf, string.format("todoist://today-%d", timestamp))

  setup_navigation(state)
  setup_actions(state)
  setup_autocmds(state)

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
  end, { buffer = layout.buf, noremap = true, silent = true })

  -- Close
  vim.keymap.set('n', 'q', function()
    if state.augroup then
      pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
    end
    if vim.api.nvim_win_is_valid(state.win) then
      pcall(vim.api.nvim_win_close, state.win, true)
    end
  end, { buffer = layout.buf, noremap = true, silent = true })

  vim.schedule(function()
    move_cursor(state, 0)
  end)
end

return M
