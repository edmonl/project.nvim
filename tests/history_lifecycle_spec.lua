local project_nvim = require('project_nvim')
local history = require('project_nvim.utils.history')
local uv = vim.uv

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))
local storage_a, storage_b = test_root .. '/storage-a', test_root .. '/storage-b'
local file_a = storage_a .. '/project_nvim/project_history'
local file_b = storage_b .. '/project_nvim/project_history'
local a, b, c = test_root .. '/a', test_root .. '/b', test_root .. '/c'
for _, dir in ipairs({ storage_a .. '/project_nvim', storage_b .. '/project_nvim', a, b, c }) do
  assert(vim.fn.mkdir(dir, 'p') == 1)
end
assert(vim.fn.writefile({ a }, file_a) == 0)
assert(vim.fn.writefile({ b }, file_b) == 0)

local watchers = {}
local new_fs_event = uv.new_fs_event
uv.new_fs_event = function(...)
  local event = new_fs_event(...)
  table.insert(watchers, event)
  return event
end

local opened_files = {}
local fs_open = uv.fs_open
uv.fs_open = function(file, mode, permissions, callback)
  if callback then
    table.insert(opened_files, file)
  end
  return fs_open(file, mode, permissions, callback)
end

local function setup(datapath)
  project_nvim.setup({ manual_mode = true, datapath = datapath })
end

local function wait_for_projects(expected)
  assert(
    vim.wait(2000, function()
      return vim.deep_equal(history.get_recent_projects(), expected)
    end, 10),
    'Expected history ' .. vim.inspect(expected) .. ', got ' .. vim.inspect(history.get_recent_projects())
  )
end

if test_case == 'reconfigure' then
  setup(storage_a)
  wait_for_projects({ a })
  setup(storage_b)
  assert(history.recent_projects == nil, 'Changing storage must discard the previously loaded history')
  wait_for_projects({ b })

  assert(vim.fn.writefile({ c }, file_b) == 0)
  wait_for_projects({ c })
  assert(#watchers == 2, 'Changing storage must replace the watcher')
  assert(watchers[1]:is_closing(), 'The previous watcher must be closed')
  assert(watchers[2]:is_active(), 'The new storage must be watched')

  local reads_before = #opened_files
  assert(vim.fn.writefile({ b }, file_a) == 0)
  assert(not vim.wait(200, function()
    return #opened_files > reads_before
  end, 10), 'Changes under the previous storage directory must not trigger a reload')
elseif test_case == 'repeat_setup' then
  setup(storage_a)
  wait_for_projects({ a })
  for _ = 1, 3 do
    setup(storage_a)
    assert(vim.deep_equal(history.get_recent_projects(), { a }), 'Repeated setup must keep loaded history available')
  end
  wait_for_projects({ a })

  assert(vim.fn.writefile({ c }, file_a) == 0)
  wait_for_projects({ c })
  assert(#watchers == 1 and watchers[1]:is_active(), 'Repeated setup must retain one active watcher')
  assert(
    #vim.api.nvim_get_autocmds({ group = 'project_nvim_history', event = 'VimLeavePre' }) == 1,
    'Repeated setup must retain one history shutdown hook'
  )
elseif test_case == 'stale_mkdir' then
  local fs_mkdir = uv.fs_mkdir
  local pending_mkdir
  uv.fs_mkdir = function(dir, mode, callback)
    if callback and dir == storage_a .. '/project_nvim' then
      pending_mkdir = function()
        fs_mkdir(dir, mode, callback)
      end
      return
    end
    return fs_mkdir(dir, mode, callback)
  end
  setup(storage_a)
  assert(pending_mkdir, 'The initial load must be waiting to create its storage directory')
  uv.fs_mkdir = fs_mkdir
  setup(storage_b)
  wait_for_projects({ b })

  pending_mkdir()
  assert(
    vim.wait(2000, function()
      return #opened_files == 2
    end, 10),
    'Timed out waiting for the previous storage to open'
  )
  assert(opened_files[2] == file_a, 'A pending load must retain its original storage path')
elseif test_case == 'stale_open' or test_case == 'stale_read' then
  local operation = test_case == 'stale_open' and 'fs_open' or 'fs_read'
  local original = uv[operation]
  local pending_completion
  local pending_fd
  local closed = false
  local fs_close = uv.fs_close
  uv.fs_close = function(fd, callback)
    if fd == pending_fd then
      closed = true
    end
    return fs_close(fd, callback)
  end
  uv[operation] = function(first, second, third, callback)
    if callback then
      return original(first, second, third, function(err, result)
        pending_fd = test_case == 'stale_open' and result or first
        pending_completion = function()
          callback(err, result)
        end
      end)
    end
    return original(first, second, third, callback)
  end
  setup(storage_a)
  assert(
    vim.wait(2000, function()
      return pending_completion ~= nil
    end, 10),
    'Timed out waiting for the initial history load to pause'
  )
  uv[operation] = original
  setup(storage_b)
  wait_for_projects({ b })

  local expected = { b }
  if test_case == 'stale_read' then
    -- Returning to A must not make a read from its earlier initialization valid.
    assert(vim.fn.writefile({ c }, file_a) == 0)
    setup(storage_a)
    expected = { c }
    wait_for_projects(expected)
  end

  pending_completion()
  assert(
    vim.wait(2000, function()
      return closed
    end, 10),
    'A stale load must close its file descriptor'
  )
  assert(vim.deep_equal(history.get_recent_projects(), expected), 'A stale load must not replace the selected history')
else
  error('Unknown test case: ' .. test_case)
end
