"""Check provenance hashes and decode every bundled effect on Apple's audio stack."""
from pathlib import Path
import hashlib, json, struct, subprocess, tempfile, sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('Resources/Imported')
manifest = json.loads((root/'manifest.json').read_text())
for asset in manifest['assets']:
    path = root/asset['file']; data = path.read_bytes()
    assert len(data) == asset['bytes'] and hashlib.sha256(data).hexdigest() == asset['sha256'], path
    if asset['kind'] == 'texture':
        assert data[:8] == b'\x89PNG\r\n\x1a\n', path
        assert struct.unpack('>II',data[16:24]) == (512,512), path
        subprocess.run(['sips','-g','pixelWidth','-g','pixelHeight',str(path)],check=True)
    else:
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder)/'decoded.wav'
            subprocess.run(['afconvert','-f','WAVE','-d','LEI16',str(path),str(output)],check=True)
            import wave
            with wave.open(str(output)) as wav:
                seconds = wav.getnframes()/wav.getframerate()
                assert wav.getnchannels() == asset['channels'], path
                assert abs(seconds-asset['seconds']) < 0.2, (path,seconds)
                assert wav.getframerate() == asset['rate'], path
                assert wav.getnframes() > 0, path
    print('VERIFIED',path)
assert {p.name for p in root.iterdir()} == {a['file'] for a in manifest['assets']} | {'manifest.json'}
