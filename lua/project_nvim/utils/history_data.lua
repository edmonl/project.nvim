-- History transformations only; callers supply filtering policies and own I/O.
local M = {}
local is_windows = vim.fn.has('win32') or vim.fn.has('wsl')

---Returns the path representation used for history comparisons and output.
---@param project string
---@return string
function M.normalise_path(project)
  local normalised = project:gsub('\\', '/'):gsub('//', '/')
  if is_windows then
    normalised = normalised:sub(1, 1):lower() .. normalised:sub(2)
  end
  return normalised
end

local function keep_last_occurrences(projects)
  local counts = {}
  for _, project in ipairs(projects) do
    local normalised = M.normalise_path(project)
    counts[normalised] = (counts[normalised] or 0) + 1
  end

  local result = {}
  for _, project in ipairs(projects) do
    local normalised = M.normalise_path(project)
    if counts[normalised] == 1 then
      table.insert(result, normalised)
    else
      counts[normalised] = counts[normalised] - 1
    end
  end
  return result
end

---Removes all matching paths from a project list in place, if it is loaded.
---@param projects string[]?
---@param project string
function M.remove_project(projects, project)
  if projects == nil then
    return
  end

  local normalised = M.normalise_path(project)
  for index = #projects, 1, -1 do
    if M.normalise_path(projects[index]) == normalised then
      table.remove(projects, index)
    end
  end
end

---Parses history, filtering original paths before normalizing and deduplicating.
---@param contents string
---@param include_project fun(project: string): boolean
---@return string[]
function M.parse(contents, include_project)
  local projects = {}
  for project in contents:gmatch('[^\r\n]+') do
    if include_project(project) then
      table.insert(projects, project)
    end
  end
  return keep_last_occurrences(projects)
end

---Merges visits without mutating inputs, then filters normalized, deduplicated paths.
---@param recent_projects string[]?
---@param session_projects string[]
---@param include_project fun(project: string): boolean
---@return string[]
function M.collect(recent_projects, session_projects, include_project)
  local projects = {}
  if recent_projects ~= nil then
    vim.list_extend(projects, recent_projects)
  end
  vim.list_extend(projects, session_projects)

  local result = {}
  for _, project in ipairs(keep_last_occurrences(projects)) do
    if include_project(project) then
      table.insert(result, project)
    end
  end
  return result
end

---Encodes the current history window, with a trailing newline for nonempty output.
---@param projects string[]
---@return string
function M.serialize(projects)
  if #projects > 100 then
    -- Preserve the existing inclusive slice, which retains 101 entries.
    projects = vim.list_slice(projects, #projects - 100, #projects)
  end
  if #projects == 0 then
    return ''
  end
  return table.concat(projects, '\n') .. '\n'
end

return M
