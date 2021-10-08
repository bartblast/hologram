"use strict";

import { assert, fixtureOperationParamsKeyword, fixtureOperationParamsMap, fixtureOperationSpecExpressionNode, mockWindow, sinon } from "./support/commons";
import Runtime from "../../assets/js/hologram/runtime";
import Type from "../../assets/js/hologram/type";

const TestLayoutModule = class {}
const TestPageModule = class {}
const TestTargetModule = class {}
const TestComponentModule1 = class {}
const TestComponentModule2 = class {}

const window = mockWindow()
const runtime = Runtime.getInstance(window)

describe("buildOperation()", () => {
  let context, expected;

  beforeEach(() => {
    context = {
      bindings: Type.map({}),
      layoutModule: TestLayoutModule,
      pageModule: TestPageModule,
      targetModule: TestTargetModule,
      targetId: "test_target_id"
    }

    expected = Type.atom("test_action")
  })

  it("builds operation from event handler spec with expression node", () => {
    const specTuple = Type.tuple([
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const eventHandlerSpec = {
      value: [fixtureOperationSpecExpressionNode(specTuple)]
    }

    const result = runtime.buildOperation(eventHandlerSpec, context)
    
    assert.deepStrictEqual(result.name, expected)
  })

  it("builds operation from event handler spec with text node", () => {
    const eventHandlerSpec = {
      value: [Type.textNode("test_action")]
    }

    const result = runtime.buildOperation(eventHandlerSpec, context)
    
    assert.deepStrictEqual(result.name, expected)
  })
})

describe("buildOperationFromExpressionNode()", () => {
  let context;

  beforeEach(() => {
    context = {
      bindings: Type.map({}),
      layoutModule: TestLayoutModule,
      pageModule: TestPageModule,
      targetModule: TestTargetModule,
      targetId: "test_target_id"
    }
  })

  it("builds operation from an expression node spec with target specified", () => {
    const specTuple = Type.tuple([
      Type.atom("page"),
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(specTuple)

    const result = runtime.buildOperationFromExpressionNode(expressionNode, context)

    const expected = {
      targetModule: TestPageModule,
      targetId: null,
      name: Type.atom("test_action"),
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })

  it("builds operation from an expression node spec without target specified", () => {
    const specTuple = Type.tuple([
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(specTuple)

    const result = runtime.buildOperationFromExpressionNode(expressionNode, context)

    const expected = {
      targetModule: TestTargetModule,
      targetId: "test_target_id",
      name: Type.atom("test_action"),
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildOperationFromExpressionNodeWithTarget()", () => {
  let name, paramsMap, paramsKeyword;

  beforeEach(() => {
    name = Type.atom("test")
    paramsKeyword = fixtureOperationParamsKeyword()
    paramsMap = fixtureOperationParamsMap()

    runtime.componentModules = {
      test_component_1: TestComponentModule1,
      test_component_2: TestComponentModule2
    }
  })

  it("builds layout target operation if the first spec elem is equal to :layout boxed atom", () => {
    const target = Type.atom("layout")

    const specElems = [
      target,
      name,
      paramsKeyword
    ]

    const context = {layoutModule: TestLayoutModule}

    const result = runtime.buildOperationFromExpressionNodeWithTarget(specElems, context)

    const expected = {
      targetModule: TestLayoutModule,
      targetId: null,
      name: name,
      params: paramsMap
    }

    assert.deepStrictEqual(result, expected)
  })

  it("builds page target operation if the first spec elem is equal to :page boxed atom", () => {
    const target = Type.atom("page")

    const specElems = [
      target,
      name,
      paramsKeyword
    ]

    const context = {pageModule: TestPageModule}

    const result = runtime.buildOperationFromExpressionNodeWithTarget(specElems, context)

    const expected = {
      targetModule: TestPageModule,
      targetId: null,
      name: name,
      params: paramsMap
    }

    assert.deepStrictEqual(result, expected)
  })

  it("builds component target operation if the first spec elem is different than :page or :layout boxed atom", () => {
    const target = Type.atom("test_component_2")

    const specElems = [
      target,
      name,
      paramsKeyword
    ]

    const result = runtime.buildOperationFromExpressionNodeWithTarget(specElems, {})

    const expected = {
      targetModule: TestComponentModule2,
      targetId: "test_component_2",
      name: name,
      params: paramsMap
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildOperationFromExpressionNodeWithoutTarget()", () => {
  it("builds operation from an expression node spec without target specified", () => {
    const name = Type.atom("test")
    const paramsKeyword = fixtureOperationParamsKeyword()

    const specElems = [
      name,
      paramsKeyword
    ]

    const context = {targetModule: TestTargetModule, targetId: "test_id"}

    const result = Runtime.buildOperationFromExpressionNodeWithoutTarget(specElems, context)

    const expected = {
      targetModule: TestTargetModule,
      targetId: "test_id",
      name: name,
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })
})

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

describe("getModuleByComponentId()", () => {
  it("returns the class of the component with the given ID", () => {
    runtime.componentModules = {
      component1: TestComponentModule1,
      component2: TestComponentModule2
    }

    const result = runtime.getModuleByComponentId("component2")

    assert.equal(result, TestComponentModule2)
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

describe("hasOperationTarget()", () => {
  it("returns true if the first 2 spec elems are bounded atoms", () => {
    const specElems = [Type.atom("a"), Type.atom("b")]
    const result = Runtime.hasOperationTarget(specElems)

    assert.isTrue(result)
  })

  it("returns false if there is only 1 spec elem", () => {
    const specElems = [Type.atom("a")]
    const result = Runtime.hasOperationTarget(specElems)

    assert.isFalse(result)
  })

  it("returns false if the first spec elem is not a bounded atom", () => {
    const specElems = [Type.integer(1), Type.atom("b")]
    const result = Runtime.hasOperationTarget(specElems)

    assert.isFalse(result)
  })

  it("returns false if the second spec elem is not a bounded atom", () => {
    const specElems = [Type.atom("a"), Type.integer(2)]
    const result = Runtime.hasOperationTarget(specElems)

    assert.isFalse(result)
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