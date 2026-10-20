local project_nvim = require('project_nvim')
local config = require('project_nvim.config')
local path = require('project_nvim.utils.path')
local project = require('project_nvim.project')

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))

if test_case == 'option_preparation' then
  -- Exercise option preparation without starting history I/O or editor hooks.
  path.init = function() end
  project.init = function() end
  local defaults_before = vim.deepcopy(config.defaults)
  local options = {
    manual_mode = true,
    datapath = test_root,
    detection_methods = { 'pattern' },
    patterns = { 'custom.marker' },
    ignore_lsp = { 'ignored' },
    exclude_dirs = { '~/project-nvim-excluded/*', test_root .. '/excluded/*' },
    silent_chdir = false,
    show_hidden = true,
    scope_chdir = 'tab',
  }
  local options_before = vim.deepcopy(options)
  for _ = 1, 2 do
    vim.opt.autochdir = true
    assert(project_nvim.setup(options) == nil)
    assert(not vim.o.autochdir)
    assert(config.options.manual_mode and config.options.show_hidden)
    assert(not config.options.silent_chdir and config.options.scope_chdir == 'tab')
    assert(config.options.datapath == test_root)
    assert(vim.deep_equal(config.options.detection_methods, { 'pattern' }))
    assert(vim.deep_equal(config.options.patterns, { 'custom.marker' }))
    assert(vim.deep_equal(config.options.ignore_lsp, { 'ignored' }))
    assert(path.is_excluded(vim.fn.expand('~') .. '/project-nvim-excluded/project'))
    assert(path.is_excluded(test_root .. '/excluded/project'))
    assert(not path.is_excluded(test_root .. '/included/project'))
    assert(vim.deep_equal(options, options_before), 'Setup must not mutate caller options')
    assert(vim.deep_equal(config.defaults, defaults_before), 'Setup must not mutate defaults')
  end

  project_nvim.setup()
  assert(vim.deep_equal(config.options, defaults_before), 'Omitted options must reset to defaults')
  project_nvim.setup({})
  assert(vim.deep_equal(config.options, defaults_before), 'Empty options must reset to defaults')
elseif test_case == 'configuration_only' then
  path.init = function()
    error('Option preparation must not initialize paths')
  end
  project.init = function()
    error('Option preparation must not initialize project hooks')
  end
  local paths_before = { path.datapath, path.projectpath, path.historyfile }
  local commands_before = vim.api.nvim_get_commands({})
  local autocmds_before = vim.api.nvim_get_autocmds({})
  vim.opt.autochdir = true

  config.setup({ manual_mode = true, datapath = test_root, exclude_dirs = { '~/project-nvim-excluded/*' } })

  assert(config.options.datapath == test_root)
  assert(path.is_excluded(vim.fn.expand('~') .. '/project-nvim-excluded/project'))
  assert(vim.o.autochdir, 'Option preparation must not change editor settings')
  assert(vim.deep_equal({ path.datapath, path.projectpath, path.historyfile }, paths_before))
  assert(vim.deep_equal(vim.api.nvim_get_commands({}), commands_before))
  assert(vim.deep_equal(vim.api.nvim_get_autocmds({}), autocmds_before))
elseif test_case == 'initialization_order' then
  local phases = {}
  local expected_datapath

  local init_paths = path.init
  path.init = function()
    table.insert(phases, 'paths')
    assert(config.options.datapath == expected_datapath, 'Prepare options before initializing paths')
    assert(not vim.o.autochdir, 'Disable autochdir before initializing paths')
    init_paths()
  end
  project.init = function()
    table.insert(phases, 'project')
    assert(path.datapath == config.options.datapath)
    assert(path.projectpath == config.options.datapath .. '/project_nvim')
    assert(path.historyfile == path.projectpath .. '/project_history')
  end

  for _, datapath in ipairs({ test_root, test_root .. '/second' }) do
    phases = {}
    expected_datapath = datapath
    vim.opt.autochdir = true
    project_nvim.setup({ manual_mode = true, datapath = datapath })
    assert(config.options.datapath == datapath)
    assert(vim.deep_equal(phases, { 'paths', 'project' }), 'Preserve initialization order')
  end
else
  error('Unknown test case: ' .. test_case)
end
