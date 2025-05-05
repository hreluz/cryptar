# Cryptar

<p align="center">
    <img src="cryptar_logo.png" width="250">
</p>

**Cryptar** is a Bash utility script to compress and encrypt (or decrypt and extract) directories using `tar` and `gpg`, with support for both interactive and non-interactive (automated) usage.

## 🔐 What It Does

Cryptar securely compresses directories into encrypted `.tar.gz.gpg` archives, and can also decrypt and extract them when needed. It supports optional password automation via environment variables.

---

## 🚀 Features

- Compress and encrypt any directory using `tar` + `gpg`
- Decrypt and extract previously encrypted archives
- Interactive or automated password input via `$PASSPHRASE`
- Safe error handling and helpful `--help` usage message

---

## 📦 Usage

### Compress a Directory

```bash
./cryp_tar.sh -c -s <source_dir> -o <output_file.tar.gz.gpg>
```

### Decompress an Encrypted Archive

```bash
./cryp_tar.sh -d -i <input_file.tar.gz.gpg> -o <output_dir>
```

### Show Help

```bash
./cryp_tar.sh --help
```

---

## 🔧 Options

| Option     | Description                                             |
|------------|---------------------------------------------------------|
| `-c`       | Compression mode                                        |
| `-d`       | Decompression mode                                      |
| `-s <dir>` | Source directory to compress                            |
| `-i <file>`| Input file to decrypt                                   |
| `-o <path>`| Output file or output directory                         |
| `-h`       | Show help                                               |

---

## 🔐 Environment Variables

- `PASSPHRASE`: If set, enables non-interactive password input.

```bash
PASSPHRASE="mypassword" ./cryp_tar.sh -c -s myfolder -o backup.tar.gz.gpg
```

---

## 📋 Examples

**Interactive Compression:**
```bash
./cryp_tar.sh -c -s project -o project.tar.gz.gpg
```

**Automated Decompression:**
```bash
PASSPHRASE="secret123" ./cryp_tar.sh -d -i project.tar.gz.gpg -o ./extracted
```

---

## 📎 Requirements

- Bash
- `tar`
- `gpg` (GnuPG)

---

## 📄 License

MIT License (or specify your own)