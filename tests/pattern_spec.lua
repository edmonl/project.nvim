local config = require('project_nvim.config')
local project = require('project_nvim.project')

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))
local workspace = test_root .. '/workspace'
local repo = workspace .. '/repo'
local nested = repo .. '/nested'
local leaf = nested .. '/leaf'
assert(vim.fn.mkdir(leaf, 'p') == 1)

local function write_file(file)
  assert(vim.fn.writefile({}, file) == 0)
end

write_file(repo .. '/root.marker')
write_file(repo .. '/other.marker')
write_file(repo .. '/project.sln')
write_file(nested .. '/nested.marker')
write_file(leaf .. '/main.lua')

local function assert_root(start_dir, patterns, expected_root, expected_method)
  vim.api.nvim_buf_set_name(0, start_dir .. '/buffer.lua')
  config.options.patterns = patterns
  local patterns_before = vim.deepcopy(patterns)
  local cwd_before = vim.fn.getcwd()
  local root, method = project.find_pattern_root()
  assert(root == expected_root, 'Expected root ' .. tostring(expected_root) .. ', got ' .. tostring(root))
  assert(method == expected_method, 'Expected method ' .. tostring(expected_method) .. ', got ' .. tostring(method))

  -- The extracted detector must use its arguments, not the current buffer/config.
  vim.api.nvim_buf_set_name(0, test_root .. '/unrelated/buffer.lua')
  config.options.patterns = {}
  local direct_root, direct_method = require('project_nvim.pattern').find_root(start_dir, patterns)
  assert(direct_root == expected_root and direct_method == expected_method, 'Standalone detection must match')
  assert(vim.deep_equal(patterns, patterns_before), 'Detection must not mutate patterns')
  assert(vim.fn.getcwd() == cwd_before, 'Detection must not change the working directory')
end

if test_case == 'precedence' then
  -- Search the nearest directory first, then evaluate its patterns in order.
  assert_root(leaf, { 'root.marker', '*.lua' }, leaf, 'pattern *.lua')
  assert_root(leaf, { '*.sln', 'nested.marker' }, nested, 'pattern nested.marker')
  assert_root(leaf, { 'other.marker', 'root.marker' }, repo, 'pattern other.marker')
  assert_root(leaf, { 'root.marker', 'other.marker' }, repo, 'pattern root.marker')
  assert_root(leaf, { '*.sln' }, repo, 'pattern *.sln')
  assert_root(leaf, { 'main.?ua' }, leaf, 'pattern main.?ua')
  assert_root(leaf, {}, nil, nil)
  assert_root(leaf, { 'project-nvim-absent.marker' }, nil, nil)

  -- A failed scan still permits searching parents, or matching a directory name.
  assert_root(leaf .. '/missing', { 'main.lua' }, leaf, 'pattern main.lua')
  assert_root(leaf .. '/missing', { '=missing' }, leaf .. '/missing', 'pattern =missing')

  -- Directory entries are cached for one search only.
  assert_root(leaf, { 'new.marker' }, nil, nil)
  write_file(leaf .. '/new.marker')
  assert_root(leaf, { 'new.marker' }, leaf, 'pattern new.marker')
elseif test_case == 'exclusions' then
  -- Exclusion skips the current directory, not all of its ancestors.
  assert_root(leaf, { '!main.lua', '*.lua', 'nested.marker' }, nested, 'pattern nested.marker')
  assert_root(leaf, { '!=leaf', '*.lua', 'root.marker' }, repo, 'pattern root.marker')
  assert_root(leaf, { '!^repo', '*.lua', 'root.marker' }, repo, 'pattern root.marker')
  assert_root(leaf, { '!>nested', '*.lua', 'nested.marker' }, nested, 'pattern nested.marker')
  assert_root(leaf, { '!project-nvim-absent.marker', '*.lua' }, leaf, 'pattern *.lua')
  assert_root(leaf, { '!main.lua' }, nil, nil)

  -- A positive match wins immediately, even if a later exclusion would match.
  assert_root(leaf, { '*.lua', '!main.lua' }, leaf, 'pattern *.lua')
elseif test_case == 'relationships' then
  assert_root(leaf, { '=leaf' }, leaf, 'pattern =leaf')
  assert_root(leaf, { '=repo' }, repo, 'pattern =repo')
  assert_root(leaf, { '^repo' }, leaf, 'pattern ^repo')
  assert_root(leaf, { '^workspace' }, leaf, 'pattern ^workspace')
  assert_root(leaf, { '^leaf' }, nil, nil)
  assert_root(leaf, { '>nested' }, leaf, 'pattern >nested')
  assert_root(leaf, { '>repo' }, nested, 'pattern >repo')
  assert_root(leaf, { '>workspace' }, repo, 'pattern >workspace')
  assert_root(leaf, { '>leaf' }, nil, nil)
else
  error('Unknown test case: ' .. test_case)
end
