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
  const state = game.newGame("classic")
  fillBottomExcept(state, [6, 7, 8, 9])
  state.current = { kind: "I", rotation: 0, x: 6, y: 18 }
  game.hardDrop(state)
  assert.equal(state.lines, 1)
  assert.equal(state.score, 100, "a single line awards 100 points at level one")
  assert.equal(state.board[game.HEIGHT - 1].every(cell => cell === ""), true)
}

{
  const state = game.newGame("classic")
  state.current = { kind: "I", rotation: 0, x: 3, y: -1 }
  game.hardDrop(state)
  assert.equal(state.score, 38, "hard drops award two points per descended row")
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

console.log("Game engine tests passed")
