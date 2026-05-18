const std = @import("std");
const config = @import("config");

// ── Public types ─────────────────────────────────────────────────────────────

pub const Args = struct {
    __commands__: union(enum) {
        version: struct {},
        check: struct {
            not: ?[]const u8 = null,
            is: ?[]const u8 = null,
            glob: bool = false,
        },
        convert: struct {
            variant: []const u8,
            not: ?[]const u8 = null,
            is: ?[]const u8 = null,
            glob: bool = false,
        },
    },
};

/// Parsed CLI result.  All string slices point into memory owned by the
/// allocator passed to `parse()`.
pub const Cli = struct {
    args: Args,
    /// Explicit file paths, or glob patterns when --glob is active.
    positional_args: []const [:0]const u8,
};

// ── Entry point ───────────────────────────────────────────────────────────────

pub fn parse(allocator: std.mem.Allocator, _: std.Io, proc_args: std.process.Args) !Cli {
    const argv = try proc_args.toSlice(allocator);
    const prog: []const u8 = if (argv.len > 0) argv[0] else "crlf";
    const rest: []const [:0]const u8 = if (argv.len > 1) argv[1..] else &.{};

    // Scan for top-level --help / --version before the subcommand token.
    var i: usize = 0;
    while (i < rest.len) {
        const arg = rest[i];
        if (eq(arg, "--help") or eq(arg, "-h")) {
            printTopHelp(prog);
            std.process.exit(0);
        }
        if (eq(arg, "--version")) {
            std.debug.print("{s}\n", .{config.version});
            std.process.exit(0);
        }
        if (!std.mem.startsWith(u8, arg, "-")) break; // first non-option = subcommand
        std.debug.print("Error: unknown option '{s}'.\nRun '{s} --help' for usage.\n", .{ arg, prog });
        std.process.exit(1);
    }

    if (i >= rest.len) {
        std.debug.print("Error: a subcommand is required (check | convert | version).\nRun '{s} --help' for usage.\n", .{prog});
        std.process.exit(1);
    }

    const sub = rest[i];
    i += 1;

    if (eq(sub, "version")) return .{ .args = .{ .__commands__ = .{ .version = .{} } }, .positional_args = &.{} };
    if (eq(sub, "check")) return parseSubCmd(allocator, prog, "check", rest[i..]);
    if (eq(sub, "convert")) return parseSubCmd(allocator, prog, "convert", rest[i..]);

    std.debug.print("Error: unknown subcommand '{s}'.\nRun '{s} --help' for usage.\n", .{ sub, prog });
    std.process.exit(1);
}

// ── Subcommand parser ─────────────────────────────────────────────────────────

fn parseSubCmd(
    allocator: std.mem.Allocator,
    prog: []const u8,
    comptime cmd: []const u8,
    rest: []const [:0]const u8,
) !Cli {
    var not_val: ?[]const u8 = null;
    var is_val: ?[]const u8 = null;
    var glob: bool = false;
    var variant_val: ?[]const u8 = null; // convert only
    var positionals = std.ArrayList([:0]const u8).empty;
    var end_opts: bool = false;

    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        const arg = rest[i];

        if (end_opts) {
            try positionals.append(allocator, arg);
            continue;
        }

        if (eq(arg, "--")) {
            end_opts = true;
            continue;
        }

        if (eq(arg, "--help") or eq(arg, "-h")) {
            printTopHelp(prog);
            std.process.exit(0);
        }

        if (eq(arg, "--glob") or eq(arg, "-g")) {
            glob = true;
            continue;
        }

        if (eq(arg, "--not") or eq(arg, "-n")) {
            i += 1;
            if (i >= rest.len) die("'--not' requires a value.\nRun '{s} --help' for usage.\n", .{prog});
            not_val = rest[i];
            continue;
        }

        if (eq(arg, "--is") or eq(arg, "-i")) {
            i += 1;
            if (i >= rest.len) die("'--is' requires a value.\nRun '{s} --help' for usage.\n", .{prog});
            is_val = rest[i];
            continue;
        }

        if (comptime eq(cmd, "convert")) {
            if (eq(arg, "--variant") or eq(arg, "-v")) {
                i += 1;
                if (i >= rest.len) die("'--variant' requires a value.\nRun '{s} --help' for usage.\n", .{prog});
                variant_val = rest[i];
                continue;
            }
        }

        if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: unknown option '{s}'.\nRun '{s} --help' for usage.\n", .{ arg, prog });
            std.process.exit(1);
        }

        try positionals.append(allocator, arg);
    }

    const paths = try positionals.toOwnedSlice(allocator);

    if (comptime eq(cmd, "check")) {
        return .{
            .args = .{ .__commands__ = .{ .check = .{ .not = not_val, .is = is_val, .glob = glob } } },
            .positional_args = paths,
        };
    } else {
        if (variant_val == null)
            die("'--variant' is required for 'convert'.\nRun '{s} --help' for usage.\n", .{prog});
        return .{
            .args = .{ .__commands__ = .{ .convert = .{ .variant = variant_val.?, .not = not_val, .is = is_val, .glob = glob } } },
            .positional_args = paths,
        };
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

inline fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn die(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("Error: " ++ fmt, args);
    std.process.exit(1);
}

// ── Help text ─────────────────────────────────────────────────────────────────

const VARIANTS =
    \\  lf   / unix   Unix / Linux / macOS
    \\  crlf / win    Windows
    \\  cr   / mac    Classic Mac OS
;

fn printTopHelp(prog: []const u8) void {
    std.debug.print(
        \\Usage:
        \\  {s} check   [-g] [--not VARIANT] [--is VARIANT] <path...>
        \\  {s} convert -v VARIANT [-g] [--not VARIANT] [--is VARIANT] <path...>
        \\
        \\Commands:
        \\  check    Analyze files and report their line ending variant
        \\  convert  Convert file line endings to a target variant
        \\  version  Print version
        \\
        \\Options:
        \\  -v, --variant VARIANT  Target variant for convert (required)
        \\  -g, --glob             Treat positional args as glob patterns
        \\                           *.zig          current directory only
        \\                           src/*.zig      direct children of src/
        \\                           src/**/*.zig   recursive under src/
        \\  -n, --not VARIANT      Exclude files that already have this line ending
        \\  -i, --is  VARIANT      Include only files with this line ending
        \\  -h, --help             Show this help
        \\      --version          Print version and exit
        \\
        \\Variants:
        \\
    ++ VARIANTS ++ "\n", .{ prog, prog });
}
