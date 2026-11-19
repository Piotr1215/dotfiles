The patches are retired. Rebuild from fork main after the reconciliation PR merges, without applying them.

Piotr: "don't fuck up the s again". On a row with a start attribute, lowercase `s` must only stop the task, with no open, command, page, or note. For a started `+piotr` row, keep the window layout and focus as they are; `HANDOFF_SWITCH=1` suppresses stop navigation. A row without a start attribute keeps its handoff action. Commit `29033f10` broke this rule; `81ffd568` fixed it. Run the isolated selection smoke test before installing a rebuilt binary.
