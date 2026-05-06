# Overview
I have created a fork of https://github.com/mshiyaf/todoist.nvim and I want to update it so that I can use it. 

**Current state (as of initial setup):**
- The plugin already targets the Todoist REST API v2 (`https://api.todoist.com/rest/v2`).
- The custom UI (`custom_ui.lua`) groups tasks by **priority** (Urgent/High/Medium/Normal headers).
- There is a split layout: left pane = task list, right pane = task detail preview.
- An fzf-based UI also exists as an alternative (`today_view_ui = "fzf"` in config).
- Auth supports: inline config token, `TODOIST_API_TOKEN` env var, or saved file via `:TodoistLogin`.

# Decisions
1. **API**: Migrate from `https://api.todoist.com/rest/v2` to `https://api.todoist.com/api/v1/`.
2. **UI grouping**: Replace priority-based grouping with project-based grouping. Tasks should be colored by priority within each project section. Apply to both `custom` and `fzf` UIs.
3. **Plugin manager**: lazy.nvim.

# Testing
No automated tests exist. Testing is done manually by loading the plugin in Neovim.
To test: open Neovim with the plugin loaded and use `:TodoistToday` or `:TodoistTasks`.

# Pushing Code
I am currently working on SSH. When you want to push code, please use arjun-shanmugam as the username and find my personal access token on my local machine -- ~/Documents/GitHub/github_personal_access_token
Always write detailed, clear, concise commit messages.

# Goals
1. Update the plugin's existing functionality to match the new Todoist API. Here is the API: feel free to explore it as you need information 
2. Update the plugin's UI so that tasks are organized by project.
