local config = require('project_nvim.config')
local history = require('project_nvim.utils.history')
local project = require('project_nvim.project')
-- Keep history filesystem watching outside these LSP lifecycle tests.
history.has_watch_setup = true

local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))
local project_dir, other_dir = test_root .. '/project', test_root .. '/other'
assert(vim.fn.mkdir(project_dir) == 1)
assert(vim.fn.mkdir(other_dir) == 1)

local function setup(options)
  config.setup(vim.tbl_extend('force', {
    datapath = test_root,
    patterns = {},
  }, options or {}))
end

local function new_buffer(dir)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, dir .. '/file-' .. buf .. '.lua')
  vim.bo[buf].filetype = 'lua'
  return buf
end

-- Exercise Neovim's real LSP lifecycle without an external server process.
local function server(dispatchers)
  local closing, request_id = false, 0
  local function stop()
    if not closing then
      closing = true
      vim.schedule(function()
        dispatchers.on_exit(0, 0)
      end)
    end
  end

  return {
    request = function(method, _, callback)
      request_id = request_id + 1
      vim.schedule(function()
        callback(nil, method == 'initialize' and { capabilities = {} } or nil)
      end)
      return true, request_id
    end,
    notify = function(method)
      if method == 'exit' then
        stop()
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = stop,
  }
end

local client_ids = {}
local function start_client(root, buf, name)
  local attached = 0
  local on_attach = function()
    attached = attached + 1
  end
  local client_config = {
    name = name or 'project-test-' .. (#client_ids + 1),
    cmd = server,
    root_dir = root,
    on_attach = on_attach,
  }
  local id = assert(vim.lsp.start(client_config, { bufnr = buf }))
  table.insert(client_ids, id)
  assert(
    vim.wait(2000, function()
      return attached > 0
    end, 10),
    'Timed out waiting for LSP attachment'
  )
  assert(attached == 1, 'The client on_attach callback must run exactly once')
  assert(client_config.on_attach == on_attach, 'The plugin must not wrap client callbacks')
  return id
end

local function assert_attach_handlers(count)
  assert(#vim.api.nvim_get_autocmds({ group = 'project_nvim', event = 'LspAttach' }) == count)
end

local current_buf = new_buffer(project_dir)
local background_buf = new_buffer(other_dir)
vim.api.nvim_set_current_buf(current_buf)
vim.api.nvim_set_current_dir(test_root)

if test_case == 'root_selection' then
  setup({ manual_mode = true, ignore_lsp = { 'ignored' }, patterns = { 'project.marker' } })
  assert(vim.fn.writefile({}, project_dir .. '/project.marker') == 0)
  assert(project.find_lsp_root() == nil)

  start_client(other_dir, current_buf, 'ignored')
  start_client(nil, current_buf, 'rootless')
  start_client(other_dir, background_buf, 'unrelated')
  assert(project.find_lsp_root() == nil, 'Ignored, rootless and unrelated clients must not supply a root')
  assert(project.get_project_root() == project_dir, 'Pattern detection must remain a fallback')

  local valid_id = start_client(test_root, current_buf, 'valid')
  local root, name = project.find_lsp_root()
  assert(root == test_root and name == 'valid', 'Attached clients do not require config.filetypes')
  assert(project.get_project_root() == test_root)

  config.options.detection_methods = { 'pattern', 'lsp' }
  assert(project.get_project_root() == project_dir, 'Detection-method order must be respected')
  config.options.detection_methods = { 'lsp', 'pattern' }
  vim.lsp.buf_detach_client(current_buf, valid_id)
  assert(project.get_project_root() == project_dir)
elseif test_case == 'attach_lifecycle' then
  local original_start, original_start_client = vim.lsp.start, vim.lsp.start_client
  setup()
  assert(vim.lsp.start == original_start and vim.lsp.start_client == original_start_client)

  local id = start_client(project_dir, current_buf)
  assert(vim.fn.getcwd() == project_dir, 'Attachment must update the active project')
  assert(project.last_project == project_dir)
  assert(vim.deep_equal(history.session_projects, { project_dir }))

  history.session_projects = {}
  start_client(other_dir, background_buf)
  assert(vim.api.nvim_get_current_buf() == current_buf)
  assert(vim.fn.getcwd() == project_dir, 'A background attachment must not change the active directory')
  assert(project.last_project == project_dir)
  assert(vim.deep_equal(history.session_projects, {}))

  vim.api.nvim_set_current_buf(background_buf)
  assert(vim.fn.getcwd() == other_dir, 'Entering an attached background buffer must detect its root')

  local next_buf = new_buffer(project_dir)
  vim.api.nvim_set_current_buf(next_buf)
  assert(vim.lsp.buf_attach_client(next_buf, id))
  assert(vim.fn.getcwd() == project_dir, 'Reusing an existing client must also trigger root detection')
elseif test_case == 'reconfigure' then
  setup()
  setup()
  assert_attach_handlers(1)
  history.session_projects = {}
  local id = start_client(project_dir, current_buf)
  assert(vim.deep_equal(history.session_projects, { project_dir }), 'Repeated setup must not duplicate updates')

  setup({ manual_mode = true })
  assert_attach_handlers(0)
  vim.api.nvim_set_current_dir(test_root)
  history.session_projects = {}
  local manual_buf = new_buffer(project_dir)
  vim.api.nvim_set_current_buf(manual_buf)
  assert(vim.lsp.buf_attach_client(manual_buf, id))
  assert(vim.fn.getcwd() == test_root)
  assert(vim.deep_equal(history.session_projects, {}))
  vim.cmd('ProjectRoot')
  assert(vim.fn.getcwd() == project_dir, 'Manual root detection must still work')

  setup({ detection_methods = { 'pattern' } })
  assert_attach_handlers(0)
  vim.api.nvim_set_current_dir(test_root)
  local pattern_buf = new_buffer(project_dir)
  vim.api.nvim_set_current_buf(pattern_buf)
  assert(vim.lsp.buf_attach_client(pattern_buf, id))
  assert(vim.fn.getcwd() == test_root, 'Disabling LSP detection must remove the attach handler')

  setup()
  assert_attach_handlers(1)
  local next_buf = new_buffer(project_dir)
  vim.api.nvim_set_current_buf(next_buf)
  assert(vim.lsp.buf_attach_client(next_buf, id))
  assert(vim.fn.getcwd() == project_dir, 'Re-enabling LSP detection must restore the handler')
else
  error('Unknown test case: ' .. test_case)
end

for _, id in ipairs(client_ids) do
  vim.lsp.get_client_by_id(id):stop(true)
end
assert(
  vim.wait(2000, function()
    for _, id in ipairs(client_ids) do
      if vim.lsp.get_client_by_id(id) ~= nil then
        return false
      end
    end
    return true
  end, 10),
  'Timed out waiting for LSP shutdown'
)
