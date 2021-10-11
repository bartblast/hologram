"use strict";

import { assert, fixtureOperationParamsKeyword, fixtureOperationParamsMap, fixtureOperationSpecExpressionNode, mockWindow, sinon } from "./support/commons";
import Runtime from "../../assets/js/hologram/runtime";
import Type from "../../assets/js/hologram/type";

const TestLayoutModule = class {}
const TestPageModule = class {}
const TestTargetModule = class {}

const window = mockWindow()
const runtime = Runtime.getInstance(window)

describe("executeAction()", () => {
  let actionSpec, context;

  beforeEach(() => {
    const actionSpecTuple = Type.tuple([
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    actionSpec = {
      value: [fixtureOperationSpecExpressionNode(actionSpecTuple)]
    }

    const stateElems = {}
    stateElems[Type.atomKey("x")] = Type.integer(9)

    context = {
      bindings: Type.map({}),
      layoutModule: TestLayoutModule,
      pageModule: TestPageModule,
      targetId: "test_target_id",
      state: Type.map(stateElems)
    }
  })

  it("executes action which returns new state only", () => {
    const TargetModuleMock = class {
      static action(_name, _params, state) {
        return state
      }
    }
    context.targetModule = TargetModuleMock

    const result = runtime.executeAction(actionSpec, context)

    const expected = {
      newState: context.state,
      commandName: null,
      commandParams: null
    }

    assert.deepStrictEqual(result, expected)
  })

  it("executes action which returns new state and command name", () => {
    const TargetModuleMock = class {
      static action(_name, _params, state) {
        return Type.tuple([state, Type.atom("test_command")])
      }
    }
    context.targetModule = TargetModuleMock

    const result = runtime.executeAction(actionSpec, context)

    const expected = {
      newState: context.state,
      commandName: Type.atom("test_command"),
      commandParams: Type.list([])
    }

    assert.deepStrictEqual(result, expected)
  })

  it("executes action which returns new state, command name and command params", () => {
    const TargetModuleMock = class {
      static action(_name, _params, state) {
        const commandParams = Type.list[
          Type.tuple([
            Type.atom("a"),
            Type.integer(1)
          ])
        ]

        return Type.tuple([state, Type.atom("test_command"), commandParams])
      }
    }
    context.targetModule = TargetModuleMock

    const result = runtime.executeAction(actionSpec, context)

    const expected = {
      newState: context.state,
      commandName: Type.atom("test_command"),
      commandParams: Type.list[
        Type.tuple([
          Type.atom("a"),
          Type.integer(1)
        ])
      ]
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("getInstance()", () => {
  it("creates a new Runtime object if it doesn't exist yet", () => {
    const window = mockWindow()
    const runtime = Runtime.getInstance(window)

    assert.isTrue(runtime instanceof Runtime)
    assert.equal(window.__hologramRuntime__, runtime)
  })

  it("doesn't create a new Runtime object if it already exists", () => {
    const window = mockWindow()
    const runtime1 = Runtime.getInstance(window)
    const runtime2 = Runtime.getInstance(window)

    assert.equal(runtime2, runtime1)
  })
})

describe("getCommandNameFromActionResult()", () => {
  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map({})
    const commandName = Runtime.getCommandNameFromActionResult(actionResult)

    assert.isNull(commandName)
  })

  it("fetches the command name from an action result that is a boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_target"),
      Type.atom("test_command")
    ])

    const commandName = Runtime.getCommandNameFromActionResult(actionResult)
    const expected = Type.atom("test_command")

    assert.deepStrictEqual(commandName, expected)
  })

  it("fetches the command name from an action result that is a boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_command")
    ])

    const commandName = Runtime.getCommandNameFromActionResult(actionResult)
    const expected = Type.atom("test_command")

    assert.deepStrictEqual(commandName, expected)
  })

  it("returns null if the action result is a boxed tuple that doesn't contain command name", () => {
    const actionResult = Type.tuple([
      Type.map({}),
    ])

    const commandName = Runtime.getCommandNameFromActionResult(actionResult)

    assert.isNull(commandName)
  })
})

describe("getCommandParamsFromActionResult()", () => {
  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map({})
    const commandParams = Runtime.getCommandParamsFromActionResult(actionResult)

    assert.isNull(commandParams)
  })

  it("fetches the command params from an action result that is a boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_target"),
      Type.atom("test_command"),
      fixtureOperationParamsKeyword()
    ])

    const commandParams = Runtime.getCommandParamsFromActionResult(actionResult)
    const expected = fixtureOperationParamsKeyword()

    assert.deepStrictEqual(commandParams, expected)
  })

  it("fetches the command params from an action result that is a boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_command"),
      fixtureOperationParamsKeyword()
    ])

    const commandParams = Runtime.getCommandParamsFromActionResult(actionResult)
    const expected = fixtureOperationParamsKeyword()

    assert.deepStrictEqual(commandParams, expected)
  })

  it("returns null if the action result is a boxed tuple that doesn't contain command params", () => {
    const actionResult = Type.tuple([
      Type.map({}),
    ])

    const commandParams = Runtime.getCommandNameFromActionResult(actionResult)

    assert.isNull(commandParams)
  })
})

describe("getStateFromActionResult()", () => {
  it("fetches the state from an action result that is a boxed map", () => {
    const actionResult = Type.map({})
    const state = Runtime.getStateFromActionResult(actionResult)

    assert.equal(state, actionResult)
  })

  it("fetches the state from an action result that is a boxed tuple", () => {
    const actionResult = Type.tuple([Type.map({}), Type.atom("test_command")])
    const state = Runtime.getStateFromActionResult(actionResult)

    assert.deepStrictEqual(state, Type.map({}))
  })
})

describe("getTargetFromActionResult()", () => {
  it("returns null if the action result is a boxed map", () => {
    const actionResult = Type.map({})
    const target = Runtime.getTargetFromActionResult(actionResult)

    assert.isNull(target)
  })

  it("fetches the target from an action result that is a boxed tuple that contains target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
      Type.atom("test_target"),
      Type.atom("test_command")
    ])

    const target = Runtime.getTargetFromActionResult(actionResult)
    const expected = Type.atom("test_target")

    assert.deepStrictEqual(target, expected)
  })

  it("returns null if the action result is a boxed tuple that doesn't contain target", () => {
    const actionResult = Type.tuple([
      Type.map({}),
    ])

    const target = Runtime.getCommandNameFromActionResult(actionResult)

    assert.isNull(target)
  })
})















describe("executeAction2()", () => {
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

    runtime.executeAction2(action, actionParams, state, context)

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

    runtime.executeAction2(action, actionParams, state, context)

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

    runtime.executeAction2(action, actionParams, state, context)

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