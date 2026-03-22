#!/usr/bin/env python3
"""Test polyglot plugin that always denies."""
import json, sys

req = json.load(sys.stdin)
print(json.dumps({
    "name": "deny-plugin",
    "passed": False,
    "reason": "[LaneKeep] DENIED by plugin:deny-plugin — test denial",
    "decision": "deny"
}))
