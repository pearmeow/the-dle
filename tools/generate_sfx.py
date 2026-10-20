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
            # Rounded, low bubble pop: smooth attack, falling pitch, no noise transient.
            phase = 2 * math.pi * (230 * t + 140 * 0.018 * (1 - math.exp(-t / 0.018)))
            envelope = (1 - math.exp(-t / 0.004)) * math.exp(-t / 0.020)
            envelope *= max(0, 1 - (t / duration) ** 2)
            value = 0.25 * math.sin(phase) * envelope
        for start, frequency, length in notes:
            age = t - start
            if 0 <= age < length:
                envelope = min(1, age / 0.008) * math.exp(-age * 7) * min(1, (length - age) / 0.04)
                value += 0.24 * envelope * (math.sin(2 * math.pi * frequency * age) + 0.18 * math.sin(2 * math.pi * frequency * 2 * age))
        samples.append(struct.pack('<h', int(max(-0.9, min(0.9, value)) * 32767)))
    with wave.open(str(OUT / (name + '.wav')), 'wb') as file:
        file.setnchannels(1); file.setsampwidth(2); file.setframerate(RATE)
        file.writeframes(b''.join(samples))
write('button', [], 0.10, tap=True)
write('correct', [(0, 523.25, .38), (.10, 659.25, .38), (.20, 783.99, .42)], .65)
write('miss', [(0, 349.23, .19), (.10, 293.66, .23)], .36)
write('progress', [(0, 440, .17), (.08, 587.33, .22)], .33)
write('complete', [(0, 523.25, .4), (.12, 659.25, .4), (.24, 783.99, .4), (.38, 1046.5, .55)], .98)
print('Generated 5 original feedback sounds')
