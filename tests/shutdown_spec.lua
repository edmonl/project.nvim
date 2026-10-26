local project_nvim = require('project_nvim')
local history = require('project_nvim.utils.history')
local uv = vim.uv

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))
local historyfile = test_root .. '/project_nvim/project_history'
local watchers = {}
local new_fs_event = uv.new_fs_event
uv.new_fs_event = function(...)
  if vim.v.exiting ~= vim.NIL then
    local marker = assert(io.open(test_root .. '/late-watcher', 'w'))
    marker:write('Watcher allocated during shutdown\n')
    marker:close()
  end
  local event = new_fs_event(...)
  table.insert(watchers, event)
  return event
end
vim.api.nvim_create_autocmd('VimLeave', {
  once = true,
  callback = function()
    for _, event in ipairs(watchers) do
      if not event:is_closing() then
        vim.fn.writefile({ 'Watcher left open during shutdown' }, test_root .. '/late-watcher')
      end
    end
  end,
})

if test_case == 'immediate_exit' then
  local fs_open = uv.fs_open
  local pending_open
  -- Hold the history open until VimLeave to exercise the shutdown race reliably.
  uv.fs_open = function(file, mode, permissions, callback)
    if callback and file == historyfile then
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
  assert(#watchers == 0, 'The test must exit with history loading still pending')
  vim.api.nvim_create_autocmd('VimLeave', {
    once = true,
    callback = function()
      pending_open()
    end,
  })
elseif test_case == 'active_watch' then
  assert(vim.fn.mkdir(test_root .. '/project_nvim') == 1)
  local a, b = test_root .. '/a', test_root .. '/b'
  assert(vim.fn.mkdir(a) == 1)
  assert(vim.fn.mkdir(b) == 1)
  assert(vim.fn.writefile({ a }, historyfile) == 0)
  project_nvim.setup({ manual_mode = true, datapath = test_root })

  assert(
    vim.wait(2000, function()
      return vim.deep_equal(history.get_recent_projects(), { a })
    end, 10),
    'Timed out waiting for the initial history load'
  )

  assert(vim.fn.writefile({ b }, historyfile) == 0)
  assert(
    vim.wait(2000, function()
      return vim.deep_equal(history.get_recent_projects(), { b })
    end, 10),
    'The active watcher must still reload history changes'
  )
  history.delete_project(b)
else
  error('Unknown test case: ' .. test_case)
end

-- The runner verifies this visit was saved after Neovim exits.
history.add_project(test_root)
