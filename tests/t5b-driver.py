#!/usr/bin/env python3
"""Feather/Wings-style TTY stop simulator.

Runs the container entrypoint inside a real pty (exactly how Wings-family
daemons create Tty:true containers), waits for the database to report ready,
then writes the literal stop command text (^C) into the pty master - the same
bytes a daemon sends through its attach stream. Propagates the entrypoint's
exit code.
"""
import os
import pty
import select
import subprocess
import sys
import threading
import time

READY = os.environ.get("TTY_READY_MATCH", "ready to accept connections").encode().lower()
STOP_TEXT = os.environ.get("TTY_STOP_TEXT", "^C\n").encode()
BOOT_WAIT = int(os.environ.get("TTY_BOOT_MAX", "120"))
SHUTDOWN_WAIT = int(os.environ.get("TTY_SHUTDOWN_MAX", "60"))

master_fd, slave_fd = pty.openpty()
proc = subprocess.Popen(
    ["/bin/bash", "/entrypoint.sh"],
    stdin=slave_fd,
    stdout=slave_fd,
    stderr=slave_fd,
    start_new_session=True,
    close_fds=True,
)
os.close(slave_fd)

out_lock = threading.Lock()


def relay(fd: int, stop_flag: list) -> None:
    while not stop_flag[0]:
        r, _, _ = select.select([fd], [], [], 0.2)
        if not r:
            continue
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        with out_lock:
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
    try:
        os.close(fd)
    except OSError:
        pass


stop_flag = [False]
threading.Thread(target=relay, args=(master_fd, stop_flag), daemon=True).start()

deadline = time.time() + BOOT_WAIT
ready = False
# Scan the shared console log the entrypoint mirrors boot output into.
console_log = "/home/container/.logs/console.log"
while time.time() < deadline:
    try:
        with open(console_log, "r", errors="replace") as f:
            if READY in f.read().lower().encode(errors="ignore"):
                ready = True
                break
    except OSError:
        pass
    if proc.poll() is not None:
        break
    time.sleep(1)

if not ready and proc.poll() is None:
    with out_lock:
        print(f"[t5b-driver] boot marker not seen in {BOOT_WAIT}s; sending stop anyway", flush=True)

time.sleep(2)
try:
    os.write(master_fd, STOP_TEXT)
except OSError as exc:
    with out_lock:
        print(f"[t5b-driver] failed to write stop text: {exc}", flush=True)

try:
    rc = proc.wait(timeout=SHUTDOWN_WAIT)
except subprocess.TimeoutExpired:
    with out_lock:
        print("[t5b-driver] entrypoint did not exit after stop text", flush=True)
    proc.kill()
    rc = proc.wait(timeout=10)

stop_flag[0] = True
sys.exit(rc)
