//! UART driver
//! Lets the kernel to send text to the terminal.
//! 
//! HARDWARE NOTE
//!
//! Current target:
//!     QEMU virt / ARM64 / PL011
//!
//! If porting to another ARM board:
//!     - The uart.write() API can remain.
//!     - The register addresses and bits will probably change.
//!     - Check the board/SoC reference manual before using it.
//!
//! For example:
//!     I'll be implementing STM32, and use its USART peripheral instead of PL011.
const base: usize = 0x0900_0000;

// Data Register (DR)
// Writing a character here tells the UART to transmit it.
// base + 0x00 meants the register is at its base address.
// 
// Volatile is used because normally loads and stores are assumed to not have side effects
// if a given load or store should have side effects, volatile is used.
const dr: *volatile u32 = @ptrFromInt(base + 0x00);

// Flag Register (FR)
// Read this register to check UART's current status.
const fr: *volatile u32 = @ptrFromInt(base + 0x18);

// Bit 5 of the Flag Register
// Transmit FIFO Full.
//
// FIFO is a small queue that holds characters waiting to be sent.
// 1 << 5 sets only bit 5, producing binary 0010_0000 (32).
// If this bit is 1, the queue is full.
// If this bit is 0, there is room for another character.
const txff: u32 = 1 << 5;

/// Send one character through the UART.
pub fn putc(c: u8) void {
    // Busy-waiting
    // Checking the Flag Register while the transmit queue is full
    // fr.* and dr.* used to read the value stored in the hardware register.
    while (fr.* & txff != 0) {}
    dr.* = c;
}

/// Send whole string through the UART.
pub fn write(s: []const u8) void {
    for (s) |c| {
        putc(c);
    }
}
