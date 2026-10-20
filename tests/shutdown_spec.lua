local config = require('project_nvim.config')
local project_nvim = require('project_nvim')
local history = require('project_nvim.utils.history')
local path = require('project_nvim.utils.path')

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))

if test_case == 'immediate_exit' then
  local uv = vim.uv
  local fs_open = uv.fs_open
  local pending_open
  -- Hold the history open until VimLeave to exercise the shutdown race reliably.
  uv.fs_open = function(file, mode, permissions, callback)
    if callback and file == path.historyfile then
      pending_open = function()
        fs_open(file, mode, permissions, callback)
      end
      return
    end
    return fs_open(file, mode, permissions, callback)
  end

  project_nvim.setup({ manual_mode = true, datapath = test_root })
  assert(
    vim.wait(2000, function()
      return pending_open ~= nil
    end, 10),
    'Timed out waiting for the pending history open'
  )
  uv.fs_open = fs_open
  assert(not history.has_watch_setup, 'The test must exit with history loading still pending')

  local new_fs_event = uv.new_fs_event
  uv.new_fs_event = function(...)
    if vim.v.exiting ~= vim.NIL then
      local marker = assert(io.open(test_root .. '/late-watcher', 'w'))
      marker:write('Watcher allocated during shutdown\n')
      marker:close()
    end
    return new_fs_event(...)
  end
  vim.api.nvim_create_autocmd('VimLeave', {
    once = true,
    callback = function()
      pending_open()
    end,
  })
elseif test_case == 'active_watch' then
  config.options = { datapath = test_root }
  path.init()
  path.create_scaffolding()
  local a, b = test_root .. '/a', test_root .. '/b'
  assert(vim.fn.mkdir(a) == 1)
  assert(vim.fn.mkdir(b) == 1)
  assert(vim.fn.writefile({ a }, path.historyfile) == 0)
  project_nvim.setup({ manual_mode = true, datapath = test_root })

  assert(
    vim.wait(2000, function()
      return vim.deep_equal(history.get_recent_projects(), { a })
    end, 10),
    'Timed out waiting for the initial history load'
  )

  assert(vim.fn.writefile({ b }, path.historyfile) == 0)
  assert(
    vim.wait(2000, function()
      return vim.deep_equal(history.get_recent_projects(), { b })
    end, 10),
    'The active watcher must still reload history changes'
  )
else
  error('Unknown test case: ' .. test_case)
end
