local eq = assert.are.same
local user_functions = require('user_functions') -- Assuming your generate_mappings function is in this module


describe('Neovim Mappings', function()
  it('should generate the correct mapping command', function()
    local action = 'c'
    local inner_outer = 'i'
    local text_object = 'w'

    local expected_command = '"c' .. action .. inner_outer .. text_object
    local generated_command = neovim_mappings.generate_mappings_command(action, inner_outer, text_object)

    eq(expected_command, generated_command)
  end)
end)
