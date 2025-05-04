#!/usr/bin/env bash
# __nvim_verbose.sh - Advanced Neovim configuration explorer with Telescope integration
# Allows browsing key mappings, settings, and highlight groups with source information

set -euo pipefail

command_type=${1:-"map"}
current_dir=$(pwd)
temp_file=$(mktemp /tmp/nvim_verbose_XXXXXXXX)

# Create Lua script for key mappings
create_keymaps_script() {
  cat > /tmp/keymaps_script.lua << 'LUAEOF'
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

-- Custom action to show verbose mapping info
local function show_verbose_mapping(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    if selection then
        -- Close telescope
        actions.close(prompt_bufnr)
        
        -- Try to get the mapping info directly from the selection
        local lhs = selection.lhs or selection.value or selection[1]
        local mode = selection.mode or selection[2] or "n"
        
        if type(lhs) == "string" then
            -- Create a new scratch buffer for the verbose output
            vim.cmd('enew')
            vim.cmd('setlocal buftype=nofile bufhidden=wipe noswapfile')
            vim.cmd('nnoremap <buffer> q :q<CR>')
            
            -- Run the verbose command and redirect output to our buffer
            vim.fn.execute('redir => g:verbose_output')
            vim.cmd('silent verbose ' .. mode .. 'map ' .. lhs)
            vim.fn.execute('redir END')
            
            -- Insert the output into the buffer
            vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.g.verbose_output, '\n'))
            vim.cmd('setlocal nomodified readonly')
            vim.cmd('normal! gg')
            
            -- Set a useful buffer name
            vim.cmd('file VerboseMapping:' .. lhs)
        else
            print("Error: Could not determine the key mapping")
        end
    end
end

-- Run telescope with custom mappings
require('telescope.builtin').keymaps({
    attach_mappings = function(_, map)
        -- Use 'enter' to show verbose info
        map('i', '<CR>', show_verbose_mapping)
        map('n', '<CR>', show_verbose_mapping)
        
        -- Keep default mappings
        return true
    end
})
LUAEOF
}

# Create Lua script for settings
create_settings_script() {
  cat > /tmp/options_script.lua << 'LUAEOF'
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

-- Custom action to show verbose option info
local function show_verbose_option(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    if selection then
        -- Close telescope
        actions.close(prompt_bufnr)
        
        -- Create a new scratch buffer for the verbose output
        vim.cmd('enew')
        vim.cmd('setlocal buftype=nofile bufhidden=wipe noswapfile')
        vim.cmd('nnoremap <buffer> q :q<CR>')
        
        -- Run the verbose command and redirect output to our buffer
        vim.fn.execute('redir => g:verbose_output')
        vim.cmd('silent verbose set ' .. selection.value .. '?')
        vim.fn.execute('redir END')
        
        -- Insert the output into the buffer
        vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.g.verbose_output, '\n'))
        vim.cmd('setlocal nomodified readonly')
        vim.cmd('normal! gg')
        
        -- Set a useful buffer name
        vim.cmd('file VerboseSetting:' .. selection.value)
    end
end

-- Run telescope with custom mappings
require('telescope.builtin').vim_options({
    attach_mappings = function(_, map)
        -- Use 'enter' to show verbose info
        map('i', '<CR>', show_verbose_option)
        map('n', '<CR>', show_verbose_option)
        
        -- Keep default mappings
        return true
    end
})
LUAEOF
}

# Create Lua script for highlight groups
create_highlights_script() {
  cat > /tmp/highlights_script.lua << 'LUAEOF'
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

-- Custom action to show verbose highlight info
local function show_verbose_highlight(prompt_bufnr)
    local selection = action_state.get_selected_entry(prompt_bufnr)
    if selection then
        -- Close telescope
        actions.close(prompt_bufnr)
        
        -- Create a new scratch buffer for the verbose output
        vim.cmd('enew')
        vim.cmd('setlocal buftype=nofile bufhidden=wipe noswapfile')
        vim.cmd('nnoremap <buffer> q :q<CR>')
        
        -- Run the verbose command and redirect output to our buffer
        vim.fn.execute('redir => g:verbose_output')
        vim.cmd('silent verbose highlight ' .. selection.value)
        vim.fn.execute('redir END')
        
        -- Insert the output into the buffer
        vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(vim.g.verbose_output, '\n'))
        vim.cmd('setlocal nomodified readonly')
        vim.cmd('normal! gg')
        
        -- Set a useful buffer name
        vim.cmd('file VerboseHighlight:' .. selection.value)
    end
end

-- Run telescope with custom mappings
require('telescope.builtin').highlights({
    attach_mappings = function(_, map)
        -- Use 'enter' to show verbose info
        map('i', '<CR>', show_verbose_highlight)
        map('n', '<CR>', show_verbose_highlight)
        
        -- Keep default mappings
        return true
    end
})
LUAEOF
}

# Main logic
case "$command_type" in
  "map"|"nmap"|"vmap"|"imap")
    create_keymaps_script
    nvim -V1 "$temp_file" -c "cd $current_dir" -c "luafile /tmp/keymaps_script.lua"
    rm -f /tmp/keymaps_script.lua
    ;;
  "set")
    create_settings_script
    nvim -V1 "$temp_file" -c "cd $current_dir" -c "luafile /tmp/options_script.lua"
    rm -f /tmp/options_script.lua
    ;;
  "hi"|"highlight")
    create_highlights_script
    nvim -V1 "$temp_file" -c "cd $current_dir" -c "luafile /tmp/highlights_script.lua"
    rm -f /tmp/highlights_script.lua
    ;;
  *)
    nvim -V1 "$temp_file" -c "cd $current_dir" -c "lua vim.cmd('au VimEnter * call feedkeys(\":\\\\verbose ${command_type} \")')"
    ;;
esac

# Clean up temp file
rm -f "$temp_file"