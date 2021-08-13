import { assert, mockWindow, sinon } from "./support/commons";
import Runtime from "../../assets/js/hologram/runtime";

describe("executeAction()", () => {
  let action, actionParams, clientPushCommandFake, command, domRenderFake, runtime, state, window;

  beforeEach(() => {
    action = {type: "atom", value: "test_action"}
    command = {type: "atom", value: "test_command"}

    actionParams = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": {type: "integer", value: 2}
      }
    }

    state = {
      type: "map", 
      data: {
        "~atom[x]": {type: "integer", value: 1}, 
        "~atom[y]": {type: "integer", value: 2}
      }
    }

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
        static action(_action, params, state) {
          state.data["~atom[x]"].value += params.data["~atom[b]"].value
          return {type: "tuple", data: [state, command]}
        }
      }
    }

    runtime.executeAction(action, actionParams, state, context)

    const expectedState = {
      type: "map", 
      data: {
        "~atom[x]": {type: "integer", value: 3},
        "~atom[y]": {type: "integer", value: 2}
      }
    }

    assert.deepStrictEqual(runtime.state, expectedState)

    const commandName = {type: "atom", value: "test_command"}
    const commandParams = {type: "map", data: {}}
    sinon.assert.calledWith(clientPushCommandFake, commandName, commandParams, context);
    sinon.assert.calledWith(domRenderFake, context.pageModule)
  })

  it("action returns a tuple including a command with params", () => {
    const commandParams = {
      type: "map",
      data: {
        "~atom[m]": {type: "integer", value: 9},
        "~atom[n]": {type: "integer", value: 8}
      }
    }

    const context = {
      pageModule: class {},
      scopeModule: class {
        static action(_action, params, state) {
          state.data["~atom[x]"].value += params.data["~atom[b]"].value
          return {type: "tuple", data: [state, command, commandParams]}
        }
      }
    }

    runtime.executeAction(action, actionParams, state, context)

    const expectedState = {
      type: "map",
      data: {
        "~atom[x]": {type: "integer", value: 3},
        "~atom[y]": {type: "integer", value: 2}
      }
    }

    assert.deepStrictEqual(runtime.state, expectedState)

    const commandName = {type: "atom", value: "test_command"}
    sinon.assert.calledWith(clientPushCommandFake, commandName, commandParams, context);
    sinon.assert.calledWith(domRenderFake, context.pageModule)
  })

  it("action result is not a tuple", () => {
    const context = {
      pageModule: class {},
      scopeModule: class {
        static action(_action, params, state) {
          state.data["~atom[x]"].value += params.data["~atom[b]"].value
          return state
        }
      }
    }

    runtime.executeAction(action, actionParams, state, context)

    const expectedState = {
      type: "map", 
      data: {
        "~atom[x]": {type: "integer", value: 3},
        "~atom[y]": {type: "integer", value: 2}
      }
    }

    assert.deepStrictEqual(runtime.state, expectedState)

    sinon.assert.notCalled(clientPushCommandFake);
    sinon.assert.calledWith(domRenderFake, context.pageModule)
  })
})

describe("handleEventAction()", () => {
  let context, event, fake, runtime, state;

  beforeEach(() => {
    const window = mockWindow()
    runtime = new Runtime(window)

    fake = sinon.fake();
    runtime.executeAction = fake

    state = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 123}
      }
    }

    context = {
      pageModule: class {},
      scopeModule: class {}
    }

    event = {}
  });

  it("handles string event value", () => {
    const eventValue = "test_action_name"

    runtime.handleEventAction(eventValue, state, context, event)

    const actionName = {type: "atom", value: "test_action_name"}
    const actionParams = {type: "map", data: {}}

    sinon.assert.calledWith(fake, actionName, actionParams, state, context)
  })

  it("handles expression event value", () => {
    const eventValue = {
      type: "expression",
      callback: (_$state) => {
        return {
          type: "tuple",
          data: [
            {type: "atom", value: "test_action_name"},
            {
              type: "list",
              data: [
                {
                  type: "tuple", 
                  data: [
                    {type: "atom", value: "a"},
                    {type: "integer", value: 1}
                  ]
                },
                {
                  type: "tuple", 
                  data: [
                    {type: "atom", value: "b"},
                    {type: "integer", value: 2}
                  ]
                },
              ]
            }
          ]
        }
      }
    }

    runtime.handleEventAction(eventValue, state, context, event)

    const actionName = {type: "atom", value: "test_action_name"}

    const actionParams = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": {type: "integer", value: 2}
      }
    }

    sinon.assert.calledWith(fake, actionName, actionParams, state, context)
  })
})

describe("handleEventCommand()", () => {
  let context, event, fake, runtime, state;

  beforeEach(() => {
    const window = mockWindow()
    runtime = new Runtime(window)
    runtime.client = {}

    fake = sinon.fake();
    runtime.client.pushCommand = fake

    state = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 123}
      }
    }

    context = {
      pageModule: class {},
      scopeModule: class {}
    }

    event = {}
  });

  it("handles string event value", () => {
    const eventValue = "test_command_name"

    runtime.handleEventCommand(eventValue, state, context, event)

    const commandName = {type: "atom", value: "test_command_name"}
    const commandParams = {type: "map", data: {}}

    sinon.assert.calledWith(fake, commandName, commandParams, context)
  })

  it("handles expression event value", () => {
    const eventValue = {
      type: "expression",
      callback: (_$state) => {
        return {
          type: "tuple",
          data: [
            {type: "atom", value: "test_command_name"},
            {
              type: "list",
              data: [
                {
                  type: "tuple", 
                  data: [
                    {type: "atom", value: "a"},
                    {type: "integer", value: 1}
                  ]
                },
                {
                  type: "tuple", 
                  data: [
                    {type: "atom", value: "b"},
                    {type: "integer", value: 2}
                  ]
                },
              ]
            }
          ]
        }
      }
    }

    runtime.handleEventCommand(eventValue, state, context, event)

    const commandName = {type: "atom", value: "test_command_name"}

    const commandParams = {
      type: "map", 
      data: {
        "~atom[a]": {type: "integer", value: 1},
        "~atom[b]": {type: "integer", value: 2}
      }
    }

    sinon.assert.calledWith(fake, commandName, commandParams, context)
  })
})