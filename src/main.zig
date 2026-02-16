const std = @import("std");
const zig_crlf = @import("zig_crlf");
const fs = std.fs;
const mem = std.mem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2 or mem.eql(u8, args[1], "--help") or mem.eql(u8, args[1], "-h")) {
        printHelp();
        return;
    }

    const command = args[1];

    if (mem.eql(u8, command, "check")) {
        if (args.len < 3) {
            std.debug.print("Usage: crlf check <glob_pattern> ...\n", .{});
            return;
        }
        try handleCheck(allocator, null, args[2..]);
    } else if (mem.eql(u8, command, "not")) {
        if (args.len < 4) {
            std.debug.print("Usage: crlf not <variant> <glob_pattern> ...\n", .{});
            return;
        }
        const filter_variant = zig_crlf.LineEndingVariant.fromString(args[2]) orelse {
            std.debug.print("Invalid variant: {s}. Use win, unix, mac, crlf, lf, or cr.\n", .{args[2]});
            return;
        };
        try handleCheck(allocator, filter_variant, args[3..]);
    } else if (mem.eql(u8, command, "convert")) {
        if (args.len < 4) {
            std.debug.print("Usage: crlf convert <target_variant> <glob_pattern> ...\n", .{});
            return;
        }
        const target_variant = zig_crlf.LineEndingVariant.fromString(args[2]) orelse {
            std.debug.print("Invalid variant: {s}. Use win, unix, mac, crlf, lf, or cr.\n", .{args[2]});
            return;
        };
        try handleConvert(allocator, target_variant, args[3..]);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        printHelp();
    }
}

fn handleCheck(allocator: mem.Allocator, filter_variant: ?zig_crlf.LineEndingVariant, patterns: []const [:0]u8) !void {
    var dir = try fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        for (patterns) |pattern| {
            if (zig_crlf.matchesGlob(allocator, pattern, entry.path)) {
                const file = try entry.dir.openFile(entry.basename, .{});
                defer file.close();

                const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
                defer allocator.free(content);

                const info = zig_crlf.detectLineEndings(content);

                // If filter_variant is provided, only print if it DOES NOT match
                if (filter_variant) |fv| {
                    if (info.variant == fv) break;
                }

                std.debug.print("LF: {d: <3} | CRLF: {d: <3} | CR: {d: <3} | {s: <6} | {s}\n", .{
                    info.lf_count,
                    info.crlf_count,
                    info.cr_count,
                    info.variant.toString(),
                    entry.path,
                });
                break;
            }
        }
    }
}

fn handleConvert(allocator: mem.Allocator, target: zig_crlf.LineEndingVariant, patterns: []const [:0]u8) !void {
    var dir = try fs.cwd().openDir(".", .{ .iterate = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;

        for (patterns) |pattern| {
            if (zig_crlf.matchesGlob(allocator, pattern, entry.path)) {
                const file = try entry.dir.openFile(entry.basename, .{});
                const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
                file.close();
                defer allocator.free(content);

                const converted = try zig_crlf.convertLineEndings(allocator, content, target);
                defer allocator.free(converted);

                if (mem.eql(u8, content, converted)) {
                    // std.debug.print("Skipping {s} (already correct)\n", .{entry.path});
                    break;
                }

                const out_file = try entry.dir.createFile(entry.basename, .{});
                defer out_file.close();
                try out_file.writeAll(converted);

                std.debug.print("Converted {s} to {s}\n", .{ entry.path, target.toString() });
                break;
            }
        }
    }
}

fn printHelp() void {
    const help_text =
        \\Line Ending Utility (crlf)
        \\
        \\Usage:
        \\  crlf check <glob_pattern> ...
        \\  crlf not <variant> <glob_pattern> ...
        \\  crlf convert <variant> <glob_pattern> ...
        \\
        \\Commands:
        \\  check    Analyze files and show their line ending variants.
        \\  not      Analyze files and show those that DO NOT match the specified variant.
        \\  convert  Convert line endings in files to a specific variant.
        \\
        \\Variants:
        \\  win, crlf    Windows style (record separator: \r\n)
        \\  unix, lf     Unix/Linux/macOS style (record separator: \n)
        \\  mac, cr      Classic Mac style (record separator: \r)
        \\
        \\Line Ending Explanations:
        \\  - LF (Line Feed, \n, 0x0A): Used by Unix, Linux, and modern macOS.
        \\  - CRLF (Carriage Return + Line Feed, \r\n, 0x0D 0x0A): Used by Windows.
        \\  - CR (Carriage Return, \r, 0x0D): Used by classic Mac OS (pre-OSX).
        \\
        \\Mixed line endings occur when a file contains more than one type of 
        \\record separator, which can cause issues with some compilers and editors.
        \\
        \\Glob Patterns:
        \\  * matches any number of characters within a directory.
        \\  ** matches any number of characters across directories.
        \\  Example: "*.zig", "src/**/*.zig", "test_*.txt"
    ;
    std.debug.print("{s}\n", .{help_text});
}
