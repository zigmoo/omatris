import QtQuick
import QtMultimedia

Item {
  id: audio

  property real musicVolume: 0.35
  property real effectsVolume: 0.7
  property bool muted: false
  property bool active: false
  property bool gamePaused: false

  property var watchedGame: null
  property int seenEffectSerial: 0
  property string seenStatus: ""
  property double lastMoveAt: 0
  property double lastPreviewAt: 0

  readonly property bool musicShouldPlay: active && !gamePaused && !muted && musicVolume > 0

  function updateMusic() {
    if (musicShouldPlay) musicPlayer.play()
    else musicPlayer.pause()
  }

  function watchGame(game) {
    watchedGame = game
    seenEffectSerial = game ? game.effectSerial : 0
    seenStatus = game ? game.status : ""
  }

  function playAction(action) {
    if (muted || effectsVolume <= 0) return
    if (action === "left" || action === "right") {
      var now = Date.now()
      if (now - lastMoveAt < 32) return
      lastMoveAt = now
      moveSound.play()
    } else if (action === "rotateLeft" || action === "rotateRight") {
      rotateSound.play()
    } else if (action === "hold") {
      holdSound.play()
    }
  }

  function previewEffect() {
    var now = Date.now()
    if (now - lastPreviewAt < 120) return
    lastPreviewAt = now
    rotateSound.play()
  }

  function syncGame(game) {
    if (!game) {
      watchGame(null)
      return
    }
    if (watchedGame !== game) {
      watchGame(game)
      return
    }

    if (game.effectSerial !== seenEffectSerial) {
      seenEffectSerial = game.effectSerial
      if (game.lastHardDropDistance > 0) hardDropSound.play()
      else lockSound.play()

      if (game.lastLockSpin) tspinSound.play()
      else if (game.lastClearedRows.length === 1) singleSound.play()
      else if (game.lastClearedRows.length === 2) doubleSound.play()
      else if (game.lastClearedRows.length === 3) tripleSound.play()
      else if (game.lastClearedRows.length >= 4) omatrisSound.play()
    }

    if (game.status !== seenStatus) {
      if (game.status === "over") gameOverSound.play()
      seenStatus = game.status
    }
  }

  onMusicShouldPlayChanged: updateMusic()
  Component.onCompleted: updateMusic()

  AudioOutput {
    id: musicOutput
    volume: audio.muted ? 0 : audio.musicVolume * 0.72
    Behavior on volume { NumberAnimation { duration: 180 } }
  }

  MediaPlayer {
    id: musicPlayer
    source: Qt.resolvedUrl("assets/audio/music.ogg")
    audioOutput: musicOutput
    loops: MediaPlayer.Infinite
  }

  SoundEffect { id: moveSound; source: Qt.resolvedUrl("assets/audio/move.wav"); volume: audio.effectsVolume * 0.32; muted: audio.muted }
  SoundEffect { id: rotateSound; source: Qt.resolvedUrl("assets/audio/rotate.wav"); volume: audio.effectsVolume * 0.4; muted: audio.muted }
  SoundEffect { id: holdSound; source: Qt.resolvedUrl("assets/audio/hold.wav"); volume: audio.effectsVolume * 0.48; muted: audio.muted }
  SoundEffect { id: lockSound; source: Qt.resolvedUrl("assets/audio/lock.wav"); volume: audio.effectsVolume * 0.42; muted: audio.muted }
  SoundEffect { id: hardDropSound; source: Qt.resolvedUrl("assets/audio/hard-drop.wav"); volume: audio.effectsVolume * 0.62; muted: audio.muted }
  SoundEffect { id: singleSound; source: Qt.resolvedUrl("assets/audio/single.wav"); volume: audio.effectsVolume * 0.5; muted: audio.muted }
  SoundEffect { id: doubleSound; source: Qt.resolvedUrl("assets/audio/double.wav"); volume: audio.effectsVolume * 0.56; muted: audio.muted }
  SoundEffect { id: tripleSound; source: Qt.resolvedUrl("assets/audio/triple.wav"); volume: audio.effectsVolume * 0.64; muted: audio.muted }
  SoundEffect { id: omatrisSound; source: Qt.resolvedUrl("assets/audio/omatris.wav"); volume: audio.effectsVolume * 0.72; muted: audio.muted }
  SoundEffect { id: tspinSound; source: Qt.resolvedUrl("assets/audio/tspin.wav"); volume: audio.effectsVolume * 0.68; muted: audio.muted }
  SoundEffect { id: gameOverSound; source: Qt.resolvedUrl("assets/audio/game-over.wav"); volume: audio.effectsVolume * 0.56; muted: audio.muted }
}
