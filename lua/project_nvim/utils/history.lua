local path = require('project_nvim.utils.path')
local history_data = require('project_nvim.utils.history_data')
local uv = vim.uv
local M = {}

M.recent_projects = nil -- projects from previous neovim sessions
M.session_projects = {} -- projects from current neovim session
local deleted_projects = {}
local projectpath = vim.fn.stdpath('data') .. '/project_nvim'
local watcher
-- Setup invalidates pending reads even when the same storage path is selected again.
local generation = 0

local function open_history(directory, mode, callback)
  local historyfile = directory .. '/project_history'
  if callback ~= nil then -- async
    uv.fs_mkdir(directory, 448, function()
      uv.fs_open(historyfile, mode, 438, callback)
    end)
  else -- sync
    uv.fs_mkdir(directory, 448)
    return uv.fs_open(historyfile, mode, 438)
  end
end

local function dir_exists(dir)
  local stat = uv.fs_stat(dir)
  if stat ~= nil and stat.type == 'directory' then
    return true
  end
  return false
end

local function include_loaded_project(project)
  return not deleted_projects[history_data.normalise_path(project)]
    and not path.is_excluded(project)
    and dir_exists(project)
end

local function include_recorded_project(project)
  -- Exclusions apply to disk history, not to visits already recorded this session.
  return not deleted_projects[history_data.normalise_path(project)] and dir_exists(project)
end

---Records a project visit and allows a previously deleted project to return.
---@param project string
function M.add_project(project)
  deleted_projects[history_data.normalise_path(project)] = nil
  table.insert(M.session_projects, project)
end

---Removes a project from history until it is visited or explicitly added again.
---@param project string
function M.delete_project(project)
  deleted_projects[history_data.normalise_path(project)] = true
  history_data.remove_project(M.recent_projects, project)
  history_data.remove_project(M.session_projects, project)
end

local function read_projects_from_history_sync()
  local file = open_history(projectpath, 'r')
  if file == nil then
    M.recent_projects = {}
    return
  end

  local stat = uv.fs_fstat(file)
  local contents = stat and uv.fs_read(file, stat.size, -1) or ''
  uv.fs_close(file)
  M.recent_projects = history_data.parse(contents, include_loaded_project)
end

local function stop_watch()
  if watcher ~= nil then
    watcher:stop()
    watcher:close()
    watcher = nil
  end
end

local function setup_watch()
  -- Pending history reads may finish after VimLeave, during event-loop teardown.
  if watcher ~= nil or vim.v.exiting ~= vim.NIL then
    return
  end

  local event = uv.new_fs_event()
  if event == nil then
    return
  end
  watcher = event
  local started = event:start(projectpath, {}, function(err, _, events)
    -- Events already queued by a replaced watcher must not reload the new history.
    if err ~= nil or event ~= watcher then
      return
    end
    if events['change'] then
      M.recent_projects = nil
      M.read_projects_from_history()
    end
  end)
  if not started then
    stop_watch()
  end
end

---Loads disk history asynchronously and starts watching while Neovim is active.
function M.read_projects_from_history()
  local load_generation = generation
  open_history(projectpath, 'r', function(_, fd)
    if load_generation ~= generation then
      if fd ~= nil then
        uv.fs_close(fd, function() end)
      end
      return
    end
    setup_watch()
    if fd ~= nil then
      uv.fs_fstat(fd, function(_, stat)
        if stat == nil or load_generation ~= generation then
          uv.fs_close(fd, function() end)
          return
        end
        uv.fs_read(fd, stat.size, -1, function(_, data)
          uv.fs_close(fd, function() end)
          if load_generation == generation and data ~= nil then
            M.recent_projects = history_data.parse(data, include_loaded_project)
          end
        end)
      end)
    end
  end)
end

---Returns existing, non-deleted projects ordered by their last recorded visit.
---@return string[]
function M.get_recent_projects()
  return history_data.collect(M.recent_projects, M.session_projects, include_recorded_project)
end

---Saves synchronously for shutdown, preserving unloaded history when appending.
function M.write_projects_to_history()
  -- Unlike read projects, write projects is synchronous
  -- because it runs when vim ends
  local mode = 'w'
  if M.recent_projects == nil then
    if next(deleted_projects) == nil then
      mode = 'a'
    else
      read_projects_from_history_sync()
    end
  end
  local file = open_history(projectpath, mode)

  if file ~= nil then
    local contents = history_data.serialize(M.get_recent_projects())
    uv.fs_write(file, contents, -1)
    uv.fs_close(file)
  end
end

---Configures history storage, loads it, and owns its watcher and shutdown hook.
---@param datapath string
function M.init(datapath)
  local directory = datapath .. '/project_nvim'
  generation = generation + 1
  if directory ~= projectpath then
    stop_watch()
    M.recent_projects = nil
  end
  projectpath = directory

  local group = vim.api.nvim_create_augroup('project_nvim_history', { clear = true })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      generation = generation + 1
      stop_watch()
      M.write_projects_to_history()
    end,
  })

  M.read_projects_from_history()
end

return M
