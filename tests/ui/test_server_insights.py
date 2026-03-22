#!/usr/bin/env python3
"""Tests for compute_trace_summary() in the LaneKeep UI server."""

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

# Add the ui/ directory to sys.path so we can import server module
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / 'ui'))
import server  # noqa: E402


def _pre(decision, tool_use_id=None, evaluators=None, **extra):
    entry = {'event_type': 'PreToolUse', 'decision': decision}
    if tool_use_id is not None:
        entry['tool_use_id'] = tool_use_id
    if evaluators is not None:
        entry['evaluators'] = evaluators
    entry.update(extra)
    return entry


def _post(tool_use_id=None, decision='allow', user_denied=False, evaluators=None, **extra):
    entry = {'event_type': 'PostToolUse', 'decision': decision}
    if tool_use_id is not None:
        entry['tool_use_id'] = tool_use_id
    if user_denied:
        entry['user_denied'] = True
    if evaluators is not None:
        entry['evaluators'] = evaluators
    entry.update(extra)
    return entry


class TestComputeTraceSummary(unittest.TestCase):

    def test_pretooluse_only_counting(self):
        """PostToolUse decisions must not inflate decision counts."""
        entries = [
            _pre('deny', tool_use_id='t1'),
            _pre('warn', tool_use_id='t2'),
            _pre('allow', tool_use_id='t3'),
            _post(tool_use_id='t1', decision='allow'),
            _post(tool_use_id='t2', decision='allow'),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['deny'], 1)
        self.assertEqual(s['warn'], 1)
        self.assertEqual(s['allow'], 1)
        # Not 3 allows (which would happen if PostToolUse counted)

    def test_total_counts_pretooluse_only(self):
        """Total should count only PreToolUse entries (not PostToolUse)."""
        entries = [
            _pre('deny', tool_use_id='t1'),
            _pre('warn', tool_use_id='t2'),
            _pre('allow', tool_use_id='t3'),
            _post(tool_use_id='t1'),
            _post(tool_use_id='t2'),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['total'], 3)

    def test_ask_correlation_approved(self):
        """Ask with matching PostToolUse (user_denied=false) -> approved."""
        entries = [
            _pre('ask', tool_use_id='t1'),
            _post(tool_use_id='t1', user_denied=False),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_approved'], 1)
        self.assertEqual(s['asks_denied'], 0)
        self.assertEqual(s['asks_unknown'], 0)
        self.assertEqual(s['ask'], 1)
        # Verify the entry was mutated
        self.assertTrue(entries[0]['user_approved'])

    def test_ask_correlation_denied(self):
        """Ask with matching PostToolUse (user_denied=true) -> denied."""
        entries = [
            _pre('ask', tool_use_id='t1'),
            _post(tool_use_id='t1', user_denied=True),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_approved'], 0)
        self.assertEqual(s['asks_denied'], 1)
        self.assertEqual(s['asks_unknown'], 0)
        self.assertFalse(entries[0]['user_approved'])

    def test_ask_no_tool_use_id(self):
        """Ask without tool_use_id -> unknown."""
        entries = [_pre('ask')]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_unknown'], 1)
        self.assertEqual(s['asks_approved'], 0)
        self.assertEqual(s['asks_denied'], 0)
        self.assertIsNone(entries[0]['user_approved'])

    def test_ask_no_matching_post(self):
        """Ask with tool_use_id but no matching PostToolUse, not last -> inferred denied."""
        entries = [
            _pre('ask', tool_use_id='t1'),
            _post(tool_use_id='t999'),  # different ID — session continued
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_denied'], 1)
        self.assertEqual(s['asks_unknown'], 0)
        self.assertEqual(s['asks_approved'], 0)
        self.assertFalse(entries[0]['user_approved'])

    def test_unmatched_ask_middle_inferred_denied(self):
        """Unmatched ask in the middle of entries -> inferred denied."""
        entries = [
            _pre('ask', tool_use_id='t1'),
            _pre('allow', tool_use_id='t2'),
            _post(tool_use_id='t2'),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_denied'], 1)
        self.assertEqual(s['asks_unknown'], 0)
        self.assertFalse(entries[0]['user_approved'])

    def test_unmatched_ask_last_stays_unknown(self):
        """Unmatched ask as the very last entry -> stays unknown (pending)."""
        entries = [
            _pre('allow', tool_use_id='t1'),
            _post(tool_use_id='t1'),
            _pre('ask', tool_use_id='t2'),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_unknown'], 1)
        self.assertEqual(s['asks_denied'], 0)
        self.assertIsNone(entries[2]['user_approved'])

    def test_multiple_unmatched_asks_only_last_unknown(self):
        """Multiple unmatched asks: all but the last are inferred denied."""
        entries = [
            _pre('ask', tool_use_id='t1'),
            _pre('ask', tool_use_id='t2'),
            _pre('ask', tool_use_id='t3'),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_denied'], 2)
        self.assertEqual(s['asks_unknown'], 1)
        self.assertFalse(entries[0]['user_approved'])
        self.assertFalse(entries[1]['user_approved'])
        self.assertIsNone(entries[2]['user_approved'])

    def test_ask_no_tuid_not_last_inferred_denied(self):
        """Ask without tool_use_id, not last entry -> inferred denied."""
        entries = [
            _pre('ask'),
            _pre('allow', tool_use_id='t1'),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['asks_denied'], 1)
        self.assertEqual(s['asks_unknown'], 0)
        self.assertFalse(entries[0]['user_approved'])

    def test_pii_only_from_pretooluse(self):
        """PII detections on PostToolUse entries must not be counted."""
        pii_evaluator = [{'detections': [{'category': 'pii', 'type': 'ssn'}]}]
        entries = [
            _pre('allow', tool_use_id='t1', evaluators=pii_evaluator),
            _post(tool_use_id='t1', evaluators=copy.deepcopy(pii_evaluator)),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['pii_input'], 1)  # only the PreToolUse one

    def test_empty_entries(self):
        """Empty list returns all zeros."""
        s = server.compute_trace_summary([])
        self.assertEqual(s['total'], 0)
        self.assertEqual(s['deny'], 0)
        self.assertEqual(s['warn'], 0)
        self.assertEqual(s['ask'], 0)
        self.assertEqual(s['allow'], 0)
        self.assertEqual(s['pii_input'], 0)
        self.assertEqual(s['asks_approved'], 0)
        self.assertEqual(s['asks_denied'], 0)
        self.assertEqual(s['asks_unknown'], 0)

    def test_mixed_realistic_scenario(self):
        """Realistic mix: verify exact counts."""
        entries = [
            _pre('deny', tool_use_id='t1'),
            _post(tool_use_id='t1', decision='allow'),
            _pre('allow', tool_use_id='t2'),
            _post(tool_use_id='t2', decision='allow'),
            _pre('ask', tool_use_id='t3'),
            _post(tool_use_id='t3', user_denied=False),
            _pre('ask', tool_use_id='t4'),
            _post(tool_use_id='t4', user_denied=True),
            _pre('warn', tool_use_id='t5'),
            _post(tool_use_id='t5', decision='allow'),
        ]
        s = server.compute_trace_summary(entries)
        self.assertEqual(s['total'], 5)  # 5 PreToolUse only
        self.assertEqual(s['deny'], 1)
        self.assertEqual(s['warn'], 1)
        self.assertEqual(s['ask'], 2)
        self.assertEqual(s['allow'], 1)
        self.assertEqual(s['asks_approved'], 1)
        self.assertEqual(s['asks_denied'], 1)
        self.assertEqual(s['asks_unknown'], 0)

    def test_decision_sum_never_exceeds_total(self):
        """Sum of decision counts must never exceed total."""
        entries = [
            _pre('deny'), _pre('warn'), _pre('ask'), _pre('allow'),
            _post(decision='allow'), _post(decision='allow'),
        ]
        s = server.compute_trace_summary(entries)
        decision_sum = s['deny'] + s['warn'] + s['ask'] + s['allow']
        self.assertLessEqual(decision_sum, s['total'])



class TestComputeAlltimeFromTraces(unittest.TestCase):
    """Tests for _compute_alltime_from_traces() — all-time metrics from trace files."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.trace_dir = Path(self.tmpdir) / 'traces'
        self.trace_dir.mkdir()
        # Reset the cache between tests
        server._alltime_cache = {'key': None, 'data': None}

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write_trace(self, filename, entries):
        path = self.trace_dir / filename
        with open(path, 'w') as f:
            for entry in entries:
                f.write(json.dumps(entry) + '\n')

    def test_multiple_trace_files_aggregation(self):
        """Decisions across multiple trace files are correctly summed."""
        self._write_trace('session-A.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash', 'latency_ms': 5,
             'evaluators': [{'name': 'RuleEngine', 'passed': False}]},
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash', 'latency_ms': 3,
             'evaluators': [{'name': 'HardBlock', 'passed': False}]},
        ])
        self._write_trace('session-B.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Read', 'latency_ms': 2},
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Write', 'latency_ms': 4,
             'evaluators': [{'name': 'RuleEngine', 'passed': False}]},
        ])

        result = server._compute_alltime_from_traces(self.trace_dir)

        self.assertEqual(result['decisions']['deny'], 3)
        self.assertEqual(result['decisions']['allow'], 1)
        self.assertEqual(result['top_denied_tools']['Bash'], 2)
        self.assertEqual(result['top_denied_tools']['Write'], 1)
        self.assertEqual(result['top_evaluators']['RuleEngine'], 2)
        self.assertEqual(result['top_evaluators']['HardBlock'], 1)
        self.assertEqual(result['latency']['count'], 4)
        self.assertEqual(result['latency']['sum_ms'], 14)
        self.assertEqual(result['latency']['max_ms'], 5)

    def test_caching_returns_same_result(self):
        """Same mtime key should return cached result without re-reading."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash'},
        ])
        result1 = server._compute_alltime_from_traces(self.trace_dir)
        result2 = server._compute_alltime_from_traces(self.trace_dir)
        self.assertIs(result1, result2)  # Same object reference = cached

    def test_empty_trace_dir(self):
        """Empty trace directory returns zeroed metrics."""
        result = server._compute_alltime_from_traces(self.trace_dir)

        self.assertEqual(result['decisions'], {'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0})
        self.assertEqual(result['top_denied_tools'], {})
        self.assertEqual(result['top_evaluators'], {})
        self.assertEqual(result['pii_input'], 0)
        self.assertEqual(result['latency']['count'], 0)

    def test_nonexistent_trace_dir(self):
        """Nonexistent trace directory returns zeroed metrics."""
        result = server._compute_alltime_from_traces(Path(self.tmpdir) / 'nonexistent')

        self.assertEqual(result['decisions'], {'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0})
        self.assertEqual(result['pii_input'], 0)

    def test_malformed_jsonl_lines_skipped(self):
        """Malformed JSONL lines are skipped gracefully."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash'},
        ])
        # Append malformed lines
        with open(self.trace_dir / 'session.jsonl', 'a') as f:
            f.write('not valid json\n')
            f.write('{broken\n')
            f.write('\n')  # empty line

        result = server._compute_alltime_from_traces(self.trace_dir)
        self.assertEqual(result['decisions']['deny'], 1)

    def test_posttooluse_excluded(self):
        """PostToolUse entries should not be counted in decisions."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash'},
            {'event_type': 'PostToolUse', 'decision': 'allow', 'tool_name': 'Bash'},
        ])

        result = server._compute_alltime_from_traces(self.trace_dir)
        self.assertEqual(result['decisions']['deny'], 1)
        self.assertEqual(result['decisions']['allow'], 0)

    def test_pii_detection_counted(self):
        """PII detections are counted from evaluator results."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Bash',
             'evaluators': [{'name': 'InputPII', 'passed': True,
                             'detections': [{'category': 'pii', 'type': 'ssn'}]}]},
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Read',
             'evaluators': [{'name': 'InputPII', 'passed': True,
                             'detections': [{'category': 'pii', 'type': 'email'}]}]},
        ])

        result = server._compute_alltime_from_traces(self.trace_dir)
        self.assertEqual(result['pii_input'], 2)


if __name__ == '__main__':
    unittest.main()
