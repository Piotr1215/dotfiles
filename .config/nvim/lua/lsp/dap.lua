local dap, dapui = require("dap"), require("dapui")

require 'packer'.startup(function()
  use "mfussenegger/nvim-dap"
end)

dap.adapters.dockerfile = {
  type = 'executable';
  command = 'buildg';
  args = { 'dap', "serve" };
}

dap.adapters.lldb = {
  type = "executable",
  command = "/usr/bin/lldb-vscode", -- adjust as needed
  -- command = "/usr/bin/rust-lldb", -- adjust as needed
  name = "lldb",
}

dap.configurations.rust = {
  {
    name = "Launch",
    type = "lldb",
    request = "launch",
    program = function()
      return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/target/debug/", "file")
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
    args = {},
    runInTerminal = false,
  },
}
dap.configurations.dockerfile = {
  {
    type = "dockerfile",
    name = "Dockerfile Configuration",
    request = "launch",
    stopOnEntry = true,
    program = "${file}",
  },
}

dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
  dapui.close()
end
dap.configurations.go = {
  {
    type = 'go';
    name = 'Debug';
    request = 'launch';
    showLog = false;
    program = "${file}";
    dlvToolPath = vim.fn.exepath('~/go/bin/dlv') -- Adjust to where delve is installed
  },
}

