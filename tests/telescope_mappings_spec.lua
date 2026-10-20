local project_nvim = require('project_nvim')
local test_case = assert(os.getenv('PROJECT_NVIM_TEST_CASE'))
local test_root = assert(os.getenv('PROJECT_NVIM_TEST_DIR'))
local bindings, select_default, builtin_call
local prompt_bufnr = 1

local builtin = {}
for _, name in ipairs({ 'find_files', 'file_browser', 'live_grep', 'oldfiles' }) do
  builtin[name] = function(options)
    builtin_call = { name = name, options = options }
  end
end

-- Only the Telescope interfaces used to build the picker are needed here.
local modules = {
  telescope = {
    register_extension = function(extension)
      return extension
    end,
  },
  ['telescope.finders'] = {
    new_table = function(options)
      return options
    end,
  },
  ['telescope.pickers'] = {
    new = function(_, options)
      return {
        find = function()
          bindings = { n = {}, i = {} }
          assert(
            options.attach_mappings(prompt_bufnr, function(mode, key, action, options)
              assert(options == nil or type(options) == 'table', 'Mapping options must be a table')
              assert(bindings[mode][key] == nil, 'Duplicate mapping: ' .. mode .. ' ' .. key)
              bindings[mode][key] = action
            end),
            'The picker must retain Telescope defaults'
          )
        end,
      }
    end,
  },
  ['telescope.config'] = { values = {
    generic_sorter = function()
      return function() end
    end,
  } },
  ['telescope.actions'] = {
    close = function() end,
    _close = function() end,
    select_default = {
      replace = function(_, action)
        select_default = action
      end,
    },
  },
  ['telescope.actions.state'] = {
    get_selected_entry = function()
      return { value = test_root }
    end,
  },
  ['telescope.builtin'] = builtin,
  ['telescope.pickers.entry_display'] = {
    create = function()
      return function(items)
        return items
      end
    end,
  },
}
for name, module in pairs(modules) do
  package.loaded[name] = module
end

project_nvim.setup({ manual_mode = true, datapath = test_root })
local extension = require('telescope._extensions.projects')
local function setup(mappings)
  extension.setup({ mappings = mappings })
end

local function open_picker()
  extension.exports.projects({})
end

if test_case == 'default_mappings' then
  setup()
  open_picker()
  assert(vim.tbl_count(bindings.n) == 6 and vim.tbl_count(bindings.i) == 6)
  for _, key in ipairs({ 'f', 'b', 'd', 's', 'r', 'w' }) do
    assert(type(bindings.n[key]) == 'function')
    assert(bindings.n[key] == bindings.i['<c-' .. key .. '>'])
  end

  bindings.n.f(prompt_bufnr)
  assert(builtin_call.name == 'find_files' and builtin_call.options.cwd == test_root)
  builtin_call = nil
  select_default()
  assert(builtin_call.name == 'find_files', 'Default selection must still find files')
elseif test_case == 'custom_mappings' then
  local custom_mappings = {
    n = { find_project_files = 'p', change_working_directory = '<CR>' },
    i = { recent_project_files = '<c-y>' },
  }
  local original_mappings = vim.deepcopy(custom_mappings)
  setup(custom_mappings)
  assert(vim.deep_equal(custom_mappings, original_mappings), 'Extension setup must not mutate its input')
  open_picker()
  assert(bindings.n.f == nil and bindings.n.w == nil and bindings.i['<c-r>'] == nil)
  assert(bindings.n.p == bindings.i['<c-f>'])
  assert(bindings.i['<c-y>'] == bindings.n.r)
  assert(bindings.n.d ~= nil, 'Unspecified shortcuts must retain their defaults')
  bindings.n.p(prompt_bufnr)
  assert(builtin_call.name == 'find_files')
  bindings.i['<c-y>'](prompt_bufnr)
  assert(builtin_call.name == 'oldfiles' and builtin_call.options.cwd_only)
  builtin_call = nil
  local dir, changed = bindings.n['<CR>'](prompt_bufnr)
  assert(dir == test_root and changed and builtin_call == nil)

  project_nvim.setup({ manual_mode = true, datapath = test_root })
  open_picker()
  assert(bindings.n.p ~= nil and bindings.n.f == nil, 'Project setup must preserve Telescope configuration')

  setup()
  open_picker()
  assert(bindings.n.f ~= nil and bindings.n.p == nil and bindings.n.w ~= nil)
  assert(bindings.i['<c-r>'] ~= nil and bindings.i['<c-y>'] == nil)
elseif test_case == 'disabled_mappings' then
  setup({
    n = { find_project_files = false, delete_project = false },
    i = { delete_project = false },
  })
  open_picker()
  assert(vim.tbl_count(bindings.n) == 4 and vim.tbl_count(bindings.i) == 5)
  assert(bindings.n.f == nil and bindings.n.d == nil and bindings.i['<c-d>'] == nil)
  assert(bindings.i['<c-f>'] ~= nil, 'Disabling a shortcut must only affect its configured mode')
  assert(bindings.n.w == bindings.i['<c-w>'])
  select_default()
  assert(builtin_call.name == 'find_files', 'Disabling shortcuts must preserve default selection')
else
  error('Unknown test case: ' .. test_case)
end
