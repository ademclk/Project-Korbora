const std = @import("std");

/// Default image: everything. Can override with specifying the modules like `-Dmodules=console,mem,...`.
const default_modules = "console,mem,measure,partition,detsim";

const QemuCase = struct {
    name: []const u8,
    modules: []const u8,
    transcript: []const u8,
};

/// Images booted by `zig build qemu-test`. Each transcript is compared against
/// the captured serial output of the corresponding module set.
const qemu_cases = [_]QemuCase{
    .{ .name = "console", .modules = "console", .transcript = "tests/qemu/console.txt" },
    .{ .name = "console-mem", .modules = "console,mem", .transcript = "tests/qemu/console-mem.txt" },
    .{ .name = "console-detsim", .modules = "console,detsim", .transcript = "tests/qemu/console-detsim.txt" },
    .{ .name = "default", .modules = default_modules, .transcript = "tests/qemu/default.txt" },
    .{ .name = "console-faultprobe", .modules = "console,faultprobe", .transcript = "tests/qemu/console-faultprobe.txt" },
};

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

    const kernel = addKernel(b, target, optimize, modules, "korbora.elf");
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
    const transcript_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/transcript.zig"),
            .target = b.graph.host,
        }),
    });
    const test_step = b.step("test", "Run host-side unit tests");
    test_step.dependOn(&b.addRunArtifact(host_tests).step);
    test_step.dependOn(&b.addRunArtifact(transcript_tests).step);

    // Automated boot test: build each image, boot it headlessly in QEMU, and
    // compare the serial log with the checked-in transcript.
    const checker = b.addExecutable(.{
        .name = "transcript-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/transcript_check.zig"),
            .target = b.graph.host,
        }),
    });

    const qemu_test = b.step("qemu-test", "Boot images headlessly in QEMU and compare their serial output");
    var previous: ?*std.Build.Step = null;

    for (qemu_cases) |case| {
        const image = addKernel(b, target, optimize, case.modules, b.fmt("korbora-{s}.elf", .{case.name}));

        const command = b.addSystemCommand(&.{"sh"});
        command.addFileArg(b.path("tools/qemu_boot_test.sh"));
        command.addArtifactArg(checker);
        command.addArg(case.name);
        command.addArg(case.modules);
        command.addFileArg(b.path(case.transcript));
        command.addArtifactArg(image);

        // Serialize the runs so their output is deterministic and easy to read.
        if (previous) |step| command.step.dependOn(step);
        previous = &command.step;

        qemu_test.dependOn(&command.step);
    }
}

fn addKernel(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    modules: []const u8,
    name: []const u8,
) *std.Build.Step.Compile {
    const options = b.addOptions();
    options.addOption([]const u8, "modules", modules);

    // The linker script places the kernel sections and defines memory symbols
    // used by startup code and the memory-related modules.
    const kernel = b.addExecutable(.{
        .name = name,
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

    return kernel;
}
