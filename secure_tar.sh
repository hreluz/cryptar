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
  -h, --help    Show help message

Environment Variables:
  PASSPHRASE    If set, used as password non-interactively

Examples:
  Compress a folder interactively:
    $0 -c -s myfolder -o archive.tar.gz.gpg

  Decompress with an environment variable:
    PASSPHRASE="mypassword" $0 -d -i archive.tar.gz.gpg -o ./output
EOF
}

# Handle --help before getopts
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  show_help
  exit 0
fi

# Default values
MODE=""
SOURCE=""
INPUT=""
OUTPUT=""

# Parse options
while getopts ":cds:i:o:h" opt; do
  case "$opt" in
    c) MODE="compress" ;;
    d) MODE="decompress" ;;
    s) SOURCE="$OPTARG" ;;
    i) INPUT="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    h) show_help; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
    :) echo "Missing argument for -$OPTARG" >&2; exit 1 ;;
  esac
done

# Perform compression
if [[ "$MODE" == "compress" ]]; then
  if [[ -z "$SOURCE" || -z "$OUTPUT" ]]; then
    echo "Error: -s and -o are required in compression mode." >&2
    exit 1
  fi
  if [[ -n "$PASSPHRASE" ]]; then
    tar -czf - "$SOURCE" | gpg --symmetric --cipher-algo AES256 \
      --batch --yes --passphrase "$PASSPHRASE" --pinentry-mode loopback -o "$OUTPUT"
  else
    tar -czf - "$SOURCE" | gpg --symmetric --cipher-algo AES256 \
      --pinentry-mode loopback -o "$OUTPUT"
  fi
  echo "Directory '$SOURCE' compressed and encrypted as '$OUTPUT'."

# Perform decompression
elif [[ "$MODE" == "decompress" ]]; then
  if [[ -z "$INPUT" || -z "$OUTPUT" ]]; then
    echo "Error: -i and -o are required in decompression mode." >&2
    exit 1
  fi
  mkdir -p "$OUTPUT"
  if [[ -n "$PASSPHRASE" ]]; then
    gpg -d --batch --yes --passphrase "$PASSPHRASE" --pinentry-mode loopback "$INPUT" \
      | tar -xzf - -C "$OUTPUT"
  else
    gpg -d --pinentry-mode loopback "$INPUT" | tar -xzf - -C "$OUTPUT"
  fi
  echo "File '$INPUT' decrypted and extracted to '$OUTPUT'."

else
  echo "Error: You must specify either -c (compress) or -d (decompress)." >&2
  show_help
  exit 1
fi
