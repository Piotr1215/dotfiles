#!/usr/bin/env bash
set -e

# Add Mason-installed tools to PATH (for gopls and other LSPs)
export PATH="$HOME/.local/share/nvim/mason/bin:$PATH"

# Read input
INPUT=$(cat)

# Extract file path
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')

# Check if file is a Go file
if [[ ! "$FILE_PATH" =~ \.go$ ]]; then
    exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Get just the filename for output
FILENAME=$(basename "$FILE_PATH")

# Find the module root (directory containing go.mod)
find_module_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/go.mod" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

MODULE_ROOT=$(find_module_root "$(dirname "$FILE_PATH")" || dirname "$FILE_PATH")

# Initialize diagnostic message
DIAGNOSTICS=""
HAS_ERRORS=false
HAS_WARNINGS=false

# Format the file with gofmt (always available with Go)
if command -v gofmt &> /dev/null; then
    gofmt -w "$FILE_PATH" 2>/dev/null || true
fi

# Fix imports with goimports if available
if command -v goimports &> /dev/null; then
    goimports -w "$FILE_PATH" 2>/dev/null || true
fi

# Run tests and check coverage if this is a package with tests
if command -v go &> /dev/null && [[ -f "$MODULE_ROOT/go.mod" ]]; then
    cd "$MODULE_ROOT"

    # Get the package directory
    PKG_DIR=$(dirname "$FILE_PATH")
    REL_PATH=$(realpath --relative-to="$MODULE_ROOT" "$PKG_DIR")
    PKG_PATH="./$REL_PATH"

    # Check if this package has test files
    HAS_TESTS=false
    if ls "$PKG_DIR"/*_test.go &>/dev/null 2>&1; then
        HAS_TESTS=true
    fi

    # Determine if current file is a test file
    IS_TEST_FILE=false
    if [[ "$FILENAME" =~ _test\.go$ ]]; then
        IS_TEST_FILE=true
    fi

    # Run tests if package has tests
    if [[ "$HAS_TESTS" == true ]]; then
        # Run tests with coverage
        TEST_OUTPUT=$(go test -short -covermode=atomic "$PKG_PATH" 2>&1) || TEST_FAILED=true

        if [[ "$TEST_FAILED" == true ]]; then
            # Extract the actual error, not the full output
            ERROR_MSG=$(echo "$TEST_OUTPUT" | grep -E "^\s*(.*_test\.go:[0-9]+:|FAIL:|Error:|panic:)" | head -5)
            if [[ -n "$ERROR_MSG" ]]; then
                DIAGNOSTICS="${DIAGNOSTICS}
❌ TEST FAILURES:
${ERROR_MSG}
FAIL"
                HAS_ERRORS=true
            else
                DIAGNOSTICS="${DIAGNOSTICS}
❌ TEST FAILURES:
FAIL	$PKG_PATH"
                HAS_ERRORS=true
            fi
        else
            # Extract coverage percentage correctly
            if [[ "$TEST_OUTPUT" =~ coverage:[[:space:]]+([0-9]+\.[0-9]+)%[[:space:]]of[[:space:]]statements ]]; then
                COVERAGE="${BASH_REMATCH[1]}"

                # Format test success message with coverage
                DIAGNOSTICS="${DIAGNOSTICS}
✅ TESTS: ok  	$PKG_PATH	coverage: ${COVERAGE}% of statements"

                # Check if coverage is low (using awk for float comparison)
                if awk "BEGIN {exit !($COVERAGE < 70)}"; then
                    DIAGNOSTICS="${DIAGNOSTICS}
   ⚠️  Low coverage: ${COVERAGE}% (recommended: 70%+)"
                    HAS_WARNINGS=true
                fi
            else
                # No coverage info (might be a package with no statements to cover)
                DIAGNOSTICS="${DIAGNOSTICS}
✅ TESTS: ok  	$PKG_PATH"
            fi
        fi
    fi

    # Check if this specific non-test file has a corresponding test file
    if [[ "$IS_TEST_FILE" == false ]]; then
        EXPECTED_TEST_FILE="${FILE_PATH%.go}_test.go"
        if [[ ! -f "$EXPECTED_TEST_FILE" ]]; then
            EXPECTED_TEST="${FILENAME%.go}_test.go"
            DIAGNOSTICS="${DIAGNOSTICS}

📝 No test file found (expected: $EXPECTED_TEST)"
            HAS_WARNINGS=true
        fi
    fi
fi

# Run compiler check to catch REAL errors (undefined vars, duplicate declarations, etc)
if command -v go &> /dev/null && [[ -f "$MODULE_ROOT/go.mod" ]]; then
    cd "$MODULE_ROOT"

    # Get the package directory
    PKG_DIR=$(dirname "$FILE_PATH")
    REL_PATH=$(realpath --relative-to="$MODULE_ROOT" "$PKG_DIR")
    PKG_PATH="./$REL_PATH"

    # Try to build the package to get compiler errors
    BUILD_OUTPUT=$(go build -o /dev/null "$PKG_PATH" 2>&1) || true

    if [[ -n "$BUILD_OUTPUT" ]]; then
        # Extract errors for the current file
        FILE_NAME=$(basename "$FILE_PATH")
        FILE_ERRORS=$(echo "$BUILD_OUTPUT" | grep "$FILE_NAME" || true)

        if [[ -n "$FILE_ERRORS" ]]; then
            # Parse out the actual errors (format: file.go:line:col: error message)
            COMPILER_ERRORS=$(echo "$FILE_ERRORS" | grep -E "\.go:[0-9]+:[0-9]+:" || true)

            if [[ -n "$COMPILER_ERRORS" ]]; then
                DIAGNOSTICS="${DIAGNOSTICS}

❌ COMPILER ERRORS:
$COMPILER_ERRORS"
                HAS_ERRORS=true
            fi
        fi
    fi

    # Also run gopls if available for additional LSP diagnostics
    if command -v gopls &> /dev/null; then
        # Use gopls to get additional diagnostics (like shadowed variables)
        # Note: gopls works best when called on the whole module
        GOPLS_OUTPUT=$(gopls call -method "textDocument/publishDiagnostics" "$FILE_PATH" 2>&1) || true

        # For now, just note if gopls is available
        # Full LSP integration would require more complex setup
    fi
elif command -v go &> /dev/null && [[ -f "$MODULE_ROOT/go.mod" ]]; then
    # Fallback to go vet if gopls not available
    cd "$MODULE_ROOT"
    # Run vet on the package, not individual file
    PKG_DIR=$(dirname "$FILE_PATH")
    REL_PATH=$(realpath --relative-to="$MODULE_ROOT" "$PKG_DIR")
    PKG_PATH="./$REL_PATH"

    VET_OUTPUT=$(go vet "$PKG_PATH" 2>&1) || true
    if [[ -n "$VET_OUTPUT" ]]; then
        # Only show errors related to the current file
        FILE_ERRORS=$(echo "$VET_OUTPUT" | grep "$(basename "$FILE_PATH")" || true)
        if [[ -n "$FILE_ERRORS" ]]; then
            DIAGNOSTICS="${DIAGNOSTICS}

❌ GO VET ERRORS:
$FILE_ERRORS"
            HAS_ERRORS=true
        fi
    fi
fi

# Check cyclomatic complexity (simplified)
if command -v gocyclo &> /dev/null; then
    COMPLEX_FUNCS=$(gocyclo -over 10 "$FILE_PATH" 2>/dev/null | head -5) || true
    if [[ -n "$COMPLEX_FUNCS" ]]; then
        # Format the output to be more readable
        FORMATTED_COMPLEX=$(echo "$COMPLEX_FUNCS" | awk '{print $1, $2, $3}')
        DIAGNOSTICS="${DIAGNOSTICS}

⚠️  HIGH COMPLEXITY (cyclomatic > 10):
$FORMATTED_COMPLEX"
        HAS_WARNINGS=true
    fi
fi

# Build final diagnostic message
FINAL_MSG="Go diagnostics for $FILENAME:"

if [[ -n "$DIAGNOSTICS" ]]; then
    FINAL_MSG="${FINAL_MSG}
${DIAGNOSTICS}"
fi

# Add summary
if [[ "$HAS_ERRORS" == true ]]; then
    FINAL_MSG="${FINAL_MSG}

✗ File has error(s) that must be fixed"
elif [[ "$HAS_WARNINGS" == true ]]; then
    FINAL_MSG="${FINAL_MSG}

⚠ File has warnings - consider addressing them"
else
    FINAL_MSG="${FINAL_MSG}

✓ File formatted and passes all checks"
fi

# Output result
jq -n --arg reason "$FINAL_MSG" '{
    decision: "block",
    reason: $reason,
    hookSpecificOutput: {
        hookEventName: "PostToolUse"
    }
}'

# Exit with appropriate code
if [[ "$HAS_ERRORS" == true ]]; then
    exit 2
else
    exit 0
fi