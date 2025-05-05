#!/bin/bash

# Secure TAR using GPG with password protection.
# Supports interactive and non-interactive use via $PASSPHRASE.

show_help() {
  cat << EOF
Usage:
  $0 -c -s <source_dir> -o <output_file>     Compress and encrypt
  $0 -d -i <input_file> -o <output_dir>      Decrypt and extract
  $0 -h | --help                             Show this help message

Options:
  -c            Compress mode
  -d            Decompress mode
  -s <dir>      Source directory to compress (used with -c)
  -i <file>     Encrypted input file to decrypt (used with -d)
  -o <file|dir> Output file or directory
  -p <file>     Optional: read passphrase from file (overrides PASSPHRASE)
  -h, --help    Show help message

Environment Variables:
  PASSPHRASE    If set, used as password non-interactively

Examples:
  Compress a folder interactively:
    $0 -c -s myfolder -o archive.tar.gz.gpg

  Decompress with an environment variable:
    PASSPHRASE="mypassword" $0 -d -i archive.tar.gz.gpg -o ./output

  Decompress with password from file:
    $0 -d -i archive.tar.gz.gpg -o ./output -p secret.txt
EOF
}

parse_arguments() {
  # Handle --help before getopts
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
  fi

  while getopts ":cds:i:o:p:h" opt; do
    case "$opt" in
      c) MODE="compress" ;;
      d) MODE="decompress" ;;
      s) SOURCE="$OPTARG" ;;
      i) INPUT="$OPTARG" ;;
      o) OUTPUT="$OPTARG" ;;
      p) PASSPHRASE_FILE="$OPTARG" ;;
      h) show_help; exit 0 ;;
      \?) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
      :) echo "Missing argument for -$OPTARG" >&2; exit 1 ;;
    esac
  done

  # Load password from file if specified
  if [[ -n "$PASSPHRASE_FILE" ]]; then
    if [[ -f "$PASSPHRASE_FILE" ]]; then
      PASSPHRASE="$(< "$PASSPHRASE_FILE")"
    else
      echo "❌ Error: Password file not found: $PASSPHRASE_FILE" >&2
      exit 1
    fi
  fi
}

compress() {
  if [[ -z "$SOURCE" || -z "$OUTPUT" ]]; then
    echo "❌ Error: -s (source) and -o (output) are required for compression." >&2
    exit 1
  fi

  if [[ -n "$PASSPHRASE" ]]; then
    tar -czf - "$SOURCE" | gpg --symmetric --cipher-algo AES256 \
      --batch --yes --passphrase "$PASSPHRASE" --pinentry-mode loopback -o "$OUTPUT"
  else
    tar -czf - "$SOURCE" | gpg --symmetric --cipher-algo AES256 \
      --pinentry-mode loopback -o "$OUTPUT"
  fi

  echo "✅ Directory '$SOURCE' compressed and encrypted to '$OUTPUT'"
}


decompress() {
  if [[ -z "$INPUT" || -z "$OUTPUT" ]]; then
    echo "❌ Error: -i (input) and -o (output) are required for decompression." >&2
    exit 1
  fi

  mkdir -p "$OUTPUT"

  if [[ -n "$PASSPHRASE" ]]; then
    gpg -d --batch --yes --passphrase "$PASSPHRASE" --pinentry-mode loopback "$INPUT" \
      | tar -xzf - -C "$OUTPUT"
  else
    gpg -d --pinentry-mode loopback "$INPUT" | tar -xzf - -C "$OUTPUT"
  fi

  echo "✅ File '$INPUT' decrypted and extracted to '$OUTPUT'"
}

# -------- Main execution flow --------
MODE=""
SOURCE=""
INPUT=""
OUTPUT=""
PASSPHRASE=""
PASSPHRASE_FILE=""

parse_arguments "$@"

case "$MODE" in
  compress)   compress ;;
  decompress) decompress ;;
  *)
    echo "❌ Error: You must specify either -c (compress) or -d (decompress)" >&2
    show_help
    exit 1
    ;;
esac