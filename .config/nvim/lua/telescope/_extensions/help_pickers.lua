return require("telescope").register_extension {
  exports = {
    tldr = require("user_functions.telescope_help").tldr,
    cheat = require("user_functions.telescope_help").cheat,
    shellcheck = require("user_functions.telescope_help").shellcheck,
  },
}
