#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_COUNT=0

fail() {
    echo "not ok - $*" >&2
    exit 1
}

assert_eq() {
    local expected=$1 actual=$2 message=$3
    [[ "$actual" == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_file_exists() {
    [[ -f "$1" ]] || fail "expected file to exist: $1"
}

assert_file_missing() {
    [[ ! -e "$1" ]] || fail "expected path to be absent: $1"
}

run_test() {
    local name=$1
    shift
    if "$@"; then
        TEST_COUNT=$((TEST_COUNT + 1))
        echo "ok $TEST_COUNT - $name"
    else
        fail "$name"
    fi
}

with_fixture() {
    local test_function=$1
    local fixture_root
    fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/flutter-font-fix-test.XXXXXX")
    (
        export FLUTTER_CJK_CONFIG_DIR="$fixture_root/config"
        export FLUTTER_CJK_SO_LIB_DIR="$fixture_root/cache"
        export FLUTTER_CJK_SNAP_ROOT="$fixture_root/snap"
        export FLUTTER_CJK_NOTO_DIR="$fixture_root/noto"
        export FLUTTER_CJK_SERVICE_FILE="$fixture_root/flutter-font-fix.service"
        export FIXTURE_ROOT="$fixture_root"
        # shellcheck source=../flutter-font-fix
        source "$PROJECT_DIR/flutter-font-fix"
        "$test_function"
    )
    local status=$?
    find "$fixture_root" -mindepth 1 -delete
    rmdir "$fixture_root"
    return "$status"
}

create_non_snap_record_fixture() {
    local name=${1:-app}
    local current=${2:-replacement}
    local exe="$FIXTURE_ROOT/$name"
    local so="$FIXTURE_ROOT/$name.so"
    local backup="$so.bak"

    printf 'executable' > "$exe"
    chmod +x "$exe"
    printf 'original' > "$backup"
    printf '%s' "$current" > "$so"

    local original_sha replacement_sha
    original_sha=$(sha256sum "$backup" | awk '{print $1}')
    replacement_sha=$(printf 'replacement' | sha256sum | awk '{print $1}')
    write_non_snap_record "$exe" "$so" "$backup" \
        3.24.5 3.24.3 "$original_sha" "$replacement_sha"
    printf '%s\n' "$exe"
}

test_source_has_no_side_effects() {
    [[ ! -e "$CONFIG_DIR" ]]
}

test_non_snap_restore_success() {
    local exe record so backup
    exe=$(create_non_snap_record_fixture "My App")
    so="$exe.so"
    backup="$so.bak"
    record=$(find_non_snap_record "$exe")

    restore_non_snap_record "$record" >/dev/null

    assert_eq "original" "$(<"$so")" "original SO should be restored"
    assert_file_missing "$backup"
    assert_file_missing "$record"
}

test_non_snap_restore_rejects_modified_current_so() {
    local exe record so
    exe=$(create_non_snap_record_fixture "modified")
    so="$exe.so"
    record=$(find_non_snap_record "$exe")
    printf 'application-upgrade' > "$so"

    if restore_non_snap_record "$record" >/dev/null 2>&1; then
        return 1
    fi

    assert_eq "application-upgrade" "$(<"$so")" "modified SO must not be overwritten"
    assert_file_exists "$record"
    assert_file_exists "$so.bak"
}

test_non_snap_restore_rejects_modified_backup() {
    local exe record
    exe=$(create_non_snap_record_fixture "backup-change")
    record=$(find_non_snap_record "$exe")
    printf 'wrong-backup' > "$exe.so.bak"

    if restore_non_snap_record "$record" >/dev/null 2>&1; then
        return 1
    fi

    assert_eq "replacement" "$(<"$exe.so")" "current SO must remain untouched"
    assert_file_exists "$record"
}

test_non_snap_basename_ambiguity() {
    mkdir -p "$FIXTURE_ROOT/one" "$FIXTURE_ROOT/two"
    create_non_snap_record_fixture "one/app" >/dev/null
    create_non_snap_record_fixture "two/app" >/dev/null

    local output status
    set +e
    output=$(find_non_snap_record app 2>&1)
    status=$?
    set -e

    [[ $status -eq 2 ]]
    [[ "$output" == *"Multiple non-Snap records"* ]]
}

mock_curl() {
    local url="" output="" previous="" arg
    for arg in "$@"; do
        if [[ "$previous" == "-o" ]]; then
            output="$arg"
            previous=""
            continue
        fi
        if [[ "$arg" == "-o" ]]; then
            previous="-o"
            continue
        fi
        [[ "$arg" == mock://* ]] && url="$arg"
    done
    [[ -n "$url" && -n "$output" ]] || return 1
    cp "$FIXTURE_ROOT/remote/${url##*/}" "$output"
}

prepare_download_fixture() {
    mkdir -p "$FIXTURE_ROOT/remote"
    GITHUB_RAW_LIB="mock://lib"
    printf 'verified-content' > "$FIXTURE_ROOT/remote/libflutter_linux_gtk.so.9.9.9"
    local hash
    hash=$(sha256sum "$FIXTURE_ROOT/remote/libflutter_linux_gtk.so.9.9.9" | awk '{print $1}')
    printf '%s  libflutter_linux_gtk.so.9.9.9\n' "$hash" > "$FIXTURE_ROOT/remote/SHA256SUMS"
    curl() { mock_curl "$@"; }
}

test_download_accepts_valid_checksum() {
    prepare_download_fixture
    local result
    result=$(download_so_file_if_needed 9.9.9)
    assert_file_exists "$result"
    assert_eq "verified-content" "$(<"$result")" "verified SO content"
    assert_file_exists "$SO_LIB_DIR/SHA256SUMS"
}

test_download_rejects_checksum_mismatch() {
    prepare_download_fixture
    printf 'tampered-content' > "$FIXTURE_ROOT/remote/libflutter_linux_gtk.so.9.9.9"

    if download_so_file_if_needed 9.9.9 >/dev/null 2>&1; then
        return 1
    fi

    assert_file_missing "$SO_LIB_DIR/libflutter_linux_gtk.so.9.9.9"
    ! find "$SO_LIB_DIR" -maxdepth 1 -name '*.tmp.*' | grep -q .
}

test_download_rejects_missing_manifest_entry() {
    prepare_download_fixture
    : > "$FIXTURE_ROOT/remote/SHA256SUMS"

    if download_so_file_if_needed 9.9.9 >/dev/null 2>&1; then
        return 1
    fi

    assert_file_missing "$SO_LIB_DIR/libflutter_linux_gtk.so.9.9.9"
}

test_cached_so_is_reverified() {
    prepare_download_fixture
    local result
    result=$(download_so_file_if_needed 9.9.9)
    printf 'changed-after-download' > "$result"

    if download_so_file_if_needed 9.9.9 >/dev/null 2>&1; then
        return 1
    fi
}

test_snap_real_path_rejects_tampered_cached_so() {
    local app="tampered-app"
    local target_dir="$SNAP_ROOT/$app/current/lib"
    local cached_so="$SO_LIB_DIR/libflutter_linux_gtk.so.9.9.9"
    local mount_marker="$FIXTURE_ROOT/engine-mounted"
    mkdir -p "$target_dir" "$SO_LIB_DIR"
    printf 'application-engine' > "$target_dir/libflutter_linux_gtk.so"
    printf 'tampered-cache' > "$cached_so"
    printf '%064d  %s\n' 0 "${cached_so##*/}" > "$SO_LIB_DIR/SHA256SUMS"

    detect_flutter_version_from_so() { echo 9.9.9; }
    find_all_available_versions() { echo "9.9.9|local|true"; }
    mount_so_replacement() {
        : > "$mount_marker"
        return 0
    }
    export FLUTTER_CJK_DISABLE_SO_DOWNLOAD=1

    if do_mount "$app" true >/dev/null 2>&1; then
        return 1
    fi
    assert_file_missing "$mount_marker"
}

test_non_snap_real_path_rejects_tampered_cached_so() {
    local exe="$FIXTURE_ROOT/demo-executable"
    local target_so="$FIXTURE_ROOT/application.so"
    local cached_so="$SO_LIB_DIR/libflutter_linux_gtk.so.9.9.9"
    mkdir -p "$SO_LIB_DIR"
    printf 'executable' > "$exe"
    chmod +x "$exe"
    printf 'original-engine' > "$target_so"
    printf 'tampered-cache' > "$cached_so"
    printf '%064d  %s\n' 0 "${cached_so##*/}" > "$SO_LIB_DIR/SHA256SUMS"

    get_so_path_from_executable() { echo "$target_so"; }
    extract_engine_hash_from_so() { printf '%040d\n' 0; }
    update_flutter_hash_version_cache() { return 0; }
    find_flutter_version_by_hash() { echo 9.9.9; }
    find_all_available_versions() { echo "9.9.9|local|true"; }
    export FLUTTER_CJK_DISABLE_SO_DOWNLOAD=1

    if handle_executable_app "$exe" >/dev/null 2>&1; then
        return 1
    fi
    assert_eq "original-engine" "$(<"$target_so")" \
        "non-Snap target must not be replaced with an unverified cache"
}

test_snap_so_mount_uses_test_root() {
    local app="demo-app"
    local target_dir="$SNAP_ROOT/$app/current/lib"
    local replacement="$FIXTURE_ROOT/replacement.so"
    local calls="$FIXTURE_ROOT/mount.calls"
    mkdir -p "$target_dir"
    printf 'target' > "$target_dir/libflutter_linux_gtk.so"
    printf 'replacement' > "$replacement"

    umount() { return 0; }
    mount() {
        printf '%s\n' "$*" >> "$calls"
        return 0
    }

    mount_so_replacement "$app" "$replacement" >/dev/null

    assert_file_exists "$calls"
    grep -Fq -- "--bind $replacement $target_dir/libflutter_linux_gtk.so" "$calls"
}

test_installer_deploys_local_modules() {
    export FLUTTER_CJK_TARGET_BIN="$FIXTURE_ROOT/bin/flutter-font-fix"
    export FLUTTER_CJK_TARGET_MODULE_DIR="$FIXTURE_ROOT/libexec"
    export FLUTTER_CJK_REPO_REF="test/installer-branch"
    # shellcheck source=../install.sh
    source "$PROJECT_DIR/install.sh"

    (
        cd "$PROJECT_DIR"
        install_binary >/dev/null
        install_modules >/dev/null ||
            fail "first-time local module installation should succeed"
    )

    local module
    for module in engine non-snap snap system cli; do
        assert_file_exists "$FLUTTER_CJK_TARGET_MODULE_DIR/$module.sh"
    done

    assert_file_exists "${FLUTTER_CJK_TARGET_BIN}.paths"
    env -u FLUTTER_CJK_MODULE_DIR -u FLUTTER_CJK_SO_LIB_DIR \
        "$FLUTTER_CJK_TARGET_BIN" -l >/dev/null

    (
        unset FLUTTER_CJK_MODULE_DIR FLUTTER_CJK_SO_LIB_DIR
        # shellcheck source=/dev/null
        source "$FLUTTER_CJK_TARGET_BIN"
        assert_eq "$FLUTTER_CJK_TARGET_MODULE_DIR" "$MODULE_DIR" \
            "installed entrypoint should load its persisted module directory"
        assert_eq "$FIXTURE_ROOT/cache" "$SO_LIB_DIR" \
            "installed entrypoint should load its persisted SO directory"
        assert_eq "test/installer-branch" "$REPO_REF" \
            "installed entrypoint should load its persisted repository ref"
        assert_eq \
            "https://raw.githubusercontent.com/krystic/flutter-arm-cjk-fix/test/installer-branch" \
            "$GITHUB_RAW_BASE" \
            "installed entrypoint should download from its persisted repository ref"
    )
}

test_installer_uses_custom_so_directory() {
    local install_root="$FIXTURE_ROOT/install-source"
    local source_lib="$install_root/lib"
    local so_name="libflutter_linux_gtk.so.9.9.9"
    mkdir -p "$source_lib"
    printf 'custom-so' > "$source_lib/$so_name"
    (
        cd "$source_lib"
        sha256sum "$so_name" > SHA256SUMS
    )

    # shellcheck source=../install.sh
    source "$PROJECT_DIR/install.sh"
    (
        cd "$install_root"
        init_so_dir >/dev/null
    )

    assert_file_exists "$FIXTURE_ROOT/cache/$so_name"
    assert_file_exists "$FIXTURE_ROOT/cache/SHA256SUMS"
}

test_installer_downloads_remote_modules() {
    export FLUTTER_CJK_TARGET_BIN="$FIXTURE_ROOT/bin/flutter-font-fix"
    export FLUTTER_CJK_TARGET_MODULE_DIR="$FIXTURE_ROOT/remote-libexec"
    # shellcheck source=../install.sh
    source "$PROJECT_DIR/install.sh"

    curl() {
        local url="" output="" previous="" arg
        for arg in "$@"; do
            if [[ "$previous" == "-o" ]]; then
                output="$arg"
                previous=""
                continue
            fi
            [[ "$arg" == "-o" ]] && { previous="-o"; continue; }
            [[ "$arg" == https://* ]] && url="$arg"
        done
        cp "$PROJECT_DIR/src/${url##*/}" "$output"
    }

    (
        cd "$FIXTURE_ROOT"
        install_modules >/dev/null
    )

    local module
    for module in engine non-snap snap system cli; do
        assert_file_exists "$FLUTTER_CJK_TARGET_MODULE_DIR/$module.sh"
    done
}

test_installer_failed_download_preserves_existing_modules() {
    export FLUTTER_CJK_TARGET_MODULE_DIR="$FIXTURE_ROOT/existing-libexec"
    # shellcheck source=../install.sh
    source "$PROJECT_DIR/install.sh"

    mkdir -p "$FLUTTER_CJK_TARGET_MODULE_DIR"
    local module
    for module in engine non-snap snap system cli; do
        printf 'old-%s\n' "$module" > "$FLUTTER_CJK_TARGET_MODULE_DIR/$module.sh"
    done

    curl() {
        local output="" previous="" arg
        for arg in "$@"; do
            if [[ "$previous" == "-o" ]]; then
                output="$arg"
                previous=""
                continue
            fi
            [[ "$arg" == "-o" ]] && { previous="-o"; continue; }
            [[ "$arg" == */snap.sh ]] && return 1
        done
        printf 'new-module\n' > "$output"
    }

    if (
        cd "$FIXTURE_ROOT"
        install_modules >/dev/null 2>&1
    ); then
        return 1
    fi

    for module in engine non-snap snap system cli; do
        assert_eq "old-$module" \
            "$(<"$FLUTTER_CJK_TARGET_MODULE_DIR/$module.sh")" \
            "failed module download must preserve the existing module set"
    done
    ! find "$FIXTURE_ROOT" -maxdepth 1 -name 'existing-libexec.tmp.*' | grep -q .
}

test_entrypoint_rejects_incomplete_module_set() {
    local incomplete_dir="$FIXTURE_ROOT/incomplete"
    mkdir -p "$incomplete_dir"
    cp "$PROJECT_DIR/src/engine.sh" "$incomplete_dir/engine.sh"

    local output status
    set +e
    output=$(FLUTTER_CJK_MODULE_DIR="$incomplete_dir" \
        "$PROJECT_DIR/flutter-font-fix" -l 2>&1)
    status=$?
    set -e

    [[ $status -ne 0 ]]
    [[ "$output" == *"Required module not found"* ]]
}

run_test "sourcing the main script has no side effects" \
    with_fixture test_source_has_no_side_effects
run_test "non-Snap restore succeeds and cleans state" \
    with_fixture test_non_snap_restore_success
run_test "non-Snap restore rejects a modified current SO" \
    with_fixture test_non_snap_restore_rejects_modified_current_so
run_test "non-Snap restore rejects a modified backup" \
    with_fixture test_non_snap_restore_rejects_modified_backup
run_test "ambiguous non-Snap basenames require a full path" \
    with_fixture test_non_snap_basename_ambiguity
run_test "download accepts a matching SHA-256" \
    with_fixture test_download_accepts_valid_checksum
run_test "download rejects a SHA-256 mismatch" \
    with_fixture test_download_rejects_checksum_mismatch
run_test "download rejects a missing manifest entry" \
    with_fixture test_download_rejects_missing_manifest_entry
run_test "cached SO files are reverified" \
    with_fixture test_cached_so_is_reverified
run_test "Snap real selection rejects a tampered cached SO" \
    with_fixture test_snap_real_path_rejects_tampered_cached_so
run_test "non-Snap real selection rejects a tampered cached SO" \
    with_fixture test_non_snap_real_path_rejects_tampered_cached_so
run_test "Snap SO mounting is simulated under the test root" \
    with_fixture test_snap_so_mount_uses_test_root
run_test "installer deploys all local modules" \
    with_fixture test_installer_deploys_local_modules
run_test "installer copies SO files to the custom directory" \
    with_fixture test_installer_uses_custom_so_directory
run_test "installer downloads all modules outside a checkout" \
    with_fixture test_installer_downloads_remote_modules
run_test "failed module download preserves the installed module set" \
    with_fixture test_installer_failed_download_preserves_existing_modules
run_test "entrypoint rejects an incomplete module set" \
    with_fixture test_entrypoint_rejects_incomplete_module_set

echo "1..$TEST_COUNT"
