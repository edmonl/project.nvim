local config = require('project_nvim.config')
local path = require('project_nvim.utils.path')

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))
local a, b, c, d = test_root .. '/a', test_root .. '/b', test_root .. '/c', test_root .. '/d'

config.options = { datapath = test_root, exclude_dirs = {} }
path.init()
path.create_scaffolding()
for _, dir in ipairs({ a, b, c, d }) do
  assert(vim.fn.mkdir(dir) == 1)
end

local function fresh_history()
  package.loaded['project_nvim.utils.history'] = nil
  return require('project_nvim.utils.history')
end

local function assert_projects(actual, expected)
  assert(vim.deep_equal(actual, expected), 'Expected ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(actual))
end

local function write_history()
  assert(vim.fn.writefile({ a, b, c }, path.historyfile) == 0)
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
elseif test_case == 'save_before_load' then
  local history = fresh_history()
  write_history()
  history.session_projects = { b, d }
  assert(history.recent_projects == nil)

  history.delete_project(b)
  history.write_projects_to_history()

  assert_projects(vim.fn.readfile(path.historyfile), { a, c, d })

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
