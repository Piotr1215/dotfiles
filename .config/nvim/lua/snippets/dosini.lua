local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local sn = ls.snippet_node
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta

return {
  -- Create a systemd service unit file
  s("service", {
    t({"[Unit]", "Description="}), i(1, "Service description"),
    t({"", "After="}), i(2, "network.target"),
    t({"", "", "[Service]", "Type="}), c(3, {
      t("simple"), t("forking"), t("oneshot"), t("notify"), t("dbus")
    }),
    t({"", "Restart="}), c(4, {
      t("no"), t("on-failure"), t("always"), t("on-success"), t("on-watchdog"), t("on-abort")
    }),
    t({"", "RestartSec="}), i(5, "30"),
    t({"", "ExecStart="}), i(6, "/path/to/executable"),
    t({"", "", "[Install]", "WantedBy="}), c(7, {
      t("multi-user.target"), t("default.target"), t("graphical.target"), 
      t("network.target"), t("network-online.target"), t("basic.target")
    }),
    t(""), i(0)
  }),

  -- Create a systemd timer unit file
  s("timer", {
    t({"[Unit]", "Description="}), i(1, "Timer description"),
    t({"", "", "[Timer]", "OnBootSec="}), i(2, "10min"),
    t({"", "OnUnitActiveSec="}), i(3, "1h"),
    t({"", "Unit="}), i(5, "service_name"), t(".service  ;can be ommited, defaults to the service with the same name"),
    t({"", "", "[Install]", "WantedBy="}), c(4, {
      t("timers.target"), t("multi-user.target")
    }),
    t(""), i(0)
  }),

}