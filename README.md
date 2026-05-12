# Line Ending Utility (`crlf`)

A lightweight Zig utility to check and convert line endings across files.

> Download pre-build binaries for your OS from the [releases](https://github.com/hrgdavor/zig-crlf/releases) page.

## Features

- **Multi-variant Detection**: Identifies LF (Unix), CRLF (Windows), CR (Classic Mac), and Mixed line endings.
- **Batch Conversion**: Convert files to your preferred line ending variant.
- **Shell-Expansion Friendly by Default**: Positional arguments are treated as explicit file paths.
- **Optional Recursive Glob Mode**: Enable recursive pattern search with `--glob` / `-g`.
- **Detailed Reporting**: Shows counts for each line ending type found in a file.

## Usage


- positional args are explicit file paths.
- recursive glob matching is available only with `--glob` / `-g`.

This makes `crlf` align with shell expansion workflows on linux, where your shell expands patterns like `*.java` before invoking the command.

### Shell expansion vs recursive glob mode

Shell expansion (default mode, no `--glob`):

```powershell
# PowerShell expands *.zig to explicit files in the current directory
./zig-out/bin/crlf check *.zig
```

```bash
# Bash expands recursively when globstar is enabled
shopt -s globstar
./zig-out/bin/crlf check src/**/*.zig
```

Recursive glob mode inside `crlf`:

```powershell
./zig-out/bin/crlf check --glob "src/**/*.zig"
./zig-out/bin/crlf convert --variant unix --glob "src/**/*.zig"
```

### How to target only the current folder with `--glob`

In `--glob` mode, `*` does **not** cross directory separators.

Optimization note:

- When all provided patterns are simple local globs (for example `*.md`, `*.zig`),
  `crlf` uses a current-directory-only scan and does **not** walk subfolders.
- Patterns that include path separators or recursive intent (for example `src/*.zig`,
  `src/**/*.zig`) use directory traversal as needed.

- `*.zig`: only `.zig` files in the current working directory.
- `src/*.zig`: only `.zig` files directly under `src` (not subfolders).
- `src/**/*.zig`: `.zig` files under `src` recursively.

Examples:

```powershell
# Current folder only
./zig-out/bin/crlf check --glob "*.zig"

# Only direct children of src/
./zig-out/bin/crlf check --glob "src/*.zig"

# Recursive under src/
./zig-out/bin/crlf check --glob "src/**/*.zig"
```

### Check Line Endings
Analyze files to see what variants they are using:

```powershell
./zig-out/bin/crlf check src/main.zig src/args.zig README.md
```

**Example Output:**
```
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_cr.txt
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_crlf.txt
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_lf.txt
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_mixed.txt
```

### Filter By Variant
Use `--not` to exclude files with a specific line ending variant:

```powershell
./zig-out/bin/crlf check --not lf src/main.zig src/args.zig
```

This is useful for finding files that need conversion to a specific variant.

Use `--is` for the opposite behavior (include only one variant):

```powershell
./zig-out/bin/crlf check --is crlf src/main.zig src/args.zig
```

### Convert Line Endings
Convert files to a specific variant (`win`/`crlf`, `unix`/`lf`, or `mac`/`cr`):

```powershell
./zig-out/bin/crlf convert --variant unix src/main.zig src/args.zig
```

Convert with filtering (for example, skip already-LF files):

```powershell
./zig-out/bin/crlf convert --variant unix --not lf src/main.zig src/args.zig
```

Convert only files currently using CRLF:

```powershell
./zig-out/bin/crlf convert --variant unix --is crlf src/main.zig src/args.zig
```

### Recursive glob mode examples (`--glob`)

```powershell
./zig-out/bin/crlf check --glob "src/**/*.zig" "README.md"
./zig-out/bin/crlf check --glob --not lf "src/**/*.zig"
./zig-out/bin/crlf convert --variant unix --glob --is crlf "src/**/*.zig"
```

### Help
For more details and variant aliases:

```powershell
./zig-out/bin/crlf --help
```

## Line Ending Variants
- **LF** (Line Feed, `\n`): Standard on Linux, Unix, and modern macOS.
- **CRLF** (Carriage Return + Line Feed, `\r\n`): Standard on Windows.
- **CR** (Carriage Return, `\r`): Standard on classic Mac OS (pre-OSX).


# Build Instructions

## Prerequisites
- [Zig 0.16.0](https://ziglang.org/download/) or later.

## Build from Source
To build the utility for your native platform:

```powershell
zig build -Doptimize=ReleaseSafe
```

The binary will be available at `./zig-out/bin/crlf` (or `crlf.exe` on Windows).

To build for other platforms: `x86_64-windows`, `aarch64-windows`, `x86_64-linux`, `aarch64-linux`, `x86_64-macos`, `aarch64-macos`

```
zig build -Dtarget={platform} -Doptimize=ReleaseSafe
```
