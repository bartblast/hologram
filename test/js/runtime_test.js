
import { assert, mockWindow } from "./support/commons";
import Runtime from "../../assets/js/hologram/runtime";

describe("getInstance()", () => {
  globalThis.window = mockWindow()
  
  it("creates a new Runtime object if it doesn't exist yet", () => {
    const runtime = Runtime.getInstance()

    assert.isTrue(runtime instanceof Runtime)
    assert.equal(globalThis.__hologramRuntime__, runtime)
  })

  it("doesn't create a new Runtime object if it already exists", () => {    
    const runtime1 = Runtime.getInstance()
    const runtime2 = Runtime.getInstance()

    assert.equal(runtime2, runtime1)
  })
})