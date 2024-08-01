local group_id = vim.api.nvim_create_augroup("LuaReloadModule", { clear = true })

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group_id,
  pattern = "*.lua",
  callback = function()
    local first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
    -- Only reload if the first line is local M = {}
    if first_line and first_line:match "^local%s+M%s*=%s*{}" then
      local file_path = vim.fn.expand "%:p"
      local module_name = vim.fn.fnamemodify(file_path, ":.:r")

      package.loaded[module_name] = nil

      vim.notify("Module Reloaded: " .. module_name, nil, {
        title = "Notification",
        timeout = 500,
        render = "compact",
      })
    end
  end,
  desc = "Reload the current module on save",
})
