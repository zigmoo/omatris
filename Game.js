.pragma library

var WIDTH = 10
var HEIGHT = 20
var LOCK_DELAY = 500
var MAX_LOCK_RESETS = 15

var SHAPES = {
  I: [
    ["....", "IIII", "....", "...."],
    ["..I.", "..I.", "..I.", "..I."],
    ["....", "....", "IIII", "...."],
    [".I..", ".I..", ".I..", ".I.."]
  ],
  O: [
    [".OO.", ".OO.", "....", "...."],
    [".OO.", ".OO.", "....", "...."],
    [".OO.", ".OO.", "....", "...."],
    [".OO.", ".OO.", "....", "...."]
  ],
  T: [
    [".T..", "TTT.", "....", "...."],
    [".T..", ".TT.", ".T..", "...."],
    ["....", "TTT.", ".T..", "...."],
    [".T..", "TT..", ".T..", "...."]
  ],
  S: [
    [".SS.", "SS..", "....", "...."],
    [".S..", ".SS.", "..S.", "...."],
    ["....", ".SS.", "SS..", "...."],
    ["S...", "SS..", ".S..", "...."]
  ],
  Z: [
    ["ZZ..", ".ZZ.", "....", "...."],
    ["..Z.", ".ZZ.", ".Z..", "...."],
    ["....", "ZZ..", ".ZZ.", "...."],
    [".Z..", "ZZ..", "Z...", "...."]
  ],
  J: [
    ["J...", "JJJ.", "....", "...."],
    [".JJ.", ".J..", ".J..", "...."],
    ["....", "JJJ.", "..J.", "...."],
    [".J..", ".J..", "JJ..", "...."]
  ],
  L: [
    ["..L.", "LLL.", "....", "...."],
    [".L..", ".L..", ".LL.", "...."],
    ["....", "LLL.", "L...", "...."],
    ["LL..", ".L..", ".L..", "...."]
  ]
}

// SRS kick coordinates converted to the board's coordinate system, where
// positive y points down. TETR.IO's SRS+ keeps the regular JLSTZ table and
// mirrors the I piece's right-side kicks onto its left-side transitions.
var JLSTZ_KICKS = {
  "0>1": [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
  "1>0": [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
  "1>2": [[0, 0], [1, 0], [1, 1], [0, -2], [1, -2]],
  "2>1": [[0, 0], [-1, 0], [-1, -1], [0, 2], [-1, 2]],
  "2>3": [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]],
  "3>2": [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
  "3>0": [[0, 0], [-1, 0], [-1, 1], [0, -2], [-1, -2]],
  "0>3": [[0, 0], [1, 0], [1, -1], [0, 2], [1, 2]]
}

var I_KICKS_SRS_PLUS = {
  "0>1": [[0, 0], [-2, 0], [1, 0], [-2, 1], [1, -2]],
  "1>0": [[0, 0], [2, 0], [-1, 0], [2, -1], [-1, 2]],
  "1>2": [[0, 0], [-1, 0], [2, 0], [-1, -2], [2, 1]],
  "2>1": [[0, 0], [1, 0], [-2, 0], [1, 2], [-2, -1]],
  "2>3": [[0, 0], [-1, 0], [2, 0], [-1, 2], [2, -1]],
  "3>2": [[0, 0], [1, 0], [-2, 0], [1, -2], [-2, 1]],
  "3>0": [[0, 0], [-2, 0], [1, 0], [-2, -1], [1, 2]],
  "0>3": [[0, 0], [2, 0], [-1, 0], [2, 1], [-1, -2]]
}

function emptyBoard() {
  var board = []
  for (var y = 0; y < HEIGHT; y++) {
    var row = []
    for (var x = 0; x < WIDTH; x++) row.push("")
    board.push(row)
  }
  return board
}

function shuffledBag() {
  var bag = ["I", "O", "T", "S", "Z", "J", "L"]
  for (var i = bag.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1))
    var temp = bag[i]
    bag[i] = bag[j]
    bag[j] = temp
  }
  return bag
}

function fillQueue(state) {
  while (state.queue.length < 5) {
    if (state.bag.length === 0) state.bag = shuffledBag()
    state.queue.push(state.bag.shift())
  }
}

function cellsFor(kind, rotation) {
  var rows = SHAPES[kind][((rotation % 4) + 4) % 4]
  var cells = []
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      if (rows[y][x] !== ".") cells.push({ x: x, y: y })
    }
  }
  return cells
}

function collides(state, piece, dx, dy, rotation) {
  var cells = cellsFor(piece.kind, rotation)
  for (var i = 0; i < cells.length; i++) {
    var x = piece.x + dx + cells[i].x
    var y = piece.y + dy + cells[i].y
    if (x < 0 || x >= WIDTH || y >= HEIGHT) return true
    if (y >= 0 && state.board[y][x] !== "") return true
  }
  return false
}

function spawn(state, kind) {
  state.current = { kind: kind, rotation: 0, x: 3, y: -1 }
  state.canHold = true
  state.lastAction = "spawn"
  state.lastRotationKick = -1
  state.grounded = false
  state.lockDelayRemaining = LOCK_DELAY
  state.lockResets = 0
  state.pendingHardDropDistance = 0
  if (collides(state, state.current, 0, 0, 0)) {
    if (state.mode === "practice") {
      state.board = emptyBoard()
      state.lastEvent = "Board cleared — keep practicing"
    } else {
      state.status = "over"
      state.lastEvent = "Top out"
    }
  }
}

function spawnNext(state) {
  fillQueue(state)
  var kind = state.queue.shift()
  fillQueue(state)
  spawn(state, kind)
}

function newGame(mode) {
  var state = {
    mode: mode || "classic",
    board: emptyBoard(),
    current: null,
    queue: [],
    bag: [],
    hold: "",
    canHold: true,
    score: 0,
    lines: 0,
    level: 1,
    practiceSpeed: 1.0,
    status: "playing",
    paused: false,
    lastAction: "spawn",
    lastRotationKick: -1,
    grounded: false,
    lockDelayRemaining: LOCK_DELAY,
    lockResets: 0,
    tSpins: 0,
    tSpinMinis: 0,
    effectSerial: 0,
    lastLandingEdges: [],
    lastLockedCells: [],
    lastLandedKind: "",
    lastHardDropDistance: 0,
    lastLockSpin: "",
    lastClearedRows: [],
    pendingHardDropDistance: 0,
    highScoreRecorded: false,
    isNewHighScore: false,
    lastEvent: mode === "practice" ? "No top-outs. Take your time." : "Good luck"
  }
  fillQueue(state)
  spawnNext(state)
  return state
}

function qualifiesForLocalBest(state, previousBest) {
  return !!state
    && state.status === "playing"
    && state.mode !== "practice"
    && state.score > (previousBest || 0)
}

function endRun(state) {
  if (!state || state.status !== "playing") return false
  state.status = "over"
  state.paused = false
  state.lastEvent = "Run ended"
  return true
}

function move(state, dx, dy, awardSoftDrop) {
  if (!state || state.status !== "playing" || state.paused) return false
  if (!collides(state, state.current, dx, dy, state.current.rotation)) {
    var wasGrounded = state.grounded
    state.current.x += dx
    state.current.y += dy
    state.lastAction = "move"
    state.lastRotationKick = -1
    updateGroundedState(state, wasGrounded, awardSoftDrop !== false)
    if (dy > 0 && awardSoftDrop !== false) state.score += 1
    return true
  }
  return false
}

function updateGroundedState(state, wasGrounded, allowReset) {
  state.grounded = collides(state, state.current, 0, 1, state.current.rotation)
  if (!state.grounded) {
    state.lockDelayRemaining = LOCK_DELAY
    return
  }
  if (!wasGrounded) {
    state.lockDelayRemaining = LOCK_DELAY
  } else if (allowReset && state.lockResets < MAX_LOCK_RESETS) {
    state.lockDelayRemaining = LOCK_DELAY
    state.lockResets += 1
  }
}

function rotate(state, direction) {
  if (!state || state.status !== "playing" || state.paused) return false
  var currentRotation = state.current.rotation
  var nextRotation = (currentRotation + direction + 4) % 4
  var kickTable = state.current.kind === "I" ? I_KICKS_SRS_PLUS : JLSTZ_KICKS
  var kicks = state.current.kind === "O" ? [[0, 0]] : kickTable[currentRotation + ">" + nextRotation]
  for (var i = 0; i < kicks.length; i++) {
    if (!collides(state, state.current, kicks[i][0], kicks[i][1], nextRotation)) {
      var wasGrounded = state.grounded
      state.current.x += kicks[i][0]
      state.current.y += kicks[i][1]
      state.current.rotation = nextRotation
      state.lastAction = "rotate"
      state.lastRotationKick = i
      updateGroundedState(state, wasGrounded, true)
      return true
    }
  }
  return false
}

function occupiedForTSpin(state, x, y) {
  if (x < 0 || x >= WIDTH || y >= HEIGHT) return true
  if (y < 0) return false
  return state.board[y][x] !== ""
}

function tSpinType(state) {
  var piece = state.current
  if (!piece || piece.kind !== "T" || state.lastAction !== "rotate") return ""

  var centerX = piece.x + 1
  var centerY = piece.y + 1
  var corners = [
    occupiedForTSpin(state, centerX - 1, centerY - 1),
    occupiedForTSpin(state, centerX + 1, centerY - 1),
    occupiedForTSpin(state, centerX + 1, centerY + 1),
    occupiedForTSpin(state, centerX - 1, centerY + 1)
  ]
  var occupied = 0
  for (var i = 0; i < corners.length; i++) if (corners[i]) occupied += 1
  if (occupied < 3) return ""

  var frontByRotation = [[0, 1], [1, 2], [2, 3], [3, 0]]
  var front = frontByRotation[piece.rotation]
  if ((corners[front[0]] && corners[front[1]]) || state.lastRotationKick === 4)
    return "full"
  return "mini"
}

function clearCompletedLines(state) {
  var kept = []
  var cleared = 0
  for (var y = 0; y < HEIGHT; y++) {
    var full = true
    for (var x = 0; x < WIDTH; x++) {
      if (state.board[y][x] === "") { full = false; break }
    }
    if (full) cleared += 1
    else kept.push(state.board[y])
  }
  while (kept.length < HEIGHT) {
    var row = []
    for (var col = 0; col < WIDTH; col++) row.push("")
    kept.unshift(row)
  }
  state.board = kept
  return cleared
}

function completedLineRows(state) {
  var rows = []
  for (var y = 0; y < HEIGHT; y++) {
    var full = true
    for (var x = 0; x < WIDTH; x++) {
      if (state.board[y][x] === "") { full = false; break }
    }
    if (full) rows.push(y)
  }
  return rows
}

function landingEdgesFor(state, piece) {
  var cells = cellsFor(piece.kind, piece.rotation)
  var edges = []
  for (var i = 0; i < cells.length; i++) {
    var x = piece.x + cells[i].x
    var y = piece.y + cells[i].y
    if (y < 0) continue
    if (y + 1 >= HEIGHT || state.board[y + 1][x] !== "")
      edges.push({ x: x, y: y })
  }
  return edges
}

function lockPiece(state) {
  var piece = state.current
  var spin = tSpinType(state)
  var landingEdges = landingEdgesFor(state, piece)
  var cells = cellsFor(piece.kind, piece.rotation)
  var lockedCells = []
  var aboveBoard = false
  for (var i = 0; i < cells.length; i++) {
    var x = piece.x + cells[i].x
    var y = piece.y + cells[i].y
    if (y < 0) aboveBoard = true
    else {
      state.board[y][x] = piece.kind
      lockedCells.push({ x: x, y: y })
    }
  }

  if (aboveBoard && state.mode !== "practice") {
    state.status = "over"
    state.lastEvent = "Top out"
    return
  }
  if (aboveBoard) state.board = emptyBoard()

  var clearedRows = completedLineRows(state)
  state.lastLandingEdges = landingEdges
  state.lastLockedCells = lockedCells
  state.lastLandedKind = piece.kind
  state.lastHardDropDistance = state.pendingHardDropDistance || 0
  state.lastLockSpin = spin
  state.lastClearedRows = clearedRows
  state.effectSerial += 1

  var cleared = clearCompletedLines(state)
  if (spin) {
    var spinScores = spin === "mini" ? [100, 200, 400, 0] : [400, 800, 1200, 1600]
    var points = spinScores[cleared] * state.level
    state.score += points
    state.lines += cleared
    if (spin === "mini") state.tSpinMinis += 1
    else state.tSpins += 1
    var spinName = spin === "mini" ? "T-Spin Mini" : "T-Spin"
    var clearName = cleared === 1 ? " Single" : cleared === 2 ? " Double" : cleared === 3 ? " Triple" : ""
    state.lastEvent = spinName + clearName + "  +" + points
  } else if (cleared > 0) {
    var linePoints = [0, 100, 300, 500, 800][cleared] * state.level
    state.score += linePoints
    state.lines += cleared
    state.lastEvent = cleared === 4 ? "Omatris  +" + linePoints : cleared + (cleared === 1 ? " line" : " lines") + "  +" + linePoints
  } else {
    state.lastEvent = ""
  }

  if (cleared > 0) {
    if (state.mode !== "practice") state.level = 1 + Math.floor(state.lines / 10)
    if (state.mode === "classic" && state.lines >= 40) {
      state.status = "won"
      state.lastEvent = "40 lines complete"
      return
    }
  }
  spawnNext(state)
}

function tick(state) {
  if (!state || state.status !== "playing" || state.paused) return false
  if (!move(state, 0, 1, false) && !state.grounded) {
    state.grounded = true
    state.lockDelayRemaining = LOCK_DELAY
  }
  return true
}

function advanceLockDelay(state, elapsed) {
  if (!state || state.status !== "playing" || state.paused || !state.grounded) return false
  if (!collides(state, state.current, 0, 1, state.current.rotation)) {
    state.grounded = false
    state.lockDelayRemaining = LOCK_DELAY
    return false
  }
  state.lockDelayRemaining -= elapsed
  if (state.lockDelayRemaining > 0) return false
  lockPiece(state)
  return true
}

function hardDrop(state) {
  if (!state || state.status !== "playing" || state.paused) return false
  var distance = 0
  while (!collides(state, state.current, 0, distance + 1, state.current.rotation)) distance += 1
  state.pendingHardDropDistance = distance
  state.current.y += distance
  if (distance > 0) {
    state.lastAction = "move"
    state.lastRotationKick = -1
  }
  state.score += distance * 2
  lockPiece(state)
  return true
}

function hold(state) {
  if (!state || state.status !== "playing" || state.paused || !state.canHold) return false
  var currentKind = state.current.kind
  if (state.hold === "") {
    state.hold = currentKind
    spawnNext(state)
  } else {
    var nextKind = state.hold
    state.hold = currentKind
    spawn(state, nextKind)
  }
  state.canHold = false
  return true
}

function ghostY(state) {
  if (!state || !state.current) return 0
  var distance = 0
  while (!collides(state, state.current, 0, distance + 1, state.current.rotation)) distance += 1
  return state.current.y + distance
}

function activeCell(state, row, column) {
  if (!state || !state.current) return ""
  var cells = cellsFor(state.current.kind, state.current.rotation)
  for (var i = 0; i < cells.length; i++) {
    if (state.current.x + cells[i].x === column && state.current.y + cells[i].y === row)
      return state.current.kind
  }
  return ""
}

function ghostCell(state, row, column) {
  if (!state || !state.current) return false
  var gy = ghostY(state)
  var cells = cellsFor(state.current.kind, state.current.rotation)
  for (var i = 0; i < cells.length; i++) {
    if (state.current.x + cells[i].x === column && gy + cells[i].y === row)
      return true
  }
  return false
}

function previewCell(kind, row, column) {
  if (!kind) return false
  var cells = cellsFor(kind, 0)
  for (var i = 0; i < cells.length; i++) {
    if (cells[i].x === column && cells[i].y === row) return true
  }
  return false
}

function dropInterval(state) {
  if (!state) return 700
  if (state.mode === "practice") {
    if (state.practiceSpeed <= 0) return 700
    return Math.max(75, Math.round(700 / state.practiceSpeed))
  }
  return Math.max(75, Math.round(850 * Math.pow(0.82, state.level - 1)))
}
