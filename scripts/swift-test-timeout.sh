#!/bin/sh
exec python3 "$(dirname "$0")/../Tools/hang-guard.py" run "$@"
