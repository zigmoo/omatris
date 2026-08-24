.pragma library

function targets(controlCount) {
  var result = [
    { kind: "volume", id: "music", x: 0.5, y: 0 },
    { kind: "volume", id: "effects", x: 2.5, y: 0 }
  ]

  for (var index = 0; index < controlCount; index++) {
    var cardColumn = index % 2
    var row = 1 + Math.floor(index / 2)
    result.push({ kind: "control", controlIndex: index, slot: 0, x: cardColumn * 2, y: row })
    result.push({ kind: "control", controlIndex: index, slot: 1, x: cardColumn * 2 + 1, y: row })
  }

  var hotkeyRow = 2 + Math.floor((controlCount - 1) / 2)
  result.push({ kind: "hotkey", id: "globalHotkey", x: 1.5, y: hotkeyRow })
  result.push({ kind: "action", id: "reset", x: 0, y: hotkeyRow + 1 })
  result.push({ kind: "action", id: "mute", x: 1.5, y: hotkeyRow + 1 })
  result.push({ kind: "action", id: "back", x: 3, y: hotkeyRow + 1 })
  return result
}

function targetAt(focus, controlCount) {
  var all = targets(controlCount)
  if (focus < 0 || focus >= all.length) return all[0]
  return all[focus]
}

function controlFocus(controlIndex, slot) {
  return 2 + controlIndex * 2 + slot
}

function actionFocus(controlCount, actionOffset) {
  return hotkeyFocus(controlCount) + 1 + actionOffset
}

function hotkeyFocus(controlCount) {
  return 2 + controlCount * 2
}

function move(focus, horizontal, vertical, controlCount) {
  var all = targets(controlCount)
  var current = targetAt(focus, controlCount)
  var bestIndex = focus
  var bestPrimary = Infinity
  var bestSecondary = Infinity

  for (var index = 0; index < all.length; index++) {
    if (index === focus) continue
    var candidate = all[index]
    var primary
    var secondary

    if (horizontal !== 0) {
      if (candidate.y !== current.y || (candidate.x - current.x) * horizontal <= 0) continue
      primary = Math.abs(candidate.x - current.x)
      secondary = 0
    } else {
      if ((candidate.y - current.y) * vertical <= 0) continue
      primary = Math.abs(candidate.y - current.y)
      secondary = Math.abs(candidate.x - current.x)
    }

    if (primary < bestPrimary || (primary === bestPrimary && secondary < bestSecondary)) {
      bestIndex = index
      bestPrimary = primary
      bestSecondary = secondary
    }
  }

  return bestIndex
}

function tab(focus, backwards, controlCount) {
  var count = targets(controlCount).length
  return (focus + (backwards ? count - 1 : 1)) % count
}
