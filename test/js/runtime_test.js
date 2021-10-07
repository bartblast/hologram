"use strict";

import { assert, fixtureOperationParamsKeyword, fixtureOperationParamsMap, fixtureOperationSpecExpressionNode, mockWindow, sinon } from "./support/commons";
import Runtime from "../../assets/js/hologram/runtime";
import Type from "../../assets/js/hologram/type";

describe("buildOperationSpecFromExpression()", () => {
  let context, runtime, TestPageModule, TestTargetModule;

  beforeEach(() => {
    const window = mockWindow()
    runtime = new Runtime(window)

    const TestLayoutModule = class {}
    TestPageModule = class {}
    TestTargetModule = class {}

    context = {
      bindings: Type.map({}),
      layoutModule: TestLayoutModule,
      pageModule: TestPageModule,
      targetModule: TestTargetModule,
      targetId: "test_target_id"
    }
  })

  it("builds operation spec from an expression node with target specified", () => {
    const specTuple = Type.tuple([
      Type.atom("page"),
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(specTuple)

    const result = runtime.buildOperationSpecFromExpression(expressionNode, context)

    const expected = {
      targetModule: TestPageModule,
      targetId: null,
      name: Type.atom("test_action"),
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })

  it("builds operation spec from an expression node without target specified", () => {
    const specTuple = Type.tuple([
      Type.atom("test_action"),
      fixtureOperationParamsKeyword()
    ])

    const expressionNode = fixtureOperationSpecExpressionNode(specTuple)

    const result = runtime.buildOperationSpecFromExpression(expressionNode, context)

    const expected = {
      targetModule: TestTargetModule,
      targetId: "test_target_id",
      name: Type.atom("test_action"),
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildOperationSpecFromExpressionWithTarget()", () => {
  let name, paramsMap, paramsKeyword, runtime, TestComponent2Module;

  beforeEach(() => {
    name = Type.atom("test")
    paramsKeyword = fixtureOperationParamsKeyword()
    paramsMap = fixtureOperationParamsMap()

    const window = mockWindow()
    runtime = new Runtime(window)

    const TestComponent1Module = class {}
    TestComponent2Module = class {}

    runtime.componentModules = {
      test_component_1: TestComponent1Module,
      test_component_2: TestComponent2Module
    }
  })

  it("builds layout operation spec if the first spec elem is equal to :layout boxed atom", () => {
    const target = Type.atom("layout")

    const specElems = [
      target,
      name,
      paramsKeyword
    ]

    const TestLayoutModule = class {}
    const context = {layoutModule: TestLayoutModule}

    const result = runtime.buildOperationSpecFromExpressionWithTarget(specElems, context)

    const expected = {
      targetModule: TestLayoutModule,
      targetId: null,
      name: name,
      params: paramsMap
    }

    assert.deepStrictEqual(result, expected)
  })

  it("builds page operation spec if the first spec elem is equal to :page boxed atom", () => {
    const target = Type.atom("page")

    const specElems = [
      target,
      name,
      paramsKeyword
    ]

    const TestPageModule = class {}
    const context = {pageModule: TestPageModule}

    const result = runtime.buildOperationSpecFromExpressionWithTarget(specElems, context)

    const expected = {
      targetModule: TestPageModule,
      targetId: null,
      name: name,
      params: paramsMap
    }

    assert.deepStrictEqual(result, expected)
  })

  it("builds component operation spec if the first spec elem is different than :page or :layout boxed atom", () => {
    const target = Type.atom("test_component_2")

    const specElems = [
      target,
      name,
      paramsKeyword
    ]

    const result = runtime.buildOperationSpecFromExpressionWithTarget(specElems, {})

    const expected = {
      targetModule: TestComponent2Module,
      targetId: "test_component_2",
      name: name,
      params: paramsMap
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildOperationSpecFromExpressionWithoutTarget()", () => {
  it("builds operation spec from an expression without target specified", () => {
    const name = Type.atom("test")
    const paramsKeyword = fixtureOperationParamsKeyword()

    const specElems = [
      name,
      paramsKeyword
    ]

    const TestTargetModule = class {}
    const context = {targetModule: TestTargetModule, targetId: "test_id"}

    const result = Runtime.buildOperationSpecFromExpressionWithoutTarget(specElems, context)

    const expected = {
      targetModule: TestTargetModule,
      targetId: "test_id",
      name: name,
      params: fixtureOperationParamsMap()
    }

    assert.deepStrictEqual(result, expected)
  })
})

describe("buildOperationSpecFromTextNode()", () => {
  it("builds operation spec from a text node", () => {
    const TestTargetModule = class {}
    const context = {targetModule: TestTargetModule}
    const textNode = Type.textNode("test")

    const expected = {
      targetModule: TestTargetModule,
      targetId: null,
      name: Type.atom("test"),
      params: Type.map({})
    }

    const result = Runtime.buildOperationSpecFromTextNode(textNode, context)

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
    const window = mockWindow()
    const runtime = Runtime.getInstance(window)

    const TestComponentModule1 = class {}
    const TestComponentModule2 = class {}

    runtime.componentModules = {
      component1: TestComponentModule1,
      component2: TestComponentModule2
    }

    const result = runtime.getModuleByComponentId("component2")

    assert.equal(result, TestComponentModule2)
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