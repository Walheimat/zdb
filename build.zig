const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Zig module for core logic
    const zdb_mod = b.createModule(.{
        .root_source_file = b.path("src/zdb.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    // Shared library
    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "zdb",
        .root_module = zdb_mod,
    });

    // Add C++ shim with native callbacks (uses SBTypeSummary::CreateWithCallback)
    lib.root_module.addCSourceFile(.{
        .file = b.path("shim/shim_callback.cpp"),
        .flags = &.{"-std=c++17"},
    });
    lib.root_module.addIncludePath(b.path("shim"));

    // LLDB headers and library - check LLVM_PATH env var, with platform fallbacks
    const llvm_path = b.graph.environ_map.get("LLVM_PATH") orelse blk: {
        const fallbacks = switch (@import("builtin").os.tag) {
            .macos => &[_][]const u8{
                "/opt/homebrew/opt/llvm", // Homebrew ARM64
                "/usr/local/opt/llvm", // Homebrew x86_64
            },
            .linux => &[_][]const u8{
                "/usr/lib/llvm-22",
                "/usr/lib/llvm-21",
                "/usr/lib/llvm-20",
                "/usr/lib/llvm-19",
                "/usr/lib/llvm-18",
                "/usr/lib/llvm-17",
                "/usr",
            },
            else => &[_][]const u8{"/usr"},
        };
        for (fallbacks) |path| {
            std.Io.Dir.accessAbsolute(b.graph.io, b.fmt("{s}/include/lldb/API/LLDB.h", .{path}), .{}) catch continue;
            break :blk b.allocator.dupe(u8, path) catch @panic("OOM");
        }
        @panic("LLVM not found. Set LLVM_PATH environment variable.");
    };

    lib.root_module.addSystemIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{llvm_path}) });
    lib.root_module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{llvm_path}) });
    lib.root_module.linkSystemLibrary("lldb", .{});

    b.installArtifact(lib);

    // Tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/zdb.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
