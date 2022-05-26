local install_path = '~/.config/nvim/data/site/pack/packer/start/packer.nvim'

if fn.empty(fn.glob(install_path)) > 0 then
  packer_bootstrap = fn.system({
    'git',
    'clone',
    '--depth', '1',
    'https://github.com/wbthomason/packer.nvim',
    install_path
  })
end

return require('packer').startup(function()
  use 'wbthomason/packer.nvim'
end)
