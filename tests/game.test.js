const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const sourcePath = path.join(__dirname, "..", "Game.js")
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "")
const game = { Math }
vm.createContext(game)
vm.runInContext(source, game)

function fillBottomExcept(state, columns) {
  for (let column = 0; column < game.WIDTH; column++) {
    state.board[game.HEIGHT - 1][column] = columns.includes(column) ? "" : "T"
  }
}

for (const mode of ["classic", "endless", "practice", "overlay"]) {
  const state = game.newGame(mode)
  assert.equal(state.mode, mode)
  assert.equal(state.board.length, 20)
  assert.ok(state.board.every(row => row.length === 10))
  assert.equal(state.queue.length, 5)
  assert.ok(state.current)
  assert.equal(state.practiceSpeed, 1)
}

{
  const state = game.newGame("practice")
  assert.equal(game.dropInterval(state), 700)
  state.practiceSpeed = 0.5
  assert.equal(game.dropInterval(state), 1400)
  state.practiceSpeed = 1.5
  assert.equal(game.dropInterval(state), 467)
  state.practiceSpeed = 0
  assert.equal(game.dropInterval(state), 700, "the UI disables gravity when Practice speed is off")
}

{
  const state = game.newGame("classic")
  const firstPiece = state.current.kind
  assert.equal(game.hold(state), true)
  assert.equal(state.hold, firstPiece)
  assert.notEqual(state.current.kind, firstPiece, "holding an empty slot spawns the next piece")
  assert.equal(state.canHold, false)
  assert.equal(game.hold(state), false, "hold is limited to once per piece")
}

{
  const state = game.newGame("classic")
  const initialScore = state.score
  game.tick(state)
  assert.equal(state.score, initialScore, "automatic gravity does not award points")
  game.move(state, 0, 1)
  assert.equal(state.score, initialScore + 1, "soft drops award one point per row")
}

{
  const state = game.newGame("endless")
  state.current = { kind: "O", rotation: 0, x: 3, y: 18 }
  game.tick(state)
  assert.equal(state.grounded, true)
  assert.equal(state.board[19][4], "", "a grounded piece waits before locking")
  assert.equal(game.advanceLockDelay(state, 450), false)
  assert.equal(game.move(state, -1, 0), true)
  assert.equal(state.lockDelayRemaining, game.LOCK_DELAY, "ground movement resets the lock delay")
  assert.equal(game.advanceLockDelay(state, 500), true)
  assert.equal(state.board[19][3], "O")
}

{
  const state = game.newGame("endless")
  state.current = { kind: "T", rotation: 0, x: 3, y: 18 }
  assert.equal(game.rotate(state, 1), true, "SRS can kick a piece away from the floor")
  assert.equal(state.current.rotation, 1)
  assert.equal(state.current.x, 2)
  assert.equal(state.current.y, 17)
  assert.equal(state.lastRotationKick, 2)
}

{
  const right = game.I_KICKS_SRS_PLUS["0>1"]
  const left = game.I_KICKS_SRS_PLUS["0>3"]
  assert.deepEqual(
    JSON.parse(JSON.stringify(left)),
    JSON.parse(JSON.stringify(right.map(([x, y]) => [-x, y]))),
    "SRS+ mirrors the I piece's left rotation kicks across the y-axis"
  )
}

{
  const state = game.newGame("classic")
  fillBottomExcept(state, [6, 7, 8, 9])
  state.current = { kind: "I", rotation: 0, x: 6, y: 18 }
  game.hardDrop(state)
  assert.equal(state.lines, 1)
  assert.equal(state.score, 100, "a single line awards 100 points at level one")
  assert.equal(state.board[game.HEIGHT - 1].every(cell => cell === ""), true)
  assert.deepEqual(JSON.parse(JSON.stringify(state.lastClearedRows)), [19])
  assert.deepEqual(
    JSON.parse(JSON.stringify(state.lastLandingEdges)),
    [{ x: 6, y: 19 }, { x: 7, y: 19 }, { x: 8, y: 19 }, { x: 9, y: 19 }],
    "the landing effect follows only the piece edges supported by the floor"
  )
}

{
  const state = game.newGame("classic")
  state.current = { kind: "I", rotation: 0, x: 3, y: -1 }
  game.hardDrop(state)
  assert.equal(state.score, 38, "hard drops award two points per descended row")
  assert.equal(state.lastHardDropDistance, 19, "hard drops retain their travel distance for visual effects")
  assert.deepEqual(
    JSON.parse(JSON.stringify(state.lastLockedCells)),
    [{ x: 3, y: 19 }, { x: 4, y: 19 }, { x: 5, y: 19 }, { x: 6, y: 19 }]
  )
}

{
  const state = game.newGame("endless")
  state.board[18][3] = "J"
  state.board[18][5] = "L"
  state.current = { kind: "T", rotation: 0, x: 3, y: 18 }
  state.lastAction = "rotate"
  state.lastRotationKick = 0
  game.hardDrop(state)
  assert.equal(state.score, 400, "a no-line T-spin receives its spin score")
  assert.equal(state.tSpins, 1)
  assert.equal(state.lastLockSpin, "full")
  assert.equal(state.lastEvent, "T-Spin  +400")
}

{
  const state = game.newGame("endless")
  state.board[18][3] = "J"
  state.current = { kind: "T", rotation: 0, x: 3, y: 18 }
  state.lastAction = "rotate"
  state.lastRotationKick = 0
  game.hardDrop(state)
  assert.equal(state.score, 100, "three occupied corners with one front corner is a T-spin mini")
  assert.equal(state.tSpinMinis, 1)
  assert.equal(state.lastEvent, "T-Spin Mini  +100")
}

{
  const state = game.newGame("endless")
  fillBottomExcept(state, [3, 4, 5])
  state.board[18][3] = "J"
  state.board[18][5] = "L"
  state.current = { kind: "T", rotation: 0, x: 3, y: 18 }
  state.lastAction = "rotate"
  state.lastRotationKick = 0
  game.hardDrop(state)
  assert.equal(state.lines, 1)
  assert.equal(state.score, 800, "a T-spin single receives its spin score")
  assert.equal(state.lastEvent, "T-Spin Single  +800")
}

{
  const state = game.newGame("endless")
  state.board = game.emptyBoard()
  for (let column = 0; column < game.WIDTH; column++) {
    if (![3, 4, 5].includes(column)) state.board[18][column] = "J"
    if (column !== 4) state.board[19][column] = "L"
  }
  state.board[17][3] = "S"
  state.current = { kind: "T", rotation: 1, x: 3, y: 17 }
  state.lastAction = "move"
  state.lastRotationKick = -1
  assert.equal(game.rotate(state, 1), true, "the T rotates into a standard T-spin-double slot")
  game.hardDrop(state)
  assert.equal(state.lines, 2)
  assert.equal(state.score, 1200)
  assert.equal(state.lastEvent, "T-Spin Double  +1200")
}

{
  const state = game.newGame("endless")
  state.board[18][3] = "J"
  state.board[18][5] = "L"
  state.current = { kind: "T", rotation: 0, x: 3, y: 17 }
  state.lastAction = "rotate"
  state.lastRotationKick = 0
  assert.equal(game.move(state, 0, 1), true)
  game.hardDrop(state)
  assert.equal(state.score, 1, "translation after rotation cancels T-spin recognition")
  assert.equal(state.tSpins, 0)
}

{
  const state = game.newGame("classic")
  state.lines = 39
  fillBottomExcept(state, [6, 7, 8, 9])
  state.current = { kind: "I", rotation: 0, x: 6, y: 18 }
  game.hardDrop(state)
  assert.equal(state.lines, 40)
  assert.equal(state.status, "won")
}

{
  const state = game.newGame("practice")
  state.board[0][4] = "Z"
  state.board[0][5] = "Z"
  game.spawn(state, "O")
  assert.equal(state.status, "playing")
  assert.ok(state.board.every(row => row.every(cell => cell === "")))
}

{
  const state = game.newGame("endless")
  state.board[0][4] = "Z"
  state.board[0][5] = "Z"
  game.spawn(state, "O")
  assert.equal(state.status, "over")
  assert.equal(state.lastEvent, "Top out")
}

{
  const state = game.newGame("endless")
  state.score = 1200
  assert.equal(game.qualifiesForLocalBest(state, 1199), true)
  assert.equal(game.qualifiesForLocalBest(state, 1200), false, "a tied score is not a new local best")
  assert.equal(game.endRun(state), true)
  assert.equal(state.status, "over")
  assert.equal(state.paused, false)
  assert.equal(game.qualifiesForLocalBest(state, 0), false, "a finished run cannot be finalized twice")
}

{
  const state = game.newGame("practice")
  state.score = 99999
  assert.equal(game.qualifiesForLocalBest(state, 0), false, "practice scores are never local bests")
}

console.log("Game engine tests passed")
