"""Inspect AAB native ELF load alignment using only Python's standard library.

This does not replace Play's bundle validation, generated-APK zip alignment,
or a physical 16-KB-device smoke test.
"""
import argparse
import hashlib
import json
import struct
import zipfile
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('bundle', type=Path)
    args = parser.parse_args()
    native = []
    with zipfile.ZipFile(args.bundle) as archive:
        assert archive.testzip() is None, 'Corrupt ZIP member'
        assert 'base/manifest/AndroidManifest.xml' in archive.namelist()
        for name in archive.namelist():
            if not name.endswith('.so'):
                continue
            data = archive.read(name)
            assert data[:4] == b'\x7fELF', name
            endian = '<' if data[5] == 1 else '>'
            is64 = data[4] == 2
            phoff = struct.unpack_from(endian + ('Q' if is64 else 'I'), data, 32 if is64 else 28)[0]
            entsize, count = struct.unpack_from(endian + 'HH', data, 54 if is64 else 42)
            aligns = []
            for i in range(count):
                offset = phoff + i * entsize
                if struct.unpack_from(endian + 'I', data, offset)[0] == 1:
                    aligns.append(struct.unpack_from(endian + ('Q' if is64 else 'I'), data, offset + (48 if is64 else 28))[0])
            ok = bool(aligns) and all(a >= 16384 for a in aligns)
            native.append({'file': name, 'load_alignment': aligns, '16kb_aligned': ok})
            if '/arm64-v8a/' in name or '/x86_64/' in name:
                assert ok, f'64-bit native library is not 16 KB aligned: {name}'
    assert any('/arm64-v8a/' in entry['file'] for entry in native), 'Missing ARM64'
    result = {'bundle': args.bundle.name, 'bytes': args.bundle.stat().st_size,
        'sha256': hashlib.sha256(args.bundle.read_bytes()).hexdigest(),
        'native_libraries': native,
        'limit': 'ELF/ZIP integrity check only; Play validation and signed-install tests still required.'}
    output = args.bundle.with_suffix('.verification.json')
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))

if __name__ == '__main__': main()
