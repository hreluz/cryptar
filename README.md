# Cryptar

<p align="center">
    <img src="cryptar_logo.png" width="250">
</p>

**Cryptar** is a Bash utility to compress and encrypt (or decrypt and extract) files and directories using `tar` and `gpg`, with support for both interactive and non-interactive usage.

---

## What It Does

Cryptar securely compresses files or directories into encrypted `.tar.gz.gpg` archives and can decrypt and extract them when needed. Supports symmetric (passphrase) and asymmetric (public-key) encryption.

---

## Features

- Compress and encrypt any file or directory using `tar` + `gpg`
- Decrypt and extract previously encrypted archives
- **List archive contents** without extracting
- Symmetric (AES256) or asymmetric (public-key) encryption
- Configurable compression level (1–9)
- **Passphrase never exposed in process list** — passed via file descriptor
- Auto-appends `.tar.gz.gpg` extension if omitted
- Shows output file size after compression
- `--dry-run` flag to preview actions without executing
- `--force` flag to skip overwrite confirmation
- Interactive or automated passphrase input via `$PASSPHRASE` env var or `-p <file>`

---

## Usage

### Compress a File or Directory

```bash
./cryptar.sh -c -s <source> -o <output.tar.gz.gpg>
```

### Decompress an Encrypted Archive

```bash
./cryptar.sh -d -i <input.tar.gz.gpg> -o <output_dir>
```

### List Archive Contents

```bash
./cryptar.sh -l -i <input.tar.gz.gpg>
```

### Show Help

```bash
./cryptar.sh --help
```

---

## Options

| Option       | Description                                                      |
|--------------|------------------------------------------------------------------|
| `-c`         | Compression mode                                                 |
| `-d`         | Decompression mode                                               |
| `-l`         | List contents of an encrypted archive                            |
| `-s <path>`  | Source file or directory to compress                             |
| `-i <file>`  | Input file to decrypt                                            |
| `-o <path>`  | Output file or directory                                         |
| `-p <file>`  | Read passphrase from file (overrides `PASSPHRASE` env var)       |
| `-k <keyid>` | Recipient key ID for asymmetric (public-key) encryption          |
| `-z <1-9>`   | Compression level (default: 6)                                   |
| `-n`         | Dry run — show what would happen without doing it                |
| `-f`         | Force overwrite of existing output file without prompting        |
| `-h`         | Show help                                                        |

---

## Password Methods

Passphrase is passed via a file descriptor — it never appears in `ps` output.

Priority order:
1. `-p <file>` — read passphrase from a file
2. `PASSPHRASE` environment variable
3. Interactive prompt (compression asks twice to confirm)

Not needed when using asymmetric encryption (`-k`).

---

## Asymmetric Encryption

Use a GPG public key instead of a passphrase. The recipient's key must be in your keyring.

### Generate a GPG key pair

```bash
gpg --full-generate-key
```

Follow the prompts (RSA 4096 or Ed25519 recommended). When done, verify your key was created:

```bash
gpg --list-keys
```

You'll see output like:

```
pub   ed25519 2026-04-21 [SC]
      A1B2C3D4E5F6...
uid   [ultimate] Your Name <you@example.com>
sub   cv25519 2026-04-21 [E]
```

Use the email address (or key ID) as the recipient with `-k`.

### Share your public key (optional)

If encrypting for someone else, export your public key and send it to them:

```bash
# Export
gpg --armor --export you@example.com > mykey.pub

# Recipient imports it
gpg --import mykey.pub
```

### Encrypt and decrypt

```bash
# Encrypt
./cryptar.sh -c -s myfolder -o backup.tar.gz.gpg -k user@example.com

# Decrypt (uses private key from local keyring)
./cryptar.sh -d -i backup.tar.gz.gpg -o ./output -k user@example.com
```

---

## Examples

**Interactive compression:**
```bash
./cryptar.sh -c -s project -o project.tar.gz.gpg
```

**Max compression, force overwrite:**
```bash
./cryptar.sh -c -s project -o project.tar.gz.gpg -z 9 -f
```

**Automated decompression:**
```bash
PASSPHRASE="secret123" ./cryptar.sh -d -i project.tar.gz.gpg -o ./extracted
```

**Passphrase from file:**
```bash
./cryptar.sh -d -i archive.tar.gz.gpg -o ./output -p secret.txt
```

**List contents without extracting:**
```bash
PASSPHRASE="secret123" ./cryptar.sh -l -i archive.tar.gz.gpg
```

**Dry run:**
```bash
./cryptar.sh -c -s myfolder -o backup -n
```

---

## Requirements

- Bash
- `tar`
- `gpg` (GnuPG)

---

## License

MIT License
