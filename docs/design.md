# Project Korbora

Korbora is a small, modular unikernel written in Zig, targeting Arm SoCs. One image contains the kernel and only the modules a product needs, selected at build time. The codebase is kept small enough to manage.

## 1. Product directions

The same kernel core is configured into different products by choosing modules.

| Direction | How we achieve it | Key modules |
| --- | --- | --- |
| **Separation kernel** | Mixed partitioning to achieve provable isolation | `partition`, `sched`, `ipc` |
| **Secure edge compute** | Small signed images, measured boot, fast boot, OTA updates, minimal attack surface. (To be used with drones, vehicles, and sensors.) | `measure`, `ota`, `verify` |
| **Cross-domain / data-diode gateway** | Single purpose appliance | `guard`, `net`, `ipc` |
| **Hardened network and crypto appliance** | Encrypted link gateways, secure telemetry relays, key-handling modules. | `net`, `crypto`, `keystore` |
| **Deterministic test/simulation platform** | Reproducible execution. Seeded randomness, virtual time, replayable runs. | `detsim` |

## 2. Principles

1. **No hidden control flow.** Errors are values. No exceptions, no implicit background tasks. Concurrency and execution boundaries are visible in source.
2. **No hidden allocations.** Memory is static or handed out during init. `mem.lock()` is called after init, any later allocation panics.
3. **Comptime over runtime.** Image composition, partition tables, schedules and budgets are checked at compile time. "Dynamic" means the image is composed per product at build time, not loaded code at run time.
4. **Small trusted base.** Every module is optional, and unused modules are not analyzed or linked.
5. **Verifiable images.** An image is measured (SHA-256) at boot so it can be compared against a signed manifest.

## 3. Modularity

A module is a Zig file under `src/modules/` that declares:

```zig
pub const name = "example";
pub const requires = [_][]const u8{"console"}; // optional
pub fn init() !void { ... }
```

- All modules are listed in [`src/modules/all.zig`](../src/modules/all.zig).
- Modules folder with be grouped later to prevent confusion.
- The image selects modules with `-Dmodules=a,b,c` defaulted tp `console,mem,measure,partition,detsim`.
- [`src/kernel/registry.zig`](../src/kernel/registry.zig) resolves the set at compile time into dependency order. An unknown module, duplicate, missing dependency or cycle is a compile error.
- `kmain` runs each module's `init` in that order, then locks memory.

Example `zig build -Dmodules=measure` fails with `module 'measure' requires 'console' which is not enabled`. This could be improved by grouping.

## 4. Repository layout

```text
build.zig / build.zig.zon   Build graph, module selection, QEMU run step
docs/design.md              This document
src/main.zig                Kernel entry (kmain), panic handler, image composition
src/kernel/registry.zig     Comptime module resolver (host-testable)
src/arch/aarch64/           Boot code, exception vectors, linker script, PL011 UART
src/modules/                Optional modules
src/root.zig                Root for host-side unit tests
```

## 5. Current modules

| Module | Status | Purpose |
| --- | --- | --- |
| `console` | working | PL011 output, allocation-free formatted print |
| `mem` | working | Static bump allocator over the free RAM region; locked after init |
| `measure` | working | SHA-256 of the loaded image |
| `partition` | **declaration only** | Static partition table with compile-time checks on time slices. No isolation is enforced yet |
| `detsim` | working | Seeded PRNG and a virtual clock |
| `faultprobe` | test only | Triggers a deliberate misaligned access to exercise the exception vector table |

The exception vector table lives in `src/arch/aarch64/exceptions.zig`. It is installed before `kmain` and reports the vector, `ESR_EL1`, `ELR_EL1` and `FAR_EL1` on the UART before halting. Build the M2 test image with `zig build run -Dmodules=console,faultprobe`; it must print a fault report instead of spinning.

## 6. Roadmap

Each milestone ends with a check that can be run and passed. Milestones are in order; do not start one before the previous exit check passes.

### Phase A: Basics (boots, prints, survives)

| # | Milestone | Scope | Exit check |
| --- | --- | --- | --- |
| **M0** | **Hello on QEMU** | Boot at EL1, set the stack, clear BSS, write to the UART. Only the `console` module. | `zig build run -Dmodules=console` prints `Hello from Korbora` |
| M1 | Module system | Comptime registry, `-Dmodules=`, ordered init, `mem`, `measure`, `detsim`. | `zig build test` passes. Missing-dependency builds fail to compile. Default image prints all module lines |
| M2 | Fault visibility | Exception vector table. Handler prints ESR, ELR and FAR, then halts. Panic prints a message. | A deliberate bad access in a test image prints a fault report and halts instead of spinning |
| M3 | Automated boot test | A script that boots QEMU headless, captures serial output and compares it to an expected transcript. Run it for several module sets. | `zig build qemu-test` passes and fails on a changed transcript |

### Phase B: Core kernel

| # | Milestone | Scope | Exit check |
| --- | --- | --- | --- |
| M4 | MMU and caches | Identity-mapped page tables, then normal memory attributes. Drop the strict-align/no-FP workaround. Add W^X (write xor execute) mappings for text/rodata/data. | A write to rodata faults with a report. Image runs with caches on |
| M5 | Timer and interrupts | GICv2/v3 setup, generic timer tick, IRQ handling. | Periodic tick count printed. `detsim` virtual clock can be driven from the tick |
| M6 | Static tasks and scheduler | Fixed task table at comptime, cooperative then timer-driven preemption, a static stack per task. | Two tasks interleave output in a fixed order. Run twice gives identical output |
| M7 | IPC | Fixed-size message channels declared at comptime. No allocation. | Producer and consumer tasks exchange messages. Overflow returns an error value |
| M8 | SMP | Bring up secondary cores (PSCI), per-core stacks, one spinlock primitive. | All cores print an ID. Scheduler runs a task on each core |

### Phase C: Isolation (separation kernel)

| # | Milestone | Scope | Exit check |
| --- | --- | --- | --- |
| M9 | Privilege split | Run tasks at EL0 with syscalls (SVC). Kernel stays at EL1. | An EL0 task cannot touch kernel memory. The fault is reported and the task is stopped |
| M10 | Partitions | Per-partition address space from the `partition` table. Memory budgets enforced. | Partition A writing to partition B's memory faults. Test image proves it |
| M11 | Time partitioning | Fixed major frame with static slices. An overrunning partition is cut off at its slice end. | A busy-loop partition does not delay the other partition's slice start beyond a set bound |
| M12 | Hypervisor mode (optional) | Run at EL2 with stage-2 translation to host guest workloads. | A guest runs and cannot reach memory outside its stage-2 map |

### Phase D: Trust and updates (secure edge)

| # | Milestone | Scope | Exit check |
| --- | --- | --- | --- |
| M13 | Signed images | Image manifest, Ed25519 signature check in `verify` using `std.crypto`, compare against the `measure` digest. | Tampered image refuses to start. Good image starts |
| M14 | Boot chain and A/B slots | Small first-stage loader, two image slots, boot counter, rollback on failure. | A deliberately failing image rolls back to the previous slot |
| M15 | OTA | Receive an image over a link, verify it, write it to the inactive slot, switch. | Update from a test host works and a corrupted transfer is rejected |

### Phase E: Connectivity and gateways

| # | Milestone | Scope | Exit check |
| --- | --- | --- | --- |
| M16 | virtio-net and minimal stack | Driver, Ethernet, ARP, IPv4, UDP. Static buffers. | The image answers a UDP echo from the host |
| M17 | `crypto` and `keystore` | AEAD channel (std.crypto), keys held in one isolated partition, zeroized on use. | Encrypted echo works. Other partitions cannot read key memory |
| M18 | `guard` and data diode | One-way channel, a rule-based filter and a protocol break. | A malformed or disallowed message is dropped and logged. Reverse traffic is impossible by construction |

### Phase F: Determinism and assurance

| # | Milestone | Scope | Exit check |
| --- | --- | --- | --- |
| M19 | Deterministic record/replay | Record inputs and interrupt timing in `detsim`. Replay them. | Two replays of one recording give byte-identical serial output |
| M20 | Fault injection and fuzzing | Fuzz the parsers (`guard`, `net`, manifest). Inject faults into the sim. | Fuzz run finds no crash. Injected faults are handled and reported |
| M21 | Real hardware port | Second `arch`/board target (a real Arm SoC) behind the same module interface. | M0 and M3 checks pass on hardware |
| M22 | Assurance package | Traceability from requirements to tests, memory and timing budget report, trusted-base size report. | Reports generate from `zig build` and are checked in CI |

## 7. Build and run

```sh
zig build                          # builds zig-out/bin/korbora.elf
zig build run                      # boots in qemu-system-aarch64 (Ctrl-A X to quit)
zig build test                     # host-side unit tests
zig build -Dmodules=console,mem    # smaller image
zig build --release=small          # release image
```
