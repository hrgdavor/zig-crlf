# Line Ending Utility (`crlf`)

A lightweight Zig utility to check and convert line endings across multiple files using glob patterns.

## Features

- **Multi-variant Detection**: Identifies LF (Unix), CRLF (Windows), CR (Classic Mac), and Mixed line endings.
- **Batch Conversion**: Convert files to your preferred line ending variant.
- **Multiple Glob Support**: Target specific files or directories using multiple wildcard patterns (e.g., `src/**/*.zig README.md`).
- **Recursive Globbing**: Support for standard `**` recursive matching across directories.
- **Detailed Reporting**: Shows counts for each line ending type found in a file.

## Build Instructions

### Prerequisites
- [Zig 0.15.0](https://ziglang.org/download/) or later.

### Build from Source
To build the utility for your native platform:

```powershell
zig build -Doptimize=ReleaseSmall
```

The binary will be available at `./zig-out/bin/crlf` (or `crlf.exe` on Windows).

## Usage

### Check Line Endings
Analyze files to see what variants they are using (supports multiple patterns):

```powershell
./zig-out/bin/crlf check "src/**/*.zig" "README.md"
```

**Example Output:**
```
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_cr.txt
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_crlf.txt
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_lf.txt
LF: 2   | CRLF: 0   | CR: 0   | lf     | test_mixed.txt
```

### Convert Line Endings
Convert files to a specific variant (`win`/`crlf`, `unix`/`lf`, or `mac`/`cr`):

```powershell
./zig-out/bin/crlf convert unix "src/*.zig"
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
