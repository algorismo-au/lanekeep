#!/usr/bin/env python3
"""Tests for server.py API endpoints — focused on recent changes:
   trace pagination, trends time-range filter, cache correctness."""

import json
import os
import sys
import tempfile
import threading
import time
import unittest
from datetime import datetime, timezone, timedelta
from http.client import HTTPConnection
from pathlib import Path
from urllib.parse import urlencode

# Add the UI directory to path so we can import server internals
LANEKEEP_UI = Path(__file__).resolve().parent.parent.parent / 'ui'
sys.path.insert(0, str(LANEKEEP_UI))

import server as srv


def make_trace_entry(ts_offset_min=0, decision='allow', tool='Bash', event_type='PreToolUse', latency_ms=10):
    """Create a trace entry with timestamp offset from a base time."""
    base = datetime(2026, 3, 15, 10, 0, 0, tzinfo=timezone.utc)
    ts = base + timedelta(minutes=ts_offset_min)
    return {
        'timestamp': ts.isoformat().replace('+00:00', 'Z'),
        'event_type': event_type,
        'tool_name': tool,
        'decision': decision,
        'reason': f'test {decision}',
        'latency_ms': latency_ms,
        'session_id': 'test-session',
        'tool_use_id': f'{decision}-{ts_offset_min}',
    }


class ServerAPITestCase(unittest.TestCase):
    """Start a real server on a random port and test the HTTP API."""

    @classmethod
    def setUpClass(cls):
        cls.tmpdir = tempfile.mkdtemp()
        cls.project_dir = Path(cls.tmpdir) / 'project'
        cls.project_dir.mkdir()
        cls.traces_dir = cls.project_dir / '.lanekeep' / 'traces'
        cls.traces_dir.mkdir(parents=True)

        # Copy default config
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls.project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls.project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')

        # Write test trace entries
        entries = []
        # 10 deny entries spread across 3 hours
        for i in range(10):
            entries.append(make_trace_entry(i * 20, 'deny', 'Bash'))
        # 5 allow entries
        for i in range(5):
            entries.append(make_trace_entry(200 + i * 10, 'allow', 'Read'))
        # 3 warn entries
        for i in range(3):
            entries.append(make_trace_entry(300 + i * 10, 'warn', 'Write'))
        # 2 recent entries (within last hour relative to latest)
        entries.append(make_trace_entry(350, 'allow', 'Bash'))
        entries.append(make_trace_entry(355, 'deny', 'Bash'))

        trace_file = cls.traces_dir / 'test-session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

        # Patch globals and start server
        srv.PROJECT_DIR = cls.project_dir
        srv.CONFIG_PATH = cls.project_dir / 'lanekeep.json'

        # Reset caches
        srv._trace_cache.update({'key': None, 'data': None, 'limit': None})
        srv._trace_entries_cache.update({'key': None, 'entries': None, 'summary': None})
        srv._trends_cache.update({'key': None, 'data': None})

        # Find free port and start server
        import socket
        sock = socket.socket()
        sock.bind(('127.0.0.1', 0))
        cls.port = sock.getsockname()[1]
        sock.close()

        from http.server import ThreadingHTTPServer
        cls.server = ThreadingHTTPServer(('127.0.0.1', cls.port), srv.Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        import shutil
        shutil.rmtree(cls.tmpdir, ignore_errors=True)

    def get(self, path):
        conn = HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('GET', path)
        resp = conn.getresponse()
        body = resp.read().decode()
        conn.close()
        try:
            return resp.status, json.loads(body)
        except json.JSONDecodeError:
            raise AssertionError(f'Non-JSON response (status={resp.status}): {body[:200]}')

    # ── Trace endpoint tests ──

    def test_trace_default_returns_entries(self):
        status, data = self.get('/api/trace?limit=100')
        self.assertEqual(status, 200)
        self.assertIn('entries', data)
        self.assertEqual(len(data['entries']), 20)  # 10 deny + 5 allow + 3 warn + 2 recent

    def test_trace_limit_works(self):
        status, data = self.get('/api/trace?limit=5')
        self.assertEqual(status, 200)
        self.assertEqual(len(data['entries']), 5)

    def test_trace_offset_pagination(self):
        # Get first page
        _, page1 = self.get('/api/trace?limit=5&offset=0&sort=timestamp&sort_dir=asc')
        # Get second page
        _, page2 = self.get('/api/trace?limit=5&offset=5&sort=timestamp&sort_dir=asc')
        self.assertEqual(len(page1['entries']), 5)
        self.assertEqual(len(page2['entries']), 5)
        # Pages should not overlap
        ts1 = [e['timestamp'] for e in page1['entries']]
        ts2 = [e['timestamp'] for e in page2['entries']]
        self.assertEqual(len(set(ts1) & set(ts2)), 0)

    def test_trace_offset_beyond_end_returns_empty(self):
        _, data = self.get('/api/trace?limit=10&offset=9999')
        self.assertEqual(len(data['entries']), 0)

    def test_trace_sort_asc(self):
        _, data = self.get('/api/trace?limit=100&sort=timestamp&sort_dir=asc')
        timestamps = [e['timestamp'] for e in data['entries']]
        self.assertEqual(timestamps, sorted(timestamps))

    def test_trace_sort_desc(self):
        _, data = self.get('/api/trace?limit=100&sort=timestamp&sort_dir=desc')
        timestamps = [e['timestamp'] for e in data['entries']]
        self.assertEqual(timestamps, sorted(timestamps, reverse=True))

    def test_trace_decision_filter(self):
        _, data = self.get('/api/trace?limit=100&decision=deny')
        for e in data['entries']:
            self.assertEqual(e['decision'], 'deny')
        self.assertEqual(data['total_filtered'], 11)  # 10 + 1 recent deny

    def test_trace_total_filtered_and_total_all(self):
        _, data = self.get('/api/trace?limit=100&decision=warn')
        self.assertEqual(data['total_filtered'], 3)
        self.assertEqual(data['total_all'], 20)

    def test_trace_summary_present(self):
        _, data = self.get('/api/trace?limit=100')
        s = data['summary']
        self.assertIn('total', s)
        self.assertIn('deny', s)
        self.assertIn('allow', s)
        self.assertGreater(s['total'], 0)

    def test_trace_invalid_limit_returns_400(self):
        status, _ = self.get('/api/trace?limit=abc')
        self.assertEqual(status, 400)

    # ── Trends endpoint tests ──

    def test_trends_default_returns_buckets(self):
        status, data = self.get('/api/trends')
        self.assertEqual(status, 200)
        self.assertIn('buckets', data)
        self.assertGreater(len(data['buckets']), 0)
        self.assertEqual(data['range'], 'all')

    def test_trends_buckets_have_required_fields(self):
        _, data = self.get('/api/trends')
        for b in data['buckets']:
            self.assertIn('t', b)
            self.assertIn('actions', b)
            self.assertIn('decisions', b)
            self.assertIn('latency_p50', b)
            self.assertIn('latency_p95', b)

    def test_trends_range_filter(self):
        # All entries are from 2026-03-15 10:00 to ~16:00
        # '1h' range from now (2026-03-20) should return empty since entries are days old
        _, data = self.get('/api/trends?range=1h')
        self.assertEqual(data['range'], '1h')
        # Entries are 5 days old, so 1h filter should return 0 buckets
        self.assertEqual(len(data['buckets']), 0)

    def test_trends_1h_empty_includes_latest_timestamp(self):
        """When 1h filter returns 0 buckets, response should include latest_timestamp."""
        _, data = self.get('/api/trends?range=1h')
        self.assertEqual(len(data['buckets']), 0)
        self.assertIn('latest_timestamp', data)
        # Timestamp should be parseable and match latest entry (355 min offset = ~15:55)
        from datetime import datetime as DT
        lt = DT.fromisoformat(data['latest_timestamp'])
        self.assertEqual(lt.hour, 15)
        self.assertEqual(lt.minute, 55)

    def test_trends_range_all_no_latest_timestamp(self):
        """Unfiltered (all) responses should NOT include latest_timestamp."""
        _, data = self.get('/api/trends?range=all')
        self.assertGreater(len(data['buckets']), 0)
        self.assertNotIn('latest_timestamp', data)

    def test_trends_range_all_returns_all(self):
        _, data = self.get('/api/trends?range=all')
        self.assertGreater(len(data['buckets']), 0)

    def test_trends_range_30d_includes_recent_entries(self):
        # Entries from 5 days ago should be within 30d range
        _, data = self.get('/api/trends?range=30d')
        self.assertGreater(len(data['buckets']), 0)

    def test_trends_invalid_range_treated_as_all(self):
        _, data = self.get('/api/trends?range=invalid')
        self.assertEqual(data['range'], 'invalid')
        # Invalid range_seconds == 0, so no filtering applied
        self.assertGreater(len(data['buckets']), 0)

    def test_trends_granularity_field(self):
        _, data = self.get('/api/trends')
        self.assertIn(data['granularity'], ['hourly', 'daily', 'weekly'])

    # ── Cache correctness tests ──

    def test_trace_cache_returns_same_data(self):
        """Two identical requests should return the same data (cache hit)."""
        _, data1 = self.get('/api/trace?limit=10&offset=0&sort=timestamp&sort_dir=desc')
        _, data2 = self.get('/api/trace?limit=10&offset=0&sort=timestamp&sort_dir=desc')
        self.assertEqual(data1['entries'], data2['entries'])

    def test_empty_trace_dir_cache_not_stale(self):
        """After clearing traces, the cache should not return stale entries."""
        # First, get data with entries
        _, data_before = self.get('/api/trace?limit=100')
        self.assertGreater(len(data_before['entries']), 0)

        # Clear the trace files
        for f in self.traces_dir.glob('*.jsonl'):
            f.unlink()

        # Reset the entries cache to simulate new request
        srv._trace_entries_cache.update({'key': None, 'entries': None, 'summary': None})

        _, data_after = self.get('/api/trace?limit=100')
        self.assertEqual(len(data_after['entries']), 0)

        # Restore trace files for other tests
        entries = []
        for i in range(10):
            entries.append(make_trace_entry(i * 20, 'deny', 'Bash'))
        for i in range(5):
            entries.append(make_trace_entry(200 + i * 10, 'allow', 'Read'))
        for i in range(3):
            entries.append(make_trace_entry(300 + i * 10, 'warn', 'Write'))
        entries.append(make_trace_entry(350, 'allow', 'Bash'))
        entries.append(make_trace_entry(355, 'deny', 'Bash'))
        with open(self.traces_dir / 'test-session.jsonl', 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')
        # Reset caches
        srv._trace_entries_cache.update({'key': None, 'entries': None, 'summary': None})
        srv._trace_cache.update({'key': None, 'data': None, 'limit': None})


    # ── Context window tests ──

    def test_context_window_known_model(self):
        """Known model (claude-opus-4-6) returns 1M context window."""
        state_path = self.project_dir / '.lanekeep' / 'state.json'
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(json.dumps({
            'action_count': 5, 'token_count': 100000, 'input_tokens': 100000,
            'output_tokens': 0, 'total_events': 10, 'start_epoch': int(time.time()),
            'elapsed_seconds': 60, 'session_id': 'ctx-test',
            'token_source': 'transcript', 'model': 'claude-opus-4-6'
        }))
        status, data = self.get('/api/status')
        self.assertEqual(status, 200)
        b = data['budget']
        self.assertEqual(b['context_window_size'], 1_000_000)
        self.assertEqual(b['context_model'], 'claude-opus-4-6')
        self.assertEqual(b['context_source'], 'model')

    def test_context_window_unknown_model_returns_default(self):
        """Unknown model returns default 200K context window."""
        state_path = self.project_dir / '.lanekeep' / 'state.json'
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(json.dumps({
            'action_count': 2, 'token_count': 50000, 'input_tokens': 50000,
            'output_tokens': 0, 'total_events': 5, 'start_epoch': int(time.time()),
            'elapsed_seconds': 30, 'session_id': 'ctx-test',
            'token_source': 'transcript', 'model': 'claude-unknown-99'
        }))
        status, data = self.get('/api/status')
        self.assertEqual(status, 200)
        b = data['budget']
        self.assertEqual(b['context_window_size'], 200_000)

    def test_context_window_env_override(self):
        """LANEKEEP_CONTEXT_WINDOW_SIZE env var overrides model inference."""
        state_path = self.project_dir / '.lanekeep' / 'state.json'
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(json.dumps({
            'action_count': 1, 'token_count': 10000, 'input_tokens': 10000,
            'output_tokens': 0, 'total_events': 2, 'start_epoch': int(time.time()),
            'elapsed_seconds': 10, 'session_id': 'ctx-test',
            'token_source': 'transcript', 'model': 'claude-opus-4-6'
        }))
        os.environ['LANEKEEP_CONTEXT_WINDOW_SIZE'] = '500000'
        try:
            status, data = self.get('/api/status')
            self.assertEqual(status, 200)
            b = data['budget']
            self.assertEqual(b['context_window_size'], 500_000)
            self.assertEqual(b['context_source'], 'env')
        finally:
            del os.environ['LANEKEEP_CONTEXT_WINDOW_SIZE']

    def test_no_context_fields_when_estimate(self):
        """No context_window_size when token_source is estimate."""
        state_path = self.project_dir / '.lanekeep' / 'state.json'
        state_path.parent.mkdir(parents=True, exist_ok=True)
        state_path.write_text(json.dumps({
            'action_count': 3, 'token_count': 5000, 'input_tokens': 5000,
            'output_tokens': 0, 'total_events': 6, 'start_epoch': int(time.time()),
            'elapsed_seconds': 20, 'session_id': 'ctx-test',
            'token_source': 'estimate'
        }))
        status, data = self.get('/api/status')
        self.assertEqual(status, 200)
        b = data['budget']
        self.assertNotIn('context_window_size', b)
        self.assertNotIn('context_model', b)


if __name__ == '__main__':
    unittest.main()
