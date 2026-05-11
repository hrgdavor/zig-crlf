# Using simargs/structargs in this project (Zig 0.16)

`simargs` in older zigcli versions has been renamed to `structargs` in modern zigcli.
For Zig 0.16, this project uses `zigcli.structargs` while keeping the same struct-driven
CLI design.

## 1. Dependency wiring

### `build.zig.zon`

The dependency key is `zigcli` and it points to a Zig 0.16-compatible commit:

```zig
.dependencies = .{
    .zigcli = .{
        .url = "git+https://github.com/jiacai2050/zigcli#35e013d209b18d0e9c1df85e7e2044e15bde22ad",
        .hash = "zigcli-0.6.2-ORC7jMFFBgDegrwcsueXsOekZh-HHlKHLJQuostneMpS",
    },
},
```

`minimum_zig_version` is `0.16.0`.

### `build.zig`

Resolve `zigcli`, then import its `zigcli` module into the executable root module:

```zig
const zigcli_dep = b.dependency("zigcli", .{
    .target = target,
    .optimize = optimize,
});
const zigcli_mod = zigcli_dep.module("zigcli");

.imports = &.{
    .{ .name = "zig_crlf", .module = mod },
    .{ .name = "zigcli", .module = zigcli_mod },
},
```

## 2. Parser module (`src/args.zig`)

```zig
const zigcli = @import("zigcli");
const structargs = zigcli.structargs;
```

`Args` remains the single struct that defines top-level options and subcommands,
including:

- `__commands__` tagged union for `check` and `convert`
- `not` as an optional filter field on `check` and `convert`
- `__shorts__` for short flags
- `__messages__` for help text

## 3. Calling parse on Zig 0.16

`structargs.parse` in zigcli 0.6.x takes `io` and process args explicitly:

```zig
const opt = try structargs.parse(arena_allocator, io, proc_args, Args, .{
    .argument_prompt = "<glob_pattern> ...",
    .version_string = version,
});
```

In `src/main.zig`, use the Zig 0.16 `main` signature so `io` and args are available:

```zig
pub fn main(init: std.process.Init) !void {
    const cli = try args_mod.parse(parse_arena.allocator(), init.io, init.minimal.args);
    // ...
}
```

`Cli.positional_args` type is:

```zig
[]const [:0]const u8
```

## 4. Behavior notes

- `-h/--help` and `--version` are handled by structargs.
- Missing subcommand and missing required option are handled with user-friendly messages.
- Positional arguments after the subcommand are the glob patterns.

## 5. Maintenance checklist

1. Add or change CLI fields in `Args`.
2. Keep `__shorts__` and `__messages__` in sync.
3. Read parsed values from `opt.options` and `opt.positional_arguments`.
4. Verify on Zig 0.16:
   - `D:\wrk\zig\16\zig.exe build`
   - `D:\wrk\zig\16\zig.exe build test`