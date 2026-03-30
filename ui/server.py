#!/usr/bin/env python3
"""Minimal API server for LaneKeep Rules UI. No dependencies beyond stdlib."""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import html as html_mod
import json
import os
import re
import secrets
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

# Regex to detect nested quantifiers (ReDoS risk)
_REDOS_PATTERN = re.compile(r'\([^)]*[+*]\)[+*?]|\(\?[^)]*[+*]\)[+*?]')

MAX_BODY = 10 * 1024 * 1024  # 10 MB
MAX_BOOKMARKS = 100
VALID_DECISIONS = {'deny', 'warn', 'ask', 'allow'}

# Model name → context window size (tokens)
_MODEL_CONTEXT_WINDOWS = {
    'claude-opus-4-6': 1_000_000,
}
_DEFAULT_CONTEXT_WINDOW = 200_000


def _infer_context_window(model_name: str) -> int:
    """Map a model name to its context window size.
    Tries exact match, then strips date suffix (e.g. claude-sonnet-4-5-20250514)."""
    if not model_name:
        return _DEFAULT_CONTEXT_WINDOW
    if model_name in _MODEL_CONTEXT_WINDOWS:
        return _MODEL_CONTEXT_WINDOWS[model_name]
    # Strip date suffix: "claude-sonnet-4-5-20250514" → "claude-sonnet-4-5"
    stripped = re.sub(r'-\d{8}$', '', model_name)
    if stripped in _MODEL_CONTEXT_WINDOWS:
        return _MODEL_CONTEXT_WINDOWS[stripped]
    return _DEFAULT_CONTEXT_WINDOW

# Cache sidecar probe result to avoid repeated blocking socket connects
_sidecar_cache = {'running': False, 'ts': 0}

UI_DIR = Path(__file__).parent
LANEKEEP_DIR = UI_DIR.parent  # lanekeep/ directory (parent of ui/)

# Mtime-based response caches for trace endpoints
_trace_cache = {'key': None, 'data': None, 'limit': None}
_trace_entries_cache = {'key': None, 'entries': None, 'summary': None}  # cached parsed+sorted entries
_trends_cache = {'key': None, 'data': None}
_alltime_cache = {'key': None, 'data': None}
_docs_cache = {}  # doc_name -> {'mtime': float, 'data': str}
_graphs_cache = {'key': None, 'data': None}


def compute_trace_summary(entries):
    """Compute summary counts and ask-correlation for trace entries.

    Mutates ask entries in-place (adds 'user_approved' field).
    Returns dict with total, deny, warn, ask, allow, pii_input, asks_*.
    """
    summary = {'total': 0, 'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0,
               'pii_input': 0, 'asks_approved': 0, 'asks_denied': 0, 'asks_unknown': 0}

    # Correlate ask decisions with PostToolUse to determine user approval
    ask_by_tuid = {}
    asks_no_tuid = []
    for entry in entries:
        if entry.get('event_type') == 'PreToolUse' and entry.get('decision') == 'ask':
            tuid = entry.get('tool_use_id')
            if tuid:
                ask_by_tuid[tuid] = entry
            else:
                asks_no_tuid.append(entry)
    asks_approved = 0
    asks_denied = 0
    asks_unknown = 0
    for entry in entries:
        tuid = entry.get('tool_use_id')
        if not tuid:
            continue
        if entry.get('event_type') == 'PostToolUse' and tuid in ask_by_tuid:
            ask_entry = ask_by_tuid.pop(tuid)
            if entry.get('user_denied'):
                ask_entry['user_approved'] = False
                asks_denied += 1
            else:
                ask_entry['user_approved'] = True
                asks_approved += 1
    # Position-based denial inference: if an unmatched ask is NOT the very
    # last entry, the session continued without the tool running → denied.
    # Only the very last entry stays unknown (could still be pending).
    entry_index = {id(e): i for i, e in enumerate(entries)}
    last_idx = len(entries) - 1
    for entry in ask_by_tuid.values():
        if 'user_approved' not in entry:
            idx = entry_index.get(id(entry), last_idx)
            if idx < last_idx:
                entry['user_approved'] = False
                asks_denied += 1
            else:
                entry['user_approved'] = None
                asks_unknown += 1
    for entry in asks_no_tuid:
        idx = entry_index.get(id(entry), last_idx)
        if idx < last_idx:
            entry['user_approved'] = False
            asks_denied += 1
        else:
            entry['user_approved'] = None
            asks_unknown += 1

    summary['asks_approved'] = asks_approved
    summary['asks_denied'] = asks_denied
    summary['asks_unknown'] = asks_unknown

    # Count decisions from PreToolUse entries only (PostToolUse has its own
    # decision from ResultTransform, almost always "allow", which would
    # inflate the allow count and total decision count).
    # Entries without event_type are treated as PreToolUse (legacy format).
    for entry in entries:
        event_type = entry.get('event_type', '')
        is_pre = event_type in ('PreToolUse', 'tool_call', '')
        if is_pre and event_type != 'PostToolUse':
            summary['total'] += 1
            decision = entry.get('decision', '')
            if decision in summary:
                summary[decision] += 1
        # Count PII detections
        for ev in entry.get('evaluators', entry.get('evaluator_results', [])):
            for det in ev.get('detections', []):
                if det.get('category') == 'pii':
                    if is_pre:
                        summary['pii_input'] += 1
                    break  # count once per evaluator

    return summary


def _extract_file_path(entry):
    """Extract file_path from a trace entry, with backfill for older traces."""
    fp = entry.get('file_path')
    if fp:
        return fp
    ti = entry.get('tool_input')
    if isinstance(ti, dict):
        return ti.get('file_path')
    if isinstance(ti, str):
        try:
            return json.loads(ti).get('file_path')
        except (json.JSONDecodeError, ValueError, AttributeError):
            pass
    return None


def _compute_alltime_from_traces(trace_dir):
    """Compute all-time qualitative metrics from ALL trace files.

    Returns dict with decisions, top_denied_tools, top_evaluators, pii_input,
    latency stats, and files_touched. Uses mtime-based caching.
    """
    global _alltime_cache
    mtime_key = _trace_mtime_key(trace_dir)
    if mtime_key is not None and mtime_key == _alltime_cache['key'] and _alltime_cache['data'] is not None:
        return _alltime_cache['data']

    files_touched = {}  # fp -> {ops: {tool: count}, last_tool, last_ts, denied: int, sessions: set()}
    result = {
        'decisions': {'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0},
        'top_denied_tools': {},
        'top_evaluators': {},
        'pii_input': 0,
        'latency': {'count': 0, 'sum_ms': 0, 'max_ms': 0, 'values': []},
        'files_touched': files_touched,
    }

    if not trace_dir.exists():
        _alltime_cache['key'] = mtime_key
        _alltime_cache['data'] = result
        return result

    for trace_file in trace_dir.glob('*.jsonl'):
        try:
            with open(trace_file) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    evt = entry.get('event_type', '')
                    is_pre = evt in ('PreToolUse', 'tool_call', '')
                    if not is_pre or evt == 'PostToolUse':
                        continue
                    dec = entry.get('decision', '')
                    if dec in result['decisions']:
                        result['decisions'][dec] += 1
                    # Denied tools
                    if dec == 'deny':
                        tool = entry.get('tool_name', '')
                        if tool:
                            result['top_denied_tools'][tool] = result['top_denied_tools'].get(tool, 0) + 1
                    # Failed evaluators
                    for ev in entry.get('evaluators', entry.get('evaluator_results', [])):
                        if ev.get('passed') is False:
                            name = ev.get('name', ev.get('evaluator', ''))
                            if name:
                                result['top_evaluators'][name] = result['top_evaluators'].get(name, 0) + 1
                    # PII
                    for ev in entry.get('evaluators', entry.get('evaluator_results', [])):
                        for det in ev.get('detections', []):
                            if det.get('category') == 'pii':
                                result['pii_input'] += 1
                                break
                    # Latency
                    lat = entry.get('latency_ms')
                    if lat is not None and isinstance(lat, (int, float)) and lat >= 0:
                        result['latency']['count'] += 1
                        result['latency']['sum_ms'] += lat
                        if lat > result['latency']['max_ms']:
                            result['latency']['max_ms'] = lat
                        result['latency']['values'].append(lat)
                    # Files touched
                    fp = _extract_file_path(entry)
                    if fp:
                        tool = entry.get('tool_name', '')
                        sid = entry.get('session_id', '')
                        ts = entry.get('timestamp', '')
                        if fp not in files_touched:
                            files_touched[fp] = {'ops': {}, 'last_tool': tool, 'last_ts': ts, 'denied': 0, 'sessions': set()}
                        rec = files_touched[fp]
                        rec['ops'][tool] = rec['ops'].get(tool, 0) + 1
                        rec['last_tool'] = tool
                        rec['last_ts'] = ts
                        if dec == 'deny':
                            rec['denied'] += 1
                        if sid:
                            rec['sessions'].add(sid)
        except OSError:
            continue

    # Convert session sets to counts for JSON serialization
    for fp, rec in files_touched.items():
        rec['sessions'] = len(rec['sessions'])
    result['files_touched'] = files_touched
    _alltime_cache['key'] = mtime_key
    _alltime_cache['data'] = result
    return result


_MD_CODE_FENCE = re.compile(r'^```(\w*)\n(.*?)^```', re.MULTILINE | re.DOTALL)
_MD_TABLE_BLOCK = re.compile(r'((?:^\|.+\|\n)+)', re.MULTILINE)
_MD_BLOCKQUOTE = re.compile(r'((?:^>\s?.*\n?)+)', re.MULTILINE)
_MD_UL = re.compile(r'((?:^[ ]*[-*+] .+\n?)+)', re.MULTILINE)
_MD_OL = re.compile(r'((?:^[ ]*\d+\. .+\n?)+)', re.MULTILINE)
_MD_HR = re.compile(r'^-{3,}\s*$', re.MULTILINE)
_MD_HEADING = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)
_MD_IMG = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')
_MD_LINK = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
_MD_BOLD = re.compile(r'\*\*(.+?)\*\*')
_MD_ITALIC = re.compile(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)')
_MD_INLINE_CODE = re.compile(r'`([^`]+)`')


def _md_to_html(text):
    """Convert markdown to HTML using stdlib re only. Handles the subset used in project docs."""
    # Normalize line endings
    text = text.replace('\r\n', '\n')

    # Step 1: Extract code fences into placeholders (protect from other transforms)
    code_blocks = []
    def _replace_fence(m):
        lang = m.group(1)
        code = html_mod.escape(m.group(2))
        idx = len(code_blocks)
        lang_attr = f' class="lang-{html_mod.escape(lang)}"' if lang else ''
        code_blocks.append(f'<pre><code{lang_attr}>{code}</code></pre>')
        return f'\x00CODEBLOCK{idx}\x00'
    text = _MD_CODE_FENCE.sub(_replace_fence, text)

    # Step 1.5: Extract HTML image blocks (including wrapping <p> tags) into placeholders
    img_blocks = []
    def _replace_html_img(m):
        tag = m.group(1)
        # MED-05: Rebuild img tag from only safe attributes to prevent event handler injection
        # (e.g. <img src=x onerror=alert(1)> would execute JS without this sanitization)
        src_match = re.search(r'src="([^"]*)"', tag) or re.search(r"src='([^']*)'", tag)
        alt_match = re.search(r'alt="([^"]*)"', tag) or re.search(r"alt='([^']*)'", tag)
        w_match = re.search(r'width="(\d+)"', tag)
        src = html_mod.escape(src_match.group(1)) if src_match else ''
        alt = html_mod.escape(alt_match.group(1)) if alt_match else ''
        # Block javascript: URIs
        if re.match(r'\s*javascript:', src, re.IGNORECASE):
            src = ''
        # Rewrite relative src to absolute /images/ path
        if src.startswith('images/'):
            src = '/' + src
        max_w = f'max-width:{w_match.group(1)}px' if w_match else 'max-width:100%'
        safe_tag = f'<img src="{src}" alt="{alt}" style="{max_w};width:100%;border-radius:8px" />'
        idx = len(img_blocks)
        img_blocks.append(f'<div style="text-align:center;margin:1em 0">{safe_tag}</div>')
        return f'\x00IMGBLOCK{idx}\x00'
    # Match <p>...<img .../>...</p> wrappers or bare <img> tags
    text = re.sub(r'<p[^>]*>\s*(<img\s[^>]+/?>)\s*</p>', _replace_html_img, text)
    text = re.sub(r'(<img\s[^>]+/?>)', _replace_html_img, text)

    # Step 1.6: Escape raw HTML tags (prevent passthrough of HTML embedded in markdown)
    # Safe because code blocks and img tags are already extracted.
    # Only escapes '<' followed by a tag name (e.g. <div>, </script>), not comparisons like x < y.
    text = re.sub(r'<(?=/?[a-zA-Z])', '&lt;', text)

    # Step 2: Tables
    def _replace_table(m):
        lines = m.group(1).strip().split('\n')
        if len(lines) < 2:
            return m.group(0)
        rows = []
        for i, line in enumerate(lines):
            cells = [c.strip() for c in line.strip('|').split('|')]
            # Skip separator row (---|---|---)
            if i == 1 and all(c.strip().replace('-', '').replace(':', '') == '' for c in cells):
                continue
            tag = 'th' if i == 0 else 'td'
            row = ''.join(f'<{tag}>{html_mod.escape(c)}</{tag}>' for c in cells)
            rows.append(f'<tr>{row}</tr>')
        return '<table>' + ''.join(rows) + '</table>'
    text = _MD_TABLE_BLOCK.sub(_replace_table, text)

    # Step 3: Blockquotes
    def _replace_blockquote(m):
        inner = '\n'.join(line.lstrip('>').lstrip(' ') for line in m.group(0).strip().split('\n'))
        return f'<blockquote>{html_mod.escape(inner)}</blockquote>'
    text = _MD_BLOCKQUOTE.sub(_replace_blockquote, text)

    # Step 4: Unordered lists
    def _replace_ul(m):
        items = re.findall(r'^[ ]*[-*+] (.+)$', m.group(0), re.MULTILINE)
        li = ''.join(f'<li>{html_mod.escape(it)}</li>' for it in items)
        return f'<ul>{li}</ul>'
    text = _MD_UL.sub(_replace_ul, text)

    # Step 5: Ordered lists
    def _replace_ol(m):
        items = re.findall(r'^[ ]*\d+\. (.+)$', m.group(0), re.MULTILINE)
        li = ''.join(f'<li>{html_mod.escape(it)}</li>' for it in items)
        return f'<ol>{li}</ol>'
    text = _MD_OL.sub(_replace_ol, text)

    # Step 6: Horizontal rules
    text = _MD_HR.sub('<hr>', text)

    # Step 7: Headings
    def _heading_slug(s):
        s = s.lower().strip()
        s = re.sub(r'[^\w\s-]', '', s)
        return re.sub(r'[\s]+', '-', s).strip('-')

    def _replace_heading(m):
        level = len(m.group(1))
        content = m.group(2).strip()
        slug = _heading_slug(content)
        return f'<h{level} id="{html_mod.escape(slug)}">{html_mod.escape(content)}</h{level}>'
    text = _MD_HEADING.sub(_replace_heading, text)

    # Step 8: Images → img tags (serve via /images/ route)
    def _replace_img(m):
        alt = html_mod.escape(m.group(1))
        src = m.group(2)
        # Normalize relative paths like images/foo.png → /images/foo.png
        if src.startswith('images/'):
            src = '/' + src
        return f'<img src="{html_mod.escape(src)}" alt="{alt}" style="max-width:100%;border-radius:8px;margin:1em 0">'
    text = _MD_IMG.sub(_replace_img, text)

    # Step 9: Links
    text = _MD_LINK.sub(lambda m: f'<a href="{html_mod.escape(m.group(2))}">{html_mod.escape(m.group(1))}</a>', text)

    # Step 10: Bold
    text = _MD_BOLD.sub(lambda m: f'<strong>{html_mod.escape(m.group(1))}</strong>', text)

    # Step 11: Italic
    text = _MD_ITALIC.sub(lambda m: f'<em>{html_mod.escape(m.group(1))}</em>', text)

    # Step 12: Inline code
    text = _MD_INLINE_CODE.sub(lambda m: f'<code>{html_mod.escape(m.group(1))}</code>', text)

    # Step 13: Paragraphs — wrap remaining non-empty, non-tag text blocks
    lines = text.split('\n')
    result = []
    para = []
    block_tags = {'<pre', '<table', '<ul', '<ol', '<blockquote', '<h1', '<h2', '<h3',
                  '<h4', '<h5', '<h6', '<hr', '\x00CODEBLOCK', '\x00IMGBLOCK'}
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if para:
                result.append('<p>' + ' '.join(para) + '</p>')
                para = []
            continue
        if any(stripped.startswith(tag) for tag in block_tags) or stripped.startswith('</'):
            if para:
                result.append('<p>' + ' '.join(para) + '</p>')
                para = []
            result.append(line)
        else:
            para.append(stripped)
    if para:
        result.append('<p>' + ' '.join(para) + '</p>')

    text = '\n'.join(result)

    # Step 14: Restore code blocks
    for i, block in enumerate(code_blocks):
        text = text.replace(f'\x00CODEBLOCK{i}\x00', block)

    # Step 15: Restore img blocks
    for i, block in enumerate(img_blocks):
        text = text.replace(f'\x00IMGBLOCK{i}\x00', block)

    return text


_EMPTY_TRACE_KEY = ('__empty__',)

def _trace_mtime_key(trace_dir):
    """Composite key from trace file names + mtimes. Fast: stat only, no read."""
    try:
        files = sorted(trace_dir.glob('*.jsonl'))
        if not files:
            return _EMPTY_TRACE_KEY
        return tuple((f.name, f.stat().st_mtime_ns) for f in files)
    except OSError:
        return _EMPTY_TRACE_KEY

CONFIG_PATH = None
PROJECT_DIR = None
TLS_ACTIVE = False
ALLOWED_READ_ROOTS = []

FILE_TYPES = {
    '.json': 'json', '.md': 'md', '.yaml': 'yaml', '.yml': 'yaml',
    '.sh': 'txt', '.bats': 'txt', '.txt': 'txt', '.py': 'txt',
    '.html': 'txt', '.css': 'txt', '.js': 'txt', '.toml': 'txt',
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        qs = parse_qs(parsed.query)

        if path == '/' or path == '/index.html':
            self._serve_file(UI_DIR / 'index.html', 'text/html')
        elif path == '/api/config':
            self._serve_config()
        elif path == '/api/file':
            self._serve_project_file(qs)
        elif path == '/api/trace':
            self._serve_trace(qs)
        elif path == '/api/bookmarks':
            self._serve_bookmarks()
        elif path == '/api/status':
            self._serve_status()
        elif path == '/api/rules/update-check':
            self._serve_rules_update_check()
        elif path == '/api/audit':
            self._serve_audit()
        elif path == '/api/audit/last':
            self._serve_last_audit()
        elif path == '/api/config-trees':
            self._serve_config_trees()
        elif path == '/api/trends':
            self._serve_trends(qs)
        elif path == '/api/context':
            self._serve_context()
        elif path == '/api/graphs':
            self._serve_graphs()
        elif path == '/api/docs':
            self._serve_docs(qs)
        elif path.startswith('/fonts/'):
            fname = path.split('/')[-1]
            if fname.endswith('.woff2') and '/' not in fname and '..' not in fname:
                font_path = UI_DIR / 'fonts' / fname
                self._serve_file(font_path, 'font/woff2')
            else:
                self._respond(404, 'Not found')
        elif path.startswith('/images/'):
            # Serve images from lanekeep/images/
            img_rel = path[len('/images/'):]
            if '..' not in img_rel and not img_rel.startswith('/'):
                img_path = LANEKEEP_DIR / 'images' / img_rel
                if img_path.is_file():
                    ext = img_path.suffix.lower()
                    ctypes = {'.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
                              '.svg': 'image/svg+xml', '.gif': 'image/gif', '.webp': 'image/webp'}
                    self._serve_file(img_path, ctypes.get(ext, 'application/octet-stream'))
                else:
                    self._respond(404, 'Not found')
            else:
                self._respond(404, 'Not found')
        elif path.startswith('/js/'):
            fname = path.split('/')[-1]
            if fname.endswith('.js') and '/' not in fname and '..' not in fname:
                js_path = UI_DIR / 'js' / fname
                self._serve_file(js_path, 'application/javascript')
            else:
                self._respond(404, 'Not found')
        else:
            self._respond(404, 'Not found')

    def do_POST(self):
        # CSRF protection: reject cross-origin requests
        origin = self.headers.get('Origin', '')
        allowed = ('http://localhost:', 'http://127.0.0.1:')
        if TLS_ACTIVE:
            allowed += ('https://localhost:', 'https://127.0.0.1:')
        if origin and not origin.startswith(allowed):
            self._respond(403, json.dumps({'error': 'Cross-origin request rejected'}), 'application/json')
            return

        content_type = self.headers.get('Content-Type', '')
        if 'application/json' not in content_type:
            self._respond(415, json.dumps({'error': 'Content-Type must be application/json'}), 'application/json')
            return

        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/api/config':
            self._save_config()
        elif path == '/api/file':
            self._save_project_file()
        elif path == '/api/bookmarks':
            self._save_bookmarks()
        elif path == '/api/rules/update':
            self._apply_rules_update()
        elif path == '/api/trace/clear':
            self._clear_trace()
        elif path == '/api/settings':
            self._save_settings()
        else:
            self._respond(404, 'Not found')

    def _serve_file(self, path, content_type):
        try:
            data = path.read_bytes()
            nonce = None
            if content_type == 'text/html':
                # Generate a per-request nonce for CSP
                nonce = base64.b64encode(secrets.token_bytes(32)).decode('ascii')
                # Inject nonce into <script> and <style> tags
                nonce_bytes = nonce.encode()
                data = data.replace(b'<script>', b'<script nonce="' + nonce_bytes + b'">')
                data = data.replace(b'<script src=', b'<script nonce="' + nonce_bytes + b'" src=')
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', len(data))
            self._send_security_headers(nonce)
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self._respond(404, 'File not found')

    def _serve_config(self):
        try:
            with open(CONFIG_PATH) as f:
                config = json.load(f)
            data = json.dumps(config, indent=2).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except FileNotFoundError:
            self._respond_json_error(404, f'Config file not found: {CONFIG_PATH}')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _resolve_project_path(self, rel_path, reject_symlinks=False):
        """Resolve a relative path against PROJECT_DIR, rejecting traversal.
        When reject_symlinks=True, also reject paths that are or contain symlinks."""
        if not rel_path:
            return None, 'Missing path parameter'
        resolved = (PROJECT_DIR / rel_path).resolve()
        try:
            resolved.relative_to(PROJECT_DIR.resolve())
        except ValueError:
            return None, 'Path traversal not allowed'
        if reject_symlinks:
            # Check if the target itself is a symlink (use lstat to avoid following)
            raw_path = PROJECT_DIR / rel_path
            if raw_path.is_symlink():
                return None, 'Symlink targets not allowed for writes'
        return resolved, None

    def _is_readonly(self, resolved_path):
        """A file is read-only if it's not under PROJECT_DIR."""
        try:
            resolved_path.resolve().relative_to(PROJECT_DIR.resolve())
            return False
        except ValueError:
            return True

    def _resolve_file_path(self, raw_path):
        """Resolve a path for read access, checking against all allowed roots.
        Accepts absolute or relative paths (relative resolved against PROJECT_DIR,
        falling back to other allowed roots if the file doesn't exist there)."""
        if not raw_path:
            return None, 'Missing path parameter'
        p = Path(raw_path)
        if p.is_absolute():
            resolved = p.resolve()
        else:
            resolved = (PROJECT_DIR / p).resolve()
            if not resolved.exists():
                for root in ALLOWED_READ_ROOTS:
                    alt = (root / p).resolve()
                    if alt.exists():
                        resolved = alt
                        break
        for root in ALLOWED_READ_ROOTS:
            try:
                resolved.relative_to(root)
                return resolved, None
            except ValueError:
                continue
        return None, 'Path not in allowed directories'

    def _serve_project_file(self, qs):
        rel_path = qs.get('path', [None])[0]
        resolved, err = self._resolve_file_path(rel_path)
        if err:
            self._respond(400, json.dumps({'error': err}), 'application/json')
            return
        if not resolved.exists() or not resolved.is_file():
            self._respond(404, json.dumps({'error': 'File not found'}), 'application/json')
            return
        try:
            content = resolved.read_text(encoding='utf-8')
            ext = resolved.suffix.lower()
            ftype = FILE_TYPES.get(ext, 'txt')
            if ftype == 'json':
                try:
                    content = json.dumps(json.loads(content), indent=2)
                except json.JSONDecodeError:
                    pass
            stat = resolved.stat()
            lines = content.count('\n') + (1 if content and not content.endswith('\n') else 0)
            result = {'path': rel_path, 'content': content, 'type': ftype,
                      'readonly': self._is_readonly(resolved),
                      'size': stat.st_size, 'lines': lines,
                      'modified': stat.st_mtime}
            data = json.dumps(result).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error reading file: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _save_project_file(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length > MAX_BODY or length < 0:
                self._respond(413, 'Payload too large')
                return
            if length == 0:
                self._respond(400, json.dumps({'error': 'Empty request body'}), 'application/json')
                return
            body = json.loads(self.rfile.read(length))
            rel_path = body.get('path')
            content = body.get('content', '')
            resolved, err = self._resolve_project_path(rel_path, reject_symlinks=True)
            if err:
                self._respond(400, json.dumps({'error': err}), 'application/json')
                return
            resolved.parent.mkdir(parents=True, exist_ok=True)
            resolved.write_text(content, encoding='utf-8')
            self._respond(200, json.dumps({'ok': True}), 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error writing file: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _load_trace_entries(self, trace_dir):
        """Load and cache all trace entries. Returns (entries, summary) or ([], empty_summary)."""
        global _trace_entries_cache
        mtime_key = _trace_mtime_key(trace_dir)
        if mtime_key == _trace_entries_cache['key'] and _trace_entries_cache['entries'] is not None:
            return _trace_entries_cache['entries'], _trace_entries_cache['summary']
        jsonl_files = sorted(trace_dir.glob('*.jsonl'), key=lambda p: p.stat().st_mtime, reverse=True)
        if not jsonl_files:
            return [], {'total': 0, 'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0, 'pii_input': 0}
        all_entries = []
        for trace_file in jsonl_files:
            try:
                with open(trace_file) as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            all_entries.append(json.loads(line))
                        except json.JSONDecodeError:
                            continue
            except OSError:
                continue
        all_entries.sort(key=lambda e: e.get('timestamp', ''))
        summary = compute_trace_summary(all_entries)
        _trace_entries_cache['key'] = mtime_key
        _trace_entries_cache['entries'] = all_entries
        _trace_entries_cache['summary'] = summary
        return all_entries, summary

    def _serve_trace(self, qs):
        try:
            limit = int(qs.get('limit', ['500'])[0])
            # MED-03: Cap limit to prevent memory exhaustion
            limit = max(1, min(limit, 10000))
        except (ValueError, TypeError):
            self._respond(400, json.dumps({'error': 'Invalid limit parameter'}), 'application/json')
            return
        try:
            offset = int(qs.get('offset', ['0'])[0])
        except (ValueError, TypeError):
            offset = 0
        sort_col = qs.get('sort', [''])[0] or ''
        sort_dir = qs.get('sort_dir', ['desc'])[0]
        decision_filter = qs.get('decision', [''])[0]

        trace_dir = PROJECT_DIR / '.lanekeep' / 'traces'
        empty_summary = {'total': 0, 'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0, 'pii_input': 0}
        result = {'file': None, 'entries': [], 'summary': empty_summary, 'total_filtered': 0, 'total_all': 0}
        if not trace_dir.exists():
            self._respond(200, json.dumps(result), 'application/json')
            return
        try:
            all_entries, summary = self._load_trace_entries(trace_dir)
            if not all_entries:
                self._respond(200, json.dumps(result), 'application/json')
                return

            result['summary'] = summary
            result['total_all'] = len(all_entries)

            # Apply decision filter server-side
            if decision_filter and decision_filter != 'all':
                if decision_filter == 'pii_input':
                    filtered = [e for e in all_entries if e.get('pii_detected')]
                else:
                    filtered = [e for e in all_entries if e.get('decision') == decision_filter]
            else:
                filtered = all_entries

            # Sort server-side
            valid_sort_cols = {'timestamp', 'tool_name', 'decision', 'latency_ms', 'reason', 'source', 'event_type', 'file_path'}
            if sort_col and sort_col in valid_sort_cols:
                reverse = sort_dir == 'desc'
                def sort_key(e):
                    v = e.get(sort_col, '')
                    if v is None:
                        v = ''
                    if sort_col == 'latency_ms':
                        return v if isinstance(v, (int, float)) else 0
                    return str(v).lower()
                filtered.sort(key=sort_key, reverse=reverse)

            result['total_filtered'] = len(filtered)
            # Paginate
            page_entries = filtered[offset:offset + limit] if offset >= 0 else filtered[-limit:]
            result['entries'] = page_entries

            data = json.dumps(result).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error reading trace: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _serve_trends(self, qs):
        # Time range filter: 1h, 6h, 24h, 7d, 30d, or all (default)
        time_range = qs.get('range', ['all'])[0]
        range_seconds = {'1h': 3600, '6h': 21600, '24h': 86400, '7d': 604800, '30d': 2592000}.get(time_range, 0)
        empty = {'granularity': 'daily', 'buckets': [], 'range': time_range}
        trace_dir = PROJECT_DIR / '.lanekeep' / 'traces'
        if not trace_dir.exists():
            self._respond(200, json.dumps(empty), 'application/json')
            return
        try:
            jsonl_files = list(trace_dir.glob('*.jsonl'))
            if not jsonl_files:
                self._respond(200, json.dumps(empty), 'application/json')
                return
            mtime_key = _trace_mtime_key(trace_dir)
            # Cache only for unfiltered (all) requests
            cache_key = (mtime_key, time_range)
            if cache_key == _trends_cache['key'] and _trends_cache['data'] is not None:
                self._respond(200, _trends_cache['data'], 'application/json')
                return
            # Read all entries with timestamps from PreToolUse events
            entries = []
            now = datetime.now(tz=timezone.utc)
            for trace_file in jsonl_files:
                try:
                    with open(trace_file) as f:
                        for line in f:
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                obj = json.loads(line)
                            except json.JSONDecodeError:
                                continue
                            ts = obj.get('timestamp')
                            if not ts or obj.get('event_type') != 'PreToolUse':
                                continue
                            try:
                                dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                            except (ValueError, AttributeError):
                                continue
                            entries.append((dt, obj))
                except OSError:
                    continue
            if not entries:
                self._respond(200, json.dumps(empty), 'application/json')
                return
            entries.sort(key=lambda x: x[0])
            latest_ts = entries[-1][0].isoformat()
            # Apply time range filter relative to current time
            if range_seconds > 0:
                from datetime import timedelta
                cutoff = now - timedelta(seconds=range_seconds)
                entries = [(dt, obj) for dt, obj in entries if dt >= cutoff]
                if not entries:
                    empty['latest_timestamp'] = latest_ts
                    self._respond(200, json.dumps(empty), 'application/json')
                    return
            # Determine granularity from time range
            span = (entries[-1][0] - entries[0][0]).total_seconds()
            if span <= 7200:  # <= 2h: 5-minute buckets
                granularity = '5min'
                def bucket_key(dt):
                    return f'{dt.strftime("%H")}:{dt.minute // 5 * 5:02d}'
            elif span <= 86400:  # <= 24h
                granularity = 'hourly'
                def bucket_key(dt):
                    return dt.strftime('%Y-%m-%dT%H')
            elif span <= 14 * 86400:  # <= 14 days
                granularity = 'daily'
                def bucket_key(dt):
                    return dt.strftime('%Y-%m-%d')
            else:
                granularity = 'weekly'
                def bucket_key(dt):
                    iso = dt.isocalendar()
                    return f'{iso[0]}-W{iso[1]:02d}'
            # Bucket entries
            buckets_map = {}
            for dt, obj in entries:
                key = bucket_key(dt)
                if key not in buckets_map:
                    buckets_map[key] = {'t': key, 'actions': 0,
                        'decisions': {'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0},
                        '_latencies': []}
                b = buckets_map[key]
                b['actions'] += 1
                dec = obj.get('decision', '')
                if dec in b['decisions']:
                    b['decisions'][dec] += 1
                lat = obj.get('latency_ms')
                if lat is not None:
                    try:
                        b['_latencies'].append(float(lat))
                    except (ValueError, TypeError):
                        pass
            # Compute percentiles and build output
            def percentile(vals, p):
                if not vals:
                    return 0
                vals = sorted(vals)
                k = (len(vals) - 1) * p / 100.0
                f = int(k)
                c = f + 1 if f + 1 < len(vals) else f
                return round(vals[f] + (vals[c] - vals[f]) * (k - f), 1)
            bucket_list = []
            for key in sorted(buckets_map):
                b = buckets_map[key]
                lats = b.pop('_latencies')
                b['latency_p50'] = percentile(lats, 50)
                b['latency_p95'] = percentile(lats, 95)
                bucket_list.append(b)
            result = {'granularity': granularity, 'buckets': bucket_list, 'range': time_range}
            response_body = json.dumps(result)
            _trends_cache['key'] = cache_key
            _trends_cache['data'] = response_body
            self._respond(200, response_body, 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error computing trends: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _bookmarks_path(self):
        return PROJECT_DIR / '.lanekeep' / 'bookmarks.json'

    def _serve_bookmarks(self):
        bpath = self._bookmarks_path()
        try:
            if bpath.exists():
                bookmarks = json.loads(bpath.read_text(encoding='utf-8'))
            else:
                bookmarks = []
            data = json.dumps(bookmarks).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error reading bookmarks: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _save_bookmarks(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length > MAX_BODY or length < 0:
                self._respond(413, 'Payload too large')
                return
            if length == 0:
                self._respond(400, json.dumps({'error': 'Empty request body'}), 'application/json')
                return
            bookmarks = json.loads(self.rfile.read(length))
            if not isinstance(bookmarks, list):
                self._respond(400, json.dumps({'error': 'Expected array'}), 'application/json')
                return
            if len(bookmarks) > MAX_BOOKMARKS:
                self._respond(400, json.dumps({'error': f'Too many bookmarks (max {MAX_BOOKMARKS})'}), 'application/json')
                return
            # Validate each bookmark
            for bm in bookmarks:
                if not isinstance(bm, dict) or 'path' not in bm:
                    self._respond(400, json.dumps({'error': 'Invalid bookmark entry'}), 'application/json')
                    return
                _, err = self._resolve_file_path(bm['path'])
                if err:
                    self._respond(400, json.dumps({'error': f'{err}: {bm["path"]}'}), 'application/json')
                    return
                # Truncate comment
                if 'comment' in bm:
                    bm['comment'] = str(bm['comment'])[:200]
            bpath = self._bookmarks_path()
            bpath.parent.mkdir(parents=True, exist_ok=True)
            bpath.write_text(json.dumps(bookmarks, indent=2) + '\n', encoding='utf-8')
            self._respond(200, json.dumps({'ok': True}), 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error saving bookmarks: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _serve_status(self):
        try:
            result = {'config': {}, 'budget': {}, 'session': {}}

            # --- Config Stack ---
            lanekeep_dir = Path(os.environ.get('LANEKEEP_DIR', str(PROJECT_DIR / 'lanekeep')))
            defaults_path = lanekeep_dir / 'defaults' / 'lanekeep.json'
            defaults_info = {'path': str(defaults_path), 'rules': 0, 'version': '?'}
            if defaults_path.exists():
                try:
                    dc = json.loads(defaults_path.read_text(encoding='utf-8'))
                    defaults_info['rules'] = len(dc.get('rules', []))
                    defaults_info['version'] = str(dc.get('version', '?'))
                except (json.JSONDecodeError, OSError):
                    pass
            result['config']['defaults'] = defaults_info

            user_path = PROJECT_DIR / 'lanekeep.json'
            user_info = {'path': str(user_path), 'overrides': 0, 'profile': 'default'}
            if user_path.exists():
                try:
                    uc = json.loads(user_path.read_text(encoding='utf-8'))
                    user_info['overrides'] = len(uc.get('rules', []))
                    user_info['profile'] = uc.get('profile', 'default')
                except (json.JSONDecodeError, OSError):
                    pass
            result['config']['user'] = user_info

            env_overrides = {}
            for key in ('LANEKEEP_MAX_ACTIONS', 'LANEKEEP_MAX_TOKENS', 'LANEKEEP_MAX_INPUT_TOKENS',
                        'LANEKEEP_MAX_OUTPUT_TOKENS', 'LANEKEEP_TIMEOUT_SECONDS',
                        'LANEKEEP_MAX_TOTAL_ACTIONS', 'LANEKEEP_MAX_TOTAL_TOKENS', 'LANEKEEP_MAX_TOTAL_TIME',
                        'LANEKEEP_CONTEXT_WINDOW_SIZE',
                        'LANEKEEP_PROFILE', 'LANEKEEP_ENV', 'LANEKEEP_SEMANTIC_ENABLED'):
                val = os.environ.get(key)
                if val is not None:
                    env_overrides[key] = val
            result['config']['env'] = env_overrides

            # --- Budget ---
            start_epoch = 0
            session_id = ''
            token_source = 'unavailable'
            context_model = ''
            state_path = PROJECT_DIR / '.lanekeep' / 'state.json'
            budget = {'actions': 0, 'max_actions': 500, 'elapsed_min': 0, 'max_minutes': 1440,
                      'tokens': 0, 'input_tokens': 0, 'output_tokens': 0,
                      'max_tokens': None, 'max_input_tokens': None, 'max_output_tokens': None}
            if state_path.exists():
                try:
                    st = json.loads(state_path.read_text(encoding='utf-8'))
                    budget['actions'] = st.get('action_count', 0)
                    budget['events'] = st.get('total_events', 0)
                    start_epoch = st.get('start_epoch', 0)
                    session_id = st.get('session_id', '')
                    token_source = st.get('token_source', 'estimate')
                    context_model = st.get('model', '')
                    if start_epoch:
                        budget['elapsed_min'] = round((time.time() - start_epoch) / 60, 1)
                    budget['tokens'] = st.get('token_count', 0)
                    budget['input_tokens'] = st.get('input_tokens', 0)
                    budget['output_tokens'] = st.get('output_tokens', 0)
                except (json.JSONDecodeError, OSError):
                    pass
            # Layer 0: defaults file budget
            try:
                db = dc.get('budget', {})
                if db.get('max_actions') is not None:
                    budget['max_actions'] = int(db['max_actions'])
                if db.get('timeout_seconds') is not None:
                    budget['max_minutes'] = round(int(db['timeout_seconds']) / 60)
                if db.get('max_tokens') is not None:
                    budget['max_tokens'] = int(db['max_tokens'])
                if db.get('max_input_tokens') is not None:
                    budget['max_input_tokens'] = int(db['max_input_tokens'])
                if db.get('max_output_tokens') is not None:
                    budget['max_output_tokens'] = int(db['max_output_tokens'])
            except (NameError, ValueError, AttributeError):
                pass
            # Layer 1: project config
            cfg_path = PROJECT_DIR / 'lanekeep.json'
            if cfg_path.exists():
                try:
                    cfg = json.loads(cfg_path.read_text(encoding='utf-8'))
                    cb = cfg.get('budget', {})
                    if cb.get('max_actions') is not None:
                        budget['max_actions'] = int(cb['max_actions'])
                    if cb.get('timeout_seconds') is not None:
                        budget['max_minutes'] = round(int(cb['timeout_seconds']) / 60)
                    if cb.get('max_tokens') is not None:
                        budget['max_tokens'] = int(cb['max_tokens'])
                    if cb.get('max_input_tokens') is not None:
                        budget['max_input_tokens'] = int(cb['max_input_tokens'])
                    if cb.get('max_output_tokens') is not None:
                        budget['max_output_tokens'] = int(cb['max_output_tokens'])
                except (json.JSONDecodeError, OSError, ValueError):
                    pass
            # Layer 2: env var overrides
            if os.environ.get('LANEKEEP_MAX_ACTIONS'):
                budget['max_actions'] = int(os.environ['LANEKEEP_MAX_ACTIONS'])
            if os.environ.get('LANEKEEP_TIMEOUT_SECONDS'):
                budget['max_minutes'] = round(int(os.environ['LANEKEEP_TIMEOUT_SECONDS']) / 60)
            max_tok = os.environ.get('LANEKEEP_MAX_TOKENS')
            if max_tok:
                budget['max_tokens'] = int(max_tok)
            max_itok = os.environ.get('LANEKEEP_MAX_INPUT_TOKENS')
            if max_itok:
                budget['max_input_tokens'] = int(max_itok)
            max_otok = os.environ.get('LANEKEEP_MAX_OUTPUT_TOKENS')
            if max_otok:
                budget['max_output_tokens'] = int(max_otok)
            # All-time limits: layer through defaults → project → env
            budget['max_total_actions'] = 10000
            budget['max_total_input_tokens'] = 5000000
            budget['max_total_output_tokens'] = 5000000
            budget['max_total_tokens'] = 10000000
            budget['max_total_time_seconds'] = 1728000
            try:
                db = dc.get('budget', {})
                if db.get('max_total_actions') is not None:
                    budget['max_total_actions'] = int(db['max_total_actions'])
                if db.get('max_total_input_tokens') is not None:
                    budget['max_total_input_tokens'] = int(db['max_total_input_tokens'])
                if db.get('max_total_output_tokens') is not None:
                    budget['max_total_output_tokens'] = int(db['max_total_output_tokens'])
                if db.get('max_total_tokens') is not None:
                    budget['max_total_tokens'] = int(db['max_total_tokens'])
                if db.get('max_total_time_seconds') is not None:
                    budget['max_total_time_seconds'] = int(db['max_total_time_seconds'])
            except (NameError, ValueError, AttributeError):
                pass
            if cfg_path.exists():
                try:
                    cfg_b = json.loads(cfg_path.read_text(encoding='utf-8')).get('budget', {})
                    if cfg_b.get('max_total_actions') is not None:
                        budget['max_total_actions'] = int(cfg_b['max_total_actions'])
                    if cfg_b.get('max_total_input_tokens') is not None:
                        budget['max_total_input_tokens'] = int(cfg_b['max_total_input_tokens'])
                    if cfg_b.get('max_total_output_tokens') is not None:
                        budget['max_total_output_tokens'] = int(cfg_b['max_total_output_tokens'])
                    if cfg_b.get('max_total_tokens') is not None:
                        budget['max_total_tokens'] = int(cfg_b['max_total_tokens'])
                    if cfg_b.get('max_total_time_seconds') is not None:
                        budget['max_total_time_seconds'] = int(cfg_b['max_total_time_seconds'])
                except (json.JSONDecodeError, OSError, ValueError):
                    pass
            if os.environ.get('LANEKEEP_MAX_TOTAL_ACTIONS'):
                budget['max_total_actions'] = int(os.environ['LANEKEEP_MAX_TOTAL_ACTIONS'])
            if os.environ.get('LANEKEEP_MAX_TOTAL_INPUT_TOKENS'):
                budget['max_total_input_tokens'] = int(os.environ['LANEKEEP_MAX_TOTAL_INPUT_TOKENS'])
            if os.environ.get('LANEKEEP_MAX_TOTAL_OUTPUT_TOKENS'):
                budget['max_total_output_tokens'] = int(os.environ['LANEKEEP_MAX_TOTAL_OUTPUT_TOKENS'])
            if os.environ.get('LANEKEEP_MAX_TOTAL_TOKENS'):
                budget['max_total_tokens'] = int(os.environ['LANEKEEP_MAX_TOTAL_TOKENS'])
            if os.environ.get('LANEKEEP_MAX_TOTAL_TIME'):
                budget['max_total_time_seconds'] = int(os.environ['LANEKEEP_MAX_TOTAL_TIME'])

            # Context window: only meaningful when token_source is transcript
            budget['token_source'] = token_source
            if token_source == 'transcript' and context_model:
                ctx_override = os.environ.get('LANEKEEP_CONTEXT_WINDOW_SIZE')
                if ctx_override:
                    budget['context_window_size'] = int(ctx_override)
                    budget['context_source'] = 'env'
                else:
                    budget['context_window_size'] = _infer_context_window(context_model)
                    budget['context_source'] = 'model'
                budget['context_model'] = context_model

            result['budget'] = budget

            # --- Session ---
            trace_dir = PROJECT_DIR / '.lanekeep' / 'traces'
            session = {'trace_file': 'none', 'entries': 0,
                       'decisions': {'deny': 0, 'warn': 0, 'ask': 0, 'allow': 0},
                       'pii_input': 0,
                       'total_trace_files': 0,
                       'tier': os.environ.get('LANEKEEP_LICENSE_TIER', 'community'),
                       'platform': 'claude-code'}
            if trace_dir.exists():
                jsonl_files = sorted(trace_dir.glob('*.jsonl'),
                                     key=lambda p: p.stat().st_mtime, reverse=True)
                session['total_trace_files'] = len(jsonl_files)
                # Find current session's trace file
                current_trace = None
                if session_id:
                    candidate = trace_dir / f"{session_id}.jsonl"
                    if candidate.exists():
                        current_trace = candidate
                # Fallback: no session_id — use newest file with mtime >= start_epoch
                if current_trace is None and jsonl_files and start_epoch:
                    newest = jsonl_files[0]
                    try:
                        if newest.stat().st_mtime >= start_epoch:
                            current_trace = newest
                    except OSError:
                        pass
                if current_trace is not None:
                    session['trace_file'] = current_trace.name
                    session['top_denied_tools'] = {}
                    session['top_evaluators'] = {}
                    session['latency_values'] = []
                    sess_files = {}  # fp -> {ops: {tool: count}, last_tool, last_ts, denied: int}
                    try:
                        lines = current_trace.read_text(encoding='utf-8').strip().splitlines()
                        session['entries'] = len(lines)
                        for line in lines:
                            try:
                                entry = json.loads(line)
                                evt = entry.get('event_type', '')
                                dec = entry.get('decision', '')
                                is_pre = evt in ('PreToolUse', 'tool_call', '')
                                if is_pre and evt != 'PostToolUse':
                                    if dec in session['decisions']:
                                        session['decisions'][dec] += 1
                                    # Denied tools
                                    if dec == 'deny':
                                        tool = entry.get('tool_name', '')
                                        if tool:
                                            session['top_denied_tools'][tool] = session['top_denied_tools'].get(tool, 0) + 1
                                    # Failed evaluators
                                    for ev in entry.get('evaluators', entry.get('evaluator_results', [])):
                                        if ev.get('passed') is False:
                                            name = ev.get('name', ev.get('evaluator', ''))
                                            if name:
                                                session['top_evaluators'][name] = session['top_evaluators'].get(name, 0) + 1
                                    # Latency
                                    lat = entry.get('latency_ms')
                                    if lat is not None and isinstance(lat, (int, float)) and lat >= 0:
                                        session['latency_values'].append(lat)
                                    # Files touched
                                    fp = _extract_file_path(entry)
                                    if fp:
                                        tool = entry.get('tool_name', '')
                                        ts = entry.get('timestamp', '')
                                        if fp not in sess_files:
                                            sess_files[fp] = {'ops': {}, 'last_tool': tool, 'last_ts': ts, 'denied': 0}
                                        srec = sess_files[fp]
                                        srec['ops'][tool] = srec['ops'].get(tool, 0) + 1
                                        srec['last_tool'] = tool
                                        srec['last_ts'] = ts
                                        if dec == 'deny':
                                            srec['denied'] += 1
                                # PII (PreToolUse only)
                                for ev in entry.get('evaluators', entry.get('evaluator_results', [])):
                                    for det in ev.get('detections', []):
                                        if det.get('category') == 'pii':
                                            if evt == 'PreToolUse':
                                                session['pii_input'] += 1
                                            break
                            except json.JSONDecodeError:
                                continue
                    except OSError:
                        pass
                    session['files_touched'] = sess_files
            result['session'] = session

            # --- Cumulative Stats ---
            cum_path = PROJECT_DIR / '.lanekeep' / 'cumulative.json'
            cumulative = {}
            if cum_path.exists():
                try:
                    cumulative = json.loads(cum_path.read_text(encoding='utf-8'))
                except (json.JSONDecodeError, OSError):
                    pass
            # Add current session to cumulative totals for display
            # (display-only — cumulative.json on disk is not modified)
            cumulative['total_actions'] = cumulative.get('total_actions', 0) + budget.get('actions', 0)
            cumulative['total_events'] = cumulative.get('total_events', 0) + budget.get('events', 0)
            cumulative['total_tokens'] = cumulative.get('total_tokens', 0) + budget.get('tokens', 0)
            cumulative['total_input_tokens'] = cumulative.get('total_input_tokens', 0) + budget.get('input_tokens', 0)
            cumulative['total_output_tokens'] = cumulative.get('total_output_tokens', 0) + budget.get('output_tokens', 0)
            elapsed_secs = round((budget.get('elapsed_min', 0) or 0) * 60)
            cumulative['total_time_seconds'] = cumulative.get('total_time_seconds', 0) + elapsed_secs
            cumulative['total_sessions'] = cumulative.get('total_sessions', 0) + 1
            # Replace lossy cumulative.json qualitative fields with trace-derived data
            alltime = _compute_alltime_from_traces(trace_dir)
            cumulative['decisions'] = alltime['decisions']
            cumulative['top_denied_tools'] = alltime['top_denied_tools']
            cumulative['top_evaluators'] = alltime['top_evaluators']
            cumulative['pii'] = {'input': alltime['pii_input']}
            cumulative['latency'] = alltime['latency']
            cumulative['files_touched'] = alltime['files_touched']
            result['cumulative'] = cumulative

            # --- File Map ---
            lanekeep_dir_path = Path(os.environ.get('LANEKEEP_DIR', str(PROJECT_DIR / 'lanekeep')))
            home_dir = Path.home()
            file_map = [
                {'group': 'Project', 'entries': [
                    {'path': 'lanekeep.json', 'note': 'Project config (extends defaults)', 'exists': (PROJECT_DIR / 'lanekeep.json').exists()},
                    {'path': '.lanekeep/taskspec.json', 'note': 'Active task specification', 'exists': (PROJECT_DIR / '.lanekeep' / 'taskspec.json').exists()},
                    {'path': '.lanekeep/state.json', 'note': 'Session state (action count, tokens)', 'exists': (PROJECT_DIR / '.lanekeep' / 'state.json').exists()},
                    {'path': '.lanekeep/cumulative.json', 'note': 'All-time stats', 'exists': (PROJECT_DIR / '.lanekeep' / 'cumulative.json').exists()},
                    {'path': '.lanekeep/bookmarks.json', 'note': 'File bookmarks', 'exists': (PROJECT_DIR / '.lanekeep' / 'bookmarks.json').exists()},
                    {'path': '.lanekeep/traces/', 'note': 'JSONL audit traces', 'exists': (PROJECT_DIR / '.lanekeep' / 'traces').exists()},
                ]},
                {'group': 'LaneKeep', 'entries': [
                    {'path': 'defaults/lanekeep.json', 'note': 'Default rules and config', 'exists': (lanekeep_dir_path / 'defaults' / 'lanekeep.json').exists()},
                    {'path': 'defaults/compat.json', 'note': 'Platform compatibility', 'exists': (lanekeep_dir_path / 'defaults' / 'compat.json').exists()},
                    {'path': 'plugins.d/', 'note': 'Plugin evaluators', 'exists': (lanekeep_dir_path / 'plugins.d').exists()},
                ]},
                {'group': 'Platform', 'entries': [
                    {'path': '.claude/settings.json', 'note': 'Claude Code settings', 'exists': (home_dir / '.claude' / 'settings.json').exists()},
                    {'path': '.claude/settings.local.json', 'note': 'Local settings override', 'exists': (home_dir / '.claude' / 'settings.local.json').exists()},
                    {'path': 'CLAUDE.md', 'note': 'Project instructions', 'exists': (PROJECT_DIR / 'CLAUDE.md').exists()},
                    {'path': '.claude/CLAUDE.md', 'note': 'User-level instructions', 'exists': (home_dir / '.claude' / 'CLAUDE.md').exists()},
                    {'path': '.cursorrules', 'note': 'Cursor rules file', 'exists': (PROJECT_DIR / '.cursorrules').exists()},
                    {'path': '.cursor/rules/', 'note': 'Cursor rules directory', 'exists': (PROJECT_DIR / '.cursor' / 'rules').exists()},
                    {'path': '.ralph/', 'note': 'Ralph context events', 'exists': (PROJECT_DIR / '.ralph').exists()},
                ]},
            ]
            result['file_map'] = file_map

            socket_path_str = os.environ.get('LANEKEEP_SOCKET')
            if socket_path_str:
                socket_path = Path(socket_path_str)
            else:
                socket_path = PROJECT_DIR / '.lanekeep' / 'lanekeep.sock'
            global _sidecar_cache
            sock_str = str(socket_path)
            now = time.time()
            if now - _sidecar_cache['ts'] < 3:
                running = _sidecar_cache['running']
            else:
                running = False
                if socket_path.is_socket():
                    try:
                        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                        s.settimeout(0.3)
                        s.connect(sock_str)
                        s.shutdown(socket.SHUT_WR)
                        data = s.recv(4096)
                        s.close()
                        if data:
                            resp = data.decode('utf-8', errors='replace').strip()
                            probe = json.loads(resp)
                            if 'decision' in probe:
                                running = True
                    except (ConnectionRefusedError, OSError, json.JSONDecodeError,
                            UnicodeDecodeError, ValueError):
                        pass
                _sidecar_cache = {'running': running, 'ts': now}
            result['sidecar_running'] = running

            data = json.dumps(result, indent=2).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error serving status: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _fetch_remote_defaults(self):
        """Remote rule updates are a Pro feature. Always returns an error."""
        return None, 'Remote rule updates are a Pro feature'

    def _diff_rule_ids(self, local_rules, remote_rules):
        """Return (new_ids, removed_ids) comparing local vs remote rule IDs."""
        local_ids = {r['id'] for r in local_rules if 'id' in r}
        remote_ids = {r['id'] for r in remote_rules if 'id' in r}
        new_ids = sorted(remote_ids - local_ids)
        removed_ids = sorted(local_ids - remote_ids)
        return new_ids, removed_ids

    def _serve_audit(self):
        try:
            cmd = [str(LANEKEEP_DIR / 'bin' / 'lanekeep-audit')]
            env = dict(os.environ)
            env['PROJECT_DIR'] = str(PROJECT_DIR) if PROJECT_DIR else os.getcwd()
            env['LANEKEEP_DIR'] = str(LANEKEEP_DIR)

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30, env=env)
            output = result.stdout

            sections = []
            current_section = None

            for line in output.splitlines():
                stripped = line.strip()
                if not stripped:
                    continue

                # Summary line
                m = re.match(r'Audit complete:\s*(\d+)\s*error\(s\),\s*(\d+)\s*warning\(s\),\s*(\d+)\s*info\(s\)', stripped)
                if m:
                    continue  # handled below from globals

                # Section header: non-indented line ending with ... or :
                if not line.startswith(' ') and (stripped.endswith('...') or stripped.endswith(':')):
                    current_section = {'name': stripped.rstrip('.:').rstrip('.'), 'ok': True, 'findings': []}
                    sections.append(current_section)
                    continue

                # Skip the title line "lanekeep audit"
                if stripped == 'lanekeep audit':
                    continue

                # Findings: ERROR/WARN/INFO prefixed lines
                fm = re.match(r'(ERROR|WARN|INFO):\s*(.*)', stripped)
                if fm:
                    level_map = {'ERROR': 'error', 'WARN': 'warning', 'INFO': 'info'}
                    level = level_map[fm.group(1)]
                    if current_section:
                        current_section['findings'].append({'level': level, 'message': fm.group(2)})
                        if level in ('error', 'warning'):
                            current_section['ok'] = False
                    continue

                # OK line
                if stripped == 'OK':
                    continue

                # Count/info lines (e.g. "186 default rules, 0 custom rules")
                if current_section and (re.match(r'^\d+', stripped) or stripped.startswith('No ')):
                    current_section['findings'].append({'level': 'info', 'message': stripped})
                    continue

            # Parse summary from output
            errors = 0
            warnings = 0
            infos = 0
            sm = re.search(r'Audit complete:\s*(\d+)\s*error\(s\),\s*(\d+)\s*warning\(s\),\s*(\d+)\s*info\(s\)', output)
            if sm:
                errors = int(sm.group(1))
                warnings = int(sm.group(2))
            # Count infos from actual findings (server adds info-level entries
            # like stat lines that lanekeep-audit doesn't count)
            infos = sum(1 for sec in sections for f in sec['findings'] if f['level'] == 'info')

            response = {
                'passed': errors == 0,
                'summary': {'errors': errors, 'warnings': warnings, 'infos': infos},
                'sections': sections,
            }
            try:
                audit_file = (PROJECT_DIR or Path(os.getcwd())) / '.lanekeep' / 'last-audit.json'
                audit_file.parent.mkdir(parents=True, exist_ok=True)
                result = {'ts': datetime.now(timezone.utc).isoformat(), **response}
                audit_file.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
            except Exception:
                pass  # non-critical, don't fail the audit
            data = json.dumps(response).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except subprocess.TimeoutExpired:
            self._respond(504, json.dumps({'error': 'Audit timed out'}), 'application/json')
        except FileNotFoundError:
            self._respond(500, json.dumps({'error': 'lanekeep-audit not found'}), 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error running audit: {e}", file=sys.stderr)
            self._respond(500, json.dumps({'error': 'Internal server error'}), 'application/json')

    def _serve_last_audit(self):
        audit_file = (PROJECT_DIR or Path(os.getcwd())) / '.lanekeep' / 'last-audit.json'
        if not audit_file.is_file():
            self._respond(404, json.dumps({'error': 'No previous audit'}), 'application/json')
            return
        try:
            data = audit_file.read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error serving last audit: {e}", file=sys.stderr)
            self._respond(500, json.dumps({'error': 'Internal server error'}), 'application/json')

    def _serve_graphs(self):
        """Aggregate coverage mapping: frameworks → requirements → rules, plus trace stats."""
        global _graphs_cache
        try:
            # Cache key: config mtime + trace mtime
            config_mtime = 0
            try:
                config_mtime = Path(CONFIG_PATH).stat().st_mtime_ns
            except OSError:
                pass
            trace_dir = PROJECT_DIR / '.lanekeep' / 'traces'
            trace_key = _trace_mtime_key(trace_dir)
            cache_key = (config_mtime, trace_key)
            if cache_key == _graphs_cache['key'] and _graphs_cache['data'] is not None:
                self._respond(200, _graphs_cache['data'], 'application/json')
                return

            # Load config
            with open(CONFIG_PATH) as f:
                config = json.load(f)
            rules_list = config.get('rules', [])

            # Build rule index with compliance tags
            rules_data = {}
            for rule in rules_list:
                rid = rule.get('id', '')
                if not rid:
                    continue
                comp = rule.get('compliance', [])
                rules_data[rid] = {
                    'category': rule.get('category', ''),
                    'decision': rule.get('decision', ''),
                    'reason': rule.get('reason', ''),
                    'compliance': list(comp),
                    'enabled': rule.get('enabled', True),
                    'trace_stats': {'total': 0, 'deny': 0, 'allow': 0, 'warn': 0, 'ask': 0},
                    'files_protected': [],
                    'last_30d_denials': 0,
                }

            # Build evaluator compliance from config
            evaluator_compliance = {}
            evaluators_cfg = config.get('evaluators', {})
            for eval_name, eval_cfg in evaluators_cfg.items():
                if not isinstance(eval_cfg, dict):
                    continue
                cbc = eval_cfg.get('compliance_by_category', {})
                if cbc:
                    all_tags = []
                    for cat_tags in cbc.values():
                        if isinstance(cat_tags, list):
                            all_tags.extend(cat_tags)
                    evaluator_compliance[eval_name] = {
                        'tags': sorted(set(all_tags)),
                        'categories': {k: v for k, v in cbc.items() if isinstance(v, list)},
                        'trace_count': 0,
                    }

            # Read trace data for stats
            now_ts = time.time()
            thirty_days_ago = now_ts - (30 * 86400)
            files_by_rule = {}  # rule_id -> set of file paths
            if trace_dir.exists():
                for trace_file in trace_dir.glob('*.jsonl'):
                    try:
                        with open(trace_file) as f:
                            for line in f:
                                line = line.strip()
                                if not line:
                                    continue
                                try:
                                    entry = json.loads(line)
                                except json.JSONDecodeError:
                                    continue
                                evt = entry.get('event_type', '')
                                is_pre = evt in ('PreToolUse', 'tool_call', '')
                                if not is_pre or evt == 'PostToolUse':
                                    continue
                                dec = entry.get('decision', '')
                                # Check which rule matched
                                matched_rule = entry.get('matched_rule', '')
                                if not matched_rule:
                                    # Try evaluator_results for rule id
                                    for ev in entry.get('evaluators', entry.get('evaluator_results', [])):
                                        mr = ev.get('matched_rule', ev.get('rule_id', ''))
                                        if mr:
                                            matched_rule = mr
                                            break
                                if matched_rule and matched_rule in rules_data:
                                    rd = rules_data[matched_rule]
                                    rd['trace_stats']['total'] += 1
                                    if dec in rd['trace_stats']:
                                        rd['trace_stats'][dec] += 1
                                    # 30-day denials
                                    ts_str = entry.get('timestamp', '')
                                    if dec == 'deny' and ts_str:
                                        try:
                                            dt = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                                            if dt.timestamp() >= thirty_days_ago:
                                                rd['last_30d_denials'] += 1
                                        except (ValueError, AttributeError):
                                            rd['last_30d_denials'] += 1
                                    # Files protected
                                    fp = _extract_file_path(entry)
                                    if fp and dec == 'deny':
                                        if matched_rule not in files_by_rule:
                                            files_by_rule[matched_rule] = set()
                                        files_by_rule[matched_rule].add(fp)
                                # Count trace events per evaluator
                                for ev in entry.get('evaluators', entry.get('evaluator_results', [])):
                                    ename = ev.get('name', ev.get('evaluator', ''))
                                    if ename in evaluator_compliance:
                                        evaluator_compliance[ename]['trace_count'] += 1
                    except OSError:
                        continue

            # Populate files_protected (top 10 per rule)
            for rid, fps in files_by_rule.items():
                if rid in rules_data:
                    rules_data[rid]['files_protected'] = sorted(fps)[:10]

            # Build frameworks structure
            def _framework_prefix(tag):
                """Extract framework name from a compliance tag like 'PCI-DSS 7.1'."""
                # Known multi-word prefixes
                for prefix in ('AU Privacy Act', 'NIST SP800-53'):
                    if tag.startswith(prefix):
                        return prefix
                # General: split on first space/section-sign
                for sep in (' ', '\u00a7'):
                    idx = tag.find(sep)
                    if idx > 0:
                        return tag[:idx]
                return tag

            frameworks = {}
            # From rules
            for rid, rd in rules_data.items():
                for tag in rd['compliance']:
                    fw = _framework_prefix(tag)
                    if fw not in frameworks:
                        frameworks[fw] = {'requirements': {}}
                    req = tag
                    if req not in frameworks[fw]['requirements']:
                        frameworks[fw]['requirements'][req] = {
                            'rules': [],
                            'trace_count': 0,
                            'last_triggered': '',
                        }
                    fr = frameworks[fw]['requirements'][req]
                    if rid not in fr['rules']:
                        fr['rules'].append(rid)
                    fr['trace_count'] += rd['trace_stats']['total']

            # From evaluator compliance
            for ename, edata in evaluator_compliance.items():
                for tag in edata['tags']:
                    fw = _framework_prefix(tag)
                    if fw not in frameworks:
                        frameworks[fw] = {'requirements': {}}
                    req = tag
                    if req not in frameworks[fw]['requirements']:
                        frameworks[fw]['requirements'][req] = {
                            'rules': [],
                            'trace_count': 0,
                            'last_triggered': '',
                        }
                    fr = frameworks[fw]['requirements'][req]
                    evaluator_ref = f'eval:{ename}'
                    if evaluator_ref not in fr['rules']:
                        fr['rules'].append(evaluator_ref)
                    fr['trace_count'] += edata['trace_count']

            result = {
                'frameworks': frameworks,
                'rules': rules_data,
                'evaluator_compliance': evaluator_compliance,
            }
            response_body = json.dumps(result)
            _graphs_cache['key'] = cache_key
            _graphs_cache['data'] = response_body
            self._respond(200, response_body, 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error serving graphs: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _serve_config_trees(self):
        try:
            home = Path.home()
            skip_dirs = {'.git', 'node_modules', '__pycache__', '.tox', '.mypy_cache', '.venv'}
            max_per_group = 5000
            groups = []
            root = PROJECT_DIR if PROJECT_DIR else Path(os.getcwd())

            # Group 0: Project — all files in project root
            all_project_files = []
            for p in sorted(root.rglob('*')):
                if not p.is_file():
                    continue
                parts = p.relative_to(root).parts
                if any(part in skip_dirs for part in parts):
                    continue
                try:
                    sz = p.stat().st_size
                except OSError:
                    sz = 0
                all_project_files.append({'p': str(p.relative_to(root)), 't': (sz + 3) // 4, 's': sz})
                if len(all_project_files) >= max_per_group:
                    break
            groups.append({'name': 'Project', 'root': str(root), 'files': all_project_files})

            # Group 2: LaneKeep install dir
            lanekeep_dir = Path(os.environ.get('LANEKEEP_DIR', str(LANEKEEP_DIR)))
            lk_files = []
            if lanekeep_dir.is_dir():
                for p in sorted(lanekeep_dir.rglob('*')):
                    if not p.is_file():
                        continue
                    parts = p.relative_to(lanekeep_dir).parts
                    if any(part.startswith('.') or part in skip_dirs for part in parts):
                        continue
                    try:
                        sz = p.stat().st_size
                    except OSError:
                        sz = 0
                    lk_files.append({'p': str(p.relative_to(lanekeep_dir)), 't': (sz + 3) // 4, 's': sz})
                    if len(lk_files) >= max_per_group:
                        break
            groups.append({'name': 'LaneKeep', 'root': str(lanekeep_dir), 'files': lk_files})

            # Group 3: Platform — ~/.claude/
            claude_dir = home / '.claude'
            platform_files = []
            if claude_dir.is_dir():
                skip_exts = {'.jsonl'}
                for p in sorted(claude_dir.rglob('*')):
                    if not p.is_file():
                        continue
                    if p.suffix in skip_exts:
                        continue
                    parts = p.relative_to(claude_dir).parts
                    if any(part.startswith('.') or part in skip_dirs for part in parts):
                        continue
                    try:
                        sz = p.stat().st_size
                    except OSError:
                        sz = 0
                    platform_files.append({'p': str(p.relative_to(claude_dir)), 't': (sz + 3) // 4, 's': sz})
                    if len(platform_files) >= max_per_group:
                        break
            groups.append({'name': 'Platform', 'root': str(claude_dir), 'files': platform_files})

            data = json.dumps({'groups': groups}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error serving config trees: {e}", file=sys.stderr)
            self._respond(500, json.dumps({'error': 'Internal server error'}), 'application/json')

    def _serve_context(self):
        """Return context files (markdown, config, etc.) visible in the project."""
        try:
            files = []
            project_real = os.path.realpath(str(PROJECT_DIR))
            skip_dirs = {'.git', '.lanekeep', '.claude', 'node_modules', '__pycache__', '.venv', '.svn', '.hg'}
            for root, dirs, filenames in os.walk(str(PROJECT_DIR)):
                # MED-06: Filter symlinked directories to prevent traversal outside project
                dirs[:] = [d for d in dirs
                           if d not in skip_dirs and not d.startswith('.')
                           and not os.path.islink(os.path.join(root, d))]
                rel_root = os.path.relpath(root, str(PROJECT_DIR))
                for fn in sorted(filenames):
                    full_path = os.path.join(root, fn)
                    # MED-06: Skip symlinked files and files resolving outside project
                    if os.path.islink(full_path):
                        continue
                    if not os.path.realpath(full_path).startswith(project_real + os.sep):
                        continue
                    if fn.endswith(('.md', '.json', '.yaml', '.yml', '.toml', '.txt', '.cfg', '.ini', '.conf')):
                        if rel_root == '.':
                            files.append(fn)
                        else:
                            files.append(f"{rel_root}/{fn}")
            data = json.dumps({'files': files}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error serving context: {e}", file=sys.stderr)
            self._respond(500, json.dumps({'error': 'Internal server error'}), 'application/json')

    def _serve_docs(self, qs):
        _DOCS_MAP = {
            'readme': ('User Guide', LANEKEEP_DIR / 'README.md'),
            'developer': ('Developer Guide', LANEKEEP_DIR / 'CLAUDE.md'),
            'contributing': ('Contributing', LANEKEEP_DIR / 'CONTRIBUTING.md'),
            'security': ('Security', LANEKEEP_DIR / 'SECURITY.md'),
            'license': ('License', LANEKEEP_DIR / 'LICENSE'),
            'team': ('Team', LANEKEEP_DIR / 'ee' / 'README.md'),
        }
        doc_key = qs.get('doc', ['readme'])[0]
        if doc_key not in _DOCS_MAP:
            self._respond(400, json.dumps({'error': 'Invalid doc parameter'}), 'application/json')
            return
        title, doc_path = _DOCS_MAP[doc_key]
        try:
            if not doc_path.exists():
                self._respond(404, json.dumps({'error': 'Document not found'}), 'application/json')
                return
            mtime = doc_path.stat().st_mtime
            cached = _docs_cache.get(doc_key)
            if cached and cached['mtime'] == mtime:
                html_content = cached['data']
            else:
                md_text = doc_path.read_text(encoding='utf-8')
                # Strip leading HTML blocks (GitHub-specific logo + badges, rendered natively in UI)
                md_text = re.sub(r'^(<p[^>]*>.*?</p>\s*)+', '', md_text, flags=re.DOTALL)
                # Strip trailing HTML footer (GitHub-specific, not for Docs viewer)
                md_text = re.sub(r'\n---\s*\n\s*<div\b.*', '', md_text, flags=re.DOTALL)
                html_content = _md_to_html(md_text)
                _docs_cache[doc_key] = {'mtime': mtime, 'data': html_content}
            result = json.dumps({'title': title, 'html': html_content})
            self._respond(200, result, 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error serving doc: {e}", file=sys.stderr)
            self._respond(500, json.dumps({'error': 'Internal server error'}), 'application/json')

    def _serve_rules_update_check(self):
        try:
            defaults_path = LANEKEEP_DIR / 'defaults' / 'lanekeep.json'
            if not defaults_path.exists():
                self._respond(500, json.dumps({'error': 'Defaults file not found'}), 'application/json')
                return
            local_data = json.loads(defaults_path.read_text(encoding='utf-8'))
            local_rules = local_data.get('rules', [])

            remote_data, err = self._fetch_remote_defaults()
            if err:
                self._respond(502, json.dumps({'error': f'Failed to fetch remote: {err}'}), 'application/json')
                return
            remote_rules = remote_data.get('rules', [])

            new_ids, removed_ids = self._diff_rule_ids(local_rules, remote_rules)
            # Include details for new rules
            new_rules_detail = []
            for rule in remote_rules:
                if rule.get('id') in new_ids:
                    new_rules_detail.append({
                        'id': rule['id'],
                        'category': rule.get('category', ''),
                        'decision': rule.get('decision', ''),
                        'reason': rule.get('reason', ''),
                    })

            result = {
                'available': len(new_ids) > 0 or len(removed_ids) > 0,
                'new_rules': new_rules_detail,
                'removed_ids': removed_ids,
                'local_count': len(local_rules),
                'remote_count': len(remote_rules),
            }
            data = json.dumps(result).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error checking rule updates: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _clear_trace(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length > MAX_BODY or length < 0:
                self._respond(413, 'Payload too large')
                return
            body = json.loads(self.rfile.read(length)) if length > 0 else {}
            older_than = body.get('older_than', '')
            clear_all = body.get('all', False)

            # Build CLI args
            cmd = [str(LANEKEEP_DIR / 'bin' / 'lanekeep-trace'), 'clear']
            if clear_all:
                cmd.append('--all')
            elif older_than:
                cmd.extend(['--older-than', str(older_than)])

            env = dict(os.environ)
            env['PROJECT_DIR'] = str(PROJECT_DIR) if PROJECT_DIR else os.getcwd()
            env['LANEKEEP_DIR'] = str(LANEKEEP_DIR)

            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30, env=env)
            output = result.stdout.strip()
            if result.returncode != 0:
                err = result.stderr.strip() or output or 'Unknown error'
                self._respond(500, json.dumps({'error': err}), 'application/json')
                return
            self._respond(200, json.dumps({'message': output}), 'application/json')
        except subprocess.TimeoutExpired:
            self._respond(504, json.dumps({'error': 'Trace clear timed out'}), 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error clearing traces: {e}", file=sys.stderr)
            self._respond(500, json.dumps({'error': 'Internal server error'}), 'application/json')

    def _apply_rules_update(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length > MAX_BODY or length < 0:
                self._respond(413, 'Payload too large')
                return
            body = json.loads(self.rfile.read(length)) if length > 0 else {}
            enable_new = body.get('enable_new', False)

            defaults_path = LANEKEEP_DIR / 'defaults' / 'lanekeep.json'
            if not defaults_path.exists():
                self._respond(500, json.dumps({'error': 'Defaults file not found'}), 'application/json')
                return
            local_data = json.loads(defaults_path.read_text(encoding='utf-8'))
            local_rules = local_data.get('rules', [])

            remote_data, err = self._fetch_remote_defaults()
            if err:
                self._respond(502, json.dumps({'error': f'Failed to fetch remote: {err}'}), 'application/json')
                return
            remote_rules = remote_data.get('rules', [])

            new_ids, _ = self._diff_rule_ids(local_rules, remote_rules)

            # Backup current defaults
            backup_path = str(defaults_path) + '.bak'
            shutil.copy2(str(defaults_path), backup_path)

            # Atomic replace: write to temp file then rename
            fd = tempfile.NamedTemporaryFile(
                dir=str(defaults_path.parent), prefix='.lanekeep-defaults-', suffix='.tmp',
                delete=False, mode='w')
            try:
                fd.write(json.dumps(remote_data, indent=2) + '\n')
                fd.close()
                os.replace(fd.name, str(defaults_path))
            except BaseException:
                os.unlink(fd.name)
                raise

            # Handle disabled_rules in project config
            if not enable_new and new_ids:
                user_config = PROJECT_DIR / 'lanekeep.json'
                if not user_config.exists():
                    cfg = {'extends': 'defaults', 'disabled_rules': list(new_ids)}
                    user_config.write_text(json.dumps(cfg, indent=2) + '\n', encoding='utf-8')
                else:
                    cfg = json.loads(user_config.read_text(encoding='utf-8'))
                    extends = cfg.get('extends', '')
                    if extends == 'defaults':
                        existing = cfg.get('disabled_rules', [])
                        merged = sorted(set(existing) | set(new_ids))
                        cfg['disabled_rules'] = merged
                        user_config.write_text(json.dumps(cfg, indent=2) + '\n', encoding='utf-8')
                    # Legacy config: skip (user should migrate first)

            result = {
                'ok': True,
                'new_count': len(new_ids),
                'new_ids': list(new_ids),
            }
            data = json.dumps(result).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', len(data))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error applying rule update: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _save_config(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length > MAX_BODY or length < 0:
                self._respond(413, 'Payload too large')
                return
            if length == 0:
                self._respond(400, json.dumps({'error': 'Empty request body'}), 'application/json')
                return
            body = json.loads(self.rfile.read(length))
            new_rules = body.get('rules', [])

            # Validate required fields and decision enum
            for rule in new_rules:
                for field in ('match', 'decision', 'reason'):
                    if field not in rule:
                        self._respond(400, json.dumps({'error': f'Rule missing required field: {field}'}), 'application/json')
                        return
                if rule.get('decision') not in VALID_DECISIONS:
                    self._respond(400, json.dumps({'error': 'Invalid rule decision'}), 'application/json')
                    return

            # Validate regex patterns against ReDoS risk
            for rule in new_rules:
                for field in ('pattern', 'command', 'target'):
                    val = rule.get('match', {}).get(field, '')
                    if val and _REDOS_PATTERN.search(val):
                        self._respond(400, json.dumps({'error': f'ReDoS risk in rule pattern: {val}'}), 'application/json')
                        return

            # Validate policy patterns against ReDoS risk
            policies_data = body.get('policies', {})
            if isinstance(policies_data, dict):
                policies_data = policies_data.values()
            for policy in policies_data:
                if not isinstance(policy, dict):
                    continue
                for list_field in ('allowed', 'denied'):
                    for val in policy.get(list_field, []):
                        if val and isinstance(val, str) and _REDOS_PATTERN.search(val):
                            self._respond(400, json.dumps({'error': f'ReDoS risk in policy pattern: {val}'}), 'application/json')
                            return

            # Read existing config, update only the rules array
            with open(CONFIG_PATH) as f:
                config = json.load(f)

            # Backup before writing
            backup = str(CONFIG_PATH) + '.bak'
            shutil.copy2(CONFIG_PATH, backup)

            config['rules'] = new_rules

            if 'policies' in body:
                config['policies'] = body['policies']

            # Compute hash of new content, write hash first to avoid race (M2)
            new_content = json.dumps(config, indent=2) + '\n'
            new_hash = hashlib.sha256(new_content.encode()).hexdigest()
            self._write_config_hash(new_hash)

            # Atomic write: temp file + rename
            fd = tempfile.NamedTemporaryFile(
                dir=str(Path(CONFIG_PATH).parent),
                prefix='.lanekeep_config.',
                suffix='.tmp',
                delete=False,
                mode='w',
            )
            try:
                fd.write(new_content)
                fd.close()
                os.replace(fd.name, str(CONFIG_PATH))
            except BaseException:
                os.unlink(fd.name)
                raise
            self._respond(200, json.dumps({'ok': True}), 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error: {e}", file=sys.stderr)
            self._respond_json_error(500)

    @staticmethod
    def _validate_settings(body):
        """Validate settings payload. Returns (ok, error_message)."""
        VALID_PROFILES = {'strict', 'guided', 'autonomous', ''}
        VALID_PLATFORMS = {'linux', 'macos', 'windows'}

        # Profile
        if 'profile' in body:
            if body['profile'] not in VALID_PROFILES:
                return False, 'Invalid profile value'

        # Budget — all fields must be non-negative integers
        if 'budget' in body:
            b = body['budget']
            if not isinstance(b, dict):
                return False, 'budget must be an object'
            BUDGET_FIELDS = {'max_actions', 'max_input_tokens', 'max_output_tokens',
                             'max_tokens', 'timeout_seconds', 'max_total_actions',
                             'max_total_input_tokens', 'max_total_output_tokens',
                             'max_total_tokens', 'max_total_time_seconds'}
            for k, v in b.items():
                if k in BUDGET_FIELDS:
                    if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                        return False, f'budget.{k} must be a non-negative integer'

        # Notifications
        if 'notifications' in body:
            n = body['notifications']
            if not isinstance(n, dict):
                return False, 'notifications must be an object'
            if 'enabled' in n and not isinstance(n['enabled'], bool):
                return False, 'notifications.enabled must be a boolean'
            if 'on_stop' in n and not isinstance(n['on_stop'], bool):
                return False, 'notifications.on_stop must be a boolean'
            if 'min_session_seconds' in n:
                v = n['min_session_seconds']
                if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                    return False, 'notifications.min_session_seconds must be a non-negative integer'
            if 'platform' in n and n['platform'] not in VALID_PLATFORMS:
                return False, f'notifications.platform must be one of: {", ".join(sorted(VALID_PLATFORMS))}'

        # Trace
        if 'trace' in body:
            t = body['trace']
            if not isinstance(t, dict):
                return False, 'trace must be an object'
            if 'retention_days' in t:
                v = t['retention_days']
                if not isinstance(v, int) or isinstance(v, bool) or v < 1:
                    return False, 'trace.retention_days must be a positive integer'
            if 'max_sessions' in t:
                v = t['max_sessions']
                if not isinstance(v, int) or isinstance(v, bool) or v < 1:
                    return False, 'trace.max_sessions must be a positive integer'

        # Autoformat
        if 'autoformat' in body:
            a = body['autoformat']
            if not isinstance(a, dict):
                return False, 'autoformat must be an object'
            if 'enabled' in a and not isinstance(a['enabled'], bool):
                return False, 'autoformat.enabled must be a boolean'

        # Sandbox
        if 'sandbox' in body:
            sb = body['sandbox']
            if not isinstance(sb, dict):
                return False, 'sandbox must be an object'
            if 'enabled' in sb and not isinstance(sb['enabled'], bool):
                return False, 'sandbox.enabled must be a boolean'

        # Evaluators semantic
        if 'evaluators_semantic' in body:
            es = body['evaluators_semantic']
            if not isinstance(es, dict):
                return False, 'evaluators_semantic must be an object'
            if 'enabled' in es and not isinstance(es['enabled'], bool):
                return False, 'evaluators_semantic.enabled must be a boolean'
            if 'model' in es and not isinstance(es['model'], str):
                return False, 'evaluators_semantic.model must be a string'

        return True, None

    @staticmethod
    def _deep_merge(base, overlay):
        """Merge overlay into base dict recursively. Returns merged dict."""
        merged = dict(base)
        for k, v in overlay.items():
            if k in merged and isinstance(merged[k], dict) and isinstance(v, dict):
                merged[k] = Handler._deep_merge(merged[k], v)
            else:
                merged[k] = v
        return merged

    def _save_settings(self):
        """Save operational settings (profile, notifications, budget, trace, etc.)
        without touching rules or policies."""
        # Note: evaluators_semantic is absent from ALLOWED_KEYS because it is
        # remapped to config.evaluators.semantic below (lines 1366-1371).
        ALLOWED_KEYS = {'profile', 'notifications', 'budget', 'trace', 'autoformat', 'sandbox'}
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length > MAX_BODY or length < 0:
                self._respond(413, 'Payload too large')
                return
            if length == 0:
                self._respond(400, json.dumps({'error': 'Empty request body'}), 'application/json')
                return
            body = json.loads(self.rfile.read(length))

            # Validate all fields
            ok, err = self._validate_settings(body)
            if not ok:
                self._respond(400, json.dumps({'error': err}), 'application/json')
                return

            with open(CONFIG_PATH) as f:
                config = json.load(f)

            # Backup before writing
            backup = str(CONFIG_PATH) + '.bak'
            shutil.copy2(CONFIG_PATH, backup)

            # Deep-merge allowed top-level keys (preserves unset nested fields)
            for key in ALLOWED_KEYS:
                if key in body:
                    if key == 'profile':
                        config[key] = body[key]
                    elif isinstance(body[key], dict) and isinstance(config.get(key), dict):
                        config[key] = self._deep_merge(config[key], body[key])
                    else:
                        config[key] = body[key]

            # evaluators_semantic -> config.evaluators.semantic (deep merge)
            if 'evaluators_semantic' in body:
                if 'evaluators' not in config:
                    config['evaluators'] = {}
                existing = config['evaluators'].get('semantic', {})
                config['evaluators']['semantic'] = self._deep_merge(existing, body['evaluators_semantic'])

            new_content = json.dumps(config, indent=2) + '\n'
            new_hash = hashlib.sha256(new_content.encode()).hexdigest()
            self._write_config_hash(new_hash)

            # Atomic write: temp file + rename
            fd = tempfile.NamedTemporaryFile(
                dir=str(Path(CONFIG_PATH).parent),
                prefix='.lanekeep_config.',
                suffix='.tmp',
                delete=False,
                mode='w',
            )
            try:
                fd.write(new_content)
                fd.close()
                os.replace(fd.name, str(CONFIG_PATH))
            except BaseException:
                os.unlink(fd.name)
                raise
            self._respond(200, json.dumps({'ok': True}), 'application/json')
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            print(f"[LaneKeep UI] Error saving settings: {e}", file=sys.stderr)
            self._respond_json_error(500)

    def _write_config_hash(self, digest):
        """Write a pre-computed SHA-256 digest to .lanekeep/config_hash.
        Uses atomic write (temp + rename) with 0600 permissions."""
        try:
            hash_file = PROJECT_DIR / '.lanekeep' / 'config_hash'
            hash_file.parent.mkdir(parents=True, exist_ok=True)
            fd = tempfile.NamedTemporaryFile(
                dir=str(hash_file.parent),
                prefix='.config_hash.',
                delete=False,
                mode='w',
            )
            try:
                fd.write(digest + '\n')
                fd.close()
                os.chmod(fd.name, 0o600)
                os.replace(fd.name, str(hash_file))
            except BaseException:
                os.unlink(fd.name)
                raise
        except OSError as e:
            print(f"[LaneKeep UI] Warning: could not update config hash: {e}", file=sys.stderr)

    def _send_security_headers(self, nonce=None):
        """Send security headers. If nonce is provided, use it for CSP script-src."""
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        if nonce:
            csp = (f"default-src 'self'; script-src 'nonce-{nonce}'; "
                   f"style-src 'self' 'unsafe-inline'; object-src 'none'; "
                   f"base-uri 'self'; form-action 'self'; frame-ancestors 'none'")
        else:
            csp = ("default-src 'self'; script-src 'self'; "
                   "style-src 'self' 'unsafe-inline'; object-src 'none'; "
                   "base-uri 'self'; form-action 'self'; frame-ancestors 'none'")
        self.send_header('Content-Security-Policy', csp)

    def _respond_json_error(self, code, message='Internal server error'):
        self._respond(code, json.dumps({'error': message}), 'application/json')

    def _respond(self, code, body, content_type='text/plain'):
        try:
            data = body.encode() if isinstance(body, str) else body
            self.send_response(code)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', len(data))
            self._send_security_headers()
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, fmt, *args):
        # Quiet logging
        pass


def _ensure_self_signed_cert(cert_dir):
    """Generate a self-signed cert+key pair if they don't already exist."""
    cert_path = cert_dir / 'localhost.pem'
    key_path = cert_dir / 'localhost-key.pem'
    if cert_path.exists() and key_path.exists():
        return cert_path, key_path
    cert_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
        '-keyout', str(key_path), '-out', str(cert_path),
        '-days', '365', '-nodes',
        '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
    ], check=True, capture_output=True)
    os.chmod(str(key_path), 0o600)
    return cert_path, key_path


def main():
    global CONFIG_PATH, PROJECT_DIR, TLS_ACTIVE, ALLOWED_READ_ROOTS

    parser = argparse.ArgumentParser(description='LaneKeep Rules UI server')
    parser.add_argument('--port', type=int, default=8111, help='Port (default: 8111)')
    parser.add_argument('--config', type=str, required=True, help='Path to lanekeep.json')
    parser.add_argument('--project-dir', type=str, default=None, help='Project root directory')
    parser.add_argument('--tls', action='store_true', help='Enable TLS (HTTPS)')
    parser.add_argument('--cert', type=str, default=None, help='Path to TLS certificate')
    parser.add_argument('--key', type=str, default=None, help='Path to TLS private key')
    args = parser.parse_args()

    CONFIG_PATH = Path(args.config).resolve()
    if not CONFIG_PATH.exists():
        print(f"Error: config not found: {CONFIG_PATH}")
        raise SystemExit(1)

    if args.project_dir:
        PROJECT_DIR = Path(args.project_dir).resolve()
    else:
        PROJECT_DIR = CONFIG_PATH.parent

    ALLOWED_READ_ROOTS = [
        PROJECT_DIR.resolve(),
        Path(os.environ.get('LANEKEEP_DIR', str(PROJECT_DIR / 'lanekeep'))).resolve(),
        (Path.home() / '.claude').resolve(),
    ]

    # Try requested port, auto-increment on conflict (defense-in-depth)
    port = args.port
    server = None
    for _attempt in range(10):
        try:
            server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
            break
        except OSError:
            port += 1
    if server is None:
        print(f"Error: no free port in range {args.port}-{port - 1}", file=sys.stderr)
        raise SystemExit(1)

    # Write authoritative port after successful bind
    port_file = PROJECT_DIR / '.lanekeep' / 'ui-port'
    port_file.parent.mkdir(parents=True, exist_ok=True)
    port_file.write_text(str(port))

    if args.tls:
        if args.cert and args.key:
            cert_path, key_path = Path(args.cert), Path(args.key)
        else:
            cert_dir = Path.home() / '.lanekeep' / 'tls'
            cert_path, key_path = _ensure_self_signed_cert(cert_dir)
            print(f"TLS cert: {cert_path}")
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(str(cert_path), str(key_path))
        server.socket = ctx.wrap_socket(server.socket, server_side=True)
        TLS_ACTIVE = True
        scheme = 'https'
    else:
        scheme = 'http'

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == '__main__':
    main()
