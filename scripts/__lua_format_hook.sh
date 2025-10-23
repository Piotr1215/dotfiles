#!/usr/bin/env bash
set -e

# Add Mason bin directory to PATH for lua-language-server
export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"

# Read input
INPUT=$(cat)

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Check if file is a Lua file
if [[ ! "$FILE_PATH" =~ \.lua$ ]]; then
    # Not a Lua file, exit silently
    exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    # File doesn't exist yet (might be a new file), exit silently
    exit 0
fi

# Initialize warnings array
warnings=()

# Determine project directory (for finding .luacheckrc)
PROJECT_DIR=$(dirname "$FILE_PATH")
PREV_DIR=""
while [[ "$PROJECT_DIR" != "/" ]] && [[ "$PROJECT_DIR" != "." ]] && [[ "$PROJECT_DIR" != "$PREV_DIR" ]]; do
    if [[ -f "$PROJECT_DIR/.luacheckrc" ]] || [[ -d "$PROJECT_DIR/.git" ]]; then
        break
    fi
    PREV_DIR="$PROJECT_DIR"
    PROJECT_DIR=$(dirname "$PROJECT_DIR")
done

# If we didn't find a project directory, use current directory
if [[ "$PROJECT_DIR" == "." ]] || [[ "$PROJECT_DIR" == "/" ]]; then
    PROJECT_DIR="."
fi

# Check if stylua is available
if ! command -v stylua &> /dev/null; then
    reason="stylua is not installed. Please install it with: cargo install stylua"
    jq -n --arg reason "$reason" '{"reason": $reason}'
    exit 0
fi

# Run stylua to format the file
if ! stylua "$FILE_PATH" 2>&1; then
    warnings+=("Failed to format file with stylua")
fi

# Run basic lua syntax check using luac if available
if command -v luac &> /dev/null; then
    if ! luac -p "$FILE_PATH" 2>&1; then
        # Syntax error - this is critical and must block
        ERROR_COUNT=$((ERROR_COUNT + 1))
        ERROR_DETAILS="${ERROR_DETAILS}  • SYNTAX ERROR: Lua syntax is invalid. Check with 'luac -p $FILENAME'\n"
    fi
fi

# Run luacheck if available with COMPREHENSIVE configuration
if command -v luacheck &> /dev/null; then
    luacheck_output=""
    # Enable ALL checks with codes and ranges for better reporting
    luacheck_cmd="luacheck --codes --ranges"

    # Add max line length check
    luacheck_cmd="$luacheck_cmd --max-line-length 120"

    # Add cyclomatic complexity check (matches our lizard settings)
    luacheck_cmd="$luacheck_cmd --max-cyclomatic-complexity 10"

    # Use project-specific .luacheckrc if it exists
    if [[ -f "$PROJECT_DIR/.luacheckrc" ]]; then
        luacheck_cmd="$luacheck_cmd --config $PROJECT_DIR/.luacheckrc"
    else
        # Configure for Neovim plugins
        if [[ "$FILE_PATH" =~ /nvim/|\.nvim/|nvim- ]]; then
            # Comprehensive Neovim configuration
            luacheck_cmd="$luacheck_cmd --std luajit"

            # Add ALL common Neovim and plugin globals
            luacheck_cmd="$luacheck_cmd --globals vim"

            # Test framework globals
            luacheck_cmd="$luacheck_cmd --globals describe it assert before_each after_each pending setup teardown"

            # Common plugin globals
            luacheck_cmd="$luacheck_cmd --globals P RELOAD R"

            # Neovim runtime globals
            luacheck_cmd="$luacheck_cmd --globals jit bit"

            # Don't ignore ANY warnings - we want comprehensive feedback
            # No --no-unused, no --no-redefined, no --no-global
        else
            # For non-neovim lua files
            luacheck_cmd="$luacheck_cmd --std lua51"
        fi

        # Add read-only globals that shouldn't trigger warnings
        luacheck_cmd="$luacheck_cmd --read-globals os io string table math coroutine package"
        luacheck_cmd="$luacheck_cmd --read-globals ipairs pairs next select type tostring tonumber"
        luacheck_cmd="$luacheck_cmd --read-globals pcall xpcall error assert"
        luacheck_cmd="$luacheck_cmd --read-globals getmetatable setmetatable rawget rawset rawequal"
        luacheck_cmd="$luacheck_cmd --read-globals require print unpack"
    fi

    # Run luacheck and capture output
    # Add -- separator before filename to avoid argument parsing issues
    # Temporarily disable set -e for luacheck since it returns non-zero for warnings
    set +e
    luacheck_output=$($luacheck_cmd -- "$FILE_PATH" 2>&1)
    LUACHECK_EXIT=$?
    set -e

    if [ $LUACHECK_EXIT -ne 0 ]; then
        # Parse luacheck output - comprehensive code checking
        # ERRORS (block save):
        # E011 - syntax error
        # W111 - setting non-standard global variable
        # W112 - mutating non-standard global variable
        # W113 - accessing undefined variable
        # W211 - unused local variable (counts as error for clean code)

        # Extract errors - expanded to include unused variables as errors
        ERROR_LINES=$(echo "$luacheck_output" | grep -E "\(E[0-9]{3}\)|\(W11[123]\)|\(W211\)" | sed 's/\x1b\[[0-9;]*m//g')
        if [ -n "$ERROR_LINES" ]; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            while IFS= read -r error_line; do
                if [ -n "$error_line" ]; then
                    clean_line=$(echo "$error_line" | sed "s|$PROJECT_DIR/||" | sed 's/^[[:space:]]*/  • /')
                    ERROR_DETAILS="${ERROR_DETAILS}${clean_line}\n"
                fi
            done <<< "$ERROR_LINES"
        fi

        # WARNINGS (informational):
        # W212 - unused argument
        # W213 - unused loop variable
        # W221 - variable is never set
        # W231 - variable is never accessed
        # W241 - variable is mutated but never accessed
        # W311/W312/W313 - value assigned but never used
        # W411/W412 - variable/value redefined
        # W421/W422 - shadowing
        # W511/W512 - unreachable code
        # W561 - cyclomatic complexity too high (handled by lizard too)
        # W611-W614 - line length issues
        # W631 - line too long

        # Extract all other warnings (including W561 for complexity)
        WARNING_LINES=$(echo "$luacheck_output" | grep -E "\(W[2-6][0-9]{2}\)" | grep -v "\(W211\)" | sed 's/\x1b\[[0-9;]*m//g' | head -30)
        if [ -n "$WARNING_LINES" ]; then
            while IFS= read -r warning_line; do
                if [ -n "$warning_line" ]; then
                    clean_warning=$(echo "$warning_line" | sed "s|$PROJECT_DIR/||" | sed 's/^[[:space:]]*/  • /')
                    WARNING_DETAILS="${WARNING_DETAILS}${clean_warning}\n"
                fi
            done <<< "$WARNING_LINES"
        fi
    fi
fi

# Run llscheck for type checking if available
if command -v llscheck &> /dev/null; then
    # Look for .luarc.json in project directory
    if [[ -f "$PROJECT_DIR/.luarc.json" ]]; then
        llscheck_output=""
        # Need to set VIMRUNTIME for llscheck to work properly with Neovim
        export VIMRUNTIME=$(nvim --clean --headless --cmd 'lua io.write(os.getenv("VIMRUNTIME"))' --cmd 'quit' 2>/dev/null)

        if ! llscheck_output=$(cd "$PROJECT_DIR" && llscheck --configpath .luarc.json "$FILE_PATH" 2>&1); then
            if echo "$llscheck_output" | grep -q "Error"; then
                warnings+=("Type checking issues found. Run 'llscheck' in project directory for details.")
            fi
        fi
    fi
fi


# ALWAYS run Cyclomatic Complexity Analysis
HIGH_COMPLEXITY_COUNT=0
if command -v lizard &> /dev/null; then
    COMPLEXITY_OUTPUT=$(lizard "$FILE_PATH" --CCN 10 2>&1 || true)

    # Extract high complexity functions (remove duplicates with sort -u)
    HIGH_COMPLEX=$(echo "$COMPLEXITY_OUTPUT" | grep -E "^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+" | awk '$2 > 10 {print "  • " $NF " (CCN=" $2 ", Lines=" $1 ")"}' | sort -u)
    if [ -n "$HIGH_COMPLEX" ]; then
        HIGH_COMPLEX_MSG="\n❌ High complexity (CCN > 10) - MUST REFACTOR:\n$HIGH_COMPLEX"
        # Count high complexity functions
        HIGH_COMPLEXITY_COUNT=$(echo "$HIGH_COMPLEX" | wc -l)
        # Add to error count to block saves
        ERROR_COUNT=$((ERROR_COUNT + HIGH_COMPLEXITY_COUNT))
    fi

    # Extract moderate complexity (CCN 6-10, not 5)
    MED_COMPLEX=$(echo "$COMPLEXITY_OUTPUT" | grep -E "^[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+" | awk '$2 >= 6 && $2 <= 10 {print "  • " $NF " (CCN=" $2 ")"}' | sort -u)
    if [ -n "$MED_COMPLEX" ]; then
        MOD_COMPLEX_MSG="\n⚠️  Moderate complexity (CCN 6-10):\n$MED_COMPLEX"
    fi

    # Get summary
    AVG_LINE=$(echo "$COMPLEXITY_OUTPUT" | grep -E "^Total nloc" -A1 | tail -1)
    if [ -n "$AVG_LINE" ]; then
        AVG_COMPLEXITY=$(echo "$AVG_LINE" | awk '{print $3}')
        TOTAL_FUNCS=$(echo "$AVG_LINE" | awk '{print $5}')
        COMPLEXITY_SUMMARY="  Average CCN: $AVG_COMPLEXITY, Total Functions: $TOTAL_FUNCS"
    else
        COMPLEXITY_SUMMARY="  No functions found to analyze"
    fi
else
    COMPLEXITY_SUMMARY="  ⚠️ Install 'lizard' for complexity analysis"
fi

# Smart Test Detection and Execution
TEST_FILE=""
SPEC_FILE=""
IS_TEST_FILE=false
TEST_STATUS=""

# Check if current file is a test file
if [[ "$FILE_PATH" =~ _spec\.lua$ ]] || [[ "$FILE_PATH" =~ test.*\.lua$ ]]; then
    IS_TEST_FILE=true
    TEST_FILE="$FILE_PATH"
    # Find the source file being tested
    if [[ "$FILE_PATH" =~ _spec\.lua$ ]]; then
        # Remove _spec suffix to find source file
        SOURCE_FILE=$(echo "$FILE_PATH" | sed 's/_spec\.lua$/.lua/')
        if [ -f "$SOURCE_FILE" ]; then
            SPEC_FILE="$SOURCE_FILE"
        fi
    fi
else
    # Current file is source, look for corresponding test file
    SPEC_FILE="$FILE_PATH"

    # Extract module path for test directory structure
    # e.g., lua/pairup/rpc.lua -> test/pairup/rpc_spec.lua
    MODULE_PATH=""
    if [[ "$FILE_PATH" =~ lua/(.+)\.lua$ ]]; then
        MODULE_PATH="${BASH_REMATCH[1]}"
    fi

    # Try common test file patterns
    TEST_CANDIDATES=(
        "${FILE_PATH%.lua}_spec.lua"
        "${FILE_PATH%.lua}_test.lua"
        "$(dirname "$FILE_PATH")/test_$(basename "$FILE_PATH")"
        "$(dirname "$FILE_PATH")/../tests/$(basename "$FILE_PATH")"
        "$(dirname "$FILE_PATH")/../test/$(basename "$FILE_PATH")"
    )

    # Add test directory patterns if we have a module path
    if [ -n "$MODULE_PATH" ]; then
        # Look for tests in standard test directory structure
        TEST_CANDIDATES+=(
            "$PROJECT_DIR/test/${MODULE_PATH}_spec.lua"
            "$PROJECT_DIR/tests/${MODULE_PATH}_spec.lua"
            "$PROJECT_DIR/spec/${MODULE_PATH}_spec.lua"
            "$PROJECT_DIR/test/${MODULE_PATH%.lua}_spec.lua"
        )
    fi

    for candidate in "${TEST_CANDIDATES[@]}"; do
        if [ -f "$candidate" ]; then
            TEST_FILE="$candidate"
            break
        fi
    done
fi

# Run tests if test file exists
if [ -n "$TEST_FILE" ] && command -v busted &> /dev/null; then
    # Save current directory
    ORIG_DIR=$(pwd)

    # Find the nvim config directory (where lua/ folder is)
    TEST_DIR="$PROJECT_DIR"
    if [[ "$FILE_PATH" =~ /.config/nvim/ ]]; then
        # Find the nvim config root
        TEST_DIR=$(echo "$FILE_PATH" | sed 's|/lua/.*|/|')
    fi

    cd "$TEST_DIR" 2>/dev/null || cd "$PROJECT_DIR"

    # Set up Lua path for tests
    export LUA_PATH="./lua/?.lua;;"

    # Run tests with coverage
    TEST_OUTPUT=""
    TEST_FAILED=false

    # Clean up old coverage data
    rm -f luacov.stats.out luacov.report.out 2>/dev/null

    # Run tests with coverage
    set +e
    TEST_OUTPUT=$(busted --coverage "$TEST_FILE" 2>&1)
    TEST_EXIT=$?
    set -e

    if [ $TEST_EXIT -ne 0 ]; then
        TEST_FAILED=true
        # Extract failure details
        TEST_ERRORS=$(echo "$TEST_OUTPUT" | grep -E "Error|Failure" | head -5)
        if [ -n "$TEST_ERRORS" ]; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            ERROR_DETAILS="${ERROR_DETAILS}  • TEST FAILURES:\n$(echo "$TEST_ERRORS" | sed 's/^/      /')\n"
        fi
    fi

    # Generate coverage report if tests passed
    if [ $TEST_EXIT -eq 0 ] && [ -f "luacov.stats.out" ]; then
        luacov 2>/dev/null || true

        if [ -f "luacov.report.out" ]; then
            # Extract coverage for the file being tested
            TARGET_FILE="$SPEC_FILE"
            if [ "$IS_TEST_FILE" = true ] && [ -n "$SPEC_FILE" ]; then
                TARGET_FILE="$SPEC_FILE"
            elif [ "$IS_TEST_FILE" = false ]; then
                TARGET_FILE="$FILE_PATH"
            fi

            # Get relative path for coverage lookup
            REL_PATH=$(realpath --relative-to="$TEST_DIR" "$TARGET_FILE" 2>/dev/null || basename "$TARGET_FILE")

            # Extract coverage percentage
            COVERAGE_INFO=$(grep -A 20 "$REL_PATH" luacov.report.out 2>/dev/null | head -25)
            if [ -n "$COVERAGE_INFO" ]; then
                # Count executed vs total lines
                EXEC_LINES=$(echo "$COVERAGE_INFO" | grep -E "^[[:space:]]*[0-9]+" | wc -l)
                UNEXEC_LINES=$(echo "$COVERAGE_INFO" | grep -E "^\*+0" | wc -l)
                TOTAL_LINES=$((EXEC_LINES + UNEXEC_LINES))

                if [ $TOTAL_LINES -gt 0 ]; then
                    COVERAGE_PCT=$(echo "scale=1; $EXEC_LINES * 100 / $TOTAL_LINES" | bc)

                    # Add to test status
                    TEST_STATUS="  • Test coverage: ${COVERAGE_PCT}%"

                    # Warn if coverage is low
                    if (( $(echo "$COVERAGE_PCT < 70" | bc -l) )); then
                        WARNING_DETAILS="${WARNING_DETAILS}  • Low test coverage: ${COVERAGE_PCT}% (recommended: 70%+)\n"

                        # Show uncovered functions
                        UNCOVERED=$(echo "$COVERAGE_INFO" | grep -B1 "^\*+0" | grep "^function\|^local function" | head -3)
                        if [ -n "$UNCOVERED" ]; then
                            WARNING_DETAILS="${WARNING_DETAILS}    Uncovered functions:\n$(echo "$UNCOVERED" | sed 's/^/      - /')\n"
                        fi
                    fi
                fi
            fi
        fi
    fi

    # Extract test summary
    TEST_SUMMARY=$(echo "$TEST_OUTPUT" | grep -E "[0-9]+ success|[0-9]+ failure|[0-9]+ error" | tail -1)
    if [ -n "$TEST_SUMMARY" ]; then
        TEST_STATUS="${TEST_STATUS}\n  • Test results: $TEST_SUMMARY"
    fi

    cd "$ORIG_DIR"
elif [ -z "$TEST_FILE" ]; then
    # No test file found
    TEST_STATUS="  • No test file (expected: $(basename "${FILE_PATH%.lua}_spec.lua"))"
fi


# Collect LSP and other diagnostics into structured format
if [ ${#warnings[@]} -gt 0 ]; then
    for warning in "${warnings[@]}"; do
        # Filter out complexity/coverage warnings as they're handled separately
        if [[ ! "$warning" =~ "CCN"|"Coverage"|"Complexity" ]]; then
            LSP_DIAGNOSTICS="${LSP_DIAGNOSTICS}  • ${warning}\n"
        fi
    done
fi

# Run lua-language-server for type checking (if available)
if command -v lua-language-server &> /dev/null; then
    LSP_TEMP_DIR=$(mktemp -d)

    # Create a focused config for type checking
    cat > "$LSP_TEMP_DIR/.luarc.json" << 'EOF'
{
    "runtime.version": "LuaJIT",
    "diagnostics": {
        "enable": true,
        "globals": ["vim", "describe", "it", "assert", "before_each", "after_each"],
        "severity": {
            "cast-type-mismatch": "Warning",
            "need-check-nil": "Warning",
            "inject-field": "Warning",
            "missing-global-doc": "Information",
            "incomplete-signature-doc": "Information"
        }
    }
}
EOF

    # Run check and capture output
    LSP_CHECK_OUTPUT=$(cd "$PROJECT_DIR" && lua-language-server --check "$FILE_PATH" --configpath="$LSP_TEMP_DIR" --logpath="$LSP_TEMP_DIR" 2>&1 || true)

    # Check for diagnostics in check.json
    if [ -f "$LSP_TEMP_DIR/check.json" ]; then
        LSP_JSON=$(cat "$LSP_TEMP_DIR/check.json" 2>/dev/null || echo "[]")
        if [ "$LSP_JSON" != "[]" ] && [ -n "$LSP_JSON" ]; then
            # Parse type-checking diagnostics
            TYPE_ISSUES=$(echo "$LSP_JSON" | jq -r '.[] | select(.code | contains("cast-type") or contains("need-check") or contains("inject")) | "Line \(.range.start.line + 1): \(.message)"' 2>/dev/null || true)
            if [ -n "$TYPE_ISSUES" ]; then
                while IFS= read -r issue; do
                    if [ -n "$issue" ]; then
                        warnings+=("Type: $issue")
                    fi
                done <<< "$TYPE_ISSUES"
            fi
        fi
    fi

    rm -rf "$LSP_TEMP_DIR"
fi

# Build comprehensive diagnostic output
FULL_DIAGNOSTICS=""

# Get just the filename for cleaner output
FILENAME=$(basename "$FILE_PATH")

# Build output with proper newlines
FULL_DIAGNOSTICS="Lua diagnostics for $FILENAME:

"

# Errors section - only show if we have actual error content
HAS_ERROR_CONTENT=false
ERROR_SECTION=""

# Check if we have any actual errors to display
if [ -n "$ERROR_DETAILS" ] || ([ "$HIGH_COMPLEXITY_COUNT" -gt 0 ] && [ -n "$HIGH_COMPLEX_MSG" ]); then
    HAS_ERROR_CONTENT=true
fi

if [ "${ERROR_COUNT:-0}" -gt 0 ] && [ "$HAS_ERROR_CONTENT" = true ]; then
    ERROR_SECTION="❌ ERRORS (must fix before saving):
"
    # Include luacheck/syntax errors if any
    if [ -n "$ERROR_DETAILS" ]; then
        ERROR_OUTPUT=$(echo -e "$ERROR_DETAILS" | sed 's/^/   /')
        ERROR_SECTION="${ERROR_SECTION}${ERROR_OUTPUT}
"
    fi

    # Include high complexity as errors
    if [ "$HIGH_COMPLEXITY_COUNT" -gt 0 ] && [ -n "$HIGH_COMPLEX_MSG" ]; then
        # Only add a blank line if we had other errors before
        if [ -n "$ERROR_DETAILS" ]; then
            ERROR_SECTION="${ERROR_SECTION}
"
        fi
        ERROR_SECTION="${ERROR_SECTION}$(echo -e "$HIGH_COMPLEX_MSG")
"
    fi

    ERROR_SECTION="${ERROR_SECTION}
"
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}${ERROR_SECTION}"
fi

# Warnings section
if [ -n "$WARNING_DETAILS" ]; then
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}⚠️  WARNINGS:
"
    WARNING_OUTPUT=$(echo -e "$WARNING_DETAILS" | sed 's/^/   /')
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}${WARNING_OUTPUT}

"
fi

# Complexity section - only show if there are non-blocking issues
# (High complexity is already shown in errors section if it's blocking)
if [ -n "$MOD_COMPLEX_MSG" ]; then
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}📊 COMPLEXITY ISSUES:
"
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}$(echo -e "$MOD_COMPLEX_MSG")
"
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}
"
fi


# Test Status - show test results and coverage
if [ -n "$TEST_STATUS" ]; then
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}📝 TEST STATUS:
"
    TEST_OUTPUT=$(echo -e "$TEST_STATUS" | sed 's/^/   /')
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}${TEST_OUTPUT}

"
fi

# LSP/other diagnostics
if [ -n "$LSP_DIAGNOSTICS" ]; then
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}🔍 ADDITIONAL DIAGNOSTICS:
"
    LSP_OUTPUT=$(echo -e "$LSP_DIAGNOSTICS" | sed 's/^/   /')
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}${LSP_OUTPUT}

"
fi


# Summary line
if [ "${ERROR_COUNT:-0}" -gt 0 ]; then
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}
✗ File has errors that must be fixed"
elif [ -n "$WARNING_DETAILS" ] || [ -n "$MOD_COMPLEX_MSG" ]; then
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}
⚠ File has warnings - consider addressing them"
else
    FULL_DIAGNOSTICS="${FULL_DIAGNOSTICS}
✓ File passes all checks"
fi

# Output decision JSON for PostToolUse
# PostToolUse can only provide feedback, not block (edit already happened)
jq -n --arg reason "$FULL_DIAGNOSTICS" '{"reason": $reason}'

# Always exit 0 to avoid JSON validation errors
exit 0