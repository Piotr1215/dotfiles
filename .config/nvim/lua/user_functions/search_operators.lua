-- Search Operators Module
-- Provides search-based operators for yank, delete, and change operations
-- Usage: ,yi" (search & yank inside quotes), ,di( (search & delete inside parens), etc.

local M = {}

-- Search operator - handles yank, delete, and change operations
_G.SearchOperator = function(type)
    local pattern = vim.g.search_operator_pattern
    local saved_pos = vim.g.search_operator_saved_pos  -- Used for yank and delete
    local textobj = vim.g.search_operator_textobj
    local action = vim.g.search_operator_action
    
    if not pattern or not textobj or not action then return end
    
    -- Save current register and search register
    local saved_reg = vim.fn.getreg('"')
    local saved_reg_type = vim.fn.getregtype('"')
    local saved_search = vim.fn.getreg('/')
    
    -- Execute action at current position (where search landed)
    -- No need to search again - we're already at the right place
    local ok = pcall(function()
        -- Visual feedback and perform action
        if action == 'yank' then
            vim.cmd('normal v' .. textobj)  -- Remove ! to allow mappings
            vim.cmd('redraw')
            vim.cmd('sleep 250m')  -- Show selection for 250ms
            vim.cmd('normal! y')
        elseif action == 'delete' then
            vim.cmd('normal v' .. textobj)  -- Remove ! to allow mappings
            vim.cmd('redraw')
            vim.cmd('sleep 250m')  -- Show selection for 250ms
            vim.cmd('normal! d')
        elseif action == 'change' then
            -- For change, select and immediately change (no delay needed)
            vim.cmd('normal v' .. textobj)  -- Remove ! to allow mappings
            vim.cmd('normal! c')
            -- Force into insert mode
            vim.cmd('startinsert')
        elseif action == 'visual' then
            -- For visual, just select and stay in visual mode
            vim.cmd('normal v' .. textobj)  -- Remove ! to allow mappings
            -- Stay in visual mode - don't do anything else
        end
    end)
    
    if ok then
        if action == 'yank' and saved_pos then
            -- Restore position
            vim.fn.setpos('.', saved_pos)
            -- Don't paste - just yank only behavior
            -- vim.cmd('normal! p')
        elseif action == 'delete' and saved_pos then
            -- Restore position after delete
            vim.fn.setpos('.', saved_pos)
        -- For change, cursor stays at the changed location in insert mode
        end
        
        -- Clear search highlight after a delay (except for change/visual where user is still active)
        if action ~= 'change' and action ~= 'visual' then
            vim.defer_fn(function()
                vim.cmd('nohlsearch')
                -- Restore original search pattern
                vim.fn.setreg('/', saved_search)
            end, 500)
        end
    else
        if saved_pos then
            vim.fn.setpos('.', saved_pos)
        end
        -- Restore original register and search
        vim.fn.setreg('"', saved_reg, saved_reg_type)
        vim.fn.setreg('/', saved_search)
        vim.cmd('nohlsearch')
    end
    
    -- Cleanup
    vim.g.search_operator_pattern = nil
    vim.g.search_operator_saved_pos = nil
    vim.g.search_operator_textobj = nil
    vim.g.search_operator_action = nil
end


-- Set up the operator functions
function M.setup()
    -- New approach: Store the pending operation and trigger search
    _G.SearchOperatorPending = {}
    
    -- Function to be called after search completes
    _G.ExecuteSearchOperator = function()
        local pending = _G.SearchOperatorPending
        if not pending or not pending.action or not pending.textobj then
            -- Clear any stale autocmds
            vim.cmd('silent! autocmd! SearchOperatorExecute')
            return
        end
        
        local pattern = vim.fn.getreg('/')
        if not pattern or pattern == '' then
            _G.SearchOperatorPending = {}
            vim.cmd('silent! autocmd! SearchOperatorExecute')
            return
        end
        
        -- Store state for operator
        vim.g.search_operator_pattern = pattern
        -- For yank and delete, save the original position to return to after the operation
        -- For change, we don't need it as cursor stays in insert mode at the changed location
        vim.g.search_operator_saved_pos = pending.saved_pos_for_yank
        vim.g.search_operator_textobj = pending.textobj
        vim.g.search_operator_action = pending.action
        
        -- Clear pending
        _G.SearchOperatorPending = {}
        
        -- Set operator function and execute
        vim.opt.operatorfunc = 'v:lua.SearchOperator'
        vim.api.nvim_feedkeys('g@l', 'n', false)
    end
    
    -- Create setup functions that initiate search
    _G.YankSearchSetup = function(textobj)
        -- Store pending operation
        _G.SearchOperatorPending = {
            action = 'yank',
            textobj = textobj,
            saved_pos_for_yank = vim.fn.getpos('.')  -- Only needed for yank to return and paste
        }
        
        -- Show prompt
        vim.api.nvim_echo({{'Search & yank ' .. textobj .. ': ', 'Question'}}, false, {})
        
        -- Clear any existing autocmd and set up fresh one
        vim.cmd([[
            silent! augroup! SearchOperatorExecute
            augroup SearchOperatorExecute
                autocmd!
                autocmd CmdlineLeave / ++once call v:lua.ExecuteSearchOperator()
            augroup END
        ]])
        
        -- Return '/' to enter search mode
        return '/'
    end
    
    _G.DeleteSearchSetup = function(textobj)
        -- Store pending operation
        _G.SearchOperatorPending = {
            action = 'delete',
            textobj = textobj,
            saved_pos_for_yank = vim.fn.getpos('.')  -- Save position for delete too
        }
        
        -- Show prompt
        vim.api.nvim_echo({{'Search & delete ' .. textobj .. ': ', 'Question'}}, false, {})
        
        -- Clear any existing autocmd and set up fresh one
        vim.cmd([[
            silent! augroup! SearchOperatorExecute
            augroup SearchOperatorExecute
                autocmd!
                autocmd CmdlineLeave / ++once call v:lua.ExecuteSearchOperator()
            augroup END
        ]])
        
        -- Return '/' to enter search mode
        return '/'
    end
    
    _G.ChangeSearchSetup = function(textobj)
        -- Store pending operation
        _G.SearchOperatorPending = {
            action = 'change',
            textobj = textobj
        }
        
        -- Show prompt
        vim.api.nvim_echo({{'Search & change ' .. textobj .. ': ', 'Question'}}, false, {})
        
        -- Clear any existing autocmd and set up fresh one
        vim.cmd([[
            silent! augroup! SearchOperatorExecute
            augroup SearchOperatorExecute
                autocmd!
                autocmd CmdlineLeave / ++once call v:lua.ExecuteSearchOperator()
            augroup END
        ]])
        
        -- Return '/' to enter search mode
        return '/'
    end
    
    _G.VisualSearchSetup = function(textobj)
        -- Store pending operation
        _G.SearchOperatorPending = {
            action = 'visual',
            textobj = textobj
            -- No saved_pos needed - we want to stay at the selection
        }
        
        -- Show prompt
        vim.api.nvim_echo({{'Search & select ' .. textobj .. ': ', 'Question'}}, false, {})
        
        -- Clear any existing autocmd and set up fresh one
        vim.cmd([[
            silent! augroup! SearchOperatorExecute
            augroup SearchOperatorExecute
                autocmd!
                autocmd CmdlineLeave / ++once call v:lua.ExecuteSearchOperator()
            augroup END
        ]])
        
        -- Return '/' to enter search mode
        return '/'
    end
    
    -- Define text objects and operators
    local text_objects = {
        -- Quote-like objects
        ['"'] = 'double quotes',
        ["'"] = 'single quotes',
        ['`'] = 'backticks',
        -- Bracket pairs
        ['('] = 'parentheses', [')'] = 'parentheses',
        ['{'] = 'curly braces', ['}'] = 'curly braces', 
        ['['] = 'square brackets', [']'] = 'square brackets',
        ['<'] = 'angle brackets', ['>'] = 'angle brackets',
        -- Word objects
        ['w'] = 'word', ['W'] = 'WORD (space-delimited)',
        ['b'] = 'parentheses block', ['B'] = 'curly braces block',
        -- Line and file objects
        ['l'] = 'line',
        ['e'] = 'entire buffer',
        -- Other objects
        ['t'] = 'HTML/XML tags',
        ['p'] = 'paragraph',
        ['s'] = 'sentence',
        ['m'] = 'markdown code block (triple backticks)',
        -- Common text objects (may need plugins)
        ['i'] = 'indentation',
        ['I'] = 'indentation with line above',
        ['f'] = 'function',
        ['c'] = 'class',
        ['a'] = 'argument',
    }
    
    local operators = {
        y = { func = 'YankSearchSetup', verb = 'yank' },
        d = { func = 'DeleteSearchSetup', verb = 'delete' },
        c = { func = 'ChangeSearchSetup', verb = 'change' },
        v = { func = 'VisualSearchSetup', verb = 'select' }
    }
    
    -- Generate mappings for all combinations
    for op_key, op_info in pairs(operators) do
        for obj_key, obj_name in pairs(text_objects) do
            -- Inside text object
            local key_i = ',' .. op_key .. 'i' .. obj_key
            local desc_i = 'Search & ' .. op_info.verb .. ' inside ' .. obj_name
            vim.keymap.set('n', key_i, function()
                -- Call setup function which returns '/'
                local result = _G[op_info.func]('i' .. obj_key)
                if result == '/' then
                    -- Feed the '/' key to enter search mode with incremental search
                    vim.api.nvim_feedkeys('/', 'n', false)
                end
            end, { desc = desc_i })
            
            -- Around text object (skip redundant ones like ib, iB which don't have 'around' versions)
            if not (obj_key:match('[bB]')) then
                local key_a = ',' .. op_key .. 'a' .. obj_key
                local desc_a = 'Search & ' .. op_info.verb .. ' around ' .. obj_name
                vim.keymap.set('n', key_a, function()
                    -- Call setup function which returns '/'
                    local result = _G[op_info.func]('a' .. obj_key)
                    if result == '/' then
                        -- Feed the '/' key to enter search mode with incremental search
                        vim.api.nvim_feedkeys('/', 'n', false)
                    end
                end, { desc = desc_a })
            end
        end
    end
end

return M