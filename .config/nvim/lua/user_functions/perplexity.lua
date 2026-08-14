-- Perplexity web search into a scratch markdown buffer.
--
-- Not a gp.nvim provider: gp only speaks the OpenAI chat/completions shape,
-- while the Agent API that replaces Sonar on 2026-09-27 takes a preset plus an
-- input array and answers over SSE. __search_internet.py owns that protocol,
-- so search shells out to it rather than going through a gp agent.
--
-- Presets, cheapest first: fast, low, medium, high, xhigh, wide-research.

local M = {}

local script = vim.fn.expand("$HOME/dev/dotfiles/scripts/__search_internet.py")

-- Run a search asynchronously and stream the result into a new vertical split
-- @param query string: what to search for
-- @param preset string|nil: Agent API preset, defaults to "low"
function M.search(query, preset)
	if not query or query == "" then
		vim.notify("Perplexity: empty query", vim.log.levels.WARN)
		return
	end
	preset = preset or "low"

	vim.cmd("vnew")
	local buf = vim.api.nvim_get_current_buf()
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].buftype = "nofile"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# " .. query, "", "searching (" .. preset .. ")..." })

	vim.system({ script, "--preset", preset, query }, { text = true }, function(result)
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			local body = result.code == 0 and result.stdout or ("search failed:\n\n" .. (result.stderr or ""))
			local lines = vim.split("# " .. query .. "\n\n" .. body, "\n", { plain = true })
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		end)
	end)
end

-- Prompt for a query, then search
-- @param preset string|nil: Agent API preset, defaults to "low"
function M.prompt(preset)
	vim.ui.input({ prompt = "Perplexity search: " }, function(query)
		if query then
			M.search(query, preset)
		end
	end)
end

vim.api.nvim_create_user_command("PplxSearch", function(opts)
	M.search(opts.args, opts.bang and "high" or "low")
end, { nargs = "+", bang = true, desc = "Perplexity search (! for the high preset)" })

return M
