local config = require('project_nvim.config')
local history = require('project_nvim.utils.history')
local M = {}

---Configures the plugin, initializes history storage, and registers project hooks.
---@param options ProjectOptions?
function M.setup(options)
  config.setup(options)

  vim.opt.autochdir = false -- implicitly unset autochdir

  history.init(config.options.datapath)
  require('project_nvim.project').init()
end

M.get_recent_projects = history.get_recent_projects

return M
