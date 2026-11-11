"use strict";

import {
  assert,
  contextFixture,
  defineRuntimeGlobals,
  setDataLayer,
} from "./support/helpers.mjs";

import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramBoxedError from "../../assets/js/errors/boxed_error.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import ManuallyPortedElixirHologramQueryStage from "../../assets/js/elixir/hologram/query/stage.mjs";
import Model from "../../assets/js/model.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

// The from_query prop binding, which only from_query has. What a query prop renders is covered for
// derived fields in test/javascript/renderer_derived_test.mjs.
describe("Renderer from_query props", () => {
  const TASK = "MyApp.Task";

  const context = Type.map();
  const defaultTarget = Type.bitstring("my_default_target");
  const parentTagName = "div";
  const slots = Type.keywordList();

  const filter = ManuallyPortedElixirHologramQueryStage["filter/2"];

  // A builder as transpiled app code: it pipes the ported query stages and returns the plain
  // term, and it arrives here boxed the way any capture does.
  const builder = (arity, build) =>
    Type.anonymousFunction(
      arity,
      [
        {
          params: (_context) =>
            Array.from({length: arity}, (_item, index) =>
              Type.variablePattern(`$${index + 1}`),
            ),
          guards: [],
          body: (bodyContext) =>
            build(
              ...Array.from(
                {length: arity},
                (_item, index) => bodyContext.vars[`$${index + 1}`],
              ),
            ),
        },
      ],
      contextFixture(),
    );

  const componentNode = (moduleName, propsDom = []) =>
    Type.tuple([
      Type.atom("component"),
      Type.alias(moduleName),
      Type.list(propsDom),
      Type.list(),
    ]);

  const defineComponent = (moduleName, propDefinitions) => {
    Interpreter.defineElixirFunction(moduleName, "__props__", 0, "public", [
      {
        params: (_context) => [],
        guards: [],
        body: (_context) => Type.list(propDefinitions),
      },
    ]);

    Interpreter.defineElixirFunction(moduleName, "template", 0, "public", [
      {
        params: (_context) => [],
        guards: [],
        body: (moduleContext) =>
          Type.anonymousFunction(
            1,
            [
              {
                params: (_context) => [Type.variablePattern("vars")],
                guards: [],
                body: (_bodyContext) =>
                  Type.list([
                    Type.tuple([Type.atom("text"), Type.bitstring("rendered")]),
                  ]),
              },
            ],
            moduleContext,
          ),
      },
    ]);
  };

  const propDefinition = (name, opts) =>
    Type.tuple([Type.atom(name), Type.atom("any"), Type.keywordList(opts)]);

  const queryProp = (name, capture) =>
    propDefinition(name, [[Type.atom("from_query"), capture]]);

  const render = (node) =>
    Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

  const doneCapture = () =>
    builder(1, (done) =>
      filter(
        Type.alias(TASK),
        Type.list([Type.tuple([Type.atom("done"), done])]),
      ),
    );

  beforeEach(() => {
    setDataLayer();

    globalThis.Hologram.sync = {
      model: {
        [TASK]: {
          attributes: {done: "boolean", id: "uuid", title: "string"},
          relationships: {},
          serverOnly: [],
        },
      },
      propParams: {},
    };

    Model.reset();
    LocalDatabase.reset();
    LocalDatabase.actorUserId = null;
    GlobalRegistry.set("connectPageModule", null);
  });

  afterEach(() => {
    Hologram.dataLayer = null;
  });

  it("raises when a like-named prop is missing", () => {
    defineComponent("MyApp.MissingProp", [queryProp("tasks", doneCapture())]);

    globalThis.Hologram.sync.propParams = {
      "MyApp.MissingProp": {tasks: ["missing_prop"]},
    };

    assert.throw(
      () => render(componentNode("MyApp.MissingProp")),
      HologramBoxedError,
      "from_query for prop :tasks in MyApp.MissingProp binds argument :missing_prop - no like-named prop is set",
    );
  });

  it("raises when an argument position is named by no clause", () => {
    defineComponent("MyApp.UnnamedPosition", [
      queryProp("tasks", doneCapture()),
    ]);

    globalThis.Hologram.sync.propParams = {
      "MyApp.UnnamedPosition": {tasks: [null]},
    };

    assert.throw(
      () => render(componentNode("MyApp.UnnamedPosition")),
      HologramBoxedError,
      "from_query capture for prop :tasks in MyApp.UnnamedPosition has an argument position no clause names - it cannot bind a prop",
    );
  });

  it("raises when the build registered no params for a parameterized capture", () => {
    defineComponent("MyApp.Unregistered", [queryProp("tasks", doneCapture())]);

    assert.throw(
      () => render(componentNode("MyApp.Unregistered")),
      HologramBoxedError,
      "no registered params for from_query prop :tasks in MyApp.Unregistered - the query cache holds no entry for it",
    );
  });
});
