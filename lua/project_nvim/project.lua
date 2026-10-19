local config = require('project_nvim.config')
local history = require('project_nvim.utils.history')
local glob = require('project_nvim.utils.globtopattern')
local path = require('project_nvim.utils.path')
local uv = vim.uv
local M = {}

-- Internal states
M.last_project = nil

---Finds a root from a non-ignored LSP client attached to the current buffer.
---@return string? root
---@return string? client_name
function M.find_lsp_root()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.root_dir ~= nil and not vim.tbl_contains(config.options.ignore_lsp, client.name) then
      return client.root_dir, client.name
    end
  end

  return nil
end

function M.find_pattern_root()
  local search_dir = vim.fn.expand('%:p:h', true)
  if vim.fn.has('win32') > 0 then
    search_dir = search_dir:gsub('\\', '/')
  end

  local last_dir_cache = ''
  local curr_dir_cache = {}

  local function get_parent(path)
    path = path:match('^(.*)/')
    if path == '' then
      path = '/'
    end
    return path
  end

  local function get_files(file_dir)
    last_dir_cache = file_dir
    curr_dir_cache = {}

    local dir = uv.fs_scandir(file_dir)
    if dir == nil then
      return
    end

    while true do
      local file = uv.fs_scandir_next(dir)
      if file == nil then
        return
      end

      table.insert(curr_dir_cache, file)
    end
  end

  local function is(dir, identifier)
    dir = dir:match('.*/(.*)')
    return dir == identifier
  end

  local function sub(dir, identifier)
    local path = get_parent(dir)
    while true do
      if is(path, identifier) then
        return true
      end
      local current = path
      path = get_parent(path)
      if current == path then
        return false
      end
    end
  end

  local function child(dir, identifier)
    local path = get_parent(dir)
    return is(path, identifier)
  end

  local function has(dir, identifier)
    if last_dir_cache ~= dir then
      get_files(dir)
    end
    local pattern = glob.globtopattern(identifier)
    for _, file in ipairs(curr_dir_cache) do
      if file:match(pattern) ~= nil then
        return true
      end
    end
    return false
  end

  local function match(dir, pattern)
    local first_char = pattern:sub(1, 1)
    if first_char == '=' then
      return is(dir, pattern:sub(2))
    elseif first_char == '^' then
      return sub(dir, pattern:sub(2))
    elseif first_char == '>' then
      return child(dir, pattern:sub(2))
    else
      return has(dir, pattern)
    end
  end

  -- breadth-first search
  while true do
    for _, pattern in ipairs(config.options.patterns) do
      local exclude = false
      if pattern:sub(1, 1) == '!' then
        exclude = true
        pattern = pattern:sub(2)
      end
      if match(search_dir, pattern) then
        if exclude then
          break
        else
          return search_dir, 'pattern ' .. pattern
        end
      end
    end

    local parent = get_parent(search_dir)
    if parent == search_dir or parent == nil then
      return nil
    end

    search_dir = parent
  end
end

function M.set_pwd(dir, method)
  if dir ~= nil then
    local scope_chdir = config.options.scope_chdir
    if scope_chdir ~= 'global' and scope_chdir ~= 'tab' and scope_chdir ~= 'win' then
      return false
    end

    M.last_project = dir
    history.add_project(dir)

    if vim.fn.getcwd() ~= dir then
      if scope_chdir == 'global' then
        vim.api.nvim_set_current_dir(dir)
      elseif scope_chdir == 'tab' then
        vim.cmd('tcd ' .. vim.fn.fnameescape(dir))
      else
        vim.cmd('lcd ' .. vim.fn.fnameescape(dir))
      end

      if config.options.silent_chdir == false then
        vim.notify('Set CWD to ' .. dir .. ' using ' .. method)
      end
    end
    return true
  end

  return false
end

function M.get_project_root()
  -- returns project root, as well as method
  for _, detection_method in ipairs(config.options.detection_methods) do
    if detection_method == 'lsp' then
      local root, lsp_name = M.find_lsp_root()
      if root ~= nil then
        return root, '"' .. lsp_name .. '"' .. ' lsp'
      end
    elseif detection_method == 'pattern' then
      local root, method = M.find_pattern_root()
      if root ~= nil then
        return root, method
      end
    end
  end
end

function M.is_file()
  local buf_type = vim.bo.buftype

  local whitelisted_buf_type = { '', 'acwrite' }
  local is_in_whitelist = false
  for _, wtype in ipairs(whitelisted_buf_type) do
    if buf_type == wtype then
      is_in_whitelist = true
      break
    end
  end
  if not is_in_whitelist then
    return false
  end

  return true
end

function M.on_buf_enter()
  if vim.v.vim_did_enter == 0 then
    return
  end

  if not M.is_file() then
    return
  end

  local current_dir = vim.fn.expand('%:p:h', true)
  if not path.exists(current_dir) or path.is_excluded(current_dir) then
    return
  end

  local root, method = M.get_project_root()
  M.set_pwd(root, method)
end

function M.add_project_manually()
  local current_dir = vim.fn.expand('%:p:h', true)
  M.set_pwd(current_dir, 'manual')
end

---Registers project commands and replaces this plugin's autocommands.
function M.init()
  local group = vim.api.nvim_create_augroup('project_nvim', { clear = true })
  if not config.options.manual_mode then
    vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter' }, {
      group = group,
      nested = true,
      callback = M.on_buf_enter,
    })

    if vim.tbl_contains(config.options.detection_methods, 'lsp') then
      vim.api.nvim_create_autocmd('LspAttach', {
        group = group,
        nested = true,
        callback = function(event)
          -- Background attachments are handled when their buffer is entered.
          if event.buf == vim.api.nvim_get_current_buf() then
            M.on_buf_enter()
          end
        end,
      })
    end
  end

  vim.cmd([[
    command! ProjectRoot lua require("project_nvim.project").on_buf_enter()
    command! AddProject lua require("project_nvim.project").add_project_manually()
  ]])

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = history.write_projects_to_history,
  })

  history.read_projects_from_history()
end

return M
