local path = require('project_nvim.utils.path')
local uv = vim.uv
local M = {}
local is_windows = vim.fn.has('win32') or vim.fn.has('wsl')

M.recent_projects = nil -- projects from previous neovim sessions
M.session_projects = {} -- projects from current neovim session
M.has_watch_setup = false
local deleted_projects = {}

local function open_history(mode, callback)
  if callback ~= nil then -- async
    path.create_scaffolding(function(_, _)
      uv.fs_open(path.historyfile, mode, 438, callback)
    end)
  else -- sync
    path.create_scaffolding()
    return uv.fs_open(path.historyfile, mode, 438)
  end
end

local function dir_exists(dir)
  local stat = uv.fs_stat(dir)
  if stat ~= nil and stat.type == 'directory' then
    return true
  end
  return false
end

local function normalise_path(path_to_normalise)
  local normalised_path = path_to_normalise:gsub('\\', '/'):gsub('//', '/')

  if is_windows then
    normalised_path = normalised_path:sub(1, 1):lower() .. normalised_path:sub(2)
  end

  return normalised_path
end

local function remove_project(projects, project)
  if projects == nil then
    return
  end

  local normalised_project = normalise_path(project)
  for index = #projects, 1, -1 do
    if normalise_path(projects[index]) == normalised_project then
      table.remove(projects, index)
    end
  end
end

local function delete_duplicates(tbl)
  local cache_dict = {}
  for _, v in ipairs(tbl) do
    local normalised_path = normalise_path(v)
    if cache_dict[normalised_path] == nil then
      cache_dict[normalised_path] = 1
    else
      cache_dict[normalised_path] = cache_dict[normalised_path] + 1
    end
  end

  local res = {}
  for _, v in ipairs(tbl) do
    local normalised_path = normalise_path(v)
    if cache_dict[normalised_path] == 1 then
      table.insert(res, normalised_path)
    else
      cache_dict[normalised_path] = cache_dict[normalised_path] - 1
    end
  end
  return res
end

---Records a project visit and allows a previously deleted project to return.
---@param project string
function M.add_project(project)
  deleted_projects[normalise_path(project)] = nil
  table.insert(M.session_projects, project)
end

---Removes a project from history until it is visited or explicitly added again.
---@param project string
function M.delete_project(project)
  deleted_projects[normalise_path(project)] = true
  remove_project(M.recent_projects, project)
  remove_project(M.session_projects, project)
end

local function deserialize_history(history_data)
  -- split data to table
  local projects = {}
  for s in history_data:gmatch('[^\r\n]+') do
    if not deleted_projects[normalise_path(s)] and not path.is_excluded(s) and dir_exists(s) then
      table.insert(projects, s)
    end
  end

  projects = delete_duplicates(projects)

  M.recent_projects = projects
end

local function read_projects_from_history_sync()
  local file = open_history('r')
  if file == nil then
    M.recent_projects = {}
    return
  end

  local stat = uv.fs_fstat(file)
  local history_data = stat and uv.fs_read(file, stat.size, -1) or ''
  uv.fs_close(file)
  deserialize_history(history_data)
end

local function setup_watch()
  -- Pending history reads may finish after VimLeave, during event-loop teardown.
  if vim.v.exiting ~= vim.NIL then
    return
  end

  -- Only runs once
  if M.has_watch_setup == false then
    M.has_watch_setup = true
    local event = uv.new_fs_event()
    if event == nil then
      return
    end
    event:start(path.projectpath, {}, function(err, _, events)
      if err ~= nil then
        return
      end
      if events['change'] then
        M.recent_projects = nil
        M.read_projects_from_history()
      end
    end)
  end
end

function M.read_projects_from_history()
  open_history('r', function(_, fd)
    setup_watch()
    if fd ~= nil then
      uv.fs_fstat(fd, function(_, stat)
        if stat ~= nil then
          uv.fs_read(fd, stat.size, -1, function(_, data)
            uv.fs_close(fd, function(_, _) end)
            deserialize_history(data)
          end)
        end
      end)
    end
  end)
end

local function sanitize_projects()
  local tbl = {}
  if M.recent_projects ~= nil then
    vim.list_extend(tbl, M.recent_projects)
    vim.list_extend(tbl, M.session_projects)
  else
    tbl = M.session_projects
  end

  tbl = delete_duplicates(tbl)

  local real_tbl = {}
  for _, dir in ipairs(tbl) do
    if not deleted_projects[normalise_path(dir)] and dir_exists(dir) then
      table.insert(real_tbl, dir)
    end
  end

  return real_tbl
end

function M.get_recent_projects()
  return sanitize_projects()
end

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
  local file = open_history(mode)

  if file ~= nil then
    local res = sanitize_projects()

    -- Trim table to last 100 entries
    local len_res = #res
    local tbl_out
    if #res > 100 then
      tbl_out = vim.list_slice(res, len_res - 100, len_res)
    else
      tbl_out = res
    end

    -- Transform table to string
    local out = ''
    for _, v in ipairs(tbl_out) do
      out = out .. v .. '\n'
    end

    -- Write string out to file and close
    uv.fs_write(file, out, -1)
    uv.fs_close(file)
  end
end

return M
