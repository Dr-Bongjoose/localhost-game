#!/usr/bin/env python3
"""JOO-24 v6 completion hook: reads the tail of the v6 leg log, extracts
per-finding verdict signals, and posts an evidence comment on JOO-24.
The comment fires the issue_commented wake so Game Dev resumes automatically.
Usage: python3 joo24_v6_completion_hook.py <leg_exit_code>
"""
import json, os, re, sys, time, uuid
import urllib.error
import urllib.request

ISSUE = '6d41e893-ece3-435f-80ea-5a5a52464f1b'
LEG_LOG = '/home/bongjoose/localhost-game/builds/device_evidence/joo24_leg_v6.log'
WATCH_LOG = '/home/bongjoose/localhost-game/builds/device_evidence/joo24_v6_watchdog.log'
SHOTS = '/home/bongjoose/localhost-game/builds/qa-shots-m2'

# credentials: env first (live run), durable-file fallback (survives run death)
import json as _json
_cred_path = '/home/bongjoose/.paperclip/tmp/joo24/creds.json'
try:
    _c = _json.load(open(_cred_path))
except Exception:
    _c = {}
api = (os.environ.get('PAPERCLIP_API_URL') or _c.get('api') or '').rstrip('/')
if not api.endswith('/api'): api += '/api'
key = os.environ.get('PAPERCLIP_API_KEY') or _c.get('key') or ''
run = os.environ.get('PAPERCLIP_RUN_ID') or _c.get('run') or ''
if not key:
    print('FATAL: no API credentials (env and durable file both empty)')
    sys.exit(2)

def call(method, path, payload=None, tries=3):
    for i in range(tries):
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(api + path, data=data, method=method)
        req.add_header('Authorization', 'Bearer ' + key)
        req.add_header('User-Agent', 'paperclip-agent/1.0')
        if run: req.add_header('X-Paperclip-Run-Id', run)
        if data: req.add_header('Content-Type', 'application/json')
        try:
            with urllib.request.urlopen(req) as r:
                body = r.read().decode()
                return r.status, (json.loads(body) if body else {})
        except urllib.error.HTTPError as e:
            if e.code in (401, 403, 429, 502, 503) and i < tries - 1:
                time.sleep(3); continue
            raise

def tail(path, n=200):
    try:
        with open(path, errors='replace') as f:
            return ''.join(f.readlines()[-n:])
    except OSError:
        return '(log missing)'

leg_exit = sys.argv[1] if len(sys.argv) > 1 else '?'
leg = tail(LEG_LOG)
watch = tail(WATCH_LOG, 40)

# crude verdict extraction from the leg log
ux3_alive = len(re.findall(r'UX3_BACK\d=ALIVE', leg))
ux3_dead = len(re.findall(r'UX3_BACK\d=PROCESS_DEAD', leg))
installs = 'install: SUCCESS' in leg
probe_ok = 'PROBE_DONE' in leg
raid_ok = 'rapid raid captures done' in leg
leg_done = 'UI leg v6 complete' in leg
shots = sorted(os.listdir(SHOTS)) if os.path.isdir(SHOTS) else []
v6_shots = [s for s in shots if s.startswith('v6_')]

status = 'UNKNOWN'
if leg_exit == '0' and leg_done:
    status = 'LEG_V6_RESULT=done (leg completed fully)'
elif ux3_dead:
    status = 'LEG_V6_RESULT=ux3_regressed (BACK still force-quits)'
elif leg_exit not in ('0', '?'):
    status = f'LEG_V6_RESULT=stage_failed (leg exit code {leg_exit})'

body = f"""## [auto] v6 device leg ran — Game Dev resume hook (watchdog v5)

The JOO-24 disposition card (aae41362, accepted 21:08Z) authorized the v6 device leg on the next available device. A device appeared and the leg ran; this comment is the automated liveness hook so Game Dev picks up the verdicts next heartbeat.

- Leg exit code: {leg_exit} — {status}
- Install: {'SUCCESS' if installs else 'FAILED'}; engine probe: {'OK' if probe_ok else 'FAILED'}
- UX-3 BACK: {ux3_alive} alive / {ux3_dead} dead presses
- Raid captures: {'done' if raid_ok else 'missing'}
- v6 screenshots: {len(v6_shots)} files ({', '.join(v6_shots[:6])}{'…' if len(v6_shots) > 6 else ''})

### Leg log tail
```
{leg[-2500:]}
```
### Watchdog log tail
```
{watch[-800:]}
```

Next action (Game Dev): analyze v6_* captures in builds/qa-shots-m2/, post per-finding verdicts for BUG-1/UX-2, UX-3, UX-4 (BUG-2/UX-5/UX-6 already verified), then hand JOO-24 to The Orb for review.
"""
s, r = call('POST', f'/issues/{ISSUE}/comments',
            {'body': body, 'authorType': 'agent', 'clientRequestId': str(uuid.uuid4())})
rid = r.get('id') if isinstance(r, dict) else None
print('comment POST', s, rid)