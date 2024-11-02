#!/usr/bin/env bash

# The set -e option instructs bash to immediately exit if any command has a non-zero exit status
set -euo pipefail

# Backup directory with timestamp
BACKUP_DIR="$HOME/.task.backup.$(date +%Y%m%d_%H%M%S)"
TASK_DIR="$HOME/.task"

# Only backup and clean these data files
DATA_FILES=(
	"backlog.data"
	"completed.data"
	"pending.data"
	"undo.data"
)

backup_taskwarrior() {
	echo "📦 Creating backup of TaskWarrior data..."
	mkdir -p "$BACKUP_DIR"

	# Only copy data files
	for file in "${DATA_FILES[@]}"; do
		if [ -f "$TASK_DIR/$file" ]; then
			cp "$TASK_DIR/$file" "$BACKUP_DIR/"
			echo "Backed up: $file"
		fi
	done

	# Also backup any temporary task files
	cp "$TASK_DIR"/task.*.task "$BACKUP_DIR/" 2>/dev/null || true

	echo "✅ Backup created at: $BACKUP_DIR"
}

clean_taskwarrior() {
	echo "🧹 Cleaning TaskWarrior data..."

	# Remove only data files
	for file in "${DATA_FILES[@]}"; do
		if [ -f "$TASK_DIR/$file" ]; then
			rm -f "$TASK_DIR/$file"
			echo "Removed: $file"
		fi
	done

	# Remove temporary task files
	rm -f "$TASK_DIR"/task.*.task

	echo "✅ TaskWarrior data cleaned"
}

restore_taskwarrior() {
	if [ -d "$1" ]; then
		echo "🔄 Restoring TaskWarrior data from: $1"
		cp "$1"/*.data "$TASK_DIR/" 2>/dev/null || true
		cp "$1"/task.*.task "$TASK_DIR/" 2>/dev/null || true
		echo "✅ TaskWarrior data restored"
	else
		echo "❌ Backup directory not found: $1"
		exit 1
	fi
}

case "${1:-}" in
"backup")
	backup_taskwarrior
	;;
"clean")
	backup_taskwarrior
	clean_taskwarrior
	;;
"restore")
	if [ -z "${2:-}" ]; then
		echo "❌ Please specify the backup directory to restore from"
		echo "Usage: $0 restore <backup_directory>"
		exit 1
	fi
	restore_taskwarrior "$2"
	;;
*)
	echo "Usage: $0 {backup|clean|restore <backup_directory>}"
	echo "  backup  - Create a backup of TaskWarrior data"
	echo "  clean   - Create a backup and clean TaskWarrior data"
	echo "  restore - Restore TaskWarrior data from a backup"
	exit 1
	;;
esac
