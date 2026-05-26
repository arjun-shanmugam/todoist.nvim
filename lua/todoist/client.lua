local config = require("todoist.config")

local M = {}

local function urlencode(str)
  return tostring(str):gsub("([^%w%-%_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function build_query(params)
  if not params or vim.tbl_isempty(params) then
    return ""
  end
  local parts = {}
  for key, value in pairs(params) do
    if value ~= nil and value ~= "" then
      table.insert(parts, string.format("%s=%s", urlencode(key), urlencode(value)))
    end
  end
  if #parts == 0 then
    return ""
  end
  return "?" .. table.concat(parts, "&")
end

local function parse_response(output)
  if not output or output == "" then
    return nil, nil, "Empty response"
  end
  local body, status = output:match("^(.*)HTTPSTATUS:(%d%d%d)%s*$")
  status = tonumber(status)
  body = body or output
  local decoded
  if body and body ~= "" then
    local ok, parsed = pcall(vim.json.decode, body)
    if ok then
      decoded = parsed
    else
      decoded = body
    end
  end
  return decoded, status, nil
end

local function request(opts, cb)
  local cfg = config.get()
  if vim.fn.executable(cfg.curl_bin) ~= 1 then
    cb("curl is required but not found in PATH")
    return
  end

  local token = opts.token
  if not token or token == "" then
    cb("Missing Todoist token")
    return
  end

  local args = { cfg.curl_bin, "-sS", "-X", opts.method or "GET" }
  table.insert(args, "-H")
  table.insert(args, "Authorization: Bearer " .. token)
  table.insert(args, "-H")
  table.insert(args, "Content-Type: application/json")
  table.insert(args, "-w")
  table.insert(args, "\nHTTPSTATUS:%{http_code}\n")
  table.insert(args, "-o")
  table.insert(args, "-")

  if opts.body then
    table.insert(args, "-d")
    table.insert(args, vim.json.encode(opts.body))
  end

  local url = string.format("%s%s%s", cfg.api_base, opts.path, build_query(opts.query))
  table.insert(args, url)

  local stdout, stderr = {}, {}

  local job = vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        stdout = data
      end
    end,
    on_stderr = function(_, data)
      if data then
        stderr = data
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        cb(table.concat(stderr, "\n"))
        return
      end
      local raw = table.concat(stdout, "\n")
      local decoded, status, err = parse_response(raw)
      if err then
        cb(err)
        return
      end
      if status and status >= 400 then
        local message = decoded and decoded.message or decoded and decoded.error or decoded
        cb(string.format("Todoist API error (%s)", message or status))
        return
      end
      cb(nil, decoded)
    end,
  })

  if job <= 0 then
    cb("Failed to start curl process")
  end
end

function M.fetch_tasks(token, opts, cb)
  local all_results = {}

  local function fetch_page(cursor)
    request({
      method = "GET",
      path   = "/tasks",
      token  = token,
      query  = {
        project_id = opts and opts.project_id or nil,
        filter     = opts and opts.filter or nil,
        cursor     = cursor or nil,
      },
    }, function(err, data)
      if err then return cb(err) end
      local page = type(data) == "table" and data.results or data or {}
      for _, t in ipairs(page) do
        table.insert(all_results, t)
      end
      local next_cursor = type(data) == "table" and data.next_cursor or nil
      if next_cursor and next_cursor ~= vim.NIL and next_cursor ~= "" then
        fetch_page(next_cursor)
      else
        cb(nil, all_results)
      end
    end)
  end

  fetch_page(nil)
end

function M.add_task(token, task, cb)
  request({
    method = "POST",
    path = "/tasks",
    token = token,
    body = task,
  }, cb)
end

function M.close_task(token, task_id, cb)
  request({
    method = "POST",
    path = string.format("/tasks/%s/close", task_id),
    token = token,
  }, cb)
end

function M.reopen_task(token, task_id, cb)
  request({
    method = "POST",
    path   = string.format("/tasks/%s/reopen", task_id),
    token  = token,
  }, cb)
end

function M.update_task(token, task_id, updates, cb)
  request({
    method = "POST",
    path = string.format("/tasks/%s", task_id),
    token = token,
    body = updates,
  }, cb)
end

function M.move_task(token, task_id, body, cb)
  request({
    method = "POST",
    path = string.format("/tasks/%s/move", task_id),
    token = token,
    body = body,
  }, cb)
end

function M.reorder_tasks(token, items, cb)
  request({
    method = "POST",
    path   = "/tasks/reorder",
    token  = token,
    body   = { items = items },
  }, cb)
end

function M.delete_task(token, task_id, cb)
  request({
    method = "DELETE",
    path = string.format("/tasks/%s", task_id),
    token = token,
  }, cb)
end

function M.get_task(token, task_id, cb)
  request({
    method = "GET",
    path = string.format("/tasks/%s", task_id),
    token = token,
  }, cb)
end

function M.fetch_completed_tasks(token, cb)
  request({
    method = "GET",
    path   = "/tasks/completed",
    token  = token,
  }, function(err, data)
    if err then return cb(err) end
    local items = type(data) == "table" and data.items or {}
    if #items == 0 then return cb(nil, {}) end

    local results   = {}
    local remaining = #items
    for _, item in ipairs(items) do
      request({
        method = "GET",
        path   = string.format("/tasks/%s", item.task_id),
        token  = token,
      }, function(terr, full)
        if not terr and full then
          full.checked  = true
          full.children = {}
          table.insert(results, full)
        else
          table.insert(results, {
            id           = item.task_id,
            content      = item.content or "",
            project_id   = item.project_id,
            checked      = true,
            completed_at = item.completed_at,
            priority     = 1,
            parent_id    = nil,
            description  = item.description or "",
            due          = nil,
            children     = {},
          })
        end
        remaining = remaining - 1
        if remaining == 0 then cb(nil, results) end
      end)
    end
  end)
end

function M.fetch_projects(token, cb)
  request({
    method = "GET",
    path   = "/projects",
    token  = token,
  }, function(err, data)
    if err then return cb(err) end
    cb(nil, type(data) == "table" and data.results or data)
  end)
end

return M
