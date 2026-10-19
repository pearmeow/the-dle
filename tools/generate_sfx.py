"""Generate original, quiet UI feedback sounds with no external samples."""
from pathlib import Path
import math, random, struct, wave
RATE = 44100
OUT = Path(__file__).resolve().parents[1] / 'assets/audio/sfx'
OUT.mkdir(parents=True, exist_ok=True)
def write(name, notes, duration, tap=False):
    rng = random.Random(51)
    samples = []
    for i in range(int(RATE * duration)):
        t = i / RATE
        value = 0.0
        if tap:
            value = (0.16 * rng.uniform(-1, 1) + 0.35 * math.sin(2 * math.pi * 530 * t)) * math.exp(-t * 62) * min(1, t / 0.003)
        for start, frequency, length in notes:
            age = t - start
            if 0 <= age < length:
                envelope = min(1, age / 0.008) * math.exp(-age * 7) * min(1, (length - age) / 0.04)
                value += 0.24 * envelope * (math.sin(2 * math.pi * frequency * age) + 0.18 * math.sin(2 * math.pi * frequency * 2 * age))
        samples.append(struct.pack('<h', int(max(-0.9, min(0.9, value)) * 32767)))
    with wave.open(str(OUT / (name + '.wav')), 'wb') as file:
        file.setnchannels(1); file.setsampwidth(2); file.setframerate(RATE)
        file.writeframes(b''.join(samples))
write('button', [], 0.085, tap=True)
write('correct', [(0, 523.25, .38), (.10, 659.25, .38), (.20, 783.99, .42)], .65)
write('miss', [(0, 349.23, .19), (.10, 293.66, .23)], .36)
write('progress', [(0, 440, .17), (.08, 587.33, .22)], .33)
write('complete', [(0, 523.25, .4), (.12, 659.25, .4), (.24, 783.99, .4), (.38, 1046.5, .55)], .98)
print('Generated 5 original feedback sounds')
