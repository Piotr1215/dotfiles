-- Sidekick NES (Next Edit Suggestions) keybindings
-- These must load after mappings.lua to override any conflicts

-- Jump to next suggestion OR apply if at last suggestion
vim.keymap.set("n", "<Tab>", function()
	if not require("sidekick").nes_jump_or_apply() then
		return "<Tab>"
	end
end, { expr = true, desc = "NES: Jump/Apply Next Edit" })

-- Manual NES controls
vim.keymap.set("n", "<leader>nu", function()
	require("sidekick.nes").update()
end, { desc = "NES: Request fresh edits" })

vim.keymap.set("n", "<leader>nj", function()
	require("sidekick.nes").jump()
end, { desc = "NES: Jump to first hunk" })

vim.keymap.set("n", "<leader>na", function()
	require("sidekick.nes").apply()
end, { desc = "NES: Apply all edits" })

vim.keymap.set("n", "<leader>nc", function()
	require("sidekick").clear()
end, { desc = "NES: Clear suggestions" })

vim.keymap.set("n", "<leader>nt", function()
	require("sidekick.nes").toggle()
end, { desc = "NES: Toggle enable/disable" })
