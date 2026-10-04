# Records every lines*.json with the Hebrew neural voices, in two spellings (plain and with
# vowel marks), then transcribes each recording with Whisper to check how clearly it reads.
import json, glob, subprocess, unicodedata, re, difflib, os
import numpy as np
from faster_whisper import WhisperModel

VOICES = {'hila': 'he-IL-HilaNeural', 'avri': 'he-IL-AvriNeural'}
os.makedirs('out', exist_ok=True)
norm = lambda w: w.translate(str.maketrans('קטךםןףץ', 'כתכמנפצ'))
plain0 = lambda s: re.sub(r'[^א-ת ]', '', ''.join(c for c in unicodedata.normalize('NFD', s) if not unicodedata.combining(c))).split()
try:
    model = WhisperModel('small', device='cpu', compute_type='int8')
except Exception as e:
    print(f'::warning::whisper not available: {e}')
    model = None
report = []
for path in sorted(glob.glob('marketing/voiceover/lines*.json')):
    name = os.path.basename(path)[:-5]
    for l in json.load(open(path)):
        for tag, voice in VOICES.items():
            variants = [('text', l['text'])] + ([('nikud', l['nikud'])] if 'nikud' in l else []) + [(f'alt{i}', a) for i, a in enumerate(l.get('alts', []))]
            for variant, say in variants:
                f = f'out/{name}-{tag}-{variant}-{l["id"]}.mp3'
                r = subprocess.run(['edge-tts', '--voice', voice, f'--rate={l.get("rate", "+6%")}',
                                    '--text', say, '--write-media', f], capture_output=True, text=True)
                if r.returncode != 0:
                    print(f'::warning::{os.path.basename(f)}: {r.stderr.strip()[-300:]}')
                    continue
                heard = ''
                if model:
                    try:
                        pcm = subprocess.run(['ffmpeg', '-v', 'error', '-i', f, '-ar', '16000', '-ac', '1', '-f', 's16le', '-'],
                                             capture_output=True, check=True).stdout
                        audio = np.frombuffer(pcm, np.int16).astype(np.float32) / 32768
                        segs, _ = model.transcribe(audio, language='he', beam_size=5)
                        heard = ' '.join(s.text for s in segs).strip()
                    except Exception as e:
                        print(f'::warning::whisper {os.path.basename(f)}: {e}')
                score = difflib.SequenceMatcher(None, plain(say), plain(heard)).ratio()
                report.append({'file': os.path.basename(f), 'want': say, 'heard': heard, 'score': round(score, 2)})
                print(f'{score:.2f}  {os.path.basename(f)}  | {heard}')
json.dump(report, open('out/transcripts.json', 'w'), ensure_ascii=False, indent=1)
