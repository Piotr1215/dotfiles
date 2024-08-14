local notify = require "notify"
-- Map the key to call an inline function for kubectl apply
vim.api.nvim_set_keymap("n", "<leader>ka", "", {
  noremap = true,
  silent = false,
  callback = function()
    local current_file = vim.fn.expand "%:p"
    local cmd = "kubectl apply -f " .. current_file
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read "*a"
      handle:close()

      -- Use notify to print the result
      notify(result, "info")
    else
      notify("Failed to execute command", "error")
    end
  end,
})

-- Map the key to call an inline function for kubectl delete
vim.api.nvim_set_keymap("n", "<leader>kd", "", {
  noremap = true,
  silent = false,
  callback = function()
    local current_file = vim.fn.expand "%:p"
    local cmd = "kubectl delete -f " .. current_file
    local handle = io.popen(cmd)
    if handle then
      local result = handle:read "*a"
      handle:close()

      -- Use notify to print the result
      notify(result, "info")
    else
      notify("Failed to execute command", "error")
    end
  end,
})
