//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const mem = std.mem;
const fs = std.fs;

pub const LineEndingVariant = enum {
    lf,
    crlf,
    cr,
    mixed,
    none,

    pub fn toString(self: LineEndingVariant) []const u8 {
        return @tagName(self);
    }

    pub fn fromString(s: []const u8) ?LineEndingVariant {
        if (mem.eql(u8, s, "lf") or mem.eql(u8, s, "unix")) return .lf;
        if (mem.eql(u8, s, "crlf") or mem.eql(u8, s, "win")) return .crlf;
        if (mem.eql(u8, s, "cr") or mem.eql(u8, s, "mac")) return .cr;
        return null;
    }

    pub fn toBytes(self: LineEndingVariant) []const u8 {
        return switch (self) {
            .lf => "\n",
            .crlf => "\r\n",
            .cr => "\r",
            else => "",
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
            } else {
                cr_count += 1;
                i += 1;
            }
        } else if (content[i] == '\n') {
            lf_count += 1;
            i += 1;
        } else {
            i += 1;
        }
    }

    var variant: LineEndingVariant = .none;
    const types_present = (@as(u8, if (lf_count > 0) 1 else 0) +
        @as(u8, if (crlf_count > 0) 1 else 0) +
        @as(u8, if (cr_count > 0) 1 else 0));

    if (types_present > 1) {
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

pub fn convertLineEndings(allocator: mem.Allocator, content: []const u8, target: LineEndingVariant) ![]u8 {
    var output = std.ArrayList(u8).empty;
    errdefer output.deinit(allocator);

    const target_bytes = target.toBytes();

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\r') {
            if (i + 1 < content.len and content[i + 1] == '\n') {
                try output.appendSlice(allocator, target_bytes);
                i += 2;
            } else {
                try output.appendSlice(allocator, target_bytes);
                i += 1;
            }
        } else if (content[i] == '\n') {
            try output.appendSlice(allocator, target_bytes);
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

    if (mem.eql(u8, norm_pattern, "*") or mem.eql(u8, norm_pattern, "**")) return true;

    var it = mem.splitScalar(u8, norm_pattern, '*');
    const first = it.next().?; // Always at least one part (even if empty)

    if (!mem.startsWith(u8, norm_text, first)) return false;

    var current_text = norm_text[first.len..];
    var last_part: ?[]const u8 = null;

    while (it.next()) |part| {
        if (part.len == 0) continue; // handle ** or multiple *
        if (mem.indexOf(u8, current_text, part)) |idx| {
            current_text = current_text[idx + part.len ..];
            last_part = part;
        } else {
            return false;
        }
    }

    // If pattern didn't end with *, the text must end with the last part
    if (!mem.endsWith(u8, norm_pattern, "*")) {
        if (last_part) |lp| {
            return mem.endsWith(u8, norm_text, lp);
        } else {
            // No stars in pattern, must be EXACT match (after normalization)
            return mem.eql(u8, norm_text, first);
        }
    }

    return true;
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
    const converted = try convertLineEndings(allocator, mixed, .lf);
    defer allocator.free(converted);
    try std.testing.expectEqualStrings("line1\nline2\n", converted);
}

test "glob matching" {
    const allocator = std.testing.allocator;
    try std.testing.expect(matchesGlob(allocator, "*.txt", "hello.txt"));
    try std.testing.expect(!matchesGlob(allocator, "*.txt", "hello.zig"));
    try std.testing.expect(matchesGlob(allocator, "file.*", "file.c"));
    try std.testing.expect(matchesGlob(allocator, "f*o", "foo"));
    try std.testing.expect(matchesGlob(allocator, "src/*.zig", "src/main.zig"));
    try std.testing.expect(matchesGlob(allocator, "src/*.zig", "src\\main.zig"));
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
