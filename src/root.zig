const std = @import("std");
const mem = std.mem;

pub const LineEndingVariant = enum {
    lf,
    crlf,
    cr,
    mixed,
    none,

    pub fn toString(self: LineEndingVariant) []const u8 {
        return switch (self) {
            .lf => "lf",
            .crlf => "crlf",
            .cr => "cr",
            .mixed => "mixed",
            .none => "none",
        };
    }

    pub fn fromString(s: []const u8) ?LineEndingVariant {
        if (mem.eql(u8, s, "lf") or mem.eql(u8, s, "unix")) return .lf;
        if (mem.eql(u8, s, "crlf") or mem.eql(u8, s, "win")) return .crlf;
        if (mem.eql(u8, s, "cr") or mem.eql(u8, s, "mac")) return .cr;
        return null;
    }

    pub fn getSeparator(self: LineEndingVariant) []const u8 {
        return switch (self) {
            .lf => "\n",
            .crlf => "\r\n",
            .cr => "\r",
            .mixed, .none => "",
        };
    }
};

pub const LineEndingInfo = struct {
    variant: LineEndingVariant,
    lf_count: usize,
    crlf_count: usize,
    cr_count: usize,
};

pub fn detectLineEndings(content: []const u8) LineEndingInfo {
    var lf_count: usize = 0;
    var crlf_count: usize = 0;
    var cr_count: usize = 0;

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\r') {
            if (i + 1 < content.len and content[i + 1] == '\n') {
                crlf_count += 1;
                i += 2;
                continue;
            } else {
                cr_count += 1;
            }
        } else if (content[i] == '\n') {
            lf_count += 1;
        }
        i += 1;
    }

    var variant: LineEndingVariant = .none;
    const variants_found = (if (lf_count > 0) @as(u2, 1) else 0) +
        (if (crlf_count > 0) @as(u2, 1) else 0) +
        (if (cr_count > 0) @as(u2, 1) else 0);

    if (variants_found > 1) {
        variant = .mixed;
    } else if (lf_count > 0) {
        variant = .lf;
    } else if (crlf_count > 0) {
        variant = .crlf;
    } else if (cr_count > 0) {
        variant = .cr;
    }

    return .{
        .variant = variant,
        .lf_count = lf_count,
        .crlf_count = crlf_count,
        .cr_count = cr_count,
    };
}

pub fn convertLineEndings(allocator: mem.Allocator, content: []const u8, target: LineEndingVariant) ![]const u8 {
    const target_sep = target.getSeparator();
    if (target_sep.len == 0) return allocator.dupe(u8, content);

    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\r') {
            if (i + 1 < content.len and content[i + 1] == '\n') {
                try output.appendSlice(allocator, target_sep);
                i += 2;
            } else {
                try output.appendSlice(allocator, target_sep);
                i += 1;
            }
        } else if (content[i] == '\n') {
            try output.appendSlice(allocator, target_sep);
            i += 1;
        } else {
            try output.append(allocator, content[i]);
            i += 1;
        }
    }

    return output.toOwnedSlice(allocator);
}

pub fn matchesGlob(allocator: mem.Allocator, pattern: []const u8, text: []const u8) bool {
    if (pattern.len == 0) return text.len == 0;

    // Normalize separators for comparison
    const norm_pattern = allocator.dupe(u8, pattern) catch return false;
    defer allocator.free(norm_pattern);
    for (norm_pattern) |*c| if (c.* == '\\') {
        c.* = '/';
    };

    const norm_text = allocator.dupe(u8, text) catch return false;
    defer allocator.free(norm_text);
    for (norm_text) |*c| if (c.* == '\\') {
        c.* = '/';
    };

    return matchesGlobRecursive(norm_pattern, norm_text);
}

fn matchesGlobRecursive(pattern: []const u8, text: []const u8) bool {
    if (pattern.len == 0) return text.len == 0;

    if (std.mem.startsWith(u8, pattern, "**")) {
        const rest_pattern = pattern[2..];
        if (rest_pattern.len == 0) return true;

        if (std.mem.startsWith(u8, rest_pattern, "/")) {
            const sub_pattern = rest_pattern[1..];
            // Try matching rest of pattern against text (zero dirs matched)
            if (matchesGlobRecursive(sub_pattern, text)) return true;
            // Try matching rest of pattern against any suffix starting with /
            var i: usize = 0;
            while (i < text.len) : (i += 1) {
                if (text[i] == '/') {
                    if (matchesGlobRecursive(sub_pattern, text[i + 1 ..])) return true;
                }
            }
            return false;
        }

        // General ** (match any number of characters)
        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            if (matchesGlobRecursive(rest_pattern, text[i..])) return true;
        }
        return false;
    }

    if (pattern[0] == '*') {
        const rest_pattern = pattern[1..];
        // Standard * (matches anything except /)
        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            if (matchesGlobRecursive(rest_pattern, text[i..])) return true;
            if (i < text.len and text[i] == '/') break;
        }
        return false;
    }

    if (text.len == 0) return false;

    if (pattern[0] == text[0]) {
        return matchesGlobRecursive(pattern[1..], text[1..]);
    }

    return false;
}

test "line ending detection" {
    const lf_only = "line1\nline2\n";
    const info1 = detectLineEndings(lf_only);
    try std.testing.expectEqual(LineEndingVariant.lf, info1.variant);

    const crlf_only = "line1\r\nline2\r\n";
    const info2 = detectLineEndings(crlf_only);
    try std.testing.expectEqual(LineEndingVariant.crlf, info2.variant);

    const mixed = "line1\nline2\r\n";
    const info3 = detectLineEndings(mixed);
    try std.testing.expectEqual(LineEndingVariant.mixed, info3.variant);
}

test "line ending conversion" {
    const allocator = std.testing.allocator;
    const mixed = "line1\nline2\r\n";
    const info = detectLineEndings(mixed);
    try std.testing.expectEqual(LineEndingVariant.mixed, info.variant);

    const converted = try convertLineEndings(allocator, mixed, .lf);
    defer allocator.free(converted);
    const info_converted = detectLineEndings(converted);
    try std.testing.expectEqual(LineEndingVariant.lf, info_converted.variant);
}

test "glob matching" {
    const allocator = std.testing.allocator;
    try std.testing.expect(matchesGlob(allocator, "*.txt", "hello.txt"));
    try std.testing.expect(!matchesGlob(allocator, "*.txt", "hello.zig"));
    try std.testing.expect(matchesGlob(allocator, "file.*", "file.c"));
    try std.testing.expect(matchesGlob(allocator, "f*o", "foo"));
}

test "recursive glob matching" {
    const allocator = std.testing.allocator;
    try std.testing.expect(matchesGlob(allocator, "src/*.zig", "src/main.zig"));
    try std.testing.expect(matchesGlob(allocator, "src/*.zig", "src\\main.zig"));
    try std.testing.expect(matchesGlob(allocator, "src/**/*.zig", "src/main.zig"));
    try std.testing.expect(matchesGlob(allocator, "src/**/*.zig", "src/subdir/file.zig"));
    try std.testing.expect(matchesGlob(allocator, "**/*.zig", "src/main.zig"));
    try std.testing.expect(matchesGlob(allocator, "**/*.zig", "root.zig"));
    try std.testing.expect(matchesGlob(allocator, "src/**.zig", "src/main.zig"));
}
