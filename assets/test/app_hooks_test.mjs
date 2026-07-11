import assert from "node:assert/strict"
import fs from "node:fs"
import test from "node:test"
import vm from "node:vm"

function loadBufferedColorSlider(document) {
  const source = fs.readFileSync(new URL("../js/app.js", import.meta.url), "utf8")
  const functionStart = source.indexOf("function bindBufferedColorSlider")
  const sharedStateStart = source.lastIndexOf("let bufferedColorDispatches", functionStart)
  const start = sharedStateStart >= 0 ? sharedStateStart : functionStart
  const end = source.indexOf("Hooks.ColorHueSlider", functionStart)

  assert.notEqual(functionStart, -1)
  assert.notEqual(end, -1)

  const context = vm.createContext({
    clearTimeout,
    document,
    setTimeout
  })

  vm.runInContext(
    `${source.slice(start, end)}\nglobalThis.bindBufferedColorSlider = bindBufferedColorSlider`,
    context
  )

  return context.bindBufferedColorSlider
}

function fakeElement(value, dataset = {}) {
  const listeners = new Map()

  return {
    dataset,
    value,
    addEventListener(name, listener) {
      listeners.set(name, listener)
    },
    listener(name) {
      return listeners.get(name)
    }
  }
}

test("paired hue and saturation inputs emit one buffered color event", async () => {
  const hue = fakeElement("120", {
    type: "light",
    id: "42",
    hueInputId: "hue-42",
    saturationInputId: "saturation-42"
  })

  const saturation = fakeElement("50", {
    type: "light",
    id: "42",
    hueInputId: "hue-42",
    saturationInputId: "saturation-42"
  })

  const elements = new Map([
    ["hue-42", hue],
    ["saturation-42", saturation]
  ])

  const document = {
    addEventListener() {},
    removeEventListener() {},
    getElementById(id) {
      return elements.get(id) || null
    }
  }

  const bindBufferedColorSlider = loadBufferedColorSlider(document)
  const events = []

  const hueHook = {
    el: hue,
    pushEvent(name, payload) {
      events.push({ name, payload })
    }
  }

  const saturationHook = {
    el: saturation,
    pushEvent(name, payload) {
      events.push({ name, payload })
    }
  }

  bindBufferedColorSlider(hueHook, String)
  bindBufferedColorSlider(saturationHook, String)

  hue.value = "125"
  hue.listener("input")({ target: hue })
  saturation.value = "55"
  saturation.listener("input")({ target: saturation })

  await new Promise((resolve) => setTimeout(resolve, 250))

  assert.deepEqual(JSON.parse(JSON.stringify(events)), [
    {
      name: "set_color",
      payload: { type: "light", id: "42", hue: "125", saturation: "55" }
    }
  ])
})
