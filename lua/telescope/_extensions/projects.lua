-- Inspiration from:
-- https://github.com/nvim-telescope/telescope-project.nvim
local has_telescope, telescope = pcall(require, 'telescope')

if not has_telescope then
  return
end

local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local telescope_config = require('telescope.config').values
local actions = require('telescope.actions')
local state = require('telescope.actions.state')
local builtin = require('telescope.builtin')
local entry_display = require('telescope.pickers.entry_display')

local history = require('project_nvim.utils.history')
local project = require('project_nvim.project')
local config = require('project_nvim.config')

local default_mappings = {
  n = {
    find_project_files = 'f',
    browse_project_files = 'b',
    delete_project = 'd',
    search_in_project_files = 's',
    recent_project_files = 'r',
    change_working_directory = 'w',
  },
  i = {
    find_project_files = '<c-f>',
    browse_project_files = '<c-b>',
    delete_project = '<c-d>',
    search_in_project_files = '<c-s>',
    recent_project_files = '<c-r>',
    change_working_directory = '<c-w>',
  },
}
local project_mappings = default_mappings

----------
-- Actions
----------

local function create_finder()
  local results = history.get_recent_projects()

  -- Reverse results
  for i = 1, math.floor(#results / 2) do
    results[i], results[#results - i + 1] = results[#results - i + 1], results[i]
  end
  local displayer = entry_display.create({
    separator = ' ',
    items = {
      {
        width = 30,
      },
      {
        remaining = true,
      },
    },
  })

  local function make_display(entry)
    return displayer({ entry.name, { entry.value, 'Comment' } })
  end

  return finders.new_table({
    results = results,
    entry_maker = function(entry)
      local name = vim.fn.fnamemodify(entry, ':t')
      return {
        display = make_display,
        name = name,
        value = entry,
        ordinal = name .. ' ' .. entry,
      }
    end,
  })
end

local function change_working_directory(prompt_bufnr, prompt)
  local selected_entry = state.get_selected_entry(prompt_bufnr)
  if selected_entry == nil then
    actions.close(prompt_bufnr)
    return
  end
  local project_path = selected_entry.value
  if prompt == true then
    actions._close(prompt_bufnr, true)
  else
    actions.close(prompt_bufnr)
  end
  local cd_successful = project.set_pwd(project_path, 'telescope')
  return project_path, cd_successful
end

local function find_project_files(prompt_bufnr)
  local project_path, cd_successful = change_working_directory(prompt_bufnr, true)
  local opt = {
    cwd = project_path,
    hidden = config.options.show_hidden,
    mode = 'insert',
  }
  if cd_successful then
    builtin.find_files(opt)
  end
end

local function browse_project_files(prompt_bufnr)
  local project_path, cd_successful = change_working_directory(prompt_bufnr, true)
  local opt = {
    cwd = project_path,
    hidden = config.options.show_hidden,
  }
  if cd_successful then
    builtin.file_browser(opt)
  end
end

local function search_in_project_files(prompt_bufnr)
  local project_path, cd_successful = change_working_directory(prompt_bufnr, true)
  local opt = {
    cwd = project_path,
    hidden = config.options.show_hidden,
    mode = 'insert',
  }
  if cd_successful then
    builtin.live_grep(opt)
  end
end

local function recent_project_files(prompt_bufnr)
  local _, cd_successful = change_working_directory(prompt_bufnr, true)
  local opt = {
    cwd_only = true,
    hidden = config.options.show_hidden,
  }
  if cd_successful then
    builtin.oldfiles(opt)
  end
end

local function delete_project(prompt_bufnr)
  local selected_entry = state.get_selected_entry(prompt_bufnr)
  if selected_entry == nil then
    actions.close(prompt_bufnr)
    return
  end
  local choice = vim.fn.confirm(
    "Delete '"
      .. selected_entry.value
      .. "' from project list?\n"
      .. 'It may reappear when you visit one of its buffers or use :AddProject.',
    '&Yes\n&No',
    2
  )

  if choice == 1 then
    history.delete_project(selected_entry.value)

    local finder = create_finder()
    state.get_current_picker(prompt_bufnr):refresh(finder, {
      reset_prompt = true,
    })
  end
end

local project_actions = {
  find_project_files = find_project_files,
  browse_project_files = browse_project_files,
  delete_project = delete_project,
  search_in_project_files = search_in_project_files,
  recent_project_files = recent_project_files,
  change_working_directory = change_working_directory,
}

---Main entrypoint for Telescope.
---@param opts table
local function projects(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = 'Recent Projects',
      finder = create_finder(),
      previewer = false,
      sorter = telescope_config.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        for mode, mappings in pairs(project_mappings) do
          for action, key in pairs(mappings) do
            if key then
              local callback = assert(project_actions[action], 'Unknown project action: ' .. action)
              map(mode, key, callback)
            end
          end
        end

        local on_project_selected = function()
          find_project_files(prompt_bufnr)
        end
        actions.select_default:replace(on_project_selected)
        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  ---Configures project shortcuts from Telescope's extensions.projects section.
  ---@param ext_config table
  setup = function(ext_config)
    project_mappings = vim.tbl_deep_extend('force', default_mappings, ext_config.mappings or {})
  end,
  exports = {
    projects = projects,
  },
})
