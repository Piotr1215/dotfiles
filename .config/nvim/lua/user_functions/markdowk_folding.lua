local M = {}

_G.folding_enabled = false

function M.toggle_markdown_folding()
	if _G.folding_enabled then
		-- Disable folding
		vim.api.nvim_set_option_value("foldenable", false, { scope = "local" })
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("zR", true, false, true), "n", false) -- Unfold everything
		-- Restore previous number settings
		vim.api.nvim_set_option_value("number", M.previous_number, { scope = "local" })
		vim.api.nvim_set_option_value("relativenumber", M.previous_relativenumber, { scope = "local" })
		_G.folding_enabled = false
	else
		-- Enable folding
		-- Store current number settings
		M.previous_number = vim.api.nvim_get_option_value("number", { scope = "local" })
		M.previous_relativenumber = vim.api.nvim_get_option_value("relativenumber", { scope = "local" })

		vim.api.nvim_set_option_value("foldenable", true, { scope = "local" })
		vim.api.nvim_set_option_value("foldmethod", "expr", { scope = "local" })

		-- Custom fold expression for markdown headers
		vim.api.nvim_set_option_value(
			"foldexpr",
			"getline(v:lnum)=~'^\\s*#' ? '>' . (len(matchstr(getline(v:lnum), '^\\s*#\\+')) - 1) : '='",
			{ scope = "local" }
		)

		vim.api.nvim_set_option_value("foldlevel", 1, { scope = "local" }) -- Fold everything to the first level
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("zM", true, false, true), "n", false) -- Fold everything

		-- Set absolute line numbers
		vim.api.nvim_set_option_value("number", true, { scope = "local" })
		vim.api.nvim_set_option_value("relativenumber", false, { scope = "local" })

		_G.folding_enabled = true
	end
end

-- Create a command to toggle markdown folding
vim.api.nvim_create_user_command("ToggleMarkdownFolding", function()
	M.toggle_markdown_folding()
end, {})

vim.cmd("cabbrev tmf ToggleMarkdownFolding")
vim.api.nvim_set_keymap("n", "<leader>tm", ":ToggleMarkdownFolding<CR>", { noremap = true, silent = true })

return M
