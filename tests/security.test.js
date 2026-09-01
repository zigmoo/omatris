const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const source = fs.readFileSync(path.join(__dirname, "..", "Omatris.qml"), "utf8")

// Find Text component bodies while accounting for JavaScript bindings that
// contain their own braces. This keeps the check independent of line spacing
// and catches removal or relocation of the textFormat property.
function textBlocks(qml) {
  const blocks = []
  const marker = /\bText\s*\{/g
  let match

  while ((match = marker.exec(qml)) !== null) {
    const open = qml.indexOf("{", match.index)
    let depth = 0
    let quote = ""
    let lineComment = false
    let blockComment = false
    let close = -1

    for (let i = open; i < qml.length; i++) {
      const character = qml[i]
      const next = qml[i + 1]

      if (lineComment) {
        if (character === "\n") lineComment = false
        continue
      }
      if (blockComment) {
        if (character === "*" && next === "/") {
          blockComment = false
          i++
        }
        continue
      }
      if (quote) {
        if (character === "\\") i++
        else if (character === quote) quote = ""
        continue
      }
      if ((character === "\"" || character === "'") && !quote) {
        quote = character
        continue
      }
      if (character === "/" && next === "/") {
        lineComment = true
        i++
        continue
      }
      if (character === "/" && next === "*") {
        blockComment = true
        i++
        continue
      }
      if (character === "{") depth++
      else if (character === "}" && --depth === 0) {
        close = i
        break
      }
    }

    assert.notEqual(close, -1, "every Text component must have a closing brace")
    blocks.push(qml.slice(open + 1, close))
  }
  return blocks
}

const blocks = textBlocks(source)
const overlayTitle = blocks.filter(block =>
  /\btext\s*:\s*modelData\.title\b/.test(block)
  && /\belide\s*:\s*Text\.ElideRight\b/.test(block)
)
const overlayClass = blocks.filter(block => /\btext\s*:\s*modelData\.appClass\b/.test(block))

assert.equal(overlayTitle.length, 1, "the overlay window title sink must remain identifiable")
assert.equal(overlayClass.length, 1, "the overlay application class sink must remain identifiable")
for (const [name, block] of [["window title", overlayTitle[0]], ["application class", overlayClass[0]]]) {
  assert.match(block, /\btextFormat\s*:\s*Text\.PlainText\b/, `${name} must render as plain text`)
}

console.log("Security checks passed")
