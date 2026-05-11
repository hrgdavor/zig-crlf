const std = @import("std");
const zigcli = @import("zigcli");
const config = @import("config");
const structargs = zigcli.structargs;
const VARIANTS = "(win|crlf|unix|lf|mac|cr)";

/// The comptime configuration struct that drives structargs.
pub const Args = struct {
    help: bool = false,

    __commands__: union(enum) {
        version: struct {},
        check: struct {
            not: ?[]const u8 = null,
            is: ?[]const u8 = null,
            glob: bool = false,
            help: bool = false,

            pub const __shorts__ = .{ .not = .n, .is = .i, .glob = .g, .help = .h };
            pub const __messages__ = .{
                .not = "Exclude files with this line ending variant " ++ VARIANTS,
                .is = "Include only files with this line ending variant " ++ VARIANTS,
                .glob = "Interpret positional inputs as glob patterns; use *.zig or src/*.zig for one folder, src/**/*.zig for recursive",
                .help = "Show this help message",
            };
        },
        convert: struct {
            variant: []const u8,
            not: ?[]const u8 = null,
            is: ?[]const u8 = null,
            glob: bool = false,
            help: bool = false,

            pub const __shorts__ = .{ .not = .n, .is = .i, .glob = .g, .help = .h };
            pub const __messages__ = .{
                .variant = "Target line ending variant " ++ VARIANTS,
                .not = "Exclude files with this line ending variant " ++ VARIANTS,
                .is = "Include only files with this line ending variant " ++ VARIANTS,
                .glob = "Interpret positional inputs as glob patterns; use *.zig or src/*.zig for one folder, src/**/*.zig for recursive",
                .help = "Show this help message",
            };
        },

        pub const __messages__ = .{
            .version = "Print tool version",
            .check = "Analyze files and print their line ending variant (default: explicit files, optional --glob)",
            .convert = "Convert line endings in matched files (default: explicit files, optional --glob)",
        };
    },

    pub const __shorts__ = .{ .help = .h };
    pub const __messages__ = .{ .help = "Show this help message" };
};

/// The parsed result returned from `parse()`.
///
/// A plain data struct — all memory it references (args, positional_args)
/// is owned by the `ArenaAllocator` the caller passes to `parse()`. Free that
/// arena to release all parsing allocations.
pub const Cli = struct {
    /// Parsed flags/options/subcommand.
    args: Args,
    /// File paths (default) or glob patterns when --glob is enabled.
    positional_args: []const [:0]const u8,
};

/// Parse command-line arguments and return a `Cli`.
///
/// - `--help` / `-h` and `--version`: handled internally by structargs; the
///   process may exit before this function returns.
/// - User errors (missing subcommand, missing required option): a human-
///   readable message is printed and the process exits with code 1.
/// - All other errors are returned to the caller.
pub fn parse(arena_allocator: std.mem.Allocator, io: std.Io, proc_args: std.process.Args) !Cli {
    // `opt.options` is the typed Args struct; `opt.positional_arguments` are
    // the remaining arguments after option/subcommand parsing.
    const opt = structargs.parse(arena_allocator, io, proc_args, Args, .{
        .argument_prompt = "<path_or_pattern> ...",
        .version_string = config.version,
    }) catch |err| {
        switch (err) {
            error.MissingSubCommand => {
                std.debug.print(
                    "Error: a subcommand is required (check | convert).\n" ++
                        "Run with -h/--help for usage.\n",
                    .{},
                );
                std.process.exit(1);
            },
            error.MissingRequiredOption => {
                std.debug.print(
                    "Error: a required option is missing.\n" ++
                        "Run `crlf <command> --help` for usage.\n",
                    .{},
                );
                std.process.exit(1);
            },
            else => return err,
        }
    };

    return Cli{
        .args = opt.options,
        .positional_args = opt.positional_arguments,
    };
}
