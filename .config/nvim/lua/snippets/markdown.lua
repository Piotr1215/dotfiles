local ls = require "luasnip"
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
local isn = ls.indent_snippet_node

return {
  -- Insert slides title template
  s("sli_title", {
    t { "```bash", "~~~just intro_toilet " },
    i(1, "Title"),
    t { "", "", "~~~", "```" },
    i(0),
  }),

  -- Insert slides plantuml template
  s("sli_plant", {
    t { "```bash", "~~~just plantuml " },
    i(1, "diagram-name"),
    t { "", "", "~~~", "```" },
    i(0),
  }),

  -- Insert slides digraph template
  s("sli_digraph", {
    t { "```bash", "~~~just digraph " },
    i(1, "components"),
    t { "", "", "~~~", "```" },
    i(0),
  }),

  -- Insert slides freetext template
  s("sli_freetext", {
    t { "```bash", "~~~just freetext " },
    i(1, "Text"),
    t { "", "", "~~~", "```" },
    i(0),
  }),

  s("hint", {
    t { '{{< hint "important" >}}', "" },
    i(1, "Important hint"),
    t { "", "{{< /hint >}}" },
    i(0),
  }),

  -- Bold selected text
  s("bold", {
    t "**",
    i(1, "$TM_SELECTED_TEXT"),
    t "**",
    i(0),
  }),

  -- Insert content of /etc/os-release
  s("os", {
    t "${VIM:system('cat /etc/os-release')}",
  }),

  s("vof", {
    t "<!-- vale off -->",
    i(0),
  }),

  s("von", {
    t "<!-- vale on -->",
    i(0),
  }),

  s("expand", {
    t '{{< expand "',
    i(1),
    t '" >}}',
    t { "", "" },
    i(2),
    t { "", "{{< /expand >}}" },
    i(0),
  }),

  -- Link to Killercoda
  s("linkkc", {
    t "[",
    i(1, "Link text"),
    t "]({{TRAFFIC_HOST1_",
    i(2, "PORT"),
    t "}})",
    i(0),
  }),

  -- Details HTML snippet
  s("det", {
    t "### ",
    i(1, "TASK_DETAILS"),
    t { "", "", "<details>", "<summary>click to see the answer</summary>", "<code>" },
    i(2, "ANSWER"),
    t { "</code>", "</details>" },
    i(0),
  }),

  -- Highlight markdown text as important, it will render differently depending on the diff highlighting tooling
  s("diff", {
    t { "```diff", "! " },
    i(1, "TEXT"),
    t { " !", "```" },
    i(0),
  }),

  -- Insert href reference at the bottom
  s("refh", {
    t '<a id="',
    i(1),
    t '" href="$CLIPBOARD">[[',
    i(1),
    t "]]</a> : ",
    i(3, "desc"),
  }),

  -- Insert reference to something
  s("ref", {
    t "[[",
    i(1),
    t "]](#",
    i(1),
    t ")",
  }),

  -- Inserts YAML code snippet
  s("yml", {
    t { "```yaml", "" },
    i(1),
    t { "", "```", "" },
    i(0),
  }),

  -- Inserts rust code snippet
  s("rst", {
    t { "```rust", "" },
    i(1),
    t { "", "```", "" },
    i(0),
  }),

  -- Inserts bash code snippet
  s("bsh", {
    t { "```bash", "" },
    i(1),
    t { "", "```", "" },
    i(0),
  }),

  -- Inserts slides pre-processing snippet
  s("slides_pre", {
    t { "```bash", "~~~" },
    i(1, "command"),
    t { "" },
    i(0),
    t { "", "~~~", "```" },
  }),

  -- Inserts tmux client switch snippet
  s("tmx", {
    t { "```bash", "tmux switchc -t " },
    i(1),
    t { "", "```", "" },
    i(0),
  }),

  -- Wrap selected text in a Mark tag with color
  s("mark", {
    t '<Mark color="',
    c(1, { t "lightgray", t "red", t "blue", t "green" }),
    t '">',
    i(2, "$TM_SELECTED_TEXT"),
    t "</Mark>",
  }),

  -- Wrap selected in parenthesis
  s("par", {
    t "[",
    i(1, "$TM_SELECTED_TEXT"),
    t "]",
  }),

  -- Inserts bash code snippet
  s("bshs", {
    t { "```bash", "" },
    i(1, "$TM_SELECTED_TEXT"),
    t { "", "```", "" },
    i(0),
  }),

  -- Front matter snippet for docosaurus docs
  s("docyaml", {
    t { "---", "title: " },
    i(1, "title"),
    t { "", "sidebar_label: " },
    i(2, "label"),
    t { "", "tags:", "	- " },
    i(3, "tag1"),
    t { "", "	- " },
    i(4, "tag1"),
    t { "", "---", "" },
    i(0),
  }),

  -- Insert header with slides theme
  s("theme", {
    t {
      "---",
      "theme: ~/slides-themes/theme.json",
      "author: Piotr Zaniewski",
      "date: MMMM dd, YYYY",
      "paging: Slide %d / %d",
      "---",
    },
  }),

  -- Insert table with 2 rows and 3 columns. First row is heading.
  s("table", {
    t "| ",
    i(1, "Column1"),
    t "  | ",
    i(2, "Column2"),
    t "   | ",
    i(3, "Column3"),
    t { "   |", "|-------------- | -------------- | -------------- |", "| " },
    i(4, "Item1"),
    t "    | ",
    i(5, "Item1"),
    t "     | ",
    i(6, "Item1"),
    t { "     |", "" },
    i(0),
  }),

  -- Insert proxy link
  s("proxy", {
    t "![",
    i(1, "DiagramName"),
    t "](http://www.plantuml.com/plantuml/proxy?cache=yes&src=https://raw.githubusercontent.com/Piotr1215/",
    i(2, "Repository"),
    t "/master/diagrams/",
    i(3, "FileName"),
    t ".puml&fmt=png)",
    i(0),
  }),

  -- Quickly insert a diagram picture
  s("plant", {
    t "![",
    i(1, "DiagramName"),
    t "](diagrams/rendered/",
    i(2, "FileName"),
    t ".png)",
    i(0),
  }),

  -- Center caption under an image
  s("caption", {
    t '<p style="text-align: center;"><small>',
    i(1, "ImageDescription"),
    t { "</small></p>", "" },
  }),

  s("log", {
    t "console.log(",
    i(1, "$TM_SELECTED_TEXT"),
    t ");",
  }),

  s("blog", {
    t { "---", "title: Welcome Docusaurus v2", "description: " },
    i(1),
    t { "", "tags: [" },
    i(2),
    t ", ",
    i(3),
    t { "]", "image: ./_media/", "hide_table_of_contents: false", "---", "" },
    i(0),
  }),

  s("text", {
    t { "```text", "" },
    i(1, "$TM_SELECTED_TEXT"),
    t { "", "```" },
  }),

  s("copy", {
    t { "{{copy}}", "" },
  }),

  -- Inserts a bash code snippet with {{exec}}
  s("exec", {
    t { "```bash", "" },
    i(1, "something"),
    t { "", "```{{exec}}", "" },
    i(0),
  }),

  s("execi", {
    t { "{{exec interrupt}}", "" },
  }),

  s("note", {
    t { "> [!NOTE]", "> " },
    i(0),
  }),

  s("warn", {
    t { "> [!WARNING]", "> " },
    i(0),
  }),

  s("imp", {
    t { "> [!IMPORTANT]", "> " },
    i(0),
  }),

  -- Claude Code snippets (when CLAUDE_CODE_ENTRYPOINT=cli)

  -- INLINE CONTEXT INJECTORS (no newline, mid-sentence use)

  -- Current branch name (inline)
  s("cl_branch", {
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      local branch =
        vim.fn.system(string.format("cd %s && git branch --show-current", vim.fn.shellescape(original_dir)))
      return vim.trim(branch)
    end, {}),
  }),

  -- Git remote URL (inline)
  s("cl_remote", {
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      local remote =
        vim.fn.system(string.format("cd %s && git remote get-url origin", vim.fn.shellescape(original_dir)))
      return vim.trim(remote)
    end, {}),
  }),

  -- Last commit (inline)
  s("cl_commit", {
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      local commit = vim.fn.system(
        string.format("cd %s && git log -1 --pretty=format:'%%h - %%s (%%an, %%ar)'", vim.fn.shellescape(original_dir))
      )
      return vim.trim(commit)
    end, {}),
  }),

  -- BLOCK CONTEXT INJECTORS (multi-line with formatting)

  -- Modified files list
  s("cl_modified", {
    t { "Modified files:", "", "" },
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      local files = vim.fn.systemlist(string.format("cd %s && git diff --name-only", vim.fn.shellescape(original_dir)))
      local lines = {}
      for _, file in ipairs(files) do
        if file ~= "" then
          table.insert(lines, "- " .. file)
        end
      end
      return lines
    end, {}),
    t { "", "" },
  }),

  -- Unstaged changes
  s("cl_unstaged", {
    t { "Unstaged changes:", "", "```diff" },
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      local diff = vim.fn.system(string.format("cd %s && git diff", vim.fn.shellescape(original_dir)))
      return vim.split(diff, "\n")
    end, {}),
    t { "", "```", "", "" },
  }),

  -- Git diff insertion with formatting (CONTEXT INJECTION)
  s("cl_gdiff", {
    t { "Here are my recent changes:", "", "```diff" },
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      local diff = vim.fn.system(string.format("cd %s && git diff", vim.fn.shellescape(original_dir)))
      if diff == "" then
        return { "", "# No unstaged changes" }
      end
      return vim.split(diff, "\n")
    end, {}),
    t { "", "```", "", "" },
    i(1, "Please review and suggest improvements."),
    i(0),
  }),

  -- Git status with context
  s("cl_gstat", {
    t { "Current git status:", "", "```" },
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      local status = vim.fn.system(string.format("cd %s && git status --short", vim.fn.shellescape(original_dir)))
      if status == "" then
        return { "# Working tree clean" }
      end
      return vim.split(status, "\n")
    end, {}),
    t { "", "```", "", "" },
    i(1, "Context or question about these changes"),
    i(0),
  }),

  -- Quick context with file and diff (CONTEXT INJECTION)
  s("cl_context", {
    t { "**Recent changes:**", "```diff" },
    f(function()
      local original_dir = vim.fn.environ().PWD or vim.fn.getcwd()
      -- Just show general diff, not file-specific when in temp buffer
      local diff = vim.fn.system(string.format("cd %s && git diff", vim.fn.shellescape(original_dir)))
      if diff == "" then
        return { "", "# No unstaged changes" }
      end
      return vim.split(diff, "\n")
    end, {}),
    t { "", "```", "", "" },
    i(1, "What I need help with"),
    i(0),
  }),

  -- CLIPBOARD-AWARE CODE SNIPPETS (auto-detect yanked code + file path)

  -- Code review with clipboard detection
  s("cl_review", {
    t { "Review this code for:", "- Security vulnerabilities", "- Performance issues", "- Best practices", "", "" },
    f(function()
      -- Get clipboard content
      local clipboard = vim.fn.getreg "+"
      -- Get metadata from global var (set by <leader>cy yank helper)
      local file_path = vim.g.claude_yank_file or "unknown"
      local line_start = vim.g.claude_yank_start or "?"
      local line_end = vim.g.claude_yank_end or "?"

      if clipboard and clipboard ~= "" then
        local lines = { string.format("File: %s:%s-%s", file_path, line_start, line_end), "```" }
        vim.list_extend(lines, vim.split(clipboard, "\n"))
        table.insert(lines, "```")
        return lines
      end
      return { "```", "[Paste code here or yank with <leader>cy]", "```" }
    end, {}),
    t { "", "" },
    i(0),
  }),

  -- Refactor with clipboard detection
  s("cl_refactor", {
    t { "Refactor this code to improve readability and maintainability:", "", "" },
    f(function()
      local clipboard = vim.fn.getreg "+"
      local file_path = vim.g.claude_yank_file or "unknown"
      local line_start = vim.g.claude_yank_start or "?"
      local line_end = vim.g.claude_yank_end or "?"

      if clipboard and clipboard ~= "" then
        local lines = { string.format("File: %s:%s-%s", file_path, line_start, line_end), "```" }
        vim.list_extend(lines, vim.split(clipboard, "\n"))
        table.insert(lines, "```")
        return lines
      end
      return { "```", "[Paste code here or yank with <leader>cy]", "```" }
    end, {}),
    t { "", "" },
    i(0),
  }),

  -- Explain code with clipboard detection
  s("cl_explain", {
    t { "Explain how this code works:", "", "" },
    f(function()
      local clipboard = vim.fn.getreg "+"
      local file_path = vim.g.claude_yank_file or "unknown"
      local line_start = vim.g.claude_yank_start or "?"
      local line_end = vim.g.claude_yank_end or "?"

      if clipboard and clipboard ~= "" then
        local lines = { string.format("File: %s:%s-%s", file_path, line_start, line_end), "```" }
        vim.list_extend(lines, vim.split(clipboard, "\n"))
        table.insert(lines, "```")
        return lines
      end
      return { "```", "[Paste code here or yank with <leader>cy]", "```" }
    end, {}),
    t { "", "" },
    i(0),
  }),

  -- Write tests with clipboard detection
  s("cl_test", {
    t { "Write comprehensive tests for this code:", "", "" },
    f(function()
      local clipboard = vim.fn.getreg "+"
      local file_path = vim.g.claude_yank_file or "unknown"
      local line_start = vim.g.claude_yank_start or "?"
      local line_end = vim.g.claude_yank_end or "?"

      if clipboard and clipboard ~= "" then
        local lines = { string.format("File: %s:%s-%s", file_path, line_start, line_end), "```" }
        vim.list_extend(lines, vim.split(clipboard, "\n"))
        table.insert(lines, "```")
        return lines
      end
      return { "```", "[Paste code here or yank with <leader>cy]", "```" }
    end, {}),
    t { "", "" },
    i(0),
  }),
}
