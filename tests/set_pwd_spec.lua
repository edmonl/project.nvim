local config = require('project_nvim.config')
local history = require('project_nvim.utils.history')
local project = require('project_nvim.project')

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local scope = assert(os.getenv('PROJECT_NVIM_TEST_SCOPE'))
local target_dir = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))

config.options = {
  scope_chdir = scope,
  silent_chdir = true,
}
history.session_projects = {}
project.last_project = nil

if test_case == 'valid_scope' then
  assert(project.set_pwd(target_dir, 'test'))
  assert(vim.fn.getcwd() == target_dir)
  assert(project.last_project == target_dir)
  assert(vim.deep_equal(history.session_projects, { target_dir }))
elseif test_case == 'special_path' then
  vim.g.project_nvim_test_injected = nil

  assert(project.set_pwd(target_dir, 'test'))
  assert(vim.fn.getcwd() == target_dir)
  assert(vim.g.project_nvim_test_injected == nil)
elseif test_case == 'invalid_scope' then
  local original_dir = vim.fn.getcwd()

  assert(not project.set_pwd(target_dir, 'test'))
  assert(vim.fn.getcwd() == original_dir)
  assert(project.last_project == nil)
  assert(vim.deep_equal(history.session_projects, {}))
else
  error('Unknown test case: ' .. test_case)
end
