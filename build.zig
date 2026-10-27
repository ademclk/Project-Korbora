const std = @import("std");

/// Default image: everything. Can override with specifying the modules like `-Dmodules=console,mem,...`.
const default_modules = "console,mem,measure,partition,detsim";

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });
    const modules = b.option([]const u8, "modules", "Comma-separated modules to link into the image") orelse default_modules;

    // Build for a bare-metal AArch64 target.
    // Strict alignment and disabled FP/SIMD to keep kernel code within the
    // assumptions made by the early boot environment.
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_model = .baseline,
        .cpu_features_add = std.Target.aarch64.featureSet(&.{.strict_align}),
        .cpu_features_sub = std.Target.aarch64.featureSet(&.{ .neon, .fp_armv8 }),
    });

    const options = b.addOptions();
    options.addOption([]const u8, "modules", modules);

    // The linker script places the kernel sections and defines memory symbols
    // used by startup code and the memory-related modules.
    const kernel = b.addExecutable(.{
        .name = "korbora.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .code_model = .small,
            .red_zone = false,
            .strip = false,
        }),
    });
    kernel.root_module.addOptions("config", options);
    kernel.setLinkerScript(b.path("src/arch/aarch64/linker.ld"));
    b.installArtifact(kernel);

    // Boot the built ELF with QEMU's AArch64 virtual board.
    // `-nographic` routes the emulated serial console to the terminal.
    const qemu = b.addSystemCommand(&.{
        "qemu-system-aarch64", "-machine", "virt", "-cpu",    "cortex-a72",
        "-nographic",          "-m",       "128M", "-kernel",
    });
    qemu.addArtifactArg(kernel);
    const run = b.step("run", "Boot the image in QEMU (virt, aarch64)");
    run.dependOn(&qemu.step);

    // These tests run on the build host, not inside the kernel or QEMU.
    const host_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = b.graph.host,
        }),
    });
    const test_step = b.step("test", "Run host-side unit tests");
    test_step.dependOn(&b.addRunArtifact(host_tests).step);
}
