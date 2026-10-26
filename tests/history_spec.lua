local config = require('project_nvim.config')

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))
local historyfile = test_root .. '/project_nvim/project_history'
local a, b, c, d = test_root .. '/a', test_root .. '/b', test_root .. '/c', test_root .. '/d'

config.options = { datapath = test_root, exclude_dirs = {} }
assert(vim.fn.mkdir(test_root .. '/project_nvim') == 1)
for _, dir in ipairs({ a, b, c, d }) do
  assert(vim.fn.mkdir(dir) == 1)
end

local function fresh_history()
  package.loaded['project_nvim.utils.history'] = nil
  local history = require('project_nvim.utils.history')
  -- Configure storage without starting the load exercised by each case.
  local read_history = history.read_projects_from_history
  history.read_projects_from_history = function() end
  history.init(test_root)
  history.read_projects_from_history = read_history
  return history
end

local function assert_projects(actual, expected)
  assert(vim.deep_equal(actual, expected), 'Expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual))
end

local function write_history()
  assert(vim.fn.writefile({ a, b, c }, historyfile) == 0)
end

if test_case == 'delete_entries' then
  for _, case in ipairs({
    { project = a, recent = { b, c }, session = { c, b } },
    { project = b, recent = { a, c }, session = { c, a } },
    { project = c, recent = { a, b }, session = { b, a } },
  }) do
    local history = fresh_history()
    local alias = test_root .. '//' .. vim.fn.fnamemodify(case.project, ':t')
    history.recent_projects = { a, b, c, case.project }
    history.session_projects = { c, b, a, alias }

    history.delete_project(alias)

    assert_projects(history.recent_projects, case.recent)
    assert_projects(history.session_projects, case.session)
  end

  for _, loaded in ipairs({ false, true }) do
    local history = fresh_history()
    history.recent_projects = loaded and {} or nil
    history.session_projects = { a, b, c, b }

    history.delete_project(b)

    assert_projects(history.session_projects, { a, c })
    assert_projects(history.get_recent_projects(), { a, c })
    assert_projects(history.recent_projects, loaded and {} or nil)
  end
elseif test_case == 'delete_during_load' then
  local history = fresh_history()
  write_history()
  history.session_projects = { b, d }

  history.read_projects_from_history()
  assert(history.recent_projects == nil)
  history.delete_project(b)

  assert(
    vim.wait(2000, function()
      return history.recent_projects ~= nil
    end, 10),
    'Timed out waiting for asynchronous history loading'
  )
  assert_projects(history.recent_projects, { a, c })
  assert_projects(history.session_projects, { d })
  assert_projects(history.get_recent_projects(), { a, c, d })
elseif test_case == 'load_filtering' then
  local history = fresh_history()
  local alias = test_root .. '//a'
  local missing = test_root .. '/missing'
  config.options.exclude_dirs = { '^' .. vim.pesc(b) .. '$' }
  local lines = vim.tbl_map(function(project)
    return project .. '\r'
  end, { a, b, c, a, missing, d, alias, '' })
  assert(vim.fn.writefile(lines, historyfile) == 0)
  history.delete_project(c)

  history.read_projects_from_history()
  assert(
    vim.wait(2000, function()
      return history.recent_projects ~= nil
    end, 10),
    'Timed out waiting for filtered history loading'
  )
  assert_projects(history.recent_projects, { d, a })
  assert_projects(history.get_recent_projects(), { d, a })
elseif test_case == 'collect_projects' then
  -- Exclusions apply when loading, not when collecting already-recorded visits.
  config.options.exclude_dirs = { '^' .. vim.pesc(b) .. '$' }
  for _, loaded in ipairs({ false, true }) do
    local history = fresh_history()
    history.recent_projects = loaded and { a, d, b } or nil
    history.session_projects = { b, a, test_root .. '//b', test_root .. '/missing', c }
    local recent_before = vim.deepcopy(history.recent_projects)
    local session_before = vim.deepcopy(history.session_projects)

    assert_projects(history.get_recent_projects(), loaded and { d, a, b, c } or { a, b, c })
    assert_projects(history.recent_projects, recent_before)
    assert_projects(history.session_projects, session_before)
  end
elseif test_case == 'serialization' then
  local history = fresh_history()
  history.recent_projects = {}
  local projects = {}
  for index = 1, 102 do
    projects[index] = test_root .. '/project-' .. index
    assert(vim.fn.mkdir(projects[index]) == 1)
  end

  for _, count in ipairs({ 0, 1, 100, 101, 102 }) do
    history.session_projects = vim.list_slice(projects, 1, count)
    history.write_projects_to_history()

    -- Characterize the current inclusive slice: over 100 entries retains 101.
    local first = count > 100 and count - 100 or 1
    local expected = vim.list_slice(projects, first, count)
    assert_projects(vim.fn.readfile(historyfile), expected)
    local expected_data = #expected > 0 and table.concat(expected, '\n') .. '\n' or ''
    assert(table.concat(vim.fn.readfile(historyfile, 'b'), '\n') == expected_data)
  end

  -- Without loaded history or deletion markers, saving appends session visits.
  history = fresh_history()
  write_history()
  history.session_projects = { a, d }
  history.write_projects_to_history()
  assert_projects(vim.fn.readfile(historyfile), { a, b, c, a, d })
elseif test_case == 'save_before_load' then
  local history = fresh_history()
  write_history()
  history.session_projects = { b, d }
  assert(history.recent_projects == nil)

  history.delete_project(b)
  history.write_projects_to_history()

  assert_projects(vim.fn.readfile(historyfile), { a, c, d })

  local reloaded = fresh_history()
  reloaded.read_projects_from_history()
  assert(
    vim.wait(2000, function()
      return reloaded.recent_projects ~= nil
    end, 10),
    'Timed out waiting for saved history loading'
  )
  assert_projects(reloaded.get_recent_projects(), { a, c, d })
else
  error('Unknown test case: ' .. test_case)
end
