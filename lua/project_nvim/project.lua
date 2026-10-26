local config = require('project_nvim.config')
local history = require('project_nvim.utils.history')
local pattern = require('project_nvim.pattern')
local path = require('project_nvim.utils.path')
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

---Finds a pattern root for the current buffer using the configured patterns.
---@return string? root
---@return string? method
function M.find_pattern_root()
  return pattern.find_root(vim.fn.expand('%:p:h', true), config.options.patterns)
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

---Registers project commands and replaces project-detection autocommands.
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
end

return M
