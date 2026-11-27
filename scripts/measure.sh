#!/usr/bin/env bash
# Measure Snaplite (or any macOS .app / running PID) for binary size, cold start
# latency, physical memory footprint, CPU %, idle wakeups, and thread count.
#
# Usage:
#   scripts/measure.sh [options] [path/to/Snaplite.app]
#
# Options:
#   --pid <PID>          Attach to an already-running process (does not kill it)
#   --settle <seconds>   Seconds to settle after launch before sampling (default: 3)
#   --interval <seconds> Sample interval for top -l 2 -s <sec> (default: 3)
#   --keep-running       Do not terminate a launched process on exit
#   -v, --verbose        Print full `footprint -p <pid>` breakdown
#   -h, --help           Show this help message
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

TARGET=""
ATTACH_PID=""
SETTLE_SECS=3
TOP_INTERVAL=3
KEEP_RUNNING=0
VERBOSE=0

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pid)
            [[ $# -ge 2 ]] || { echo "ERROR: --pid requires an argument" >&2; exit 2; }
            ATTACH_PID="$2"
            shift 2
            ;;
        --settle)
            [[ $# -ge 2 ]] || { echo "ERROR: --settle requires an argument" >&2; exit 2; }
            SETTLE_SECS="$2"
            shift 2
            ;;
        --interval)
            [[ $# -ge 2 ]] || { echo "ERROR: --interval requires an argument" >&2; exit 2; }
            TOP_INTERVAL="$2"
            shift 2
            ;;
        --keep-running)
            KEEP_RUNNING=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ -n "$TARGET" ]]; then
                echo "ERROR: unexpected extra argument: $1" >&2
                exit 2
            fi
            TARGET="$1"
            shift
            ;;
    esac
done

if [[ -z "$ATTACH_PID" && -z "$TARGET" ]]; then
    TARGET="$REPO_DIR/dist/Snaplite.app"
fi

resolve_binary() {
    local path="$1"
    if [[ -d "$path" && "$path" == *.app ]]; then
        local plist="$path/Contents/Info.plist"
        local exec_name=""
        if [[ -f "$plist" ]] && [[ -x /usr/libexec/PlistBuddy ]]; then
            exec_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
        fi
        if [[ -z "$exec_name" ]]; then
            exec_name="$(basename "$path" .app)"
        fi
        local candidate="$path/Contents/MacOS/$exec_name"
        if [[ ! -x "$candidate" ]]; then
            echo "ERROR: executable not found at $candidate" >&2
            exit 1
        fi
        echo "$candidate"
    elif [[ -f "$path" && -x "$path" ]]; then
        echo "$path"
    else
        echo "ERROR: target not found or not executable: $path" >&2
        exit 1
    fi
}

LAUNCHED_PID=""
cleanup() {
    if [[ -n "$LAUNCHED_PID" && "$KEEP_RUNNING" -eq 0 ]]; then
        if kill -0 "$LAUNCHED_PID" 2>/dev/null; then
            kill -TERM "$LAUNCHED_PID" 2>/dev/null || true
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                kill -0 "$LAUNCHED_PID" 2>/dev/null || break
                sleep 0.2
            done
            if kill -0 "$LAUNCHED_PID" 2>/dev/null; then
                kill -KILL "$LAUNCHED_PID" 2>/dev/null || true
            fi
        fi
    fi
}
trap cleanup EXIT INT TERM

BIN_PATH=""
PID=""
COLD_START_STR="N/A (attached to running PID)"
COLD_START_DETAIL=""

if [[ -n "$ATTACH_PID" ]]; then
    if ! kill -0 "$ATTACH_PID" 2>/dev/null; then
        echo "ERROR: PID $ATTACH_PID is not running or not accessible" >&2
        exit 1
    fi
    PID="$ATTACH_PID"
    BIN_PATH="$(ps -p "$PID" -o comm= 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
    if [[ -n "$TARGET" ]]; then
        BIN_PATH="$(resolve_binary "$TARGET")"
    fi
else
    BIN_PATH="$(resolve_binary "$TARGET")"

    # Launch the executable directly and measure cold start until AppKit marks
    # NSRunningApplication.isFinishedLaunching == true (status item installed
    # and applicationDidFinishLaunching complete).
    LAUNCH_INFO="$(python3 - "$BIN_PATH" <<'PY'
import ctypes, ctypes.util, subprocess, sys, time

bin_path = sys.argv[1]

objc = ctypes.CDLL(ctypes.util.find_library("objc"))
ctypes.CDLL(ctypes.util.find_library("AppKit"))

objc.objc_getClass.argtypes = [ctypes.c_char_p]
objc.objc_getClass.restype = ctypes.c_void_p
objc.sel_registerName.argtypes = [ctypes.c_char_p]
objc.sel_registerName.restype = ctypes.c_void_p

msg_id_int = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int)(("objc_msgSend", objc))
msg_bool = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)(("objc_msgSend", objc))

cls_NSRunningApp = objc.objc_getClass(b"NSRunningApplication")
sel_withPid = objc.sel_registerName(b"runningApplicationWithProcessIdentifier:")
sel_isFinished = objc.sel_registerName(b"isFinishedLaunching")

t0 = time.monotonic_ns()
proc = subprocess.Popen(
    [bin_path],
    stdin=subprocess.DEVNULL,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
    start_new_session=True,
)
pid = proc.pid

deadline = t0 + int(5.0 * 1e9)
while time.monotonic_ns() < deadline:
    if proc.poll() is not None:
        print(f"EXITED {pid} {proc.returncode} exited")
        sys.exit(0)
    ra = msg_id_int(cls_NSRunningApp, sel_withPid, pid)
    if ra and msg_bool(ra, sel_isFinished):
        t1 = time.monotonic_ns()
        elapsed_ms = (t1 - t0) / 1e6
        print(f"READY {pid} {elapsed_ms:.1f} finishedLaunching")
        sys.exit(0)
    time.sleep(0.002)

t1 = time.monotonic_ns()
elapsed_ms = (t1 - t0) / 1e6
print(f"TIMEOUT {pid} {elapsed_ms:.1f} process-alive")
PY
)"
    read -r STATUS LAUNCHED_PID ELAPSED_MS READY_KIND <<<"$LAUNCH_INFO"
    if [[ "$STATUS" == "EXITED" ]]; then
        echo "ERROR: $BIN_PATH exited immediately (status $ELAPSED_MS)" >&2
        LAUNCHED_PID=""
        exit 1
    fi
    PID="$LAUNCHED_PID"
    if [[ "$STATUS" == "READY" ]]; then
        COLD_START_STR="${ELAPSED_MS} ms (${READY_KIND})"
    else
        COLD_START_STR=">${ELAPSED_MS} ms (timed out waiting for finishedLaunching; process alive)"
    fi

    if [[ "$SETTLE_SECS" -gt 0 ]]; then
        sleep "$SETTLE_SECS"
    fi
fi

# Verify process is still alive before sampling.
if ! kill -0 "$PID" 2>/dev/null; then
    echo "ERROR: PID $PID terminated before measurement completed" >&2
    exit 1
fi

# 1. Binary size & architecture
BIN_SIZE_STR="unknown"
ARCHS_STR=""
if [[ -n "$BIN_PATH" && -f "$BIN_PATH" ]]; then
    BIN_BYTES="$(stat -f '%z' "$BIN_PATH")"
    BIN_KB="$(awk -v b="$BIN_BYTES" 'BEGIN { printf "%.1f", b / 1024.0 }')"
    BIN_SIZE_STR="${BIN_BYTES} bytes (${BIN_KB} KB)"
    if command -v lipo >/dev/null 2>&1; then
        ARCHS_STR="$(lipo -archs "$BIN_PATH" 2>/dev/null || true)"
    fi
fi

# 2. Physical footprint via `footprint -p <pid>` (exact bytes for precision)
FOOTPRINT_BYTES_OUT="$(footprint -p "$PID" -f bytes --noCategories 2>&1)"
PHYS_BYTES="$(printf '%s\n' "$FOOTPRINT_BYTES_OUT" | awk '/phys_footprint:/ { print $2; exit }')"
PEAK_BYTES="$(printf '%s\n' "$FOOTPRINT_BYTES_OUT" | awk '/phys_footprint_peak:/ { print $2; exit }')"

fmt_bytes() {
    local b="$1"
    if [[ -z "$b" || ! "$b" =~ ^[0-9]+$ ]]; then
        echo "N/A"
    else
        awk -v b="$b" 'BEGIN { printf "%.2f MB (%.0f KB)", b / 1048576.0, b / 1024.0 }'
    fi
}

PHYS_FOOTPRINT="$(fmt_bytes "${PHYS_BYTES:-}")"
PHYS_PEAK="$(fmt_bytes "${PEAK_BYTES:-}")"

# 3. CPU %, memory, idle wakeups, thread count via `top -l 2 -s <interval>`
TOP_OUT="$(top -l 2 -s "$TOP_INTERVAL" -pid "$PID" -stats pid,cpu,mem,idlew,th 2>&1)"
TOP_SAMPLE="$(printf '%s\n' "$TOP_OUT" | awk -v pid="$PID" '$1 == pid { line = $0 } END { print line }')"
if [[ -n "$TOP_SAMPLE" ]]; then
    read -r _ TOP_CPU TOP_MEM TOP_IDLEW TOP_TH <<<"$TOP_SAMPLE"
else
    TOP_CPU="N/A"
    TOP_MEM="N/A"
    TOP_IDLEW="N/A"
    TOP_TH="N/A"
fi

echo "=== Snaplite Measurement ==="
echo "Target:             ${TARGET:-PID $PID}"
if [[ -n "$BIN_PATH" ]]; then
    echo "Binary:             $BIN_PATH"
fi
if [[ -n "$ARCHS_STR" ]]; then
    echo "Architectures:      $ARCHS_STR"
fi
echo "PID:                $PID"
echo "Binary size:        $BIN_SIZE_STR"
echo "Cold start:         $COLD_START_STR"
echo "Physical footprint: ${PHYS_FOOTPRINT} (peak: ${PHYS_PEAK})"
echo "CPU % (${TOP_INTERVAL}s avg):    ${TOP_CPU}%"
echo "top MEM:            ${TOP_MEM}"
echo "Idle wakeups:       ${TOP_IDLEW} (top -l 2 -s ${TOP_INTERVAL})"
echo "Threads:            ${TOP_TH}"

if [[ "$VERBOSE" -eq 1 ]]; then
    echo
    echo "--- Full footprint output ---"
    footprint -p "$PID" 2>&1
fi
