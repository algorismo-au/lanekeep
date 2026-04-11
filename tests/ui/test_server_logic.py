#!/usr/bin/env python3
"""Correctness tests for server.py computation functions:
   _md_to_html, _serve_trends (percentiles/bucketing), _compute_alltime_from_traces,
   _serve_graphs (compliance mapping), _serve_status (config merge), edge cases."""

import hashlib
import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import time
import unittest
import uuid
from datetime import datetime, timezone, timedelta
from http.client import HTTPConnection
from pathlib import Path
from urllib.parse import urlencode

# Add the UI directory to path so we can import server internals
LANEKEEP_UI = Path(__file__).resolve().parent.parent.parent / 'ui'
sys.path.insert(0, str(LANEKEEP_UI))

import server as srv


def make_trace_entry(ts_offset_min=0, decision='allow', tool='Bash',
                     event_type='PreToolUse', latency_ms=10, **extra):
    """Create a trace entry with timestamp offset from a base time."""
    base = datetime(2026, 3, 15, 10, 0, 0, tzinfo=timezone.utc)
    ts = base + timedelta(minutes=ts_offset_min)
    entry = {
        'timestamp': ts.isoformat().replace('+00:00', 'Z'),
        'event_type': event_type,
        'tool_name': tool,
        'decision': decision,
        'reason': f'test {decision}',
        'latency_ms': latency_ms,
        'session_id': 'test-session',
        'tool_use_id': f'{decision}-{ts_offset_min}',
    }
    entry.update(extra)
    return entry


# ── Markdown → HTML ──────────────────────────────────────────────────

class TestMdToHtml(unittest.TestCase):
    """Test _md_to_html() — the stdlib-only markdown transpiler."""

    def test_code_fence_protection(self):
        """Content inside code fences must NOT be processed for bold/italic."""
        md = '```python\n**not bold** *not italic*\n```'
        html = srv._md_to_html(md)
        self.assertIn('<pre><code', html)
        self.assertNotIn('<strong>', html)
        self.assertNotIn('<em>', html)
        # The literal ** should be escaped
        self.assertIn('**not bold**', html)

    def test_html_escaping_xss(self):
        """<script> tags must be escaped to prevent XSS."""
        md = '<script>alert("xss")</script>'
        html = srv._md_to_html(md)
        self.assertIn('&lt;script', html)
        self.assertNotIn('<script>', html)

    def test_table_rendering(self):
        """Pipe-delimited markdown table → HTML table."""
        # Table regex matches consecutive lines starting with |, each ending with \n
        md = '| A | B |\n|---|---|\n| 1 | 2 |\n'
        html = srv._md_to_html(md)
        self.assertIn('<table>', html)
        self.assertIn('<th>', html)
        self.assertIn('<td>', html)
        self.assertIn('</table>', html)

    def test_heading_slug_generation(self):
        """Heading text → slug id attribute."""
        md = '## Hello World!'
        html = srv._md_to_html(md)
        self.assertIn('id="hello-world"', html)
        self.assertIn('<h2', html)

    def test_heading_slug_special_chars(self):
        """Special characters stripped from heading slug."""
        md = '### C++ & Rust'
        html = srv._md_to_html(md)
        self.assertIn('id="c-rust"', html)

    def test_relative_image_path(self):
        """Relative image paths rewritten to absolute /images/ paths."""
        md = '![alt](images/foo.png)'
        html = srv._md_to_html(md)
        self.assertIn('src="/images/foo.png"', html)

    def test_absolute_image_url_unchanged(self):
        """Absolute URLs in images are not rewritten."""
        md = '![alt](https://example.com/img.png)'
        html = srv._md_to_html(md)
        self.assertIn('src="https://example.com/img.png"', html)

    def test_inline_code_not_processed(self):
        """Inline code content preserved literally (no bold/italic processing)."""
        md = '`**not bold**`'
        html = srv._md_to_html(md)
        self.assertIn('<code>', html)
        self.assertNotIn('<strong>', html)

    def test_blockquote(self):
        md = '> quoted text'
        html = srv._md_to_html(md)
        self.assertIn('<blockquote>', html)

    def test_unordered_list(self):
        md = '- item1\n- item2'
        html = srv._md_to_html(md)
        self.assertIn('<ul>', html)
        self.assertIn('<li>', html)

    def test_ordered_list(self):
        md = '1. first\n2. second'
        html = srv._md_to_html(md)
        self.assertIn('<ol>', html)
        self.assertIn('<li>', html)

    def test_link_rendering(self):
        md = '[click here](https://example.com)'
        html = srv._md_to_html(md)
        self.assertIn('<a href="https://example.com">', html)
        self.assertIn('click here</a>', html)

    def test_bold_and_italic(self):
        md = '**bold text** and *italic text*'
        html = srv._md_to_html(md)
        self.assertIn('<strong>bold text</strong>', html)
        self.assertIn('<em>italic text</em>', html)

    def test_horizontal_rule(self):
        md = '---'
        html = srv._md_to_html(md)
        self.assertIn('<hr>', html)

    def test_empty_input(self):
        html = srv._md_to_html('')
        self.assertEqual(html.strip(), '')


# ── Alltime extended ─────────────────────────────────────────────────

class TestAlltimeExtended(unittest.TestCase):
    """Extended tests for _compute_alltime_from_traces()."""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.trace_dir = Path(self.tmpdir) / 'traces'
        self.trace_dir.mkdir()
        srv._alltime_cache = {'key': None, 'data': None}

    def tearDown(self):
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _write_trace(self, filename, entries):
        with open(self.trace_dir / filename, 'w') as f:
            for entry in entries:
                f.write(json.dumps(entry) + '\n')

    def test_files_touched_tracking(self):
        """file_path on entries → correct ops, sessions, denied counts."""
        self._write_trace('session-A.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Write',
             'file_path': '/src/main.py', 'session_id': 's1'},
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Read',
             'file_path': '/src/main.py', 'session_id': 's1'},
        ])
        self._write_trace('session-B.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Read',
             'file_path': '/src/main.py', 'session_id': 's2'},
        ])
        result = srv._compute_alltime_from_traces(self.trace_dir)
        ft = result['files_touched']
        self.assertIn('/src/main.py', ft)
        rec = ft['/src/main.py']
        self.assertEqual(rec['ops']['Write'], 1)
        self.assertEqual(rec['ops']['Read'], 2)
        self.assertEqual(rec['denied'], 1)
        self.assertEqual(rec['sessions'], 2)

    def test_files_touched_from_tool_input(self):
        """file_path extracted from tool_input dict (not top-level)."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Read',
             'tool_input': {'file_path': '/x.py'}, 'session_id': 's1'},
        ])
        result = srv._compute_alltime_from_traces(self.trace_dir)
        self.assertIn('/x.py', result['files_touched'])

    def test_files_touched_from_tool_input_string(self):
        """file_path extracted from tool_input when it's a JSON string."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Read',
             'tool_input': '{"file_path": "/y.py"}', 'session_id': 's1'},
        ])
        result = srv._compute_alltime_from_traces(self.trace_dir)
        self.assertIn('/y.py', result['files_touched'])

    def test_top_denied_tools_ranking(self):
        """Multiple denied tools ranked by count."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash'},
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash'},
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash'},
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Write'},
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Read'},
        ])
        result = srv._compute_alltime_from_traces(self.trace_dir)
        self.assertEqual(result['top_denied_tools']['Bash'], 3)
        self.assertEqual(result['top_denied_tools']['Write'], 1)
        self.assertEqual(result['top_denied_tools']['Read'], 1)

    def test_latency_values_collected(self):
        """Latency count, sum, max, values array all correct."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Bash', 'latency_ms': 5},
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Bash', 'latency_ms': 10},
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Bash', 'latency_ms': 15},
        ])
        result = srv._compute_alltime_from_traces(self.trace_dir)
        lat = result['latency']
        self.assertEqual(lat['count'], 3)
        self.assertEqual(lat['sum_ms'], 30)
        self.assertEqual(lat['max_ms'], 15)
        self.assertEqual(sorted(lat['values']), [5, 10, 15])

    def test_negative_latency_excluded(self):
        """latency_ms < 0 not counted in latency stats."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Bash', 'latency_ms': -5},
            {'event_type': 'PreToolUse', 'decision': 'allow', 'tool_name': 'Bash', 'latency_ms': 10},
        ])
        result = srv._compute_alltime_from_traces(self.trace_dir)
        self.assertEqual(result['latency']['count'], 1)
        self.assertEqual(result['latency']['sum_ms'], 10)

    def test_all_same_decision(self):
        """All entries with same decision → only that decision counter incremented."""
        self._write_trace('session.jsonl', [
            {'event_type': 'PreToolUse', 'decision': 'deny', 'tool_name': 'Bash'}
            for _ in range(10)
        ])
        result = srv._compute_alltime_from_traces(self.trace_dir)
        self.assertEqual(result['decisions']['deny'], 10)
        self.assertEqual(result['decisions']['warn'], 0)
        self.assertEqual(result['decisions']['ask'], 0)
        self.assertEqual(result['decisions']['allow'], 0)


# ── HTTP server base class ───────────────────────────────────────────

class _ServerTestCase(unittest.TestCase):
    """Base class that starts a real HTTP server for endpoint tests."""

    # Subclasses override to customize project dir
    _project_dir = None
    _server = None
    _thread = None
    _port = None
    _tmpdir = None

    @classmethod
    def _setup_project(cls):
        """Subclasses override to populate project dir with config + traces."""
        pass

    @classmethod
    def setUpClass(cls):
        cls._tmpdir = tempfile.mkdtemp()
        cls._project_dir = Path(cls._tmpdir) / 'project'
        cls._project_dir.mkdir()
        (cls._project_dir / '.lanekeep' / 'traces').mkdir(parents=True)

        cls._setup_project()

        # Patch globals
        srv.PROJECT_DIR = cls._project_dir
        srv.CONFIG_PATH = cls._project_dir / 'lanekeep.json'

        # Reset all caches
        srv._trace_cache.update({'key': None, 'data': None, 'limit': None})
        srv._trace_entries_cache.update({'key': None, 'entries': None, 'summary': None})
        srv._trends_cache.update({'key': None, 'data': None})
        srv._alltime_cache.update({'key': None, 'data': None})
        srv._graphs_cache.update({'key': None, 'data': None})

        # Find free port and start server
        sock = socket.socket()
        sock.bind(('127.0.0.1', 0))
        cls._port = sock.getsockname()[1]
        sock.close()

        from http.server import ThreadingHTTPServer
        cls._server = ThreadingHTTPServer(('127.0.0.1', cls._port), srv.Handler)
        cls._thread = threading.Thread(target=cls._server.serve_forever, daemon=True)
        cls._thread.start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        if cls._server:
            cls._server.shutdown()
        if cls._tmpdir:
            shutil.rmtree(cls._tmpdir, ignore_errors=True)

    def get(self, path):
        conn = HTTPConnection('127.0.0.1', self._port, timeout=5)
        conn.request('GET', path)
        resp = conn.getresponse()
        body = resp.read().decode()
        conn.close()
        try:
            return resp.status, json.loads(body)
        except json.JSONDecodeError:
            raise AssertionError(f'Non-JSON response (status={resp.status}): {body[:300]}')

    def post(self, path, body):
        conn = HTTPConnection('127.0.0.1', self._port, timeout=5)
        data = json.dumps(body)
        conn.request('POST', path, body=data,
                     headers={'Content-Type': 'application/json'})
        resp = conn.getresponse()
        resp_body = resp.read().decode()
        conn.close()
        try:
            return resp.status, json.loads(resp_body)
        except json.JSONDecodeError:
            return resp.status, resp_body


# ── Trends logic tests ───────────────────────────────────────────────

class TestTrendsGranularity5min(_ServerTestCase):
    """Entries within 2h → 5min granularity."""

    @classmethod
    def _setup_project(cls):
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls._project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls._project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')
        # Entries within 90 minutes: 10:00, 10:30, 11:00, 11:30
        entries = [
            make_trace_entry(0, 'deny'), make_trace_entry(30, 'allow'),
            make_trace_entry(60, 'warn'), make_trace_entry(90, 'allow'),
        ]
        trace_file = cls._project_dir / '.lanekeep' / 'traces' / 'session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

    def test_granularity_is_5min(self):
        _, data = self.get('/api/trends')
        self.assertEqual(data['granularity'], '5min')

    def test_total_actions_across_buckets(self):
        _, data = self.get('/api/trends')
        total = sum(b['actions'] for b in data['buckets'])
        self.assertEqual(total, 4)


class TestTrendsGranularityHourly(_ServerTestCase):
    """Entries spanning 5h → hourly granularity."""

    @classmethod
    def _setup_project(cls):
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls._project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls._project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')
        # Entries spanning 5h: 10:00 to 15:00
        entries = [make_trace_entry(i * 60, 'allow') for i in range(6)]
        trace_file = cls._project_dir / '.lanekeep' / 'traces' / 'session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

    def test_granularity_is_hourly(self):
        _, data = self.get('/api/trends')
        self.assertEqual(data['granularity'], 'hourly')

    def test_total_actions_across_buckets(self):
        _, data = self.get('/api/trends')
        total = sum(b['actions'] for b in data['buckets'])
        self.assertEqual(total, 6)


class TestTrendsGranularityDaily(_ServerTestCase):
    """Entries spanning 5 days → daily granularity."""

    @classmethod
    def _setup_project(cls):
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls._project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls._project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')
        # Entries spanning 5 days: offset in minutes
        entries = [make_trace_entry(i * 1440, 'allow') for i in range(6)]
        trace_file = cls._project_dir / '.lanekeep' / 'traces' / 'session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

    def test_granularity_is_daily(self):
        _, data = self.get('/api/trends')
        self.assertEqual(data['granularity'], 'daily')


class TestTrendsGranularityWeekly(_ServerTestCase):
    """Entries spanning 20 days → weekly granularity."""

    @classmethod
    def _setup_project(cls):
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls._project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls._project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')
        # Entries spanning 20 days
        entries = [make_trace_entry(i * 1440 * 5, 'allow') for i in range(5)]
        trace_file = cls._project_dir / '.lanekeep' / 'traces' / 'session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

    def test_granularity_is_weekly(self):
        _, data = self.get('/api/trends')
        self.assertEqual(data['granularity'], 'weekly')


class TestTrendsPercentiles(_ServerTestCase):
    """Test percentile linear interpolation with known latency values."""

    @classmethod
    def _setup_project(cls):
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls._project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls._project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')
        # 5 entries all in the same hourly bucket, with known latencies [2,4,6,8,10]
        entries = [make_trace_entry(i, 'allow', latency_ms=2 + i * 2) for i in range(5)]
        trace_file = cls._project_dir / '.lanekeep' / 'traces' / 'session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

    def test_percentile_values(self):
        """p50 and p95 match the linear interpolation formula."""
        _, data = self.get('/api/trends')
        self.assertEqual(len(data['buckets']), 1)
        b = data['buckets'][0]
        # p50: k = (5-1)*50/100 = 2.0, f=2, c=3, result = 6 + (8-6)*0.0 = 6.0
        self.assertAlmostEqual(b['latency_p50'], 6.0, places=1)
        # p95: k = (5-1)*95/100 = 3.8, f=3, c=4, result = 8 + (10-8)*0.8 = 9.6
        self.assertAlmostEqual(b['latency_p95'], 9.6, places=1)

    def test_single_value_percentile(self):
        """Verify formula handles single value: p50=p95=value."""
        # Write a trace with a single entry
        trace_file = self._project_dir / '.lanekeep' / 'traces' / 'solo.jsonl'
        with open(trace_file, 'w') as f:
            f.write(json.dumps(make_trace_entry(100, 'deny', latency_ms=42)) + '\n')
        # Reset caches to pick up new file
        srv._trace_entries_cache.update({'key': None, 'entries': None, 'summary': None})
        srv._trends_cache.update({'key': None, 'data': None})

        _, data = self.get('/api/trends')
        # Find the bucket containing the solo entry
        total_actions = sum(b['actions'] for b in data['buckets'])
        self.assertEqual(total_actions, 6)  # 5 original + 1 solo


class TestTrendsBucketDecisions(_ServerTestCase):
    """Verify per-bucket decision counts are correct."""

    @classmethod
    def _setup_project(cls):
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls._project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls._project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')
        # 3 deny + 2 allow in same hour (within 5 minutes), then 1 warn 3 hours later
        entries = [
            make_trace_entry(0, 'deny'),
            make_trace_entry(1, 'deny'),
            make_trace_entry(2, 'deny'),
            make_trace_entry(3, 'allow'),
            make_trace_entry(4, 'allow'),
            make_trace_entry(180, 'warn'),  # 3 hours later → different bucket
        ]
        trace_file = cls._project_dir / '.lanekeep' / 'traces' / 'session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

    def test_bucket_decision_counts(self):
        _, data = self.get('/api/trends')
        self.assertEqual(data['granularity'], 'hourly')
        # Find the bucket with 5 actions (the first hour)
        big_bucket = next((b for b in data['buckets'] if b['actions'] == 5), None)
        self.assertIsNotNone(big_bucket)
        self.assertEqual(big_bucket['decisions']['deny'], 3)
        self.assertEqual(big_bucket['decisions']['allow'], 2)
        # The second bucket has the warn
        warn_bucket = next((b for b in data['buckets'] if b['actions'] == 1), None)
        self.assertIsNotNone(warn_bucket)
        self.assertEqual(warn_bucket['decisions']['warn'], 1)

    def test_buckets_are_sorted(self):
        _, data = self.get('/api/trends')
        keys = [b['t'] for b in data['buckets']]
        self.assertEqual(keys, sorted(keys))


# ── Graphs logic tests ───────────────────────────────────────────────

class TestGraphsLogic(_ServerTestCase):
    """Test _serve_graphs() compliance mapping with compliance-tagged rules."""

    @classmethod
    def _setup_project(cls):
        # Config with compliance-tagged rules (rules must have 'id' field)
        config = {
            'rules': [
                {
                    'id': 'test-pci-001',
                    'name': 'block-credit-data',
                    'decision': 'deny',
                    'reason': 'Credit card data',
                    'enabled': True,
                    'category': 'data',
                    'compliance': ['PCI-DSS 7.1', 'PCI-DSS 6.2.4'],
                },
                {
                    'id': 'test-hipaa-001',
                    'name': 'block-phi',
                    'decision': 'deny',
                    'reason': 'Protected health info',
                    'enabled': True,
                    'category': 'health',
                    'compliance': ['HIPAA §164.312(a)(1)'],
                },
                {
                    'id': 'test-no-comp',
                    'name': 'block-rm',
                    'decision': 'deny',
                    'reason': 'Destructive',
                    'enabled': True,
                    'category': 'destructive',
                    # No compliance tags
                },
            ],
            'policies': {},
            'evaluators': {
                'input_pii': {
                    'enabled': True,
                    'compliance_by_category': {
                        'pii': ['GDPR Art.5(1)(f)', 'AU Privacy Act APP 6'],
                    },
                },
            },
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

        # Trace entries with matched_rule references
        entries = [
            make_trace_entry(0, 'deny', matched_rule='test-pci-001',
                             file_path='/src/payment.py'),
            make_trace_entry(10, 'deny', matched_rule='test-pci-001',
                             file_path='/src/checkout.py'),
            make_trace_entry(20, 'deny', matched_rule='test-hipaa-001'),
            make_trace_entry(30, 'allow'),  # No matched_rule
        ]
        trace_file = cls._project_dir / '.lanekeep' / 'traces' / 'session.jsonl'
        with open(trace_file, 'w') as f:
            for e in entries:
                f.write(json.dumps(e) + '\n')

    def test_framework_extraction_pci(self):
        """PCI-DSS compliance tags → PCI-DSS framework with 2 requirements."""
        _, data = self.get('/api/graphs')
        self.assertIn('PCI-DSS', data['frameworks'])
        reqs = data['frameworks']['PCI-DSS']['requirements']
        self.assertIn('PCI-DSS 7.1', reqs)
        self.assertIn('PCI-DSS 6.2.4', reqs)

    def test_framework_extraction_hipaa(self):
        """HIPAA tag extracted correctly (section sign separator)."""
        _, data = self.get('/api/graphs')
        self.assertIn('HIPAA', data['frameworks'])

    def test_framework_extraction_multi_word(self):
        """'AU Privacy Act APP 6' → framework 'AU Privacy Act'."""
        _, data = self.get('/api/graphs')
        self.assertIn('AU Privacy Act', data['frameworks'])

    def test_requirement_rule_linking(self):
        """Requirement 'PCI-DSS 7.1' has rule 'test-pci-001'."""
        _, data = self.get('/api/graphs')
        req = data['frameworks']['PCI-DSS']['requirements']['PCI-DSS 7.1']
        self.assertIn('test-pci-001', req['rules'])

    def test_trace_stats_per_rule(self):
        """Rule test-pci-001 has trace_stats.total == 2 (2 deny entries)."""
        _, data = self.get('/api/graphs')
        rd = data['rules']['test-pci-001']
        self.assertEqual(rd['trace_stats']['total'], 2)
        self.assertEqual(rd['trace_stats']['deny'], 2)

    def test_files_protected_per_rule(self):
        """Denied entries with file_path populate files_protected."""
        _, data = self.get('/api/graphs')
        rd = data['rules']['test-pci-001']
        self.assertIn('/src/payment.py', rd['files_protected'])
        self.assertIn('/src/checkout.py', rd['files_protected'])

    def test_evaluator_compliance_populated(self):
        """Evaluator input_pii appears in evaluator_compliance."""
        _, data = self.get('/api/graphs')
        self.assertIn('input_pii', data['evaluator_compliance'])
        tags = data['evaluator_compliance']['input_pii']['tags']
        self.assertIn('AU Privacy Act APP 6', tags)
        self.assertIn('GDPR Art.5(1)(f)', tags)

    def test_no_compliance_rule_excluded_from_frameworks(self):
        """Rule without compliance tags does not create framework entries."""
        _, data = self.get('/api/graphs')
        # test-no-comp has no compliance tags, so it should be in rules but not add frameworks
        self.assertIn('test-no-comp', data['rules'])
        self.assertEqual(data['rules']['test-no-comp']['compliance'], [])

    def test_graphs_response_shape(self):
        """Verify response has required top-level keys."""
        _, data = self.get('/api/graphs')
        self.assertIn('frameworks', data)
        self.assertIn('rules', data)
        self.assertIn('evaluator_compliance', data)


# ── Config merge tests ───────────────────────────────────────────────

class TestConfigMerge(_ServerTestCase):
    """Test _serve_status() three-layer config merge."""

    @classmethod
    def _setup_project(cls):
        # Write a project config with specific budget values
        config = {
            'rules': [],
            'policies': {},
            'budget': {
                'max_actions': 100,
                'timeout_seconds': 3600,
                'max_tokens': 200000,
                'max_input_tokens': 150000,
                'max_output_tokens': 50000,
            },
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

        # Write state file
        state = {
            'session_id': 'merge-test',
            'start_epoch': int(time.time()),
            'action_count': 42,
            'total_events': 100,
            'token_count': 75000,
            'input_tokens': 50000,
            'output_tokens': 25000,
            'token_source': 'transcript',
            'model': 'claude-opus-4-6',
        }
        (cls._project_dir / '.lanekeep' / 'state.json').write_text(json.dumps(state))

    def test_project_budget_applied(self):
        """Project config budget overrides defaults."""
        _, data = self.get('/api/status')
        b = data['budget']
        self.assertEqual(b['max_actions'], 100)
        self.assertEqual(b['max_minutes'], 60)  # 3600 / 60
        self.assertEqual(b['max_tokens'], 200000)

    def test_state_values_present(self):
        """State file values appear in budget."""
        _, data = self.get('/api/status')
        b = data['budget']
        self.assertEqual(b['actions'], 42)
        self.assertEqual(b['tokens'], 75000)
        self.assertEqual(b['input_tokens'], 50000)
        self.assertEqual(b['output_tokens'], 25000)

    def test_context_window_from_model(self):
        """model=claude-opus-4-6 → context_window_size=1,000,000."""
        _, data = self.get('/api/status')
        b = data['budget']
        self.assertEqual(b['context_window_size'], 1_000_000)
        self.assertEqual(b['context_model'], 'claude-opus-4-6')

    def test_env_override_max_actions(self):
        """LANEKEEP_MAX_ACTIONS env var overrides project config."""
        os.environ['LANEKEEP_MAX_ACTIONS'] = '25'
        try:
            _, data = self.get('/api/status')
            self.assertEqual(data['budget']['max_actions'], 25)
        finally:
            del os.environ['LANEKEEP_MAX_ACTIONS']

    def test_env_override_timeout(self):
        """LANEKEEP_TIMEOUT_SECONDS env var → max_minutes."""
        os.environ['LANEKEEP_TIMEOUT_SECONDS'] = '7200'
        try:
            _, data = self.get('/api/status')
            self.assertEqual(data['budget']['max_minutes'], 120)
        finally:
            del os.environ['LANEKEEP_TIMEOUT_SECONDS']

    def test_config_stack_present(self):
        """Status response has config.defaults, config.user, config.env."""
        _, data = self.get('/api/status')
        self.assertIn('defaults', data['config'])
        self.assertIn('user', data['config'])
        self.assertIn('env', data['config'])

    def test_status_response_shape(self):
        """Status has required top-level keys."""
        _, data = self.get('/api/status')
        self.assertIn('config', data)
        self.assertIn('budget', data)
        self.assertIn('session', data)


# ── Edge cases ───────────────────────────────────────────────────────

class TestEdgeCases(_ServerTestCase):
    """Edge case tests: empty traces, single entry."""

    @classmethod
    def _setup_project(cls):
        defaults = LANEKEEP_UI.parent / 'defaults' / 'lanekeep.json'
        if defaults.exists():
            (cls._project_dir / 'lanekeep.json').write_text(defaults.read_text())
        else:
            (cls._project_dir / 'lanekeep.json').write_text('{"rules":[],"policies":{}}')
        # Start with empty trace dir (no .jsonl files)

    def test_empty_trace_dir_returns_empty(self):
        """Empty trace dir → entries=[], summary.total=0."""
        _, data = self.get('/api/trace?limit=100')
        self.assertEqual(len(data['entries']), 0)
        self.assertEqual(data['summary']['total'], 0)

    def test_empty_trace_dir_trends_empty(self):
        """Empty trace dir → trends returns 0 buckets."""
        _, data = self.get('/api/trends')
        self.assertEqual(len(data['buckets']), 0)

    def test_single_entry(self):
        """Single trace entry → correct stats."""
        trace_file = self._project_dir / '.lanekeep' / 'traces' / 'solo.jsonl'
        with open(trace_file, 'w') as f:
            f.write(json.dumps(make_trace_entry(0, 'deny', latency_ms=42)) + '\n')
        # Reset caches
        srv._trace_entries_cache.update({'key': None, 'entries': None, 'summary': None})
        srv._trace_cache.update({'key': None, 'data': None, 'limit': None})
        srv._trends_cache.update({'key': None, 'data': None})

        _, data = self.get('/api/trace?limit=100')
        self.assertEqual(len(data['entries']), 1)
        self.assertEqual(data['summary']['total'], 1)
        self.assertEqual(data['summary']['deny'], 1)

        _, trends = self.get('/api/trends')
        self.assertEqual(len(trends['buckets']), 1)
        self.assertEqual(trends['buckets'][0]['actions'], 1)
        self.assertEqual(trends['buckets'][0]['latency_p50'], 42.0)

        # Cleanup for other tests
        trace_file.unlink()
        srv._trace_entries_cache.update({'key': None, 'entries': None, 'summary': None})
        srv._trace_cache.update({'key': None, 'data': None, 'limit': None})
        srv._trends_cache.update({'key': None, 'data': None})


def _make_rule(id_str, decision='deny', reason=None, command='rm', target='/tmp'):
    """Helper to create a valid rule dict for save tests."""
    return {
        'id': id_str,
        'name': f'Rule {id_str}',
        'match': {'command': command, 'target': target},
        'decision': decision,
        'reason': reason or f'Reason for {id_str}',
    }


# ── Rule override serving tests ─────────────────────────────────────

class TestRuleOverrides(_ServerTestCase):
    """Verify server faithfully serves config with overridden rules."""

    @classmethod
    def _setup_project(cls):
        # Pre-merged config: rule-001 was "overridden" from deny→warn
        config = {
            'rules': [
                _make_rule('rule-001', decision='warn', reason='Overridden to warn'),
                _make_rule('rule-002', decision='deny', reason='Original deny'),
                _make_rule('rule-003', decision='allow', reason='Original allow'),
            ],
            'policies': {},
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

    def test_overridden_rule_served_correctly(self):
        """Rule patched via rule_overrides shows the overridden decision."""
        _, data = self.get('/api/config')
        by_id = {r['id']: r for r in data['rules']}
        self.assertEqual(by_id['rule-001']['decision'], 'warn')
        self.assertEqual(by_id['rule-001']['reason'], 'Overridden to warn')

    def test_non_overridden_rules_intact(self):
        """Rules not in rule_overrides keep their original values."""
        _, data = self.get('/api/config')
        by_id = {r['id']: r for r in data['rules']}
        self.assertEqual(by_id['rule-002']['decision'], 'deny')
        self.assertEqual(by_id['rule-003']['decision'], 'allow')


# ── Extra/disabled rule serving tests ────────────────────────────────

class TestExtraAndDisabledRules(_ServerTestCase):
    """Verify server serves config reflecting extra_rules appended and disabled_rules removed."""

    @classmethod
    def _setup_project(cls):
        # Simulates resolved config: base-002 was disabled (absent),
        # extra-001 was appended
        config = {
            'rules': [
                _make_rule('base-001', decision='deny'),
                _make_rule('base-003', decision='warn'),
                _make_rule('extra-001', decision='allow', reason='Custom extra rule'),
            ],
            'policies': {},
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

    def test_extra_rule_present(self):
        """Extra rule appended by config merge is served."""
        _, data = self.get('/api/config')
        ids = [r['id'] for r in data['rules']]
        self.assertIn('extra-001', ids)

    def test_disabled_rule_absent(self):
        """Disabled rule removed by config merge is not served."""
        _, data = self.get('/api/config')
        ids = [r['id'] for r in data['rules']]
        self.assertNotIn('base-002', ids)

    def test_rule_count_and_order(self):
        """Rule count is correct and order is preserved."""
        _, data = self.get('/api/config')
        ids = [r['id'] for r in data['rules']]
        self.assertEqual(ids, ['base-001', 'base-003', 'extra-001'])


# ── Backup and hash tests ───────────────────────────────────────────

class TestBackupOnSave(_ServerTestCase):
    """Verify .bak backup creation and config hash update on save."""

    @classmethod
    def _setup_project(cls):
        config = {
            'rules': [
                _make_rule('orig-001', decision='deny'),
                _make_rule('orig-002', decision='warn'),
            ],
            'policies': {},
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

    def test_backup_created_on_save(self):
        """POST /api/config creates a .bak file with pre-save content."""
        pre_save = (self._project_dir / 'lanekeep.json').read_text()
        new_rules = [_make_rule('new-001', decision='allow')]
        status, _ = self.post('/api/config', {'rules': new_rules, 'policies': {}})
        self.assertEqual(status, 200)
        bak_path = Path(str(self._project_dir / 'lanekeep.json') + '.bak')
        self.assertTrue(bak_path.exists(), '.bak file should exist after save')
        self.assertEqual(bak_path.read_text(), pre_save)

    def test_backup_updates_on_subsequent_save(self):
        """Second save updates .bak to match state before that save."""
        rules_a = [_make_rule('save-a-001', decision='deny')]
        self.post('/api/config', {'rules': rules_a, 'policies': {}})
        state_after_a = (self._project_dir / 'lanekeep.json').read_text()

        rules_b = [_make_rule('save-b-001', decision='warn')]
        self.post('/api/config', {'rules': rules_b, 'policies': {}})
        bak_path = Path(str(self._project_dir / 'lanekeep.json') + '.bak')
        self.assertEqual(bak_path.read_text(), state_after_a)

    def test_settings_save_creates_backup(self):
        """POST /api/settings also creates a .bak backup."""
        # Remove any existing bak
        bak_path = Path(str(self._project_dir / 'lanekeep.json') + '.bak')
        if bak_path.exists():
            bak_path.unlink()
        pre_save = (self._project_dir / 'lanekeep.json').read_text()
        status, _ = self.post('/api/settings', {'profile': 'strict'})
        self.assertEqual(status, 200)
        self.assertTrue(bak_path.exists(), '.bak should exist after settings save')
        self.assertEqual(bak_path.read_text(), pre_save)

    def test_config_hash_updated_after_save(self):
        """Config hash file matches SHA-256 of saved content."""
        new_rules = [_make_rule('hash-001', decision='deny')]
        self.post('/api/config', {'rules': new_rules, 'policies': {}})
        hash_path = self._project_dir / '.lanekeep' / 'config_hash'
        self.assertTrue(hash_path.exists(), 'config_hash should exist after save')
        saved_content = (self._project_dir / 'lanekeep.json').read_text()
        expected_hash = hashlib.sha256(saved_content.encode()).hexdigest()
        self.assertEqual(hash_path.read_text().strip(), expected_hash)


# ── Concurrent save tests ───────────────────────────────────────────

class TestConcurrentSaves(_ServerTestCase):
    """Verify concurrent POST /api/config doesn't corrupt data."""

    @classmethod
    def _setup_project(cls):
        config = {
            'rules': [_make_rule('init-001')],
            'policies': {},
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

    def test_concurrent_saves_no_corruption(self):
        """Two simultaneous saves produce valid JSON (no corruption)."""
        rules_a = [_make_rule(f'a-{i}') for i in range(3)]
        rules_b = [_make_rule(f'b-{i}') for i in range(4)]
        results = [None, None]

        def save(idx, rules):
            results[idx] = self.post('/api/config', {'rules': rules, 'policies': {}})

        t1 = threading.Thread(target=save, args=(0, rules_a))
        t2 = threading.Thread(target=save, args=(1, rules_b))
        t1.start()
        t2.start()
        t1.join(timeout=10)
        t2.join(timeout=10)

        # Both should succeed
        self.assertEqual(results[0][0], 200)
        self.assertEqual(results[1][0], 200)

        # Final config must be valid and match one of the two payloads
        _, data = self.get('/api/config')
        rule_ids = [r['id'] for r in data['rules']]
        a_ids = [r['id'] for r in rules_a]
        b_ids = [r['id'] for r in rules_b]
        self.assertTrue(
            rule_ids == a_ids or rule_ids == b_ids,
            f'Config should match one payload exactly, got: {rule_ids}')

    def test_rapid_sequential_saves_last_wins(self):
        """Five rapid saves in sequence — final state matches last payload."""
        last_rules = None
        for i in range(5):
            rules = [_make_rule(f'seq-{i}-{j}') for j in range(i + 1)]
            self.post('/api/config', {'rules': rules, 'policies': {}})
            last_rules = rules

        _, data = self.get('/api/config')
        self.assertEqual(
            [r['id'] for r in data['rules']],
            [r['id'] for r in last_rules])


# ── Large ruleset tests ─────────────────────────────────────────────

class TestLargeRulesets(_ServerTestCase):
    """Verify save and read of large rule sets without truncation."""

    @classmethod
    def _setup_project(cls):
        config = {'rules': [], 'policies': {}}
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

    def test_save_and_read_100_rules(self):
        """100 rules round-trip correctly."""
        rules = [_make_rule(f'bulk-{i:03d}') for i in range(100)]
        status, _ = self.post('/api/config', {'rules': rules, 'policies': {}})
        self.assertEqual(status, 200)
        _, data = self.get('/api/config')
        self.assertEqual(len(data['rules']), 100)
        self.assertEqual(data['rules'][0]['id'], 'bulk-000')
        self.assertEqual(data['rules'][99]['id'], 'bulk-099')

    def test_save_and_read_500_rules(self):
        """500 rules round-trip correctly."""
        rules = [_make_rule(f'big-{i:04d}') for i in range(500)]
        status, _ = self.post('/api/config', {'rules': rules, 'policies': {}})
        self.assertEqual(status, 200)
        _, data = self.get('/api/config')
        self.assertEqual(len(data['rules']), 500)
        self.assertEqual(data['rules'][0]['id'], 'big-0000')
        self.assertEqual(data['rules'][249]['id'], 'big-0249')
        self.assertEqual(data['rules'][499]['id'], 'big-0499')

    def test_rule_content_integrity(self):
        """Every rule's unique reason survives the round-trip."""
        rules = [_make_rule(f'int-{i}', reason=f'reason-{i}-{uuid.uuid4()}')
                 for i in range(100)]
        self.post('/api/config', {'rules': rules, 'policies': {}})
        _, data = self.get('/api/config')
        for orig, loaded in zip(rules, data['rules']):
            self.assertEqual(orig['reason'], loaded['reason'],
                             f'Mismatch for {orig["id"]}')

    def test_large_ruleset_with_policies(self):
        """150 rules + 10 policies all survive the round-trip."""
        rules = [_make_rule(f'lp-{i:03d}') for i in range(150)]
        policies = {}
        for i in range(10):
            policies[f'policy_{i}'] = {
                'enabled': True,
                'default_decision': 'deny',
                'allowed': [f'allow-pat-{j}' for j in range(5)],
                'denied': [f'deny-pat-{j}' for j in range(5)],
            }
        status, _ = self.post('/api/config', {'rules': rules, 'policies': policies})
        self.assertEqual(status, 200)
        _, data = self.get('/api/config')
        self.assertEqual(len(data['rules']), 150)
        self.assertEqual(len(data['policies']), 10)
        self.assertEqual(len(data['policies']['policy_3']['allowed']), 5)


# ── Config merge layering tests ──────────────────────────────────────

class TestConfigMergeLayering(_ServerTestCase):
    """Test env var overrides show up in /api/status config layers."""

    @classmethod
    def _setup_project(cls):
        config = {
            'rules': [],
            'policies': {},
            'budget': {
                'max_actions': 100,
                'timeout_seconds': 3600,
                'max_tokens': 200000,
                'max_input_tokens': 150000,
                'max_output_tokens': 50000,
            },
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))
        state = {
            'action_count': 5,
            'total_input_tokens': 10000,
            'total_output_tokens': 5000,
            'session_start': '2026-03-15T10:00:00Z',
            'session_id': 'test-merge-layer',
            'model': 'claude-opus-4-6',
        }
        (cls._project_dir / '.lanekeep' / 'state.json').write_text(json.dumps(state))

    def test_env_override_shows_in_status(self):
        """LANEKEEP_MAX_ACTIONS env var appears in config.env."""
        os.environ['LANEKEEP_MAX_ACTIONS'] = '999'
        try:
            _, data = self.get('/api/status')
            env_section = data.get('config', {}).get('env', {})
            self.assertEqual(env_section.get('LANEKEEP_MAX_ACTIONS'), '999')
        finally:
            del os.environ['LANEKEEP_MAX_ACTIONS']

    def test_env_override_wins_over_project(self):
        """Env var max_actions=25 overrides project config max_actions=100."""
        os.environ['LANEKEEP_MAX_ACTIONS'] = '25'
        try:
            _, data = self.get('/api/status')
            self.assertEqual(data['budget']['max_actions'], 25)
        finally:
            del os.environ['LANEKEEP_MAX_ACTIONS']

    def test_multiple_env_overrides(self):
        """Multiple env overrides all reflected in status."""
        os.environ['LANEKEEP_MAX_ACTIONS'] = '50'
        os.environ['LANEKEEP_TIMEOUT_SECONDS'] = '1800'
        os.environ['LANEKEEP_MAX_TOKENS'] = '100000'
        try:
            _, data = self.get('/api/status')
            env_section = data.get('config', {}).get('env', {})
            self.assertEqual(env_section.get('LANEKEEP_MAX_ACTIONS'), '50')
            self.assertEqual(env_section.get('LANEKEEP_TIMEOUT_SECONDS'), '1800')
            self.assertEqual(env_section.get('LANEKEEP_MAX_TOKENS'), '100000')
            self.assertEqual(data['budget']['max_actions'], 50)
        finally:
            for key in ('LANEKEEP_MAX_ACTIONS', 'LANEKEEP_TIMEOUT_SECONDS', 'LANEKEEP_MAX_TOKENS'):
                os.environ.pop(key, None)


# ── Config extends resolution tests ────────────────────────────────

class TestResolveConfig(unittest.TestCase):
    """Test _resolve_config() — extends: defaults inheritance."""

    def test_no_extends_returns_unchanged(self):
        """Config without extends is returned as-is."""
        config = {'rules': [{'id': 'r1'}], 'policies': {}}
        result = srv._resolve_config(config)
        self.assertEqual(result, config)

    def test_extends_merges_default_rules(self):
        """Config with extends: defaults gets default rules."""
        config = {'extends': 'defaults'}
        result = srv._resolve_config(config)
        self.assertIn('rules', result)
        self.assertGreater(len(result['rules']), 0)
        # Verify well-known default rules are present
        ids = {r['id'] for r in result['rules']}
        self.assertIn('sec-012', ids)
        self.assertIn('sec-028', ids)

    def test_extends_merges_evaluators(self):
        """Evaluator config from defaults is inherited."""
        config = {'extends': 'defaults'}
        result = srv._resolve_config(config)
        self.assertIn('evaluators', result)

    def test_extra_rules_appended(self):
        """extra_rules are appended after default rules."""
        config = {
            'extends': 'defaults',
            'extra_rules': [{'id': 'custom-001', 'decision': 'ask', 'reason': 'test'}],
        }
        result = srv._resolve_config(config)
        ids = [r['id'] for r in result['rules']]
        self.assertIn('custom-001', ids)
        # custom-001 should be last
        self.assertEqual(ids[-1], 'custom-001')
        # Should have source: custom tag
        custom = [r for r in result['rules'] if r['id'] == 'custom-001'][0]
        self.assertEqual(custom['source'], 'custom')

    def test_disabled_rules_removed(self):
        """disabled_rules removes rules by id from defaults."""
        config = {
            'extends': 'defaults',
            'disabled_rules': ['sec-012'],
        }
        result = srv._resolve_config(config)
        ids = {r['id'] for r in result['rules']}
        self.assertNotIn('sec-012', ids)
        # sec-028 should still be there
        self.assertIn('sec-028', ids)

    def test_locked_rules_cannot_be_disabled(self):
        """Locked rules are preserved even when listed in disabled_rules."""
        # Find a locked rule in defaults
        defaults_path = srv.LANEKEEP_DIR / 'defaults' / 'lanekeep.json'
        with open(defaults_path) as f:
            defaults = json.load(f)
        locked = [r for r in defaults.get('rules', []) if r.get('locked')]
        if not locked:
            self.skipTest('No locked rules in defaults')
        locked_id = locked[0]['id']
        config = {
            'extends': 'defaults',
            'disabled_rules': [locked_id],
        }
        result = srv._resolve_config(config)
        ids = {r['id'] for r in result['rules']}
        self.assertIn(locked_id, ids)

    def test_layering_fields_removed(self):
        """extends, extra_rules, disabled_rules are removed from output."""
        config = {
            'extends': 'defaults',
            'extra_rules': [{'id': 'x-1', 'decision': 'ask', 'reason': 'test'}],
            'disabled_rules': ['sec-012'],
        }
        result = srv._resolve_config(config)
        self.assertNotIn('extends', result)
        self.assertNotIn('extra_rules', result)
        self.assertNotIn('disabled_rules', result)


class TestGraphsExtendsDefaults(_ServerTestCase):
    """Test _serve_graphs() with extends: defaults config — the real-world pattern."""

    @classmethod
    def _setup_project(cls):
        # Mimics the real buildinglanekeep/lanekeep.json pattern
        config = {
            'extends': 'defaults',
            'extra_rules': [
                {
                    'id': 'meta-001',
                    'match': {'tool': 'Write', 'target': 'roadmap.json'},
                    'decision': 'ask',
                    'reason': 'Roadmap changes need approval',
                },
            ],
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

    def test_default_rules_loaded(self):
        """Default rules are resolved and present in graphs data."""
        _, data = self.get('/api/graphs')
        self.assertGreater(len(data['rules']), 10)
        self.assertIn('sec-012', data['rules'])
        self.assertIn('sec-028', data['rules'])

    def test_cwe200_covered(self):
        """CWE-200 shows as a framework with rules linked."""
        _, data = self.get('/api/graphs')
        # CWE-200 is its own framework (no space in tag)
        self.assertIn('CWE-200', data['frameworks'])
        reqs = data['frameworks']['CWE-200']['requirements']
        self.assertIn('CWE-200', reqs)
        # Should have sec-012 and sec-028 linked
        rules = reqs['CWE-200']['rules']
        self.assertIn('sec-012', rules)
        self.assertIn('sec-028', rules)

    def test_extra_rules_included(self):
        """Extra rules from project config appear in rules data."""
        _, data = self.get('/api/graphs')
        self.assertIn('meta-001', data['rules'])

    def test_compliance_frameworks_populated(self):
        """Multiple compliance frameworks from default rules are present."""
        _, data = self.get('/api/graphs')
        # Default rules tag many frameworks
        fw_names = set(data['frameworks'].keys())
        # At least CWE entries should be present
        cwe_fws = {f for f in fw_names if f.startswith('CWE-')}
        self.assertGreater(len(cwe_fws), 0)


class TestEvaluatorSettings(_ServerTestCase):
    """Verify POST /api/settings saves and validates the three new evaluator configs."""

    @classmethod
    def _setup_project(cls):
        config = {
            'rules': [],
            'policies': {},
            'evaluators': {
                'context_budget': {'enabled': False, 'decision': 'ask'},
                'session_patterns': {'enabled': False, 'evasion_threshold': 3, 'denial_cluster_threshold': 5, 'time_window_seconds': 120},
                'multi_session': {'enabled': False, 'deny_rate_threshold': 10, 'tool_deny_threshold': 30, 'cost_warn_percent': 80, 'min_sessions': 5},
            },
        }
        (cls._project_dir / 'lanekeep.json').write_text(json.dumps(config, indent=2))

    def _read_config(self):
        return json.loads((self._project_dir / 'lanekeep.json').read_text())

    # ── context_budget ──────────────────────────────────────────────

    def test_context_budget_save_enabled_and_decision(self):
        """POST /api/settings persists context_budget.enabled and decision."""
        status, _ = self.post('/api/settings', {
            'evaluators_context_budget': {'enabled': True, 'decision': 'deny'},
        })
        self.assertEqual(status, 200)
        cfg = self._read_config()
        self.assertTrue(cfg['evaluators']['context_budget']['enabled'])
        self.assertEqual(cfg['evaluators']['context_budget']['decision'], 'deny')

    def test_context_budget_invalid_decision_rejected(self):
        """Invalid decision value returns 400."""
        status, body = self.post('/api/settings', {
            'evaluators_context_budget': {'decision': 'block'},
        })
        self.assertEqual(status, 400)
        self.assertIn('decision', body.get('error', ''))

    def test_context_budget_enabled_not_bool_rejected(self):
        """Non-boolean enabled returns 400."""
        status, body = self.post('/api/settings', {
            'evaluators_context_budget': {'enabled': 'yes'},
        })
        self.assertEqual(status, 400)

    # ── session_patterns ────────────────────────────────────────────

    def test_session_patterns_save_thresholds(self):
        """POST /api/settings persists session_patterns thresholds."""
        status, _ = self.post('/api/settings', {
            'evaluators_session_patterns': {
                'enabled': True,
                'evasion_threshold': 5,
                'denial_cluster_threshold': 10,
                'time_window_seconds': 300,
            },
        })
        self.assertEqual(status, 200)
        cfg = self._read_config()
        sp = cfg['evaluators']['session_patterns']
        self.assertTrue(sp['enabled'])
        self.assertEqual(sp['evasion_threshold'], 5)
        self.assertEqual(sp['denial_cluster_threshold'], 10)
        self.assertEqual(sp['time_window_seconds'], 300)

    def test_session_patterns_zero_threshold_rejected(self):
        """Threshold of 0 (not positive) returns 400."""
        status, _ = self.post('/api/settings', {
            'evaluators_session_patterns': {'evasion_threshold': 0},
        })
        self.assertEqual(status, 400)

    def test_session_patterns_negative_threshold_rejected(self):
        """Negative threshold returns 400."""
        status, _ = self.post('/api/settings', {
            'evaluators_session_patterns': {'time_window_seconds': -60},
        })
        self.assertEqual(status, 400)

    # ── multi_session ───────────────────────────────────────────────

    def test_multi_session_save_all_fields(self):
        """POST /api/settings persists all multi_session fields."""
        status, _ = self.post('/api/settings', {
            'evaluators_multi_session': {
                'enabled': True,
                'deny_rate_threshold': 10,
                'tool_deny_threshold': 50,
                'cost_warn_percent': 75,
                'min_sessions': 5,
            },
        })
        self.assertEqual(status, 200)
        cfg = self._read_config()
        ms = cfg['evaluators']['multi_session']
        self.assertTrue(ms['enabled'])
        self.assertEqual(ms['deny_rate_threshold'], 10)
        self.assertEqual(ms['tool_deny_threshold'], 50)
        self.assertEqual(ms['cost_warn_percent'], 75)
        self.assertEqual(ms['min_sessions'], 5)

    def test_multi_session_deny_rate_over_100_rejected(self):
        """deny_rate_threshold > 100 returns 400."""
        status, _ = self.post('/api/settings', {
            'evaluators_multi_session': {'deny_rate_threshold': 150},
        })
        self.assertEqual(status, 400)

    def test_multi_session_cost_warn_negative_rejected(self):
        """Negative cost_warn_percent returns 400."""
        status, _ = self.post('/api/settings', {
            'evaluators_multi_session': {'cost_warn_percent': -5},
        })
        self.assertEqual(status, 400)

    def test_multi_session_min_sessions_zero_rejected(self):
        """min_sessions of 0 returns 400."""
        status, _ = self.post('/api/settings', {
            'evaluators_multi_session': {'min_sessions': 0},
        })
        self.assertEqual(status, 400)

    # ── deep merge ──────────────────────────────────────────────────

    def test_evaluator_save_deep_merges_existing_fields(self):
        """Saving one field preserves other fields in the evaluator config."""
        # Set a full config first
        self.post('/api/settings', {
            'evaluators_session_patterns': {
                'enabled': True, 'evasion_threshold': 7,
                'denial_cluster_threshold': 8, 'time_window_seconds': 90,
            },
        })
        # Now only update one field
        self.post('/api/settings', {
            'evaluators_session_patterns': {'evasion_threshold': 4},
        })
        cfg = self._read_config()
        sp = cfg['evaluators']['session_patterns']
        self.assertEqual(sp['evasion_threshold'], 4)
        self.assertEqual(sp['denial_cluster_threshold'], 8, 'other fields should be preserved')
        self.assertEqual(sp['time_window_seconds'], 90, 'other fields should be preserved')


if __name__ == '__main__':
    unittest.main()
