local notify = require "notify"
local utils = require "user_functions.utils"

-- Function to get the pod name for a given deployment
local function get_pod_name(deployment_name, namespace)
  local get_pod_cmd = "kubectl get pods -n "
    .. namespace
    .. " -l type=test-deployment -o jsonpath='{.items[0].metadata.name}'"
  local pod_handle = io.popen(get_pod_cmd)
  if not pod_handle then
    return nil, "Failed to execute get pod command"
  end

  local pod_name = pod_handle:read "*a"
  pod_handle:close()

  pod_name = vim.trim(pod_name)
  if pod_name == "" then
    return nil, "No pod found for deployment: " .. deployment_name
  end

  return pod_name, nil
end

-- Function to fetch logs for a given pod
local function fetch_pod_logs(pod_name, namespace)
  local cmd = "kubectl logs " .. pod_name .. " -n " .. namespace .. " 2>&1"
  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute logs command"
  end

  local result = handle:read "*a"
  handle:close()

  result = vim.trim(result)
  if result == "" then
    return nil, "No logs were returned for pod: " .. pod_name
  end

  return vim.split(result, "\n"), nil
end

-- Function to display logs in a floating window
local function display_logs_in_floating_window(logs)
  utils.create_floating_scratch(logs)
end

-- Main function to fetch and display logs for a deployment
local function kubectl_logs_for_deployment(deployment_name, namespace)
  local pod_name, pod_err = get_pod_name(deployment_name, namespace)
  if pod_err then
    notify(pod_err, "error", { title = "kubectl logs" })
    return
  end

  local logs, logs_err = fetch_pod_logs(pod_name, namespace)
  if logs_err then
    notify(logs_err, "error", { title = "kubectl logs" })
    return
  end

  display_logs_in_floating_window(logs)
end

-- Function to execute kubectl command and handle notifications
local function kubectl_command(action, use_floating_window)
  local current_file = vim.fn.expand "%:p"
  local cmd = "kubectl " .. action .. " -f " .. current_file .. " 2>&1" -- Capture both stdout and stderr
  local handle = io.popen(cmd)

  if handle then
    local result = handle:read "*a"
    handle:close()

    if result and result ~= "" then
      local formatted_result = vim.split(vim.trim(result), "\n")

      if use_floating_window then
        utils.create_floating_scratch(formatted_result)
      else
        notify(formatted_result, "info", { title = "kubectl " .. action })
      end
    else
      notify("Command executed but no output was returned", "warn", { title = "kubectl " .. action })
    end
  else
    notify("Failed to execute command", "error", { title = "kubectl " .. action })
  end
end

-- Map the key to call an inline function for kubectl apply
vim.api.nvim_set_keymap("n", "<leader>ka", "", {
  noremap = true,
  silent = false,
  callback = function()
    kubectl_command "apply"
  end,
})

-- Map the key to call an inline function for kubectl delete
vim.api.nvim_set_keymap("n", "<leader>kd", "", {
  noremap = true,
  silent = false,
  callback = function()
    kubectl_command "delete"
  end,
})

-- Map the key to call an inline function for kubectl logs
vim.api.nvim_set_keymap("n", "<leader>kl", "", {
  noremap = true,
  silent = false,
  callback = function()
    kubectl_logs_for_deployment("nginx-test", "team-b") -- Replace with your actual deployment and namespace
  end,
})
