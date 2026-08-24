.pragma library

var WIDTH = 10
var HEIGHT = 20

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
    lastEvent: mode === "practice" ? "No top-outs. Take your time." : "Good luck"
  }
  fillQueue(state)
  spawnNext(state)
  return state
}

function move(state, dx, dy, awardSoftDrop) {
  if (!state || state.status !== "playing" || state.paused) return false
  if (!collides(state, state.current, dx, dy, state.current.rotation)) {
    state.current.x += dx
    state.current.y += dy
    if (dy > 0 && awardSoftDrop !== false) state.score += 1
    return true
  }
  return false
}

function rotate(state, direction) {
  if (!state || state.status !== "playing" || state.paused) return false
  var nextRotation = (state.current.rotation + direction + 4) % 4
  var kicks = [0, -1, 1, -2, 2]
  for (var i = 0; i < kicks.length; i++) {
    if (!collides(state, state.current, kicks[i], 0, nextRotation)) {
      state.current.x += kicks[i]
      state.current.rotation = nextRotation
      return true
    }
  }
  return false
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

function lockPiece(state) {
  var piece = state.current
  var cells = cellsFor(piece.kind, piece.rotation)
  var aboveBoard = false
  for (var i = 0; i < cells.length; i++) {
    var x = piece.x + cells[i].x
    var y = piece.y + cells[i].y
    if (y < 0) aboveBoard = true
    else state.board[y][x] = piece.kind
  }

  if (aboveBoard && state.mode !== "practice") {
    state.status = "over"
    state.lastEvent = "Top out"
    return
  }
  if (aboveBoard) state.board = emptyBoard()

  var cleared = clearCompletedLines(state)
  if (cleared > 0) {
    var points = [0, 100, 300, 500, 800][cleared] * state.level
    state.score += points
    state.lines += cleared
    state.lastEvent = cleared === 4 ? "Omatris  +" + points : cleared + (cleared === 1 ? " line" : " lines") + "  +" + points
    if (state.mode !== "practice") state.level = 1 + Math.floor(state.lines / 10)
    if (state.mode === "classic" && state.lines >= 40) {
      state.status = "won"
      state.lastEvent = "40 lines complete"
      return
    }
  } else {
    state.lastEvent = ""
  }
  spawnNext(state)
}

function tick(state) {
  if (!state || state.status !== "playing" || state.paused) return false
  if (!move(state, 0, 1, false)) lockPiece(state)
  return true
}

function hardDrop(state) {
  if (!state || state.status !== "playing" || state.paused) return false
  var distance = 0
  while (!collides(state, state.current, 0, distance + 1, state.current.rotation)) distance += 1
  state.current.y += distance
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
