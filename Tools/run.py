#!/usr/bin/env python3
"""Run a command with a deadline and terminate its entire process group."""
import os, signal, subprocess, sys
seconds = float(sys.argv[1])
p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    code = p.wait(timeout=seconds)
except (subprocess.TimeoutExpired, KeyboardInterrupt):
    os.killpg(p.pid, signal.SIGTERM)
    try: p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.wait()
    code = 124
sys.exit(code)
