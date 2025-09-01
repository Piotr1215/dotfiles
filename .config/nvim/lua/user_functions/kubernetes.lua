local notify = require("notify")
local utils = require("user_functions.utils")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local Job = require("plenary.job")

local M = {}

-- Helper function to run kubectl commands
local function run_kubectl_command(args)
	local result = ""
	local job = Job:new({
		command = "kubectl",
		args = args,
		on_stdout = function(_, data)
			result = result .. data .. "\n"
		end,
	})
	job:sync()
	return vim.trim(result)
end

-- Get current context
local function get_current_context()
	return run_kubectl_command({ "config", "current-context" })
end

-- Get current namespace
local function get_current_namespace()
	local ns = run_kubectl_command({ "config", "view", "--minify", "-o", "jsonpath={..namespace}" })
	return ns ~= "" and ns or "default"
end

-- Function to get the pod name for a given deployment
local function get_pod_name(deployment_name, namespace)
	local get_pod_cmd = "kubectl get pods -n "
		.. namespace
		.. " -l type=test-deployment -o jsonpath='{.items[0].metadata.name}'"
	local pod_handle = io.popen(get_pod_cmd)
	if not pod_handle then
		return nil, "Failed to execute get pod command"
	end

	local pod_name = pod_handle:read("*a")
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

	local result = handle:read("*a")
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
	local current_file = vim.fn.expand("%:p")
	local cmd = "kubectl " .. action .. " -f " .. current_file .. " 2>&1" -- Capture both stdout and stderr
	local handle = io.popen(cmd)

	if handle then
		local result = handle:read("*a")
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
		kubectl_command("apply")
	end,
})

-- Map the key to call an inline function for kubectl delete
vim.api.nvim_set_keymap("n", "<leader>kd", "", {
	noremap = true,
	silent = false,
	callback = function()
		kubectl_command("delete")
	end,
})

-- Telescope picker for pods
function M.telescope_pods()
	local namespace = get_current_namespace()
	local pods_json = run_kubectl_command({ "get", "pods", "-n", namespace, "-o", "json" })
	local pods_data = vim.json.decode(pods_json)

	if not pods_data or not pods_data.items then
		notify("No pods found", "warn", { title = "Kubernetes" })
		return
	end

	local pods = {}
	for _, pod in ipairs(pods_data.items) do
		local status = pod.status.phase
		local ready = 0
		local total = 0

		if pod.status.containerStatuses then
			for _, container in ipairs(pod.status.containerStatuses) do
				total = total + 1
				if container.ready then
					ready = ready + 1
				end
			end
		end

		table.insert(pods, {
			name = pod.metadata.name,
			namespace = pod.metadata.namespace,
			status = status,
			ready = string.format("%d/%d", ready, total),
			age = pod.metadata.creationTimestamp,
			display = string.format(
				"%-50s %-10s %s",
				pod.metadata.name,
				status,
				ready and total and string.format("%d/%d", ready, total) or "0/0"
			),
		})
	end

	pickers
		.new({}, {
			prompt_title = "Kubernetes Pods (" .. namespace .. ")",
			finder = finders.new_table({
				results = pods,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Pod Details",
				define_preview = function(self, entry)
					local pod = entry.value
					local details = run_kubectl_command({ "describe", "pod", pod.name, "-n", pod.namespace })
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(details, "\n"))
					vim.api.nvim_buf_set_option(self.state.bufnr, "filetype", "yaml")
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						local pod = selection.value
						vim.ui.select(
							{ "Logs", "Describe", "Edit", "Delete", "Shell", "Port Forward" },
							{ prompt = "Select action for " .. pod.name },
							function(choice)
								if choice == "Logs" then
									M.kubectl_logs_for_pod(pod.name, pod.namespace)
								elseif choice == "Describe" then
									M.kubectl_describe("pod", pod.name, pod.namespace)
								elseif choice == "Edit" then
									M.kubectl_edit("pod", pod.name, pod.namespace)
								elseif choice == "Delete" then
									M.kubectl_delete_resource("pod", pod.name, pod.namespace)
								elseif choice == "Shell" then
									M.kubectl_exec_shell(pod.name, pod.namespace)
								elseif choice == "Port Forward" then
									M.kubectl_port_forward(pod.name, pod.namespace)
								end
							end
						)
					end
				end)

				-- Additional mappings
				map("i", "<C-l>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						actions.close(prompt_bufnr)
						M.kubectl_logs_for_pod(selection.value.name, selection.value.namespace)
					end
				end)

				map("i", "<C-e>", function()
					local selection = action_state.get_selected_entry()
					if selection then
						actions.close(prompt_bufnr)
						M.kubectl_exec_shell(selection.value.name, selection.value.namespace)
					end
				end)

				return true
			end,
		})
		:find()
end

-- Telescope picker for deployments
function M.telescope_deployments()
	local namespace = get_current_namespace()
	local deployments_json = run_kubectl_command({ "get", "deployments", "-n", namespace, "-o", "json" })
	local deployments_data = vim.json.decode(deployments_json)

	if not deployments_data or not deployments_data.items then
		notify("No deployments found", "warn", { title = "Kubernetes" })
		return
	end

	local deployments = {}
	for _, deploy in ipairs(deployments_data.items) do
		local ready = deploy.status.readyReplicas or 0
		local total = deploy.spec.replicas or 0

		table.insert(deployments, {
			name = deploy.metadata.name,
			namespace = deploy.metadata.namespace,
			ready = string.format("%d/%d", ready, total),
			display = string.format("%-50s %s", deploy.metadata.name, string.format("%d/%d", ready, total)),
		})
	end

	pickers
		.new({}, {
			prompt_title = "Kubernetes Deployments (" .. namespace .. ")",
			finder = finders.new_table({
				results = deployments,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						local deploy = selection.value
						vim.ui.select(
							{ "Scale", "Restart", "Edit", "Describe", "Delete", "Logs" },
							{ prompt = "Select action for " .. deploy.name },
							function(choice)
								if choice == "Scale" then
									vim.ui.input({ prompt = "Number of replicas: " }, function(replicas)
										if replicas then
											M.kubectl_scale_deployment(deploy.name, deploy.namespace, replicas)
										end
									end)
								elseif choice == "Restart" then
									M.kubectl_restart_deployment(deploy.name, deploy.namespace)
								elseif choice == "Edit" then
									M.kubectl_edit("deployment", deploy.name, deploy.namespace)
								elseif choice == "Describe" then
									M.kubectl_describe("deployment", deploy.name, deploy.namespace)
								elseif choice == "Delete" then
									M.kubectl_delete_resource("deployment", deploy.name, deploy.namespace)
								elseif choice == "Logs" then
									kubectl_logs_for_deployment(deploy.name, deploy.namespace)
								end
							end
						)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Telescope picker for services
function M.telescope_services()
	local namespace = get_current_namespace()
	local services_json = run_kubectl_command({ "get", "services", "-n", namespace, "-o", "json" })
	local services_data = vim.json.decode(services_json)

	if not services_data or not services_data.items then
		notify("No services found", "warn", { title = "Kubernetes" })
		return
	end

	local services = {}
	for _, svc in ipairs(services_data.items) do
		local ports = {}
		if svc.spec.ports then
			for _, port in ipairs(svc.spec.ports) do
				table.insert(ports, string.format("%s:%d", port.protocol or "TCP", port.port))
			end
		end

		table.insert(services, {
			name = svc.metadata.name,
			namespace = svc.metadata.namespace,
			type = svc.spec.type,
			cluster_ip = svc.spec.clusterIP,
			ports = table.concat(ports, ","),
			display = string.format(
				"%-30s %-15s %-15s %s",
				svc.metadata.name,
				svc.spec.type,
				svc.spec.clusterIP or "None",
				table.concat(ports, ",")
			),
		})
	end

	pickers
		.new({}, {
			prompt_title = "Kubernetes Services (" .. namespace .. ")",
			finder = finders.new_table({
				results = services,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						local svc = selection.value
						vim.ui.select(
							{ "Edit", "Describe", "Delete" },
							{ prompt = "Select action for " .. svc.name },
							function(choice)
								if choice == "Edit" then
									M.kubectl_edit("service", svc.name, svc.namespace)
								elseif choice == "Describe" then
									M.kubectl_describe("service", svc.name, svc.namespace)
								elseif choice == "Delete" then
									M.kubectl_delete_resource("service", svc.name, svc.namespace)
								end
							end
						)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Telescope picker for namespaces
function M.telescope_namespaces()
	local namespaces_json = run_kubectl_command({ "get", "namespaces", "-o", "json" })
	local namespaces_data = vim.json.decode(namespaces_json)

	if not namespaces_data or not namespaces_data.items then
		notify("No namespaces found", "warn", { title = "Kubernetes" })
		return
	end

	local current_ns = get_current_namespace()
	local namespaces = {}

	for _, ns in ipairs(namespaces_data.items) do
		local is_current = ns.metadata.name == current_ns
		table.insert(namespaces, {
			name = ns.metadata.name,
			status = ns.status.phase,
			current = is_current,
			display = string.format("%s%-30s %-10s", is_current and "* " or "  ", ns.metadata.name, ns.status.phase),
		})
	end

	pickers
		.new({}, {
			prompt_title = "Kubernetes Namespaces (current: " .. current_ns .. ")",
			finder = finders.new_table({
				results = namespaces,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						M.kubectl_set_namespace(selection.value.name)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Telescope picker for contexts
function M.telescope_contexts()
	local contexts_json = run_kubectl_command({ "config", "get-contexts", "-o", "json" })
	local contexts_data = vim.json.decode(contexts_json)

	if not contexts_data then
		notify("No contexts found", "warn", { title = "Kubernetes" })
		return
	end

	local current_ctx = contexts_data["current-context"]
	local contexts = {}

	for _, ctx in ipairs(contexts_data.contexts or {}) do
		local is_current = ctx.name == current_ctx
		table.insert(contexts, {
			name = ctx.name,
			cluster = ctx.context.cluster,
			user = ctx.context.user,
			namespace = ctx.context.namespace or "default",
			current = is_current,
			display = string.format(
				"%s%-30s %-20s %-15s",
				is_current and "* " or "  ",
				ctx.name,
				ctx.context.cluster,
				ctx.context.namespace or "default"
			),
		})
	end

	pickers
		.new({}, {
			prompt_title = "Kubernetes Contexts",
			finder = finders.new_table({
				results = contexts,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.name,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selection then
						M.kubectl_use_context(selection.value.name)
					end
				end)
				return true
			end,
		})
		:find()
end

-- Function to get logs for a specific pod
function M.kubectl_logs_for_pod(pod_name, namespace)
	local logs, err = fetch_pod_logs(pod_name, namespace)
	if err then
		notify(err, "error", { title = "kubectl logs" })
		return
	end
	display_logs_in_floating_window(logs)
end

-- Function to describe a resource
function M.kubectl_describe(resource_type, resource_name, namespace)
	local cmd = string.format("kubectl describe %s %s -n %s", resource_type, resource_name, namespace)
	local result = vim.fn.system(cmd)
	local lines = vim.split(result, "\n")
	utils.create_floating_scratch(lines)
end

-- Function to edit a resource
function M.kubectl_edit(resource_type, resource_name, namespace)
	local cmd = string.format("kubectl edit %s %s -n %s", resource_type, resource_name, namespace)
	vim.cmd("!" .. cmd)
end

-- Function to delete a resource
function M.kubectl_delete_resource(resource_type, resource_name, namespace)
	vim.ui.select(
		{ "Yes", "No" },
		{ prompt = string.format("Delete %s %s?", resource_type, resource_name) },
		function(choice)
			if choice == "Yes" then
				local cmd = string.format("kubectl delete %s %s -n %s", resource_type, resource_name, namespace)
				local result = vim.fn.system(cmd)
				notify(vim.trim(result), "info", { title = "kubectl delete" })
			end
		end
	)
end

-- Function to exec into a pod
function M.kubectl_exec_shell(pod_name, namespace)
	local containers =
		run_kubectl_command({ "get", "pod", pod_name, "-n", namespace, "-o", "jsonpath={.spec.containers[*].name}" })
	local container_list = vim.split(containers, " ")

	if #container_list > 1 then
		vim.ui.select(container_list, { prompt = "Select container:" }, function(container)
			if container then
				local cmd = string.format(
					"kubectl exec -it %s -c %s -n %s -- /bin/bash || kubectl exec -it %s -c %s -n %s -- /bin/sh",
					pod_name,
					container,
					namespace,
					pod_name,
					container,
					namespace
				)
				vim.cmd("split | terminal " .. cmd)
			end
		end)
	else
		local cmd = string.format(
			"kubectl exec -it %s -n %s -- /bin/bash || kubectl exec -it %s -n %s -- /bin/sh",
			pod_name,
			namespace,
			pod_name,
			namespace
		)
		vim.cmd("split | terminal " .. cmd)
	end
end

-- Function to port-forward
function M.kubectl_port_forward(pod_name, namespace)
	vim.ui.input({ prompt = "Local port:" }, function(local_port)
		if local_port then
			vim.ui.input({ prompt = "Pod port:" }, function(pod_port)
				if pod_port then
					local cmd =
						string.format("kubectl port-forward %s %s:%s -n %s", pod_name, local_port, pod_port, namespace)
					vim.cmd("split | terminal " .. cmd)
				end
			end)
		end
	end)
end

-- Function to scale deployment
function M.kubectl_scale_deployment(deployment_name, namespace, replicas)
	local cmd = string.format("kubectl scale deployment %s --replicas=%s -n %s", deployment_name, replicas, namespace)
	local result = vim.fn.system(cmd)
	notify(vim.trim(result), "info", { title = "kubectl scale" })
end

-- Function to restart deployment
function M.kubectl_restart_deployment(deployment_name, namespace)
	local cmd = string.format("kubectl rollout restart deployment %s -n %s", deployment_name, namespace)
	local result = vim.fn.system(cmd)
	notify(vim.trim(result), "info", { title = "kubectl rollout restart" })
end

-- Function to set namespace
function M.kubectl_set_namespace(namespace)
	local cmd = string.format("kubectl config set-context --current --namespace=%s", namespace)
	local result = vim.fn.system(cmd)
	notify(string.format("Switched to namespace: %s", namespace), "info", { title = "Kubernetes" })
end

-- Function to use context
function M.kubectl_use_context(context)
	local cmd = string.format("kubectl config use-context %s", context)
	local result = vim.fn.system(cmd)
	notify(string.format("Switched to context: %s", context), "info", { title = "Kubernetes" })
end

-- Get all resources in namespace
function M.kubectl_get_all()
	local namespace = get_current_namespace()
	local cmd = string.format("kubectl get all -n %s", namespace)
	local result = vim.fn.system(cmd)
	local lines = vim.split(result, "\n")
	utils.create_floating_scratch(lines)
end

-- Map the key to call an inline function for kubectl apply
vim.api.nvim_set_keymap("n", "<leader>ka", "", {
	noremap = true,
	silent = false,
	callback = function()
		kubectl_command("apply")
	end,
})

-- Map the key to call an inline function for kubectl delete
vim.api.nvim_set_keymap("n", "<leader>kd", "", {
	noremap = true,
	silent = false,
	callback = function()
		kubectl_command("delete")
	end,
})

-- Enhanced keybindings
vim.api.nvim_set_keymap(
	"n",
	"<leader>kp",
	":lua require('user_functions.kubernetes').telescope_pods()<CR>",
	{ noremap = true, silent = true, desc = "Kubernetes Pods" }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>kD",
	":lua require('user_functions.kubernetes').telescope_deployments()<CR>",
	{ noremap = true, silent = true, desc = "Kubernetes Deployments" }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>ks",
	":lua require('user_functions.kubernetes').telescope_services()<CR>",
	{ noremap = true, silent = true, desc = "Kubernetes Services" }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>kn",
	":lua require('user_functions.kubernetes').telescope_namespaces()<CR>",
	{ noremap = true, silent = true, desc = "Kubernetes Namespaces" }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>kc",
	":lua require('user_functions.kubernetes').telescope_contexts()<CR>",
	{ noremap = true, silent = true, desc = "Kubernetes Contexts" }
)
vim.api.nvim_set_keymap(
	"n",
	"<leader>kA",
	":lua require('user_functions.kubernetes').kubectl_get_all()<CR>",
	{ noremap = true, silent = true, desc = "Kubernetes Get All" }
)

-- Quick edit for current file
vim.api.nvim_set_keymap("n", "<leader>ke", "", {
	noremap = true,
	silent = false,
	desc = "Edit current k8s resource",
	callback = function()
		local file = vim.fn.expand("%:t:r")
		local namespace = get_current_namespace()
		-- Try to detect resource type from filename
		local resource_type = "deployment" -- default
		if file:match("svc") or file:match("service") then
			resource_type = "service"
		elseif file:match("pod") then
			resource_type = "pod"
		elseif file:match("cm") or file:match("configmap") then
			resource_type = "configmap"
		elseif file:match("secret") then
			resource_type = "secret"
		elseif file:match("ing") or file:match("ingress") then
			resource_type = "ingress"
		end

		vim.ui.input({ prompt = "Resource name (or leave empty to use filename): ", default = file }, function(name)
			if name and name ~= "" then
				M.kubectl_edit(resource_type, name, namespace)
			end
		end)
	end,
})

-- Get resource from current file
vim.api.nvim_set_keymap("n", "<leader>kg", "", {
	noremap = true,
	silent = false,
	desc = "Get k8s resource from current file",
	callback = function()
		kubectl_command("get", true)
	end,
})

-- Describe resource from current file
vim.api.nvim_set_keymap("n", "<leader>kdd", "", {
	noremap = true,
	silent = false,
	desc = "Describe k8s resource from current file",
	callback = function()
		kubectl_command("describe", true)
	end,
})

return M
