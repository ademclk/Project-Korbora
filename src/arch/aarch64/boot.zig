//! Entry point. 
//! - Parks secondary cores
//! - Sets up the stack
//! - Clears BSS
//! - Jumps to the kernel.

export fn _start() linksection(".text.boot") callconv(.naked) noreturn {
    asm volatile (
        // Identify current cpu core
        \\ mrs  x1, mpidr_el1
        \\ and  x1, x1, #0xff
        \\ cbnz x1, 2f
        
        // Enable FP / SIMD
        \\ mov  x0, #(3 << 20)
        \\ msr  cpacr_el1, x0
        \\ isb
        
        // Initialize the stack pointer
        \\ adrp x0, __stack_top
        \\ add  x0, x0, :lo12:__stack_top
        \\ mov  sp, x0
        
        // Find the BSS boundaries 
        \\ adrp x0, __bss_start
        \\ add  x0, x0, :lo12:__bss_start
        \\ adrp x1, __bss_end
        \\ add  x1, x1, :lo12:__bss_end
        
        // Clear BSS 8-byte 
        \\ 1:
        \\ cmp  x0, x1
        \\ b.hs 3f
        \\ str  xzr, [x0], #8
        \\ b    1b
        
        // Start the kernel main
        \\ 3:
        \\ bl   kmain
        
        // Wait for event
        \\ 2:
        \\ wfe
        \\ b    2b
    );
}
