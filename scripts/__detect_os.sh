#!/usr/bin/env bash

set -eo pipefail

detect_os() {
	declare -A os_map=(
		["linux"]="linux"
		["darwin,arm64"]="M1"
		["darwin,x86_64"]="mac"
	)

	arch=$(uname -m)
	os_type=$(echo $OSTYPE | cut -d"-" -f1)

	case "${os_type},${arch}" in
	"linux,arm" | "linux,arm64" | "linux,x86_64")
		echo "linux"
		;;
	"darwin,arm64")
		echo "M1"
		;;
	"darwin,x86_64")
		echo "mac"
		;;
	*)
		echo "Unsupported OS"
		exit 1
		;;
	esac
}
