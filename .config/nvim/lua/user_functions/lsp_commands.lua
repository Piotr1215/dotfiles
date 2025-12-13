local M = {}

-- Stop all LSP clients or specific ones by name
-- Usage: :LspStop [optional_server_name]
vim.api.nvim_create_user_command("LspStop", function(opts)
  local clients = vim.lsp.get_clients()
  local server_name = opts.args ~= "" and opts.args or nil

  if server_name then
    -- Stop specific server
    for _, client in ipairs(clients) do
      if client.name == server_name then
        vim.lsp.stop_client(client.id)
        vim.notify(string.format("Stopped LSP: %s", server_name), vim.log.levels.INFO)
        return
      end
    end
    vim.notify(string.format("LSP server '%s' not found", server_name), vim.log.levels.WARN)
  else
    -- Stop all servers
    if #clients == 0 then
      vim.notify("No LSP clients running", vim.log.levels.INFO)
      return
    end

    for _, client in ipairs(clients) do
      vim.lsp.stop_client(client.id)
    end
    vim.notify(string.format("Stopped %d LSP client(s)", #clients), vim.log.levels.INFO)
  end
end, {
  nargs = "?",
  complete = function()
    local clients = vim.lsp.get_clients()
    local names = {}
    for _, client in ipairs(clients) do
      table.insert(names, client.name)
    end
    return names
  end,
  desc = "Stop LSP clients (all or by name)",
})

-- Restart all LSP clients or specific ones by name
-- Usage: :LspRestart [optional_server_name]
vim.api.nvim_create_user_command("LspRestart", function(opts)
  local clients = vim.lsp.get_clients()
  local server_name = opts.args ~= "" and opts.args or nil

  if server_name then
    -- Restart specific server
    for _, client in ipairs(clients) do
      if client.name == server_name then
        local bufs = vim.lsp.get_buffers_by_client_id(client.id)
        vim.lsp.stop_client(client.id)
        vim.defer_fn(function()
          for _, buf in ipairs(bufs) do
            vim.api.nvim_buf_call(buf, function()
              vim.cmd "edit"
            end)
          end
          vim.notify(string.format("Restarted LSP: %s", server_name), vim.log.levels.INFO)
        end, 500)
        return
      end
    end
    vim.notify(string.format("LSP server '%s' not found", server_name), vim.log.levels.WARN)
  else
    -- Restart all servers
    if #clients == 0 then
      vim.notify("No LSP clients running", vim.log.levels.INFO)
      return
    end

    local count = #clients
    for _, client in ipairs(clients) do
      vim.lsp.stop_client(client.id)
    end
    vim.defer_fn(function()
      vim.cmd "edit"
      vim.notify(string.format("Restarted %d LSP client(s)", count), vim.log.levels.INFO)
    end, 500)
  end
end, {
  nargs = "?",
  complete = function()
    local clients = vim.lsp.get_clients()
    local names = {}
    for _, client in ipairs(clients) do
      table.insert(names, client.name)
    end
    return names
  end,
  desc = "Restart LSP clients (all or by name)",
})

-- Show information about LSP clients
-- Usage: :LspInfo
vim.api.nvim_create_user_command("LspInfo", function()
  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    vim.notify("No LSP clients attached", vim.log.levels.INFO)
    return
  end

  local lines = { "LSP Client Information:", "" }
  for _, client in ipairs(clients) do
    table.insert(lines, string.format("Client: %s (id: %d)", client.name, client.id))
    table.insert(lines, string.format("  Root dir: %s", client.config.root_dir or "N/A"))
    table.insert(lines, string.format("  Filetypes: %s", table.concat(client.config.filetypes or {}, ", ")))

    local buffers = vim.lsp.get_buffers_by_client_id(client.id)
    table.insert(lines, string.format("  Attached buffers: %d", #buffers))
    table.insert(lines, "")
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "lspinfo")

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  })
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end, {
  desc = "Show LSP client information",
})

-- Start/enable LSP servers
-- Usage: :LspStart [server_names...]
vim.api.nvim_create_user_command("LspStart", function(opts)
  local servers = vim.split(opts.args, "%s+")
  if #servers == 0 or servers[1] == "" then
    vim.notify("Usage: LspStart <server_name> [server_name...]", vim.log.levels.WARN)
    return
  end

  vim.lsp.enable(servers)
  vim.notify(string.format("Started LSP: %s", table.concat(servers, ", ")), vim.log.levels.INFO)
end, {
  nargs = "+",
  desc = "Start/enable LSP servers",
})

-- Open LSP log file
-- Usage: :LspLog
vim.api.nvim_create_user_command("LspLog", function()
  local log_path = vim.lsp.get_log_path()
  vim.cmd("edit " .. log_path)
end, {
  desc = "Open LSP log file",
})

return M
