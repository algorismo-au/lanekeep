#!/usr/bin/env python3
"""Test polyglot plugin that always allows."""
import json, sys

req = json.load(sys.stdin)
print(json.dumps({
    "name": "allow-plugin",
    "passed": True,
    "reason": "",
    "decision": "deny"
}))
