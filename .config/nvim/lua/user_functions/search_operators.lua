-- Search Operators Module
-- Provides search-based operators for yank, delete, and change operations
-- Usage: ,yi" (search & yank inside quotes), ,di( (search & delete inside parens), etc.

local M = {}

-- Search operator - handles yank, delete, and change operations
_G.SearchOperator = function(type)
    local pattern = vim.g.search_operator_pattern
    local saved_pos = vim.g.search_operator_saved_pos
    local textobj = vim.g.search_operator_textobj
    local action = vim.g.search_operator_action
    
    if not pattern or not saved_pos then return end
    
    -- Save current register and search register
    local saved_reg = vim.fn.getreg('"')
    local saved_reg_type = vim.fn.getregtype('"')
    local saved_search = vim.fn.getreg('/')
    
    -- Execute search and perform action
    local ok = pcall(function()
        -- Set search register to highlight matches
        vim.fn.setreg('/', pattern)
        vim.opt.hlsearch = true
        
        -- Search forward first
        local found = vim.fn.search(pattern)
        
        -- If not found forward, try searching backward
        if found == 0 then
            found = vim.fn.search(pattern, 'b')
        end
        
        if found == 0 then
            error('Pattern not found')
        end
        
        -- Visual feedback and perform action
        if action == 'yank' then
            vim.cmd('normal! v' .. textobj)
            vim.cmd('redraw')
            vim.cmd('sleep 250m')  -- Show selection for 250ms
            vim.cmd('normal! y')
        elseif action == 'delete' then
            vim.cmd('normal! v' .. textobj)
            vim.cmd('redraw')
            vim.cmd('sleep 250m')  -- Show selection for 250ms
            vim.cmd('normal! d')
        elseif action == 'change' then
            -- For change, select and immediately change (no delay needed)
            vim.cmd('normal! v' .. textobj)
            vim.cmd('normal! c')
            -- Force into insert mode
            vim.cmd('startinsert')
        end
    end)
    
    if ok then
        if action == 'yank' then
            local yanked = vim.fn.getreg('"')
            -- Restore position
            vim.fn.setpos('.', saved_pos)
            -- Paste the yanked text
            vim.cmd('normal! p')
        elseif action == 'delete' then
            vim.notify('Deleted from: ' .. pattern, vim.log.levels.INFO)
        -- For change, cursor stays at the changed location in insert mode
        end
        
        -- Clear search highlight after a delay (except for change where user is still editing)
        if action ~= 'change' then
            vim.defer_fn(function()
                vim.cmd('nohlsearch')
                -- Restore original search pattern
                vim.fn.setreg('/', saved_search)
            end, 500)
        end
    else
        vim.notify('Pattern not found: ' .. pattern, vim.log.levels.ERROR)
        vim.fn.setpos('.', saved_pos)
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

-- Set up the operator functions in Vimscript
function M.setup()
    vim.cmd([[
        function! YankSearchSetup(textobj)
            let g:search_operator_pattern = input('Search for: ')
            if empty(g:search_operator_pattern)
                return ''
            endif
            let g:search_operator_saved_pos = getpos('.')
            let g:search_operator_textobj = a:textobj
            let g:search_operator_action = 'yank'
            set operatorfunc=v:lua.SearchOperator
            return 'g@l'
        endfunction
        
        function! DeleteSearchSetup(textobj)
            let g:search_operator_pattern = input('Search for: ')
            if empty(g:search_operator_pattern)
                return ''
            endif
            let g:search_operator_saved_pos = getpos('.')
            let g:search_operator_textobj = a:textobj
            let g:search_operator_action = 'delete'
            set operatorfunc=v:lua.SearchOperator
            return 'g@l'
        endfunction
        
        function! ChangeSearchSetup(textobj)
            let g:search_operator_pattern = input('Search for: ')
            if empty(g:search_operator_pattern)
                return ''
            endif
            let g:search_operator_saved_pos = getpos('.')
            let g:search_operator_textobj = a:textobj
            let g:search_operator_action = 'change'
            set operatorfunc=v:lua.SearchOperator
            return 'g@l'
        endfunction
    ]])
    
    -- Define text objects and operators
    local text_objects = {
        -- Quote-like objects
        ['"'] = 'double quotes',
        ["'"] = 'single quotes',
        -- Bracket pairs
        ['('] = 'parentheses', [')'] = 'parentheses',
        ['{'] = 'curly braces', ['}'] = 'curly braces', 
        ['['] = 'square brackets', [']'] = 'square brackets',
        -- Word objects
        ['w'] = 'word', ['W'] = 'WORD (space-delimited)',
        ['b'] = 'parentheses block', ['B'] = 'curly braces block',
        -- Other objects
        ['t'] = 'HTML/XML tags',
        ['p'] = 'paragraph',
        ['s'] = 'sentence',
    }
    
    local operators = {
        y = { func = 'YankSearchSetup', verb = 'yank' },
        d = { func = 'DeleteSearchSetup', verb = 'delete' },
        c = { func = 'ChangeSearchSetup', verb = 'change' }
    }
    
    -- Generate mappings for all combinations
    for op_key, op_info in pairs(operators) do
        for obj_key, obj_name in pairs(text_objects) do
            -- Inside text object
            local key_i = ',' .. op_key .. 'i' .. obj_key
            local desc_i = 'Search & ' .. op_info.verb .. ' inside ' .. obj_name
            vim.keymap.set('n', key_i, function() 
                return vim.fn[op_info.func]('i' .. obj_key) 
            end, { expr = true, desc = desc_i })
            
            -- Around text object (skip redundant ones like ib, iB which don't have 'around' versions)
            if not (obj_key:match('[bB]')) then
                local key_a = ',' .. op_key .. 'a' .. obj_key
                local desc_a = 'Search & ' .. op_info.verb .. ' around ' .. obj_name
                vim.keymap.set('n', key_a, function() 
                    return vim.fn[op_info.func]('a' .. obj_key) 
                end, { expr = true, desc = desc_a })
            end
        end
    end
end

return M