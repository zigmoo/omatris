import QtQuick
import QtQuick.Effects
import "Game.js" as Game

Item {
  id: effects
  z: 2

  required property var controller
  required property var game
  required property int revision

  property int seenSerial: -1
  property var landingSpans: []
  property var landingCells: []
  property var dropTrails: []
  property string landingKind: ""
  property int impactRow: 19
  property var particles: []
  property int clearCount: 0
  property int particleDuration: 480
  property real landingProgress: 1
  property real dropProgress: 1
  property real particleProgress: 1

  readonly property real cellWidth: width / Game.WIDTH
  readonly property real cellHeight: height / Game.HEIGHT

  function makeLandingSpans(edges) {
    var sorted = []
    for (var edgeIndex = 0; edgeIndex < edges.length; edgeIndex++)
      sorted.push({ x: edges[edgeIndex].x, y: edges[edgeIndex].y })
    sorted.sort(function(a, b) { return a.y === b.y ? a.x - b.x : a.y - b.y })

    var spans = []
    for (var index = 0; index < sorted.length; index++) {
      var edge = sorted[index]
      var last = spans.length > 0 ? spans[spans.length - 1] : null
      if (last && last.y === edge.y && last.x + last.length === edge.x)
        last.length += 1
      else
        spans.push({ x: edge.x, y: edge.y, length: 1 })
    }
    return spans
  }

  function makeParticles(rows, serial) {
    var result = []
    var power = Math.max(1, Math.min(4, rows.length))
    var particlesPerSide = 6 + power * 3
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      for (var side = -1; side <= 1; side += 2) {
        for (var index = 0; index < particlesPerSide; index++) {
          var seed = serial * 37 + rows[rowIndex] * 17 + index * 11 + (side > 0 ? 5 : 0)
          result.push({
            side: side,
            row: rows[rowIndex],
            delay: (index % 7) * 0.025,
            travel: 24 + power * 13 + (seed % (22 + power * 8)),
            drift: (seed % (31 + power * 12)) - (15 + power * 6),
            lift: 10 + power * 5 + (seed % 17),
            size: 3.2 + power * 0.65 + (seed % 4) * 0.55,
            shade: seed % 3
          })
        }
      }
    }
    return result
  }

  function makeDropTrails(cells, distance) {
    if (distance <= 0) return []
    var columns = {}
    for (var index = 0; index < cells.length; index++) {
      var cell = cells[index]
      var key = String(cell.x)
      if (!columns[key]) columns[key] = { x: cell.x, minY: cell.y, maxY: cell.y }
      else {
        columns[key].minY = Math.min(columns[key].minY, cell.y)
        columns[key].maxY = Math.max(columns[key].maxY, cell.y)
      }
    }
    var trails = []
    for (var column in columns) {
      var value = columns[column]
      trails.push({
        x: value.x,
        startY: value.minY - distance,
        endY: value.maxY + 1
      })
    }
    return trails
  }

  function lowestImpactRow(edges, cells) {
    var row = 0
    var source = edges.length > 0 ? edges : cells
    for (var index = 0; index < source.length; index++) row = Math.max(row, source[index].y)
    return row
  }

  function syncEffect() {
    // Touch revision so updates to the JavaScript game object are observed.
    var renderToken = revision
    if (!game) {
      seenSerial = -1
      return
    }
    if (seenSerial < 0) {
      seenSerial = game.effectSerial
      return
    }
    if (game.effectSerial === seenSerial) return

    seenSerial = game.effectSerial
    var edges = game.lastLandingEdges || []
    landingSpans = makeLandingSpans(edges)
    landingCells = game.lastLockedCells || []
    landingKind = game.lastLandedKind || ""
    impactRow = lowestImpactRow(edges, landingCells)
    dropTrails = makeDropTrails(landingCells, game.lastHardDropDistance || 0)
    landingFlash.restart()
    if (dropTrails.length > 0) hardDropTrail.restart()

    if (game.lastClearedRows && game.lastClearedRows.length > 0) {
      clearCount = game.lastClearedRows.length
      particleDuration = 430 + clearCount * 105
      particles = makeParticles(game.lastClearedRows, game.effectSerial)
      particleBurst.restart()
    }
  }

  onRevisionChanged: syncEffect()
  onGameChanged: {
    seenSerial = game ? game.effectSerial : -1
    landingSpans = []
    landingCells = []
    dropTrails = []
    particles = []
  }

  Item {
    id: trailLayer
    anchors.fill: parent
    clip: true
    opacity: Math.max(0, 1 - effects.dropProgress)

    Repeater {
      model: effects.dropTrails

      delegate: Rectangle {
        required property var modelData
        readonly property real originalTop: Math.max(0, modelData.startY * effects.cellHeight)
        readonly property real originalBottom: Math.min(effects.height, modelData.endY * effects.cellHeight)
        x: (modelData.x + 0.18) * effects.cellWidth
        y: originalTop + (originalBottom - originalTop) * effects.dropProgress * 0.72
        width: effects.cellWidth * 0.64
        height: Math.max(0, originalBottom - y)
        radius: width / 2
        antialiasing: true
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop {
            position: 0.62
            color: {
              var piece = effects.controller.pieceColor(effects.landingKind)
              return Qt.rgba(piece.r, piece.g, piece.b, 0.12)
            }
          }
          GradientStop {
            position: 1.0
            color: {
              var piece = effects.controller.pieceColor(effects.landingKind)
              return Qt.rgba(piece.r, piece.g, piece.b, 0.88)
            }
          }
        }
      }
    }
  }

  MultiEffect {
    anchors.fill: impactLayer
    source: impactLayer
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 0.9
    blurMax: 32
    blurMultiplier: 1.6
    opacity: Math.max(0, 0.9 - effects.landingProgress * 0.9)
  }

  Item {
    id: impactLayer
    anchors.fill: parent

    Item {
      readonly property real waveProgress: 1 - Math.pow(1 - effects.landingProgress, 3)
      x: effects.width * (0.5 - (0.16 + waveProgress * 1.08) / 2)
      y: (effects.impactRow + 1) * effects.cellHeight - height / 2
      width: effects.width * (0.16 + waveProgress * 1.08)
      height: Math.max(56, effects.cellHeight * 2.2)
      opacity: Math.max(0, 1 - effects.landingProgress * effects.landingProgress)

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop {
            position: 0.44
            color: {
              var piece = effects.controller.pieceColor(effects.landingKind)
              return Qt.rgba(piece.r, piece.g, piece.b, 0.08)
            }
          }
          GradientStop { position: 0.5; color: effects.controller.foreground }
          GradientStop {
            position: 0.56
            color: {
              var piece = effects.controller.pieceColor(effects.landingKind)
              return Qt.rgba(piece.r, piece.g, piece.b, 0.08)
            }
          }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }
    }

    Repeater {
      model: effects.landingCells

      delegate: Rectangle {
        required property var modelData
        x: modelData.x * effects.cellWidth - 1
        y: modelData.y * effects.cellHeight - 1
        width: effects.cellWidth + 2
        height: effects.cellHeight + 2
        radius: Math.max(2, effects.cellWidth * 0.08)
        antialiasing: true
        color: effects.controller.foreground
        opacity: Math.max(0, 0.82 - effects.landingProgress * 1.05)
        scale: 1 + effects.landingProgress * 0.13
      }
    }

    Repeater {
      model: effects.landingSpans

      delegate: Rectangle {
        required property var modelData
        x: modelData.x * effects.cellWidth - 6
        y: (modelData.y + 1) * effects.cellHeight - height / 2
        width: modelData.length * effects.cellWidth + 12
        height: Math.max(6, effects.cellHeight * 0.2)
        radius: height / 2
        antialiasing: true
        color: effects.controller.foreground
        opacity: Math.max(0, 1 - effects.landingProgress * 1.15)
      }
    }
  }

  Repeater {
    model: effects.particles

    delegate: Item {
      required property var modelData
      readonly property real localProgress: Math.max(0, Math.min(1,
        (effects.particleProgress - modelData.delay) / (1 - modelData.delay)))
      readonly property real easedProgress: 1 - Math.pow(1 - localProgress, 2)
      readonly property real particleScale: 0.72 + Math.sin(localProgress * Math.PI) * 0.55
        - localProgress * 0.28
      width: modelData.size * 2.4
      height: width
      x: modelData.side < 0
        ? -width / 2 - easedProgress * modelData.travel
        : effects.width - width / 2 + easedProgress * modelData.travel
      y: (modelData.row + 0.5) * effects.cellHeight - height / 2
        + easedProgress * modelData.drift - Math.sin(localProgress * Math.PI) * modelData.lift
      opacity: localProgress <= 0 ? 0 : Math.max(0, 1 - localProgress)
      scale: particleScale

      Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: width
        radius: width / 2
        antialiasing: true
        color: {
          var particleColor = modelData.shade === 0
            ? effects.controller.accent
            : modelData.shade === 1 ? effects.controller.foreground : effects.controller.muted
          return Qt.rgba(particleColor.r, particleColor.g, particleColor.b, 0.16)
        }
      }

      Rectangle {
        anchors.centerIn: parent
        width: modelData.size
        height: width
        radius: width / 2
        antialiasing: true
        color: modelData.shade === 0
          ? effects.controller.accent
          : modelData.shade === 1 ? effects.controller.foreground : effects.controller.muted
      }
    }
  }

  NumberAnimation {
    id: landingFlash
    target: effects
    property: "landingProgress"
    from: 0
    to: 1
    duration: 460
    easing.type: Easing.OutQuart
  }

  NumberAnimation {
    id: hardDropTrail
    target: effects
    property: "dropProgress"
    from: 0
    to: 1
    duration: 300
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: particleBurst
    target: effects
    property: "particleProgress"
    from: 0
    to: 1
    duration: effects.particleDuration
    easing.type: Easing.OutCubic
  }
}
