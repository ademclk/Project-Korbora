//! AArch64 exception vector table and fault reporting.
//!
//! 16 entries of 0x80 bytes, grouped by the exception source 
//! (current EL with SP0, current EL with SPx, lower EL AArch64, lower EL AArch32) 
//! and by type (synchronous, IRQ, FIQ, SError).
//!
//! Every entry reports the vector, then the handler prints ESR_EL1, ELR_EL1
//! and FAR_EL1 before halting the core. The report goes straight to the UART
//! because the optional console module may not be linked into the image.

const uart = @import("uart.zig");

/// Install the vector table in VBAR_EL1. Called from the boot code before
/// kmain, so faults during module initialization are already visible.
export fn exceptionsInit() void {
    const table = @intFromPtr(&korbora_vectors);
    asm volatile ("msr vbar_el1, %[table]"
        :
        : [table] "r" (table),
        : .{ .memory = true });
    asm volatile ("isb");
}

/// Halt this core forever with interrupts masked.
pub fn halt() noreturn {
    asm volatile ("msr daifset, #0xf");
    while (true) asm volatile ("wfe");
}

/// Exception handler shared by every vector entry.
/// vector is the vector number (0..15) placed in x0 by the entry stub.
export fn korbora_fault_handler(vector: u64) callconv(.c) noreturn {
    var esr: u64 = undefined;
    var elr: u64 = undefined;
    var far: u64 = undefined;

    asm volatile (
        \\ mrs %[esr], esr_el1
        \\ mrs %[elr], elr_el1
        \\ mrs %[far], far_el1
        : [esr] "=r" (esr),
          [elr] "=r" (elr),
          [far] "=r" (far),
    );

    uart.write("\nFAULT: ");
    uart.write(kindName(vector % 4));
    uart.write(" (");
    uart.write(sourceName(vector / 4));
    uart.write(") vector=");
    writeDec(vector);
    uart.write("\n  ESR=");
    writeHex(esr);
    uart.write("\n  ELR=");
    writeHex(elr);
    uart.write("\n  FAR=");
    writeHex(far);
    uart.write("\nHALTED\n");

    halt();
}

/// The vector table. The linker script aligns this section to 2 KiB, the
/// VBAR_EL1 alignment requirement. Each stub is padded to the architectural
/// 0x80-byte entry size.
export fn korbora_vectors() linksection(".text.vectors") callconv(.naked) void {
    asm volatile (
    // Current EL with SP0
        \\.balign 128
        \\ mov x9, #0
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #1
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #2
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #3
        \\ b korbora_fault_entry

        // Current EL with SPx
        \\.balign 128
        \\ mov x9, #4
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #5
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #6
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #7
        \\ b korbora_fault_entry

        // Lower EL using AArch64
        \\.balign 128
        \\ mov x9, #8
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #9
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #10
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #11
        \\ b korbora_fault_entry

        // Lower EL using AArch32
        \\.balign 128
        \\ mov x9, #12
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #13
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #14
        \\ b korbora_fault_entry
        \\.balign 128
        \\ mov x9, #15
        \\ b korbora_fault_entry

        // Common entry: mask interrupts, pass the vector number, report.
        \\korbora_fault_entry:
        \\ msr daifset, #0xf
        \\ mov x0, x9
        \\ bl korbora_fault_handler
        \\1:
        \\ wfe
        \\ b 1b
    );
}

fn kindName(kind: u64) []const u8 {
    return switch (kind) {
        0 => "synchronous",
        1 => "IRQ",
        2 => "FIQ",
        3 => "SError",
        else => "unknown",
    };
}

fn sourceName(group: u64) []const u8 {
    return switch (group) {
        0 => "current EL, SP0",
        1 => "current EL, SPx",
        2 => "lower EL, AArch64",
        3 => "lower EL, AArch32",
        else => "unknown",
    };
}

fn writeDec(value: u64) void {
    var buf: [20]u8 = undefined;
    var i: usize = buf.len;
    var v = value;

    if (v == 0) {
        uart.putc('0');
        return;
    }

    while (v != 0) {
        i -= 1;
        buf[i] = @intCast('0' + (v % 10));
        v /= 10;
    }

    uart.write(buf[i..]);
}

fn writeHex(value: u64) void {
    const digits = "0123456789abcdef";
    var buf: [18]u8 = undefined;
    var i: usize = 0;

    buf[i] = '0';
    i += 1;
    buf[i] = 'x';
    i += 1;

    var shift: u6 = 60;
    while (true) {
        const nibble: u8 = @intCast((value >> shift) & 0xf);
        buf[i] = digits[nibble];
        i += 1;

        if (shift == 0) break;
        shift -= 4;
    }

    uart.write(buf[0..i]);
}
