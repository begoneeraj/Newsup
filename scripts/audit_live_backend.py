"""Read-only inventory. Print counts/status only; never print keys or URLs with credentials."""
import json
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read_env():
    result = {}
    for line in (ROOT / '.env').read_text(encoding='utf-8').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            name, value = line.split('=', 1)
            result[name.strip()] = value.strip().strip('\"').strip("'")
    return result

def main():
    env = read_env()
    base = env['SUPABASE_URL'].rstrip('/')
    parsed = urllib.parse.urlparse(base)
    if parsed.scheme != 'https' or not parsed.hostname.endswith('.supabase.co'):
        raise SystemExit('Expected a configured HTTPS Supabase project URL.')
    key = env['SUPABASE_PUBLISHABLE_KEY']
    headers = {'apikey': key, 'Prefer': 'count=exact'}
    if key.startswith('eyJ'):
        headers['Authorization'] = 'Bearer ' + key
    tables = {'fact_checks': 'created_at', 'public_events': 'last_updated',
        'science_research_reports': 'processed_at', 'data_stories': 'published_at',
        'govt_promises': 'last_updated', 'slow_crises': None, 'underreported_topics': None}
    result = {'tables': {}, 'env_configured': sorted(name for name, val in env.items() if val)}
    for table, time_field in tables.items():
        fields = time_field or 'id'
        if table == 'fact_checks': fields += ',sources,origin'
        query = {'select': fields, 'limit': '100' if table == 'fact_checks' else '1'}
        if time_field: query['order'] = time_field + '.desc'
        request = urllib.request.Request(base + '/rest/v1/' + table + '?' + urllib.parse.urlencode(query), headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                rows = json.load(response)
                info = {'status': response.status, 'content_range': response.headers.get('Content-Range')}
                if time_field and rows: info['latest'] = rows[0].get(time_field)
                if table == 'fact_checks':
                    info['sample_size'] = len(rows)
                    info['sample_without_source_links'] = sum(not row.get('sources') for row in rows)
                    info['sample_unknown_publisher'] = sum('unnamed' in str(row.get('origin', '')).lower() for row in rows)
                result['tables'][table] = info
        except urllib.error.HTTPError as error:
            result['tables'][table] = {'http_error': error.code}
        except Exception as error:
            result['tables'][table] = {'error_type': type(error).__name__}
    tracked = subprocess.run(['git', 'ls-files', '.env', 'android/key.properties', 'android/app/*.jks'], cwd=ROOT, text=True, capture_output=True)
    result['tracked_secret_files'] = tracked.stdout.splitlines()
    output = ROOT / 'build' / 'live-backend-audit.json'
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))

if __name__ == '__main__': main()
