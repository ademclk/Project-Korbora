#!/bin/sh
# Boot one kernel image headlessly in QEMU, capture the PL011 serial output and
# compare it with an expected transcript.
#
# Usage: qemu_boot_test.sh <checker> <name> <modules> <expected> <kernel>
#
# The image runs forever after initialization (the kernel idles with wfe), so
# the script polls the serial log until the transcript matches, then terminates
# QEMU. A slow or broken boot fails after the timeout instead of hanging.

set -eu

if [ "$#" -ne 5 ]; then
    echo "usage: $0 <checker> <name> <modules> <expected> <kernel>" >&2
    exit 2
fi

checker=$1
name=$2
modules=$3
expected=$4
kernel=$5
qemu=${QEMU:-qemu-system-aarch64}

if ! command -v "$qemu" >/dev/null 2>&1; then
    echo "qemu-test: '$qemu' not found; install QEMU or set QEMU=/path/to/qemu-system-aarch64" >&2
    exit 1
fi

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/korbora-qemu.XXXXXX")
serial=$tmpdir/serial.log
qemu_err=$tmpdir/qemu.err
pid=

cleanup() {
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
    rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

: >"$serial"

"$qemu" \
    -machine virt \
    -cpu cortex-a72 \
    -display none \
    -m 128M \
    -kernel "$kernel" \
    -serial "file:$serial" \
    -monitor none \
    -no-reboot \
    2>"$qemu_err" &

pid=$!

# Boot is normally well under a second. Poll so a slow machine still passes and
# a hung boot fails deterministically (400 * 50 ms = 20 s).
attempt=0
while [ "$attempt" -lt 400 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
        break
    fi

    if "$checker" "$expected" "$serial" >/dev/null 2>&1; then
        break
    fi

    sleep 0.05
    attempt=$((attempt + 1))
done

if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
fi
wait "$pid" 2>/dev/null || true
pid=

echo "qemu-test: $name (-Dmodules=$modules)"

if "$checker" "$expected" "$serial"; then
    echo "qemu-test: PASS $name"
else
    echo "qemu-test: FAIL $name" >&2
    if [ ! -s "$serial" ] && [ -s "$qemu_err" ]; then
        echo "--- qemu stderr ---" >&2
        cat "$qemu_err" >&2
    fi
    exit 1
fi
