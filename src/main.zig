const std = @import("std");
const builtin = @import("builtin");
const zig_crlf = @import("zig_crlf");
const args_mod = @import("args.zig");
const app_version = @import("app_version.zig");
const mem = std.mem;

pub fn main(init: std.process.Init) !void {
    // Zig 0.16 exposes process args and filesystem I/O through `init`.
    const allocator = std.heap.smp_allocator;

    // Keep parse-time allocations short-lived and release them in one shot.
    var parse_arena = std.heap.ArenaAllocator.init(allocator);
    defer parse_arena.deinit();

    const cli = try args_mod.parse(parse_arena.allocator(), init.io, init.minimal.args);

    // Positional args are interpreted as explicit file paths by default.
    // With `--glob`, they are treated as recursive glob patterns.
    const inputs = cli.positional_args;

    switch (cli.args.__commands__) {
        .version => {
            app_version.printHeader("zig-crlf");
        },
        .check => |sub| {
            const include_variant = try parseFilterVariant("is", sub.is);
            const exclude_variant = try parseFilterVariant("not", sub.not);
            validateFilters(include_variant, exclude_variant);
            const mode: SearchMode = if (sub.glob) .glob else .paths;
            if (inputs.len == 0) {
                std.debug.print("Usage: crlf check [--is <variant>] [--not <variant>] [--glob] <path_or_pattern> ...\n", .{});
                std.process.exit(1);
            }
            try processFiles(allocator, init.io, mode, .check, include_variant, exclude_variant, inputs);
        },
        .convert => |sub| {
            const target_variant = zig_crlf.LineEndingVariant.fromString(sub.variant) orelse {
                std.debug.print(
                    "Error: invalid variant '{s}'. Use win, unix, mac, crlf, lf, or cr.\n",
                    .{sub.variant},
                );
                std.process.exit(1);
            };
            const include_variant = try parseFilterVariant("is", sub.is);
            const exclude_variant = try parseFilterVariant("not", sub.not);
            validateFilters(include_variant, exclude_variant);
            const mode: SearchMode = if (sub.glob) .glob else .paths;
            if (inputs.len == 0) {
                std.debug.print("Usage: crlf convert --variant <variant> [--is <variant>] [--not <variant>] [--glob] <path_or_pattern> ...\n", .{});
                std.process.exit(1);
            }
            try processFiles(allocator, init.io, mode, .{ .convert = target_variant }, include_variant, exclude_variant, inputs);
        },
    }
}

const SearchMode = enum {
    // Treat each positional argument as an explicit file path.
    paths,
    // Legacy behavior: walk cwd recursively and match each positional as glob.
    glob,
};

const Operation = union(enum) {
    check,
    convert: zig_crlf.LineEndingVariant,
};

fn parseFilterVariant(filter_name: []const u8, raw: ?[]const u8) !?zig_crlf.LineEndingVariant {
    if (raw) |v| {
        return zig_crlf.LineEndingVariant.fromString(v) orelse {
            std.debug.print(
                "Error: invalid variant '{s}' for --{s}. Use win, unix, mac, crlf, lf, or cr.\n",
                .{ v, filter_name },
            );
            std.process.exit(1);
        };
    }
    return null;
}

fn validateFilters(include_variant: ?zig_crlf.LineEndingVariant, exclude_variant: ?zig_crlf.LineEndingVariant) void {
    if (include_variant != null and exclude_variant != null) {
        std.debug.print("Error: --is and --not are mutually exclusive. Use only one filter.\n", .{});
        std.process.exit(1);
    }
}

fn processFiles(
    allocator: mem.Allocator,
    io: std.Io,
    search_mode: SearchMode,
    operation: Operation,
    include_variant: ?zig_crlf.LineEndingVariant,
    exclude_variant: ?zig_crlf.LineEndingVariant,
    inputs: []const [:0]const u8,
) !void {
    if (search_mode == .paths and builtin.os.tag == .windows) {
        maybePrintWindowsGlobHint(inputs);
    }

    return switch (search_mode) {
        .paths => processExplicitFiles(allocator, io, operation, include_variant, exclude_variant, inputs),
        .glob => processGlobWalk(allocator, io, operation, include_variant, exclude_variant, inputs),
    };
}

fn maybePrintWindowsGlobHint(inputs: []const [:0]const u8) void {
    for (inputs) |item| {
        if (containsWildcard(item)) {
            std.debug.print(
                "Hint: detected wildcard-like input '{s}' in explicit-path mode on Windows.\n" ++
                    "Use --glob (or -g) to enable recursive glob matching for positional patterns.\n",
                .{item},
            );
            return;
        }
    }
}

fn containsWildcard(path: []const u8) bool {
    return std.mem.indexOfAny(u8, path, "*?[]") != null;
}

fn processExplicitFiles(
    allocator: mem.Allocator,
    io: std.Io,
    operation: Operation,
    include_variant: ?zig_crlf.LineEndingVariant,
    exclude_variant: ?zig_crlf.LineEndingVariant,
    file_paths: []const [:0]const u8,
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer dir.close(io);

    // `Dir.readFile` reads into a caller buffer in Zig 0.16; cap at 10 MiB.
    const max_file_size = 10 * 1024 * 1024;
    const file_buffer = try allocator.alloc(u8, max_file_size);
    defer allocator.free(file_buffer);

    for (file_paths) |file_path| {
        processOneFile(
            allocator,
            io,
            dir,
            operation,
            include_variant,
            exclude_variant,
            file_buffer,
            file_path,
        ) catch |err| switch (err) {
            error.FileNotFound, error.NotDir, error.IsDir, error.BadPathName => {
                std.debug.print("Skipped {s} ({s})\n", .{ file_path, @errorName(err) });
            },
            else => return err,
        };
    }
}

fn processGlobWalk(
    allocator: mem.Allocator,
    io: std.Io,
    operation: Operation,
    include_variant: ?zig_crlf.LineEndingVariant,
    exclude_variant: ?zig_crlf.LineEndingVariant,
    patterns: []const [:0]const u8,
) !void {
    // Fast path: patterns like `*.md` only need current-directory files.
    if (canUseCurrentDirOnlyGlobScan(patterns)) {
        return processGlobCurrentDirOnly(allocator, io, operation, include_variant, exclude_variant, patterns);
    }

    var dir = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    const max_file_size = 10 * 1024 * 1024;
    const file_buffer = try allocator.alloc(u8, max_file_size);
    defer allocator.free(file_buffer);

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;

        for (patterns) |pattern| {
            if (zig_crlf.matchesGlob(allocator, pattern, entry.path)) {
                try processOneFile(
                    allocator,
                    io,
                    dir,
                    operation,
                    include_variant,
                    exclude_variant,
                    file_buffer,
                    entry.path,
                );

                break;
            }
        }
    }
}

fn canUseCurrentDirOnlyGlobScan(patterns: []const [:0]const u8) bool {
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, pattern, "**") != null) return false;
        if (std.mem.indexOfAny(u8, pattern, "/\\") != null) return false;
    }
    return true;
}

fn processGlobCurrentDirOnly(
    allocator: mem.Allocator,
    io: std.Io,
    operation: Operation,
    include_variant: ?zig_crlf.LineEndingVariant,
    exclude_variant: ?zig_crlf.LineEndingVariant,
    patterns: []const [:0]const u8,
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();

    const max_file_size = 10 * 1024 * 1024;
    const file_buffer = try allocator.alloc(u8, max_file_size);
    defer allocator.free(file_buffer);

    while (try iter.next(io)) |entry| {
        if (entry.kind != .file) continue;

        for (patterns) |pattern| {
            if (zig_crlf.matchesGlob(allocator, pattern, entry.name)) {
                try processOneFile(
                    allocator,
                    io,
                    dir,
                    operation,
                    include_variant,
                    exclude_variant,
                    file_buffer,
                    entry.name,
                );
                break;
            }
        }
    }
}

fn processOneFile(
    allocator: mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    operation: Operation,
    include_variant: ?zig_crlf.LineEndingVariant,
    exclude_variant: ?zig_crlf.LineEndingVariant,
    file_buffer: []u8,
    file_path: []const u8,
) !void {
    const content = try dir.readFile(io, file_path, file_buffer);
    const info = zig_crlf.detectLineEndings(content);

    if (include_variant) |iv| {
        if (info.variant != iv) return;
    }

    if (exclude_variant) |fv| {
        if (info.variant == fv) return;
    }

    switch (operation) {
        .check => {
            std.debug.print("lf: {d: <4} | crlf: {d: <4} | cr: {d: <4} | {s: <6} | {s}\n", .{
                info.lf_count,
                info.crlf_count,
                info.cr_count,
                info.variant.toString(),
                file_path,
            });
        },
        .convert => |target| {
            const converted = try zig_crlf.convertLineEndings(allocator, content, target);
            defer allocator.free(converted);

            if (!mem.eql(u8, content, converted)) {
                // `writeFile` handles open/create/write/close for the path.
                try dir.writeFile(io, .{
                    .sub_path = file_path,
                    .data = converted,
                });

                std.debug.print("Converted {s} to {s}\n", .{ file_path, target.toString() });
            }
        },
    }
}
