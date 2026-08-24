const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const sourcePath = path.join(__dirname, "..", "SettingsNavigation.js")
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "")
const navigation = { Math, Infinity }
vm.createContext(navigation)
vm.runInContext(source, navigation)

const controls = 11
const music = 0
const effects = 1
const firstPrimary = navigation.controlFocus(0, 0)
const firstSecondary = navigation.controlFocus(0, 1)
const secondPrimary = navigation.controlFocus(1, 0)
const secondSecondary = navigation.controlFocus(1, 1)
const hotkey = navigation.hotkeyFocus(controls)
const reset = navigation.actionFocus(controls, 0)
const mute = navigation.actionFocus(controls, 1)
const back = navigation.actionFocus(controls, 2)

assert.equal(navigation.move(music, 1, 0, controls), effects)
assert.equal(navigation.move(effects, -1, 0, controls), music)
assert.equal(navigation.move(music, 0, 1, controls), firstPrimary)
assert.equal(navigation.move(effects, 0, 1, controls), secondPrimary)

assert.equal(navigation.move(firstPrimary, 1, 0, controls), firstSecondary)
assert.equal(navigation.move(firstSecondary, 1, 0, controls), secondPrimary)
assert.equal(navigation.move(secondPrimary, 1, 0, controls), secondSecondary)
assert.equal(navigation.move(secondSecondary, -1, 0, controls), secondPrimary)
assert.equal(navigation.move(secondPrimary, -1, 0, controls), firstSecondary)

assert.equal(navigation.move(navigation.controlFocus(10, 0), 0, 1, controls), hotkey)
assert.equal(navigation.move(hotkey, 0, 1, controls), mute)
assert.equal(navigation.move(reset, 1, 0, controls), mute)
assert.equal(navigation.move(mute, 1, 0, controls), back)
assert.equal(navigation.move(back, -1, 0, controls), mute)

assert.equal(navigation.tab(music, false, controls), effects)
assert.equal(navigation.tab(effects, false, controls), firstPrimary)
assert.equal(navigation.tab(firstPrimary, true, controls), effects)
assert.equal(navigation.tab(music, true, controls), back)
assert.equal(navigation.tab(back, false, controls), music)

console.log("Settings navigation tests passed")
