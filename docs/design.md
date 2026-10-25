# Project Korbora

---

## 1. Goals

Project Korbora is a systems project designed to demonstrate the full capabilities of Zig in high-integrity, embedded, and distributed systems environments.

- **Unified Typed Stack**
- **Deterministic Simulation**
- **Zero Hidden Costs**

---

## 3. The Three Principles From Zig

I got these principles from the Zig's website and adapted for this project.

### Principle 1: No Hidden Control Flow

- Errors are explicit values returned via error unions, no exceptions or unwinding.
- No callbacks that secretly schedule background tasks or hijack execution.
- Concurrency and execution boundaries are explicitly visible in source code.

### Principle 2: No Hidden Allocations

1. **Explicit Ownership & Supply**: Every module receives its memory from the caller at initialization.
2. **Compile-Time Budget Visibility**: Memory budgets are exposed in types at compile time and reported at startup. High-water marks are continuously monitored via `TrackingAllocator`.
3. **Zero Post-Init Allocations**: Dynamic memory allocation after startup is prohibited. In steady state, `lockAfterInit()` is engaged; any subsequent allocation attempt triggers a panic.

### Principle 3: Comptime

- Schemas, serialization codecs, RPC dispatch tables, memory budgets, and task schedules are generated and verified at compile time with zero runtime reflection or macros.
- Dynamism is achieved through build-time configuration and comptime-generic types.

---

## 4. Repository Layout

```text
Project Korbora/
├── core/       # Fixed-capacity containers, tracking allocator, ranged ints, comptime interfaces
├── docs/       # Architecture specifications, memory budgets, and design notes
├── examples/   # Demo projects
├── mcu/        # Freestanding Cortex-M runtime, linker scripts, drivers, minimal HAL
├── ota/        # Signed firmware updates, A/B slots, bootloader, rollback
├── rt/         # Comptime-configured RTOS
├── server/     # Static-memory server
├── sim/        # Deterministic simulator
├── src/        # Entry of the program, main 
└── wire/       # Comptime-typed RPC, framing, schema hashing, reliability layer
```

---
