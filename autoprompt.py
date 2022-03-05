#!/usr/bin/env python3
"""
Command wrapper for automatically replying to interactive prompts by matching
output patterns.
"""

import argparse
import re
import shlex
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("command", help="Command to execute")
parser.add_argument("pattern", nargs="+", help="Patterns to match")
parser.add_argument("--quiet",
                    action="store_true",
                    default=False,
                    help="Suppress STDERR output")
args = parser.parse_args()

patterns = list(args.pattern)

with subprocess.Popen(shlex.split(args.command),
                      stdin=subprocess.PIPE,
                      stderr=subprocess.PIPE,
                      encoding="utf-8") as process:
    for line in process.stderr:
        if not args.quiet:
            sys.stderr.write(line)

        m = re.search(patterns[0], line) if patterns else None
        if m is None:
            continue

        process.stdin.write(m.group(1) + "\n")
        process.stdin.flush()

        patterns.pop(0)
        if not patterns:
            process.stdin.close()
