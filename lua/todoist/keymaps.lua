local M = {}

local defaults = {
  enable = true,
  mappings = {
    open_tasks = "<leader>tt",
    login  = "<leader>tl",
    logout = "<leader>tL",
  }
}

function M.setup(opts)
  opts = opts or {}
  local config = vim.tbl_deep_extend("force", defaults, opts)

  if not config.enable then
    return
  end

  -- Register <leader>t group name with which-key if available
  pcall(function()
    local wk = require("which-key")
    if wk.add then
      wk.add({ { "<leader>t", group = "Todoist" } })
    else
      wk.register({ t = { name = "Todoist" } }, { prefix = "<leader>" })
    end
  end)

  local mappings = config.mappings

  if mappings.open_tasks then
    vim.keymap.set("n", mappings.open_tasks, "<cmd>TodoistTasks<cr>", {
      desc = "Todoist: open tasks",
      silent = true,
    })
  end

  if mappings.login then
    vim.keymap.set("n", mappings.login, "<cmd>TodoistLogin<cr>", {
      desc = "Todoist: login",
      silent = true,
    })
  end

  if mappings.logout then
    vim.keymap.set("n", mappings.logout, "<cmd>TodoistLogout<cr>", {
      desc = "Todoist: logout",
      silent = true,
    })
  end
end

return M
