local glob = require('project_nvim.utils.globtopattern')
local uv = vim.uv
local M = {}

local function get_parent(directory)
  local parent = directory:match('^(.*)/')
  if parent == '' then
    parent = '/'
  end
  return parent
end

local function matches_directory_name(directory, name)
  return directory:match('.*/(.*)') == name
end

local function has_matching_ancestor(directory, name)
  local ancestor = get_parent(directory)
  while true do
    if matches_directory_name(ancestor, name) then
      return true
    end
    local parent = get_parent(ancestor)
    if parent == ancestor then
      return false
    end
    ancestor = parent
  end
end

local function read_directory_entries(directory)
  local entries = {}
  local scan = uv.fs_scandir(directory)
  if scan == nil then
    return entries
  end

  while true do
    local entry = uv.fs_scandir_next(scan)
    if entry == nil then
      return entries
    end
    table.insert(entries, entry)
  end
end

local function matches_pattern(directory, pattern, get_entries)
  local prefix = pattern:sub(1, 1)
  local identifier = pattern:sub(2)
  if prefix == '=' then
    return matches_directory_name(directory, identifier)
  elseif prefix == '^' then
    return has_matching_ancestor(directory, identifier)
  elseif prefix == '>' then
    return matches_directory_name(get_parent(directory), identifier)
  end

  local entries = get_entries(directory)
  local entry_pattern = glob.globtopattern(pattern)
  for _, entry in ipairs(entries) do
    if entry:match(entry_pattern) ~= nil then
      return true
    end
  end
  return false
end

---Finds the nearest matching directory, evaluating patterns in their given order.
---A matching exclusion skips that directory; searching continues at its parent.
---@param start_dir string Absolute directory from which to search.
---@param patterns string[]
---@return string? root
---@return string? method
function M.find_root(start_dir, patterns)
  local search_dir = start_dir
  if vim.fn.has('win32') > 0 then
    search_dir = search_dir:gsub('\\', '/')
  end

  -- Scan lazily, at most once per directory, and never cache across searches.
  local last_scanned_directory = ''
  local cached_entries = {}
  local function get_entries(directory)
    if last_scanned_directory ~= directory then
      last_scanned_directory = directory
      cached_entries = read_directory_entries(directory)
    end
    return cached_entries
  end

  while true do
    for _, pattern in ipairs(patterns) do
      local excluded = pattern:sub(1, 1) == '!'
      if excluded then
        pattern = pattern:sub(2)
      end
      if matches_pattern(search_dir, pattern, get_entries) then
        if excluded then
          break
        end
        return search_dir, 'pattern ' .. pattern
      end
    end

    local parent = get_parent(search_dir)
    if parent == search_dir or parent == nil then
      return nil
    end
    search_dir = parent
  end
end

return M
