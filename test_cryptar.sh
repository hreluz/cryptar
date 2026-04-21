#!/bin/bash
# Test suite for cryptar.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$SCRIPT_DIR/cryptar.sh"
TMP=""
PASS=0
FAIL=0
SKIP=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────────────────────

section() { echo -e "\n${BOLD}$1${NC}"; }

ok()   { echo -e "  ${GREEN}✓${NC} $1"; (( PASS++ )); }
fail() { echo -e "  ${RED}✗${NC} $1"; (( FAIL++ )); }
skip() { echo -e "  ${YELLOW}~${NC} $1 (skipped)"; (( SKIP++ )); }

assert_exits_0() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

assert_exits_nonzero() {
  local desc="$1"; shift
  if ! "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi
}

assert_file_exists()    { [[ -e "$2" ]] && ok "$1" || fail "$1"; }
assert_file_not_exists(){ [[ ! -e "$2" ]] && ok "$1" || fail "$1"; }

assert_output_contains() {
  local desc="$1" pattern="$2"; shift 2
  if "$@" 2>&1 | grep -q "$pattern"; then ok "$desc"; else fail "$desc"; fi
}

# ── Setup / teardown ──────────────────────────────────────────────────────────

setup() {
  TMP=$(mktemp -d)

  # Source directory with nested content
  mkdir -p "$TMP/src/subdir"
  echo "hello world"    > "$TMP/src/file1.txt"
  echo "nested content" > "$TMP/src/subdir/file2.txt"

  # Single source file
  echo "single file" > "$TMP/single.txt"

  # Passphrase file
  echo "testpass" > "$TMP/passfile.txt"
}

teardown() { rm -rf "$TMP"; }

# ── Asymmetric setup (optional) ───────────────────────────────────────────────

ORIG_GNUPGHOME="${GNUPGHOME:-}"
GPG_TMP=""
GPG_KEY=""
HAVE_ASYNC_KEY=false

setup_gpg_key() {
  GPG_TMP=$(mktemp -d)
  export GNUPGHOME="$GPG_TMP"
  chmod 700 "$GPG_TMP"

  gpg --batch --gen-key 2>/dev/null <<'GPGEOF'
%no-protection
Key-Type: EdDSA
Key-Curve: Ed25519
Subkey-Type: ECDH
Subkey-Curve: Curve25519
Name-Real: Cryptar Test
Name-Email: test@cryptar.test
Expire-Date: 0
%commit
GPGEOF
  GPG_KEY="test@cryptar.test"
}

teardown_gpg_key() {
  rm -rf "$GPG_TMP"
  if [[ -n "$ORIG_GNUPGHOME" ]]; then
    export GNUPGHOME="$ORIG_GNUPGHOME"
  else
    unset GNUPGHOME
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# TESTS
# ═══════════════════════════════════════════════════════════════════════════════

run_tests() {

  # ── Argument / CLI errors ──────────────────────────────────────────────────

  section "Argument handling"

  assert_exits_0        "--help exits 0" \
    bash "$SCRIPT" --help

  assert_exits_0        "-h exits 0" \
    bash "$SCRIPT" -h

  assert_output_contains "--help output mentions usage" "Usage" \
    bash "$SCRIPT" --help

  assert_exits_nonzero  "no mode → error" \
    bash "$SCRIPT" -s "$TMP/src" -o "$TMP/out.tar.gz.gpg"

  assert_exits_nonzero  "unknown option → error" \
    bash "$SCRIPT" -X

  assert_exits_nonzero  "option missing argument → error" \
    bash "$SCRIPT" -c -s

  assert_exits_nonzero  "invalid compression level 0 → error" \
    bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/out.tar.gz.gpg" -z 0

  assert_exits_nonzero  "invalid compression level 10 → error" \
    bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/out.tar.gz.gpg" -z 10

  assert_exits_nonzero  "passphrase file not found → error" \
    bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/out.tar.gz.gpg" -p "$TMP/no_such_file.txt"

  # ── Compress — validation errors ──────────────────────────────────────────

  section "Compress — validation"

  assert_exits_nonzero  "missing -s → error" \
    bash "$SCRIPT" -c -o "$TMP/out.tar.gz.gpg"

  assert_exits_nonzero  "missing -o → error" \
    PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src"

  assert_exits_nonzero  "source does not exist → error" \
    PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/no_such_dir" -o "$TMP/out.tar.gz.gpg"

  # ── Compress — success cases ───────────────────────────────────────────────

  section "Compress — success"

  PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/dir_archive.tar.gz.gpg" \
    >/dev/null 2>&1
  assert_file_exists    "compress directory → archive created" \
    "$TMP/dir_archive.tar.gz.gpg"

  PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/single.txt" -o "$TMP/file_archive.tar.gz.gpg" \
    >/dev/null 2>&1
  assert_file_exists    "compress single file → archive created" \
    "$TMP/file_archive.tar.gz.gpg"

  # Auto-extension: pass output without .tar.gz.gpg, expect it to be appended
  PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/autoext" \
    >/dev/null 2>&1
  assert_file_exists    "auto-appends .tar.gz.gpg extension" \
    "$TMP/autoext.tar.gz.gpg"

  # Verify output size is reported in success message
  assert_output_contains "success message includes file size" "sized.tar.gz.gpg" \
    bash -c "PASSPHRASE=testpass bash '$SCRIPT' -c -s '$TMP/src' -o '$TMP/sized.tar.gz.gpg'"

  # Compression level: archives at levels 1 and 9 should both succeed
  PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/fast.tar.gz.gpg" -z 1 \
    >/dev/null 2>&1
  assert_file_exists    "compression level 1 (fast) succeeds" "$TMP/fast.tar.gz.gpg"

  PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/best.tar.gz.gpg" -z 9 \
    >/dev/null 2>&1
  assert_file_exists    "compression level 9 (best) succeeds" "$TMP/best.tar.gz.gpg"

  # Passphrase from file
  bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/pffile.tar.gz.gpg" -p "$TMP/passfile.txt" \
    >/dev/null 2>&1
  assert_file_exists    "passphrase from -p file succeeds" "$TMP/pffile.tar.gz.gpg"

  # ── Compress — overwrite behaviour ────────────────────────────────────────

  section "Compress — overwrite"

  # Create an existing archive
  PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/overwrite.tar.gz.gpg" \
    >/dev/null 2>&1

  # 'n' at overwrite prompt → abort
  if echo "n" | PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" \
      -o "$TMP/overwrite.tar.gz.gpg" >/dev/null 2>&1; then
    fail "overwrite prompt 'n' → aborts"
  else
    ok "overwrite prompt 'n' → aborts"
  fi

  # 'y' at overwrite prompt → succeeds
  if echo "y" | PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" \
      -o "$TMP/overwrite.tar.gz.gpg" >/dev/null 2>&1; then
    ok "overwrite prompt 'y' → proceeds"
  else
    fail "overwrite prompt 'y' → proceeds"
  fi

  # -f flag skips the prompt entirely
  if PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" \
      -o "$TMP/overwrite.tar.gz.gpg" -f >/dev/null 2>&1; then
    ok "-f force flag skips overwrite prompt"
  else
    fail "-f force flag skips overwrite prompt"
  fi

  # ── Compress — interactive passphrase ─────────────────────────────────────

  section "Compress — interactive passphrase"

  # Matching passphrases via stdin
  printf "mypass\nmypass\n" | bash "$SCRIPT" -c -s "$TMP/src" \
    -o "$TMP/interactive.tar.gz.gpg" >/dev/null 2>&1
  assert_file_exists    "matching interactive passphrase → archive created" \
    "$TMP/interactive.tar.gz.gpg"

  # Mismatched passphrases
  assert_exits_nonzero  "mismatched interactive passphrases → error" \
    bash -c "printf 'pass1\npass2\n' | bash '$SCRIPT' -c -s '$TMP/src' \
      -o '$TMP/mismatch.tar.gz.gpg'"

  # ── Compress — dry run ─────────────────────────────────────────────────────

  section "Compress — dry run"

  PASSPHRASE="testpass" bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/dryrun_c.tar.gz.gpg" -n \
    >/dev/null 2>&1
  assert_file_not_exists "dry run does not create output file" \
    "$TMP/dryrun_c.tar.gz.gpg"

  assert_output_contains "dry run prints dry-run message" "Dry run" \
    bash -c "PASSPHRASE=testpass bash '$SCRIPT' -c -s '$TMP/src' -o '$TMP/x' -n"

  # ── Decompress — validation errors ────────────────────────────────────────

  section "Decompress — validation"

  assert_exits_nonzero  "missing -i → error" \
    PASSPHRASE="testpass" bash "$SCRIPT" -d -o "$TMP/out"

  assert_exits_nonzero  "missing -o → error" \
    PASSPHRASE="testpass" bash "$SCRIPT" -d -i "$TMP/dir_archive.tar.gz.gpg"

  assert_exits_nonzero  "input file not found → error" \
    PASSPHRASE="testpass" bash "$SCRIPT" -d -i "$TMP/no_such.tar.gz.gpg" -o "$TMP/out"

  assert_exits_nonzero  "wrong passphrase → error" \
    PASSPHRASE="wrongpass" bash "$SCRIPT" -d -i "$TMP/dir_archive.tar.gz.gpg" -o "$TMP/wrong_out"

  # ── Decompress — success cases ─────────────────────────────────────────────

  section "Decompress — success"

  PASSPHRASE="testpass" bash "$SCRIPT" -d \
    -i "$TMP/dir_archive.tar.gz.gpg" -o "$TMP/extracted" >/dev/null 2>&1
  assert_file_exists    "decompress directory archive → output dir created" \
    "$TMP/extracted"

  # tar stores absolute paths, so files land deep under the output dir — use find
  if find "$TMP/extracted" -name "file1.txt" -type f | grep -q .; then
    ok "decompress directory archive → file1.txt restored"
  else
    fail "decompress directory archive → file1.txt restored"
  fi
  if find "$TMP/extracted" -name "file2.txt" -type f | grep -q .; then
    ok "decompress directory archive → nested file2.txt restored"
  else
    fail "decompress directory archive → nested file2.txt restored"
  fi

  # Verify file content is identical
  restored_f1=$(find "$TMP/extracted" -name "file1.txt" -type f | head -1)
  if [[ -n "$restored_f1" ]] && diff -q "$TMP/src/file1.txt" "$restored_f1" >/dev/null 2>&1; then
    ok "decompressed file1.txt content matches original"
  else
    fail "decompressed file1.txt content matches original"
  fi

  PASSPHRASE="testpass" bash "$SCRIPT" -d \
    -i "$TMP/file_archive.tar.gz.gpg" -o "$TMP/extracted_file" >/dev/null 2>&1
  if find "$TMP/extracted_file" -name "single.txt" -type f | grep -q .; then
    ok "decompress single-file archive → file restored"
  else
    fail "decompress single-file archive → file restored"
  fi

  # Passphrase from file
  bash "$SCRIPT" -d -i "$TMP/pffile.tar.gz.gpg" -o "$TMP/pffile_out" \
    -p "$TMP/passfile.txt" >/dev/null 2>&1
  assert_file_exists    "decompress with -p passphrase file → output created" \
    "$TMP/pffile_out"

  # ── Decompress — dry run ───────────────────────────────────────────────────

  section "Decompress — dry run"

  PASSPHRASE="testpass" bash "$SCRIPT" -d \
    -i "$TMP/dir_archive.tar.gz.gpg" -o "$TMP/dryrun_d_out" -n >/dev/null 2>&1
  assert_file_not_exists "dry run does not create output dir" \
    "$TMP/dryrun_d_out"

  assert_output_contains "dry run prints dry-run message" "Dry run" \
    bash -c "PASSPHRASE=testpass bash '$SCRIPT' -d \
      -i '$TMP/dir_archive.tar.gz.gpg' -o '$TMP/x' -n"

  # ── List — validation errors ───────────────────────────────────────────────

  section "List — validation"

  assert_exits_nonzero  "missing -i → error" \
    PASSPHRASE="testpass" bash "$SCRIPT" -l

  assert_exits_nonzero  "input file not found → error" \
    PASSPHRASE="testpass" bash "$SCRIPT" -l -i "$TMP/no_such.tar.gz.gpg"

  # ── List — success cases ───────────────────────────────────────────────────

  section "List — success"

  assert_output_contains "list shows file1.txt entry" "file1.txt" \
    bash -c "PASSPHRASE=testpass bash '$SCRIPT' -l -i '$TMP/dir_archive.tar.gz.gpg'"

  assert_output_contains "list shows nested file2.txt entry" "file2.txt" \
    bash -c "PASSPHRASE=testpass bash '$SCRIPT' -l -i '$TMP/dir_archive.tar.gz.gpg'"

  # List should NOT extract any files
  PASSPHRASE="testpass" bash "$SCRIPT" -l -i "$TMP/dir_archive.tar.gz.gpg" >/dev/null 2>&1
  assert_file_not_exists "list does not extract files to disk" \
    "$TMP/src_listed"

  # ── List — dry run ─────────────────────────────────────────────────────────

  section "List — dry run"

  assert_output_contains "dry run prints dry-run message" "Dry run" \
    bash -c "PASSPHRASE=testpass bash '$SCRIPT' -l \
      -i '$TMP/dir_archive.tar.gz.gpg' -n"

  # ── Asymmetric encryption ──────────────────────────────────────────────────

  section "Asymmetric (public-key) encryption"

  setup_gpg_key 2>/dev/null && HAVE_ASYNC_KEY=true || HAVE_ASYNC_KEY=false

  if [[ "$HAVE_ASYNC_KEY" == true ]]; then
    bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/asym.tar.gz.gpg" -k "$GPG_KEY" \
      >/dev/null 2>&1
    assert_file_exists    "asymmetric compress → archive created" \
      "$TMP/asym.tar.gz.gpg"

    bash "$SCRIPT" -d -i "$TMP/asym.tar.gz.gpg" -o "$TMP/asym_out" -k "$GPG_KEY" \
      >/dev/null 2>&1
    assert_file_exists    "asymmetric decompress → output created" \
      "$TMP/asym_out"
    if find "$TMP/asym_out" -name "file1.txt" -type f | grep -q .; then
      ok "asymmetric decompress → file1.txt restored"
    else
      fail "asymmetric decompress → file1.txt restored"
    fi

    assert_output_contains "asymmetric list shows file1.txt" "file1.txt" \
      bash "$SCRIPT" -l -i "$TMP/asym.tar.gz.gpg" -k "$GPG_KEY"

    assert_output_contains "asymmetric dry run mentions recipient" "$GPG_KEY" \
      bash "$SCRIPT" -c -s "$TMP/src" -o "$TMP/asym_dry" -k "$GPG_KEY" -n

    teardown_gpg_key
  else
    skip "asymmetric compress"
    skip "asymmetric decompress"
    skip "asymmetric list"
    skip "asymmetric dry run"
  fi
}

# ── Main ───────────────────────────────────────────────────────────────────────

echo -e "${BOLD}cryptar test suite${NC}"
echo "script: $SCRIPT"

setup
run_tests
teardown

echo ""
echo "─────────────────────────────"
echo -e "  ${GREEN}passed${NC}  $PASS"
[[ $FAIL -gt 0 ]] && echo -e "  ${RED}failed${NC}  $FAIL" || echo -e "  failed  $FAIL"
[[ $SKIP -gt 0 ]] && echo -e "  ${YELLOW}skipped${NC} $SKIP"
echo "─────────────────────────────"

[[ $FAIL -eq 0 ]]
