#!/bin/bash
set -uo pipefail

spinner() {
  local pid=$1
  local msg=$2
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r  %s %s " "${spinstr:$i:1}" "$msg" >&2
    i=$(( (i + 1) % ${#spinstr} ))
    sleep 0.1
  done
  printf "\r\033[2K" >&2
}

show_help() {
  cat << EOF
Usage:
  $0 -c -s <source> -o <output_file>         Compress and encrypt
  $0 -d -i <input_file> -o <output_dir>      Decrypt and extract
  $0 -l -i <input_file>                      List archive contents
  $0 -h | --help                             Show this help message

Options:
  -c              Compress mode
  -d              Decompress mode
  -l              List contents of an encrypted archive
  -s <path>       Source file or directory to compress
  -i <file>       Encrypted input file
  -o <path>       Output file or directory
  -p <file>       Read passphrase from file (overrides PASSPHRASE env var)
  -k <keyid>      Recipient key ID for asymmetric (public-key) encryption
  -z <1-9>        Compression level (default: 6)
  -n              Dry run: show what would happen without doing it
  -f              Force overwrite of existing output file
  -h, --help      Show help message

Environment Variables:
  PASSPHRASE      If set, used as passphrase non-interactively

Examples:
  Compress a folder interactively:
    $0 -c -s myfolder -o archive.tar.gz.gpg

  Compress a single file at max compression:
    $0 -c -s report.pdf -o report.tar.gz.gpg -z 9

  Decompress with environment variable:
    PASSPHRASE="mypassword" $0 -d -i archive.tar.gz.gpg -o ./output

  Encrypt with a public key (asymmetric):
    $0 -c -s myfolder -o archive.tar.gz.gpg -k user@example.com

  List archive contents without extracting:
    $0 -l -i archive.tar.gz.gpg

  Dry run:
    $0 -c -s myfolder -o archive -n
EOF
}

prompt_passphrase() {
  read -r -s -p "Enter passphrase: " PASSPHRASE; echo
}

prompt_passphrase_confirm() {
  read -r -s -p "Enter passphrase: " PASSPHRASE; echo
  read -r -s -p "Confirm passphrase: " PASSPHRASE_CONFIRM; echo
  if [[ "$PASSPHRASE" != "$PASSPHRASE_CONFIRM" ]]; then
    echo "❌ Error: Passphrases do not match." >&2
    exit 1
  fi
}

parse_arguments() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
    exit 0
  fi

  while getopts ":cdls:i:o:p:k:z:nfh" opt; do
    case "$opt" in
      c) MODE="compress" ;;
      d) MODE="decompress" ;;
      l) MODE="list" ;;
      s) SOURCE="$OPTARG" ;;
      i) INPUT="$OPTARG" ;;
      o) OUTPUT="$OPTARG" ;;
      p) PASSPHRASE_FILE="$OPTARG" ;;
      k) RECIPIENT="$OPTARG" ;;
      z) COMPRESS_LEVEL="$OPTARG" ;;
      n) DRY_RUN=true ;;
      f) FORCE=true ;;
      h) show_help; exit 0 ;;
      \?) echo "❌ Unknown option: -$OPTARG" >&2; exit 1 ;;
      :) echo "❌ Missing argument for -$OPTARG" >&2; exit 1 ;;
    esac
  done

  if [[ -n "$COMPRESS_LEVEL" ]] && ! [[ "$COMPRESS_LEVEL" =~ ^[1-9]$ ]]; then
    echo "❌ Error: Compression level must be 1–9." >&2
    exit 1
  fi

  if [[ -n "$PASSPHRASE_FILE" ]]; then
    if [[ -f "$PASSPHRASE_FILE" ]]; then
      PASSPHRASE="$(< "$PASSPHRASE_FILE")"
    else
      echo "❌ Error: Passphrase file not found: $PASSPHRASE_FILE" >&2
      exit 1
    fi
  fi
}

compress() {
  if [[ -z "$SOURCE" || -z "$OUTPUT" ]]; then
    echo "❌ Error: -s (source) and -o (output) are required for compression." >&2
    exit 1
  fi

  if [[ ! -e "$SOURCE" ]]; then
    echo "❌ Error: Source not found: $SOURCE" >&2
    exit 1
  fi

  # Auto-append extension if missing
  if [[ "$OUTPUT" != *.tar.gz.gpg ]]; then
    OUTPUT="${OUTPUT}.tar.gz.gpg"
    echo "ℹ️  Output set to '$OUTPUT'"
  fi

  if [[ -f "$OUTPUT" && "$FORCE" != true ]]; then
    read -r -p "⚠️  '$OUTPUT' already exists. Overwrite? [y/N] " confirm
    [[ "$confirm" =~ ^[yY]$ ]] || { echo "Aborted." >&2; exit 1; }
  fi

  local gpg_flags=(--batch --yes --pinentry-mode loopback)
  local level="${COMPRESS_LEVEL:-6}"

  if [[ -n "$RECIPIENT" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "🔍 Dry run: would compress '$SOURCE' → '$OUTPUT'"
      echo "   Mode: asymmetric (recipient: $RECIPIENT), compression level: $level"
      return
    fi
    ( tar -cf - "$SOURCE" | gzip "-$level" \
        | gpg --encrypt -r "$RECIPIENT" "${gpg_flags[@]}" -o "$OUTPUT" ) &
  else
    if [[ -z "$PASSPHRASE" ]]; then
      prompt_passphrase_confirm
    fi
    if [[ "$DRY_RUN" == true ]]; then
      echo "🔍 Dry run: would compress '$SOURCE' → '$OUTPUT'"
      echo "   Mode: symmetric (AES256), compression level: $level"
      return
    fi
    # Passphrase is passed via fd 3 — never appears in ps output
    ( tar -cf - "$SOURCE" | gzip "-$level" \
        | gpg --symmetric --cipher-algo AES256 "${gpg_flags[@]}" \
              --passphrase-fd 3 -o "$OUTPUT" ) 3<<<"$PASSPHRASE" &
  fi

  local pid=$!
  spinner "$pid" "Compressing and encrypting '$SOURCE'..."
  wait "$pid" || { echo "❌ Error: Compression failed." >&2; exit 1; }

  local size
  size=$(du -sh "$OUTPUT" | cut -f1)
  echo "✅ '$SOURCE' → '$OUTPUT' ($size)"
}

decompress() {
  if [[ -z "$INPUT" || -z "$OUTPUT" ]]; then
    echo "❌ Error: -i (input) and -o (output) are required for decompression." >&2
    exit 1
  fi

  if [[ ! -f "$INPUT" ]]; then
    echo "❌ Error: Input file not found: $INPUT" >&2
    exit 1
  fi

  local gpg_flags=(--batch --yes --pinentry-mode loopback)

  if [[ -z "$RECIPIENT" && -z "$PASSPHRASE" ]]; then
    prompt_passphrase
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "🔍 Dry run: would decrypt '$INPUT' → '$OUTPUT/'"
    return
  fi

  mkdir -p "$OUTPUT"

  if [[ -n "$RECIPIENT" ]]; then
    ( gpg -d "${gpg_flags[@]}" -o - "$INPUT" | tar -xzf - -C "$OUTPUT" ) &
  else
    ( gpg -d "${gpg_flags[@]}" --passphrase-fd 3 -o - "$INPUT" \
        | tar -xzf - -C "$OUTPUT" ) 3<<<"$PASSPHRASE" &
  fi

  local pid=$!
  spinner "$pid" "Decrypting and extracting '$INPUT'..."
  wait "$pid" || { echo "❌ Error: Decompression failed." >&2; exit 1; }

  echo "✅ '$INPUT' → '$OUTPUT/'"
}

list_contents() {
  if [[ -z "$INPUT" ]]; then
    echo "❌ Error: -i (input) is required to list contents." >&2
    exit 1
  fi

  if [[ ! -f "$INPUT" ]]; then
    echo "❌ Error: Input file not found: $INPUT" >&2
    exit 1
  fi

  local gpg_flags=(--batch --yes --pinentry-mode loopback)

  if [[ -z "$RECIPIENT" && -z "$PASSPHRASE" ]]; then
    prompt_passphrase
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "🔍 Dry run: would list contents of '$INPUT'"
    return
  fi

  echo "📋 Contents of '$INPUT':"
  if [[ -n "$RECIPIENT" ]]; then
    gpg -d "${gpg_flags[@]}" -o - "$INPUT" | tar -tzf -
  else
    gpg -d "${gpg_flags[@]}" --passphrase-fd 3 -o - "$INPUT" \
      3<<<"$PASSPHRASE" | tar -tzf -
  fi
}

# -------- Main --------
MODE=""
SOURCE=""
INPUT=""
OUTPUT=""
PASSPHRASE="${PASSPHRASE:-}"
PASSPHRASE_FILE=""
RECIPIENT=""
COMPRESS_LEVEL=""
DRY_RUN=false
FORCE=false

parse_arguments "$@"

case "$MODE" in
  compress)   compress ;;
  decompress) decompress ;;
  list)       list_contents ;;
  *)
    echo "❌ Error: You must specify -c (compress), -d (decompress), or -l (list)" >&2
    show_help
    exit 1
    ;;
esac
