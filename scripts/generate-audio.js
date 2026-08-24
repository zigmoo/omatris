#!/usr/bin/env node

const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const sampleRate = 44100
const outputDir = path.join(__dirname, "..", "assets", "audio")
fs.mkdirSync(outputDir, { recursive: true })

function buffer(seconds) {
  return new Float64Array(Math.ceil(seconds * sampleRate))
}

function envelope(t, duration, attack = 0.008, release = 0.1) {
  const fadeIn = Math.min(1, t / attack)
  const fadeOut = Math.min(1, (duration - t) / release)
  return Math.max(0, Math.min(fadeIn, fadeOut))
}

function addTone(target, start, duration, fromHz, toHz, gain, shape = "sine") {
  const first = Math.floor(start * sampleRate)
  const count = Math.floor(duration * sampleRate)
  let phase = 0
  for (let index = 0; index < count && first + index < target.length; index++) {
    const t = index / sampleRate
    const frequency = fromHz + (toHz - fromHz) * (t / duration)
    phase += 2 * Math.PI * frequency / sampleRate
    const wave = shape === "triangle"
      ? 2 / Math.PI * Math.asin(Math.sin(phase))
      : shape === "square" ? Math.sign(Math.sin(phase)) : Math.sin(phase)
    target[first + index] += wave * gain * envelope(t, duration)
  }
}

let noiseState = 0x5eeda11
function random() {
  noiseState ^= noiseState << 13
  noiseState ^= noiseState >>> 17
  noiseState ^= noiseState << 5
  return ((noiseState >>> 0) / 0xffffffff) * 2 - 1
}

function addNoise(target, start, duration, gain, decay = 5) {
  const first = Math.floor(start * sampleRate)
  const count = Math.floor(duration * sampleRate)
  let filtered = 0
  for (let index = 0; index < count && first + index < target.length; index++) {
    const t = index / sampleRate
    filtered = filtered * 0.55 + random() * 0.45
    target[first + index] += filtered * gain * Math.exp(-decay * t / duration)
      * envelope(t, duration, 0.002, Math.min(0.05, duration / 2))
  }
}

function normalize(channels, peak = 0.92) {
  let maximum = 0
  for (const channel of channels) {
    for (const sample of channel) maximum = Math.max(maximum, Math.abs(sample))
  }
  const scale = maximum > 0 ? peak / maximum : 1
  for (const channel of channels) {
    for (let index = 0; index < channel.length; index++) channel[index] *= scale
  }
}

function writeWav(file, channels) {
  normalize(channels)
  const frames = channels[0].length
  const channelCount = channels.length
  const dataBytes = frames * channelCount * 2
  const output = Buffer.alloc(44 + dataBytes)
  output.write("RIFF", 0)
  output.writeUInt32LE(36 + dataBytes, 4)
  output.write("WAVEfmt ", 8)
  output.writeUInt32LE(16, 16)
  output.writeUInt16LE(1, 20)
  output.writeUInt16LE(channelCount, 22)
  output.writeUInt32LE(sampleRate, 24)
  output.writeUInt32LE(sampleRate * channelCount * 2, 28)
  output.writeUInt16LE(channelCount * 2, 32)
  output.writeUInt16LE(16, 34)
  output.write("data", 36)
  output.writeUInt32LE(dataBytes, 40)
  let offset = 44
  for (let frame = 0; frame < frames; frame++) {
    for (let channel = 0; channel < channelCount; channel++) {
      const sample = Math.max(-1, Math.min(1, channels[channel][frame]))
      output.writeInt16LE(Math.round(sample * 32767), offset)
      offset += 2
    }
  }
  fs.writeFileSync(file, output)
}

function effect(name, seconds, compose) {
  const samples = buffer(seconds)
  compose(samples)
  writeWav(path.join(outputDir, name + ".wav"), [samples])
}

effect("move", 0.055, out => {
  addTone(out, 0, 0.05, 210, 155, 0.36, "triangle")
  addNoise(out, 0, 0.025, 0.11, 8)
})

effect("rotate", 0.085, out => {
  addTone(out, 0, 0.075, 390, 610, 0.36, "triangle")
  addTone(out, 0.012, 0.06, 780, 920, 0.12)
})

effect("hold", 0.15, out => {
  addTone(out, 0, 0.08, 330, 440, 0.32, "triangle")
  addTone(out, 0.055, 0.09, 494, 660, 0.28, "triangle")
})

effect("lock", 0.12, out => {
  addTone(out, 0, 0.11, 115, 58, 0.52)
  addTone(out, 0, 0.07, 230, 115, 0.22, "triangle")
  addNoise(out, 0, 0.055, 0.2, 7)
})

effect("hard-drop", 0.2, out => {
  addNoise(out, 0, 0.14, 0.24, 2.8)
  addTone(out, 0, 0.17, 260, 62, 0.46, "triangle")
  addTone(out, 0.105, 0.09, 92, 44, 0.58)
})

const clearNotes = [523.25, 659.25, 783.99, 1046.5]
for (let count = 1; count <= 4; count++) {
  const name = count === 1 ? "single" : count === 2 ? "double" : count === 3 ? "triple" : "omatris"
  effect(name, 0.13 + count * 0.065, out => {
    for (let note = 0; note < count; note++) {
      const start = note * 0.045
      addTone(out, start, 0.13, clearNotes[note], clearNotes[note] * 1.01, 0.3, "triangle")
      addTone(out, start, 0.14, clearNotes[note] * 2, clearNotes[note] * 2.01, 0.08)
    }
  })
}

effect("tspin", 0.33, out => {
  addTone(out, 0, 0.15, 330, 495, 0.32, "triangle")
  addTone(out, 0.07, 0.2, 494, 740, 0.32, "triangle")
  addTone(out, 0.13, 0.19, 659, 988, 0.28, "triangle")
  addNoise(out, 0.16, 0.1, 0.09, 6)
})

effect("game-over", 0.72, out => {
  const notes = [392, 330, 262, 196]
  for (let index = 0; index < notes.length; index++) {
    addTone(out, index * 0.14, 0.24, notes[index], notes[index] * 0.97, 0.3, "triangle")
  }
  addTone(out, 0.43, 0.28, 98, 49, 0.3)
})

function addStereoTone(left, right, start, duration, frequency, gain, pan, shape = "sine") {
  const leftGain = gain * Math.sqrt((1 - pan) / 2)
  const rightGain = gain * Math.sqrt((1 + pan) / 2)
  addTone(left, start, duration, frequency, frequency, leftGain, shape)
  addTone(right, start, duration, frequency * 1.0015, frequency * 1.0015, rightGain, shape)
}

function composeMusic() {
  const bpm = 112
  const beat = 60 / bpm
  const bars = 8
  const duration = bars * beat * 4
  const left = buffer(duration)
  const right = buffer(duration)
  const progressions = [
    [220, 261.63, 329.63],
    [174.61, 220, 261.63],
    [130.81, 164.81, 196],
    [196, 246.94, 293.66]
  ]

  for (let bar = 0; bar < bars; bar++) {
    const start = bar * beat * 4
    const chord = progressions[bar % progressions.length]
    for (let voice = 0; voice < chord.length; voice++) {
      addStereoTone(left, right, start, beat * 3.95, chord[voice], 0.055, (voice - 1) * 0.5)
      addStereoTone(left, right, start, beat * 3.95, chord[voice] / 2, 0.025, (1 - voice) * 0.35, "triangle")
    }

    for (let step = 0; step < 8; step++) {
      const note = chord[step % chord.length] * (step >= 6 ? 2 : 1)
      addStereoTone(left, right, start + step * beat / 2, beat * 0.42, note * 2, 0.09,
        step % 2 === 0 ? -0.38 : 0.38, "triangle")
    }

    for (let quarter = 0; quarter < 4; quarter++) {
      addStereoTone(left, right, start + quarter * beat, beat * 0.7, chord[0] / 2, 0.13, 0, "triangle")
      addTone(left, start + quarter * beat, 0.12, 92, 45, 0.13)
      addTone(right, start + quarter * beat, 0.12, 92, 45, 0.13)
      if (quarter === 1 || quarter === 3) {
        addNoise(left, start + quarter * beat, 0.1, 0.055, 7)
        addNoise(right, start + quarter * beat, 0.1, 0.055, 7)
      }
    }
  }

  // A quiet cross-channel echo gives the loop width without muddying gameplay.
  const delay = Math.floor(beat * 0.75 * sampleRate)
  for (let index = delay; index < left.length; index++) {
    left[index] += right[index - delay] * 0.12
    right[index] += left[index - delay] * 0.12
  }
  normalize([left, right], 0.78)
  return [left, right]
}

const temporaryMusic = path.join(os.tmpdir(), "omatris-generated-music.wav")
writeWav(temporaryMusic, composeMusic())
const encodedMusic = path.join(outputDir, "music.ogg")
const encoding = spawnSync("ffmpeg", [
  "-hide_banner", "-loglevel", "error", "-y", "-i", temporaryMusic,
  "-c:a", "libvorbis", "-q:a", "5", encodedMusic
])
fs.unlinkSync(temporaryMusic)
if (encoding.status !== 0) {
  process.stderr.write(encoding.stderr || "Could not encode music.ogg\n")
  process.exit(encoding.status || 1)
}

console.log("Generated Omatris audio assets in " + outputDir)
