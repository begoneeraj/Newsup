"""Check local Android archives without displaying credential values."""
import argparse
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    private_names = {
        'GROQ_API_KEY', 'SUPABASE_SERVICE_KEY', 'SUPABASE_SERVICE_ROLE_KEY',
        'NEWSDATA_API_KEY', 'MEDIASTACK_API_KEY', 'THE_GUARDIAN_API_KEY',
        'YOUTUBE_API_KEY', 'SUPABASE_TOKEN_30_DAY_LIMIT', 'DATA_GOV_IN_API_KEY',
    }
    credentials = {}
    for line in Path('.env').read_text(encoding='utf-8-sig').splitlines():
        name, sep, value = line.partition('=')
        value = value.strip().strip('\"').strip("'")
        if sep and name.strip() in private_names and len(value) >= 8:
            credentials[name.strip()] = value.encode()
    found = set()
    with zipfile.ZipFile(args.archive) as archive:
        for name in archive.namelist():
            data = archive.read(name)
            for key, value in credentials.items():
                if value in data:
                    found.add(key)
            if name.rsplit('/', 1)[-1] == '.env':
                found.add('PACKAGED_ENV_FILE')
    if found:
        raise SystemExit('Private configuration detected: ' + ', '.join(sorted(found)))
    print(f'PASS: no literal values from {len(credentials)} configured server credentials or .env file found in archive. This is not a full security audit.')


if __name__ == '__main__':
    main()
