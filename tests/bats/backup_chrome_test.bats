#!/usr/bin/env bats

setup() {
	BACKUP_SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../../scripts" && pwd)"
	export BACKUP_SCRIPT_DIR
	export CHROME_PROFILE_DIR="$BATS_TEST_TMPDIR/home with spaces/.config/google-chrome"
	export HOME_BACKUP="$BATS_TEST_TMPDIR/backup"
	mkdir -p "$CHROME_PROFILE_DIR" "$HOME_BACKUP"
	# Load only the command definitions, never the backup's startup or NAS writes.
	export SPECIAL_BACKUPS_DEFINITION
	SPECIAL_BACKUPS_DEFINITION="$(sed -n '/^[[:space:]]*declare -A SPECIAL_BACKUPS=(/,/^[[:space:]]*)/p' "$BACKUP_SCRIPT_DIR/__backup.sh")"
	ARCHIVE="$HOME_BACKUP/chrome_profiles.tar.gz"
	RESTORED="$BATS_TEST_TMPDIR/restored"
	mkdir -p "$RESTORED"
	RESTORED_PROFILE="$RESTORED/${CHROME_PROFILE_DIR#/}"
}

fixture_file() {
	mkdir -p "$(dirname "$CHROME_PROFILE_DIR/$1")"
	printf '%s\n' "fixture: $1" >"$CHROME_PROFILE_DIR/$1"
}

create_archive() {
	bash -eo pipefail -c 'eval "$SPECIAL_BACKUPS_DEFINITION"; eval "${SPECIAL_BACKUPS[Chrome profiles]}"'
}

@test "Chrome archive retains settings and credential database sidecars in each profile" {
	local profile item
	fixture_file 'Local State'
	fixture_file 'NativeMessagingHosts/extension.json'
	for profile in 'Default' 'Profile 1' 'Profile 12'; do
		for item in 'Preferences' 'Secure Preferences' 'Bookmarks' 'Bookmarks.bak' \
			'AccountBookmarks' 'EncryptedBookmarks' 'Login Data' 'Login Data-wal' \
			'Login Data-shm' 'Login Data For Account' 'Web Data' 'Web Data-journal' \
			'Custom Dictionary.txt' 'Extensions/extension-id/manifest.json' \
			'Local Extension Settings/extension-id/data' 'Sync Extension Settings/extension-id/data' \
			'Managed Extension Settings/extension-id/data' 'Extension State/data'; do
			fixture_file "$profile/$item"
		done
	done
	run create_archive
	[ "$status" -eq 0 ]
	tar -xzf "$ARCHIVE" -C "$RESTORED"
	diff -r "$CHROME_PROFILE_DIR" "$RESTORED_PROFILE"
}

@test "Chrome archive excludes downloaded models and transient state across profiles" {
	local profile item
	fixture_file 'Local State'
	for item in 'OptGuideOnDeviceModel/version/weights.bin' \
		'OptGuideOnDeviceClassifierModel/version/weights.bin' \
		'optimization_guide_model_store/model' 'component_crx_cache/component' \
		'DeferredBrowserMetrics/event' 'Crashpad/report' 'SingletonLock' \
		'NativeMessagingHosts/.app.socket'; do
		fixture_file "$item"
	done
	for profile in 'Default' 'Profile 1' 'Profile 12'; do
		fixture_file "$profile/Preferences"
		for item in 'Cache/data' 'Code Cache/js/data' 'GPUCache/data' \
			'Service Worker/CacheStorage/data' 'File System/data' 'IndexedDB/data' \
			'Local Storage/data' 'Session Storage/data' 'WebStorage/data' \
			'Storage/data' 'blob_storage/data' 'SharedStorage-wal' \
			'Sessions/tabs' 'Current Tabs' 'Last Session' 'History' 'History-journal' \
			'Top Sites' 'Favicons' 'Cookies' 'Cookies-wal' 'Network/Cookies' \
			'BrowsingTopicsState' '.com.google.Chrome.temp'; do
			fixture_file "$profile/$item"
		done
	done
	run create_archive
	[ "$status" -eq 0 ]
	tar -xzf "$ARCHIVE" -C "$RESTORED"
	[ -f "$RESTORED_PROFILE/Local State" ]
	for profile in 'Default' 'Profile 1' 'Profile 12'; do
		[ -f "$RESTORED_PROFILE/$profile/Preferences" ]
	done
	[ "$(find "$RESTORED_PROFILE" -type f | wc -l)" -eq 4 ]
}

@test "Chrome exclusions cannot match inside retained extension settings" {
	fixture_file 'Default/Local Extension Settings/extension-id/History'
	fixture_file 'Profile 1/Sync Extension Settings/extension-id/Cache/data'
	fixture_file 'Default/Extensions/extension-id/Service Worker/code.js'
	run create_archive
	[ "$status" -eq 0 ]
	tar -xzf "$ARCHIVE" -C "$RESTORED"
	diff -r "$CHROME_PROFILE_DIR" "$RESTORED_PROFILE"
}

@test "Chrome archive fails if its exclusions are missing" {
	fixture_file 'Default/Preferences'
	export BACKUP_SCRIPT_DIR="$BATS_TEST_TMPDIR/missing-config"
	run create_archive
	[ "$status" -ne 0 ]
}

@test "Chrome archive tolerates changed files but still reports real tar errors" {
	local fake_bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$fake_bin"
	cat >"$fake_bin/tar" <<'EOF'
#!/usr/bin/env bash
exit "$TAR_TEST_STATUS"
EOF
	chmod +x "$fake_bin/tar"
	export PATH="$fake_bin:$PATH"
	export TAR_TEST_STATUS=1
	run create_archive
	[ "$status" -eq 0 ]
	export TAR_TEST_STATUS=2
	run create_archive
	[ "$status" -ne 0 ]
}
