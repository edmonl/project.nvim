vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, err = xpcall(function()
        dofile(assert(os.getenv('PROJECT_NVIM_TEST_SPEC')))
      end, debug.traceback)
      if not ok then
        print(err)
        vim.cmd('cquit 1')
      end
      vim.cmd('qa!')
    end)
  end,
})
