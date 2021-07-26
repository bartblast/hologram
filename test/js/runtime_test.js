import { assert, mockWindow, sinon } from "./support/commons";
import Runtime from "../../assets/js/hologram/runtime";

describe("executeAction()", () => {
  let actionName, actionParams, clientPushCommandFake, command, domRenderFake, runtime, state, window;
  beforeEach(() => {
    actionName = "test_action"
    command = {type: "atom", value: "test_command"}
    actionParams = {type: "map", data: {a: {type: "integer", value: 1}, b: {type: "integer", value: 2}}}
    state = {type: "map", data: {x: {type: "integer", value: 1}, y: {type: "integer", value: 2}}}

    window = mockWindow()
    runtime = new Runtime(window)
    runtime.dom = {render() {}}

    domRenderFake = sinon.fake();
    runtime.dom.render = domRenderFake

    clientPushCommandFake = sinon.fake()
    runtime.client.pushCommand = clientPushCommandFake
  });

  it("action returns a tuple including a command without params", () => {
    const context = {
      pageModule: class {},
      scopeModule: class {
        static action(_name, params, state) {
          state.data.x.value += params.data.b.value
          return {type: "tuple", data: [state, command]}
        }
      }
    }

    runtime.executeAction(actionName, actionParams, state, context)

    const expectedState = {type: "map", data: {x: {type: "integer", value: 3}, y: {type: "integer", value: 2}}}
    assert.deepStrictEqual(runtime.state, expectedState)

    sinon.assert.calledWith(clientPushCommandFake, "test_command", {type: "map", data: {}}, context);
    sinon.assert.calledWith(domRenderFake, context.pageModule)
  })

  it("action returns a tuple including a command with params", () => {
    const commandParams = {
      type: "map",
      data: {
        m: {type: "integer", value: 9},
        n: {type: "integer", value: 8}
      }
    }

    const context = {
      pageModule: class {},
      scopeModule: class {
        static action(_name, params, state) {
          state.data.x.value += params.data.b.value
          return {type: "tuple", data: [state, command, commandParams]}
        }
      }
    }

    runtime.executeAction(actionName, actionParams, state, context)

    const expectedState = {type: "map", data: {x: {type: "integer", value: 3}, y: {type: "integer", value: 2}}}
    assert.deepStrictEqual(runtime.state, expectedState)

    sinon.assert.calledWith(clientPushCommandFake, "test_command", commandParams, context);
    sinon.assert.calledWith(domRenderFake, context.pageModule)
  })

  it("action result is not a tuple", () => {
    const context = {
      pageModule: class {},
      scopeModule: class {
        static action(_name, params, state) {
          state.data.x.value += params.data.b.value
          return state
        }
      }
    }

    runtime.executeAction(actionName, actionParams, state, context)

    const expectedState = {type: "map", data: {x: {type: "integer", value: 3}, y: {type: "integer", value: 2}}}
    assert.deepStrictEqual(runtime.state, expectedState)

    sinon.assert.notCalled(clientPushCommandFake);
    sinon.assert.calledWith(domRenderFake, context.pageModule)
  })
})