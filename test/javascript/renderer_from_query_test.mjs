"use strict";

import {
  assert,
  contextFixture,
  defineRuntimeGlobals,
} from "./support/helpers.mjs";

import HologramBoxedError from "../../assets/js/errors/boxed_error.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import ManuallyPortedElixirHologramQuery from "../../assets/js/elixir/hologram/query.mjs";
import Model from "../../assets/js/model.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors the corresponding cases of test/elixir/hologram/template/renderer_from_query_test.exs.
// What differs is where the rows come from - the client answers from its own database, and the
// policy filtering the server does has no client-side half by decision 7.
describe("Renderer from_query props", () => {
  const PROJECT = "MyApp.Project";
  const TASK = "MyApp.Task";

  const context = Type.map();
  const defaultTarget = Type.bitstring("my_default_target");
  const parentTagName = "div";
  const slots = Type.keywordList();

  const filter = ManuallyPortedElixirHologramQuery["filter/2"];
  const include = ManuallyPortedElixirHologramQuery["include/3"];
  const one = ManuallyPortedElixirHologramQuery["one/1"];
  const orderBy = ManuallyPortedElixirHologramQuery["order_by/2"];

  // What the template was rendered with - the props the pipeline resolved, which is what this
  // stage produces.
  let renderedVars = null;

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
                body: (bodyContext) => {
                  renderedVars = bodyContext.vars.vars;

                  return Type.list([
                    Type.tuple([Type.atom("text"), Type.bitstring("rendered")]),
                  ]);
                },
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

  const renderedProp = (name) =>
    renderedVars.data[Type.encodeMapKey(Type.atom(name))][1];

  const taskRow = (id, title, done, projectId = null) => ({
    done: done,
    id: id,
    project_id: projectId,
    title: title,
    title_sort: title.toLowerCase(),
  });

  beforeEach(() => {
    renderedVars = null;

    globalThis.Hologram.sync = {
      model: {
        [PROJECT]: {
          attributes: {id: "uuid", name: "string"},
          relationships: {tasks: {toMany: true, type: TASK}},
          serverOnly: [],
          sortKeys: [],
        },
        [TASK]: {
          attributes: {done: "boolean", id: "uuid", title: "string"},
          relationships: {project: {toMany: false, type: PROJECT}},
          serverOnly: [],
          sortKeys: ["title"],
        },
      },
      propParams: {},
    };

    Model.reset();
    LocalDatabase.reset();
    LocalDatabase.actorUserId = null;

    LocalDatabase.putRow(TASK, taskRow("t1", "Buy milk", false));
    LocalDatabase.putRow(TASK, taskRow("t2", "Call Ann", true));
    LocalDatabase.putRow(TASK, taskRow("t3", "Draft memo", false));
  });

  it("injects a parameterized from_query prop bound to a like-named prop", () => {
    const capture = builder(1, (done) =>
      filter(
        Type.alias(TASK),
        Type.list([Type.tuple([Type.atom("done"), done])]),
      ),
    );

    defineComponent("MyApp.Parameterized", [
      propDefinition("done", []),
      queryProp("tasks", capture),
    ]);

    globalThis.Hologram.sync.propParams = {
      "MyApp.Parameterized": {tasks: ["done"]},
    };

    render(
      componentNode("MyApp.Parameterized", [
        Type.tuple([
          Type.bitstring("done"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
          ]),
        ]),
      ]),
    );

    const tasks = renderedProp("tasks");

    assert.equal(tasks.data.length, 1);

    assert.deepStrictEqual(
      tasks.data[0].data[Type.encodeMapKey(Type.atom("title"))][1],
      Type.bitstring("Call Ann"),
    );
  });

  it("injects a zero-arity from_query prop", () => {
    const capture = builder(0, () =>
      filter(
        Type.alias(TASK),
        Type.list([Type.tuple([Type.atom("done"), Type.boolean(false)])]),
      ),
    );

    defineComponent("MyApp.ZeroArity", [queryProp("tasks", capture)]);

    render(componentNode("MyApp.ZeroArity"));

    assert.equal(renderedProp("tasks").data.length, 2);
  });

  it("rejects template values for from_query props", () => {
    const capture = builder(0, () => Type.alias(TASK));

    defineComponent("MyApp.TemplatePassed", [queryProp("tasks", capture)]);

    render(
      componentNode("MyApp.TemplatePassed", [
        Type.tuple([
          Type.bitstring("tasks"),
          Type.keywordList([
            [Type.atom("expression"), Type.tuple([Type.atom("from_template")])],
          ]),
        ]),
      ]),
    );

    assert.equal(renderedProp("tasks").data.length, 3);
  });

  // The rows come back in the order the term names, which normalization gives a total one by
  // appending the id tiebreaker - the same order the server's executor returns.
  it("orders results the way the normalized term names", () => {
    const capture = builder(0, () =>
      orderBy(Type.alias(TASK), Type.atom("title")),
    );

    defineComponent("MyApp.Ordered", [queryProp("tasks", capture)]);

    render(componentNode("MyApp.Ordered"));

    const titles = renderedProp("tasks").data.map(
      (task) => task.data[Type.encodeMapKey(Type.atom("title"))][1].text,
    );

    assert.deepStrictEqual(titles, ["Buy milk", "Call Ann", "Draft memo"]);
  });

  it("injects a single-result from_query prop as one struct", () => {
    const capture = builder(0, () =>
      one(
        filter(
          Type.alias(TASK),
          Type.list([Type.tuple([Type.atom("id"), Type.bitstring("t2")])]),
        ),
      ),
    );

    defineComponent("MyApp.SingleResult", [queryProp("task", capture)]);

    render(componentNode("MyApp.SingleResult"));

    const task = renderedProp("task");

    assert.deepStrictEqual(
      task.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
      Type.alias(TASK),
    );
  });

  it("injects nil for a single-result from_query prop matching no row", () => {
    const capture = builder(0, () =>
      one(
        filter(
          Type.alias(TASK),
          Type.list([Type.tuple([Type.atom("id"), Type.bitstring("absent")])]),
        ),
      ),
    );

    defineComponent("MyApp.NoResult", [queryProp("task", capture)]);

    render(componentNode("MyApp.NoResult"));

    assert.deepStrictEqual(renderedProp("task"), Type.nil());
  });

  it("injects a counting from_query prop as an integer", () => {
    const capture = builder(0, () =>
      ManuallyPortedElixirHologramQuery["count/1"](Type.alias(TASK)),
    );

    defineComponent("MyApp.Counting", [queryProp("count", capture)]);

    render(componentNode("MyApp.Counting"));

    assert.deepStrictEqual(renderedProp("count"), Type.integer(3));
  });

  it("boxes the entities an included relationship embeds", () => {
    LocalDatabase.putRow(PROJECT, {id: "p1", name: "Board"});
    LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t3"]);

    const capture = builder(0, () =>
      include(Type.alias(PROJECT), Type.atom("tasks"), Type.nil()),
    );

    defineComponent("MyApp.Including", [queryProp("projects", capture)]);

    render(componentNode("MyApp.Including"));

    const project = renderedProp("projects").data[0];
    const tasks = project.data[Type.encodeMapKey(Type.atom("tasks"))][1];

    assert.equal(tasks.data.length, 2);

    assert.deepStrictEqual(
      tasks.data[0].data[Type.encodeMapKey(Type.atom("__struct__"))][1],
      Type.alias(TASK),
    );
  });

  // A relationship the query did not ask about is not one it found empty - which is what the
  // sentinel says, and what a read of it reports.
  it("leaves a relationship the query did not include unasked-for", () => {
    const capture = builder(0, () => Type.alias(TASK));

    defineComponent("MyApp.NotIncluding", [queryProp("tasks", capture)]);

    render(componentNode("MyApp.NotIncluding"));

    const task = renderedProp("tasks").data[0];
    const project = task.data[Type.encodeMapKey(Type.atom("project"))][1];

    assert.deepStrictEqual(
      project.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
      Type.alias("Hologram.Entity.NotIncluded"),
    );
  });

  it("binds the actor leaf to the acting user", () => {
    LocalDatabase.actorUserId = "t1";

    const capture = builder(0, () =>
      filter(
        Type.alias(TASK),
        Type.list([
          Type.tuple([
            Type.atom("id"),
            Type.tuple([Type.atom("=="), Type.atom("actor")]),
          ]),
        ]),
      ),
    );

    defineComponent("MyApp.ActorBound", [queryProp("tasks", capture)]);

    render(componentNode("MyApp.ActorBound"));

    assert.equal(renderedProp("tasks").data.length, 1);
  });

  it("raises when a like-named prop is missing", () => {
    const capture = builder(1, (done) =>
      filter(
        Type.alias(TASK),
        Type.list([Type.tuple([Type.atom("done"), done])]),
      ),
    );

    defineComponent("MyApp.MissingProp", [queryProp("tasks", capture)]);

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
    const capture = builder(1, (done) =>
      filter(
        Type.alias(TASK),
        Type.list([Type.tuple([Type.atom("done"), done])]),
      ),
    );

    defineComponent("MyApp.UnnamedPosition", [queryProp("tasks", capture)]);

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
    const capture = builder(1, (done) =>
      filter(
        Type.alias(TASK),
        Type.list([Type.tuple([Type.atom("done"), done])]),
      ),
    );

    defineComponent("MyApp.Unregistered", [queryProp("tasks", capture)]);

    assert.throw(
      () => render(componentNode("MyApp.Unregistered")),
      HologramBoxedError,
      "no registered params for from_query prop :tasks in MyApp.Unregistered - the query cache holds no entry for it",
    );
  });
});
