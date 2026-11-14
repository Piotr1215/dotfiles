#!/usr/bin/env bash
# Search the offline NOMAD library (ZIM files) by title without typing paths.
# Usage:
#   ks QUERY...            search every ZIM
#   ks -b BOOK QUERY...    search ZIMs whose filename contains BOOK (e.g. med, wikipedia_en_all)
#   ks -l                  list the ZIM files
set -eo pipefail

zim_dir="${KIWIX_ZIM_DIR:-/mnt/nvme-backup/nomad/storage/zim}"

# usage prints help to stderr and exits 1
usage() {
    echo "usage: ks [-b BOOK] QUERY... | ks -l" >&2
    exit 1
}

# list_books prints each ZIM name without directory or extension
list_books() {
    local f
    for f in "$zim_dir"/*.zim; do
        [[ -e "$f" ]] && basename "$f" .zim
    done
}

main() {
    local book=""
    [[ -d "$zim_dir" ]] || { echo "ks: $zim_dir not found (is the NOMAD drive mounted?)" >&2; exit 1; }
    case "$1" in
        -l) list_books; return ;;
        -b) [[ -n "$2" ]] || usage; book="$2"; shift 2 ;;
    esac
    [[ $# -gt 0 ]] || usage
    local query="$*" f name found=0
    for f in "$zim_dir"/*"$book"*.zim; do
        [[ -e "$f" ]] || continue
        found=1
        name=$(basename "$f" .zim)
        kiwix-search "$f" "$query" 2>/dev/null | sed "s|^|[$name] |" || true
    done
    [[ $found -eq 1 ]] || { echo "ks: no ZIM matches '$book'" >&2; exit 1; }
}

main "$@"
