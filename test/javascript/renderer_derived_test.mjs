"use strict";

import {
  assert,
  assertBoxedError,
  contextFixture,
  defineRuntimeGlobals,
  setDataLayer,
  sinon,
} from "./support/helpers.mjs";

import Bitstring from "../../assets/js/bitstring.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import ManuallyPortedElixirHologramQueryStage from "../../assets/js/elixir/hologram/query/stage.mjs";
import Model from "../../assets/js/model.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import SyncStream from "../../assets/js/sync_stream.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors test/elixir/hologram/template/renderer_derived_test.exs and the compute cases of
// test/elixir/hologram/component/derived_test.exs. What differs is where a query's rows come from:
// the client answers from its own database.
describe("Renderer derived fields", () => {
  const ROW = "Hologram.Test.Fixtures.Entity.Module2";
  const CID = Type.bitstring("my_component");

  const context = Type.map();
  const defaultTarget = Type.bitstring("my_default_target");
  const parentTagName = "div";
  const slots = Type.keywordList();

  const count = ManuallyPortedElixirHologramQueryStage["count/1"];
  const filter = ManuallyPortedElixirHologramQueryStage["filter/2"];
  const include = ManuallyPortedElixirHologramQueryStage["include/2"];
  const one = ManuallyPortedElixirHologramQueryStage["one/1"];
  const sort = ManuallyPortedElixirHologramQueryStage["sort/2"];

  // What the template was rendered with, and what each module's template was rendered with.
  let renderedVars = null;
  let renderedVarsByModule = {};

  // What init was handed.
  let initStruct = null;

  // How many times a counting field's function ran.
  let computations = 0;

  // A function as transpiled app code, boxed the way a capture in __derived__/0 is.
  const fun = (arity, body) =>
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
            body(
              ...Array.from(
                {length: arity},
                (_item, index) => bodyContext.vars[`$${index + 1}`],
              ),
            ),
        },
      ],
      contextFixture(),
    );

  const derivedEntry = (name, type, args, body, readsState = false) =>
    Type.map([
      [Type.atom("args"), Type.list(args.map((arg) => Type.atom(arg)))],
      [Type.atom("function"), fun(args.length, body)],
      [Type.atom("name"), Type.atom(name)],
      [Type.atom("reads_state"), Type.boolean(readsState)],
      [Type.atom("type"), type],
    ]);

  const declaration = (name, opts = []) =>
    Type.tuple([Type.atom(name), Type.atom("any"), Type.keywordList(opts)]);

  const defineFunction = (moduleName, name, arity, body) =>
    Interpreter.defineElixirFunction(moduleName, name, arity, "public", [
      {
        params: (_context) =>
          Array.from({length: arity}, (_item, index) =>
            Type.variablePattern(`$${index + 1}`),
          ),
        guards: [],
        body: (bodyContext) =>
          body(
            ...Array.from(
              {length: arity},
              (_item, index) => bodyContext.vars[`$${index + 1}`],
            ),
          ),
      },
    ]);

  // queries names the derived fields the build registered as queries.
  const defineComponent = (
    moduleName,
    {derived = [], init = null, props = [], queries = [], state = []},
  ) => {
    globalThis.Hologram.sync.derivedQueries[moduleName] = queries;

    defineFunction(moduleName, "__derived__", 0, () => Type.list(derived));
    defineFunction(moduleName, "__props__", 0, () => Type.list(props));
    defineFunction(moduleName, "__state__", 0, () => Type.list(state));

    defineFunction(moduleName, "init", 2, (initProps, component) => {
      initStruct = component;

      return init ? init(initProps, component) : component;
    });

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
                  renderedVarsByModule[moduleName] = bodyContext.vars.vars;

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

  const propDom = (name, value) =>
    Type.tuple([
      Type.bitstring(name),
      Type.keywordList([[Type.atom("expression"), Type.tuple([value])]]),
    ]);

  const componentNode = (moduleName, propsDom = []) =>
    Type.tuple([
      Type.atom("component"),
      Type.alias(moduleName),
      Type.list(propsDom),
      Type.list(),
    ]);

  const statefulNode = (moduleName, propsDom = []) =>
    componentNode(moduleName, [propDom("cid", CID), ...propsDom]);

  const render = (node) =>
    Renderer.renderDom(node, context, slots, defaultTarget, parentTagName);

  const fieldOf = (term, name) => Erlang_Maps["get/2"](Type.atom(name), term);

  const renderedVar = (name) => fieldOf(renderedVars, name);

  const registeredDerived = () =>
    fieldOf(ComponentRegistry.getComponentStruct(CID), "derived");

  const putState = (component, key, value) =>
    Erlang_Maps["put/3"](
      Type.atom("state"),
      Erlang_Maps["put/3"](Type.atom(key), value, fieldOf(component, "state")),
      component,
    );

  const upcase = (term) => Type.bitstring(Bitstring.toText(term).toUpperCase());

  const concat = (left, right) =>
    Type.bitstring(Bitstring.toText(left) + Bitstring.toText(right));

  const rowNamed = (id, a, c) => ({
    a,
    b: null,
    c,
    c$sort: c,
    created_at: null,
    id,
    updated_at: null,
  });

  const ripeRows = () =>
    filter(
      Type.alias(ROW),
      Type.list([Type.tuple([Type.atom("a"), Type.boolean(true)])]),
    );

  const defineRipe = (moduleName) =>
    defineComponent(moduleName, {
      derived: [
        derivedEntry("ripe", Type.list([Type.alias(ROW)]), [], ripeRows),
      ],
      queries: ["ripe"],
    });

  const names = (rows) =>
    rows.data.map((row) => Bitstring.toText(fieldOf(row, "c")));

  beforeEach(() => {
    renderedVars = null;
    renderedVarsByModule = {};
    initStruct = null;
    computations = 0;
    setDataLayer();

    globalThis.Hologram.sync = {
      model: {
        [ROW]: {
          attributes: {
            a: "boolean",
            b: "integer",
            c: "string",
            created_at: "datetime",
            id: "uuid",
            updated_at: "datetime",
          },
          relationships: {},
          serverOnly: [],
        },
      },
      derivedQueries: {},
    };

    ComponentRegistry.clear();
    Model.reset();
    LocalDatabase.reset();
    LocalDatabase.actorUserId = null;
    GlobalRegistry.set("connectPageModule", null);
    SyncStream.rowsChangedSinceRender = false;

    LocalDatabase.putRow(ROW, rowNamed("r1", true, "banana"));
    LocalDatabase.putRow(ROW, rowNamed("r2", false, "apple"));
    LocalDatabase.putRow(ROW, rowNamed("r3", true, "cherry"));
  });

  afterEach(() => {
    ComponentRegistry.clear();
    Hologram.dataLayer = null;
    SyncStream.rowsChangedSinceRender = false;
    sinon.restore();
  });

  const rowStruct = (id) =>
    Type.struct(ROW, [[Type.atom("id"), Type.bitstring(id)]]);

  const computedValue = (moduleName, type, value) => {
    defineComponent(moduleName, {
      derived: [derivedEntry("value", type, [], () => value)],
    });

    render(componentNode(moduleName));

    return renderedVar("value");
  };

  describe("stateless component", () => {
    it("computes the fields from its props", () => {
      defineComponent("MyApp.Stateless", {
        derived: [
          derivedEntry("upper", Type.atom("string"), ["name"], upcase),
          derivedEntry("banner", Type.atom("string"), ["upper"], (upper) =>
            concat(concat(Type.bitstring("["), upper), Type.bitstring("]")),
          ),
        ],
        props: [declaration("name")],
      });

      render(
        componentNode("MyApp.Stateless", [
          propDom("name", Type.bitstring("ada")),
        ]),
      );

      assert.deepStrictEqual(renderedVar("banner"), Type.bitstring("[ADA]"));
    });

    it("computes a field from a prop the context set", () => {
      const contextKey = Type.tuple([
        Type.alias("MyApp.Themed"),
        Type.atom("theme"),
      ]);

      defineComponent("MyApp.Themed", {
        derived: [
          derivedEntry("label", Type.atom("string"), ["theme"], upcase),
        ],
        props: [
          declaration("theme", [[Type.atom("from_context"), contextKey]]),
        ],
      });

      Renderer.renderDom(
        componentNode("MyApp.Themed"),
        Type.map([[contextKey, Type.bitstring("dark")]]),
        slots,
        defaultTarget,
        parentTagName,
      );

      assert.deepStrictEqual(renderedVar("label"), Type.bitstring("DARK"));
    });

    it("raises on a field reading state", () => {
      defineComponent("MyApp.StatelessReadingState", {
        derived: [
          derivedEntry(
            "shout",
            Type.atom("string"),
            ["suffix"],
            (suffix) => suffix,
            true,
          ),
        ],
        state: [
          declaration("suffix", [[Type.atom("default"), Type.bitstring("!")]]),
        ],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.StatelessReadingState")),
        "Hologram.StateError",
        "derived field :shout in MyApp.StatelessReadingState reads state :suffix, which a component rendered without a cid doesn't have - give it a cid",
      );
    });
  });

  describe("stateful component", () => {
    it("hands init the fields reading only props", () => {
      defineComponent("MyApp.Greeting", {
        derived: [
          derivedEntry(
            "greeting",
            Type.atom("string"),
            ["first_name"],
            (firstName) => concat(Type.bitstring("Hi "), firstName),
          ),
        ],
        props: [declaration("first_name")],
      });

      render(
        statefulNode("MyApp.Greeting", [
          propDom("first_name", Type.bitstring("Ada")),
        ]),
      );

      assert.deepStrictEqual(
        fieldOf(initStruct, "derived"),
        Type.map([[Type.atom("greeting"), Type.bitstring("Hi Ada")]]),
      );
    });

    it("hands init a placeholder for a field reading state", () => {
      defineComponent("MyApp.Placeholder", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (step) => Type.integer(step.value * 2n),
            true,
          ),
        ],
        state: [declaration("step", [[Type.atom("default"), Type.integer(1)]])],
      });

      render(statefulNode("MyApp.Placeholder"));

      assert.deepStrictEqual(
        fieldOf(initStruct, "derived"),
        Type.map([
          [
            Type.atom("double"),
            Type.struct("Hologram.Component.NotComputed", [
              [Type.atom("field"), Type.atom("double")],
            ]),
          ],
        ]),
      );
    });

    it("computes a field reading state from the state init returned", () => {
      defineComponent("MyApp.Shout", {
        derived: [
          derivedEntry(
            "shout",
            Type.atom("string"),
            ["suffix"],
            (suffix) => concat(Type.bitstring("Hi"), suffix),
            true,
          ),
        ],
        init: (_props, component) =>
          putState(component, "suffix", Type.bitstring("!")),
        state: [
          declaration("suffix", [[Type.atom("default"), Type.bitstring("?")]]),
        ],
      });

      render(statefulNode("MyApp.Shout"));

      assert.deepStrictEqual(renderedVar("shout"), Type.bitstring("Hi!"));
    });

    it("computes a field reading state once on the first render", () => {
      defineComponent("MyApp.Counted", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (step) => {
              computations += 1;

              return Type.integer(step.value * 2n);
            },
            true,
          ),
        ],
        state: [declaration("step", [[Type.atom("default"), Type.integer(1)]])],
      });

      render(statefulNode("MyApp.Counted"));

      assert.equal(computations, 1);
    });

    it("holds the derived fields in the struct", () => {
      defineComponent("MyApp.Held", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (step) => Type.integer(step.value * 2n),
            true,
          ),
        ],
        state: [declaration("step", [[Type.atom("default"), Type.integer(3)]])],
      });

      render(statefulNode("MyApp.Held"));

      assert.deepStrictEqual(
        registeredDerived(),
        Type.map([[Type.atom("double"), Type.integer(6)]]),
      );
    });

    it("computes the fields again on a later render, from the state then", () => {
      defineComponent("MyApp.Rerendered", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (step) => Type.integer(step.value * 2n),
            true,
          ),
        ],
        state: [declaration("step", [[Type.atom("default"), Type.integer(1)]])],
      });

      render(statefulNode("MyApp.Rerendered"));

      ComponentRegistry.putComponentStruct(
        CID,
        putState(
          ComponentRegistry.getComponentStruct(CID),
          "step",
          Type.integer(5),
        ),
      );

      render(statefulNode("MyApp.Rerendered"));

      assert.deepStrictEqual(renderedVar("double"), Type.integer(10));
    });

    // What tells executeAction the render reached it, so that it reads the fields as computed.
    it("marks the fields current on a render, also for a component that declares none", () => {
      defineComponent("MyApp.Plain", {});

      render(statefulNode("MyApp.Plain"));

      ComponentRegistry.putComponentStruct(
        CID,
        ComponentRegistry.getComponentStruct(CID),
      );

      render(statefulNode("MyApp.Plain"));

      assert.isTrue(ComponentRegistry.isDerivedCurrent(CID));
    });

    it("raises when init stores a derived field before it is computed", () => {
      defineComponent("MyApp.Stored", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (step) => Type.integer(step.value * 2n),
            true,
          ),
        ],
        init: (_props, component) =>
          putState(
            component,
            "copy",
            fieldOf(fieldOf(component, "derived"), "double"),
          ),
        state: [
          declaration("copy"),
          declaration("step", [[Type.atom("default"), Type.integer(1)]]),
        ],
      });

      assertBoxedError(
        () => render(statefulNode("MyApp.Stored")),
        "Hologram.StateError",
        "init/2 of MyApp.Stored stored derived field :double in state :copy before it was computed - it reads state, so it's computed after init",
      );
    });
  });

  describe("query", () => {
    it("answers a field's query from the local database", () => {
      defineRipe("MyApp.Ripe");

      render(componentNode("MyApp.Ripe"));

      assert.deepStrictEqual(names(renderedVar("ripe")), ["banana", "cherry"]);
    });

    it("answers a field's query again after a row changes", () => {
      defineRipe("MyApp.RipeLater");

      render(componentNode("MyApp.RipeLater"));

      LocalDatabase.putRow(ROW, rowNamed("r2", true, "apple"));

      render(componentNode("MyApp.RipeLater"));

      assert.deepStrictEqual(names(renderedVar("ripe")), [
        "banana",
        "apple",
        "cherry",
      ]);
    });

    it("answers a count with the count the page carried under the field's name and arguments", () => {
      defineComponent("MyApp.CarriedCount", {
        queries: ["total"],
        derived: [
          derivedEntry("total", Type.atom("integer"), ["min_b"], (_minB) =>
            count(Type.alias(ROW)),
          ),
        ],
        props: [declaration("min_b")],
      });

      LocalDatabase.syncCounts = {"MyApp.CarriedCount/total/5": 42};

      render(
        componentNode("MyApp.CarriedCount", [
          propDom("min_b", Type.integer(5)),
        ]),
      );

      assert.deepStrictEqual(renderedVar("total"), Type.integer(42));
    });

    it("answers an entity type as a query of every row", () => {
      defineComponent("MyApp.EveryRow", {
        queries: ["rows"],
        derived: [
          derivedEntry("rows", Type.list([Type.alias(ROW)]), [], () =>
            Type.alias(ROW),
          ),
        ],
      });

      render(componentNode("MyApp.EveryRow"));

      assert.deepStrictEqual(names(renderedVar("rows")), [
        "banana",
        "apple",
        "cherry",
      ]);
    });

    it("answers a query of one row for a field declared as one row", () => {
      defineComponent("MyApp.FirstRow", {
        queries: ["first"],
        derived: [
          derivedEntry("first", Type.alias(ROW), [], () =>
            one(Type.alias(ROW)),
          ),
        ],
      });

      render(componentNode("MyApp.FirstRow"));

      assert.deepStrictEqual(
        fieldOf(renderedVar("first"), "__struct__"),
        Type.alias(ROW),
      );

      assert.deepStrictEqual(
        Bitstring.toText(fieldOf(renderedVar("first"), "c")),
        "banana",
      );
    });

    it("answers a stateful component's query again on a later render after a row changes", () => {
      defineRipe("MyApp.RipeStateful");

      render(statefulNode("MyApp.RipeStateful"));

      LocalDatabase.putRow(ROW, rowNamed("r2", true, "apple"));

      render(statefulNode("MyApp.RipeStateful"));

      assert.deepStrictEqual(names(renderedVar("ripe")), [
        "banana",
        "apple",
        "cherry",
      ]);
    });

    // The server spells the same key for the same rows (see "carries a count reading another
    // field's rows under those rows" in test/elixir/hologram/template/renderer_derived_test.exs).
    it("answers a count reading another field's rows with the count carried under those rows", () => {
      defineComponent("MyApp.RowsArgument", {
        queries: ["ripe", "ripe_total"],
        derived: [
          derivedEntry("ripe", Type.list([Type.alias(ROW)]), [], ripeRows),
          derivedEntry("ripe_total", Type.atom("integer"), ["ripe"], (_ripe) =>
            count(ripeRows()),
          ),
        ],
      });

      LocalDatabase.syncCounts = {
        [`MyApp.RowsArgument/ripe_total/[${ROW}#r1, ${ROW}#r3]`]: 42,
      };

      render(componentNode("MyApp.RowsArgument"));

      assert.deepStrictEqual(renderedVar("ripe_total"), Type.integer(42));
    });

    it("raises on a query result of a field the build didn't register as a query", () => {
      defineComponent("MyApp.UnregisteredDerivedQuery", {
        derived: [
          derivedEntry("ripe", Type.list([Type.alias(ROW)]), [], ripeRows),
        ],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.UnregisteredDerivedQuery")),
        "Hologram.MisuseError",
        "derived field :ripe in MyApp.UnregisteredDerivedQuery returned a query the build didn't register - a query is built in the derived field's own function or the builders it calls, not passed in as data",
      );
    });

    it("raises on a query of another shape than the type", () => {
      defineComponent("MyApp.WrongShape", {
        queries: ["total"],
        derived: [derivedEntry("total", Type.atom("integer"), [], ripeRows)],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.WrongShape")),
        "Hologram.MisuseError",
        "derived field :total in MyApp.WrongShape is declared :integer, but its query is a set of Hologram.Test.Fixtures.Entity.Module2 rows",
      );
    });

    it("answers a query built from a prop the field reads", () => {
      defineComponent("MyApp.DerivedWanted", {
        queries: ["rows"],
        derived: [
          derivedEntry(
            "rows",
            Type.list([Type.alias(ROW)]),
            ["wanted"],
            (wanted) =>
              filter(
                Type.alias(ROW),
                Type.list([Type.tuple([Type.atom("a"), wanted])]),
              ),
          ),
        ],
        props: [declaration("wanted")],
      });

      render(
        componentNode("MyApp.DerivedWanted", [
          propDom("wanted", Type.boolean(false)),
        ]),
      );

      assert.deepStrictEqual(names(renderedVar("rows")), ["apple"]);
    });

    it("computes a field over a value the template passes under its name", () => {
      defineRipe("MyApp.DerivedTemplatePassed");

      render(
        componentNode("MyApp.DerivedTemplatePassed", [
          propDom("ripe", Type.atom("from_template")),
        ]),
      );

      assert.deepStrictEqual(names(renderedVar("ripe")), ["banana", "cherry"]);
    });

    // The rows come back in the order the term names, which normalization gives a total one by
    // appending the id tiebreaker - the same order the server's executor returns.
    it("answers the rows in the order the normalized term names", () => {
      defineComponent("MyApp.DerivedSorted", {
        queries: ["rows"],
        derived: [
          derivedEntry("rows", Type.list([Type.alias(ROW)]), [], () =>
            sort(Type.alias(ROW), Type.atom("c")),
          ),
        ],
      });

      render(componentNode("MyApp.DerivedSorted"));

      assert.deepStrictEqual(names(renderedVar("rows")), [
        "apple",
        "banana",
        "cherry",
      ]);
    });

    it("answers nil for a query of one row matching no row", () => {
      defineComponent("MyApp.DerivedNoRow", {
        queries: ["row"],
        derived: [
          derivedEntry("row", Type.alias(ROW), [], () =>
            one(
              filter(
                Type.alias(ROW),
                Type.list([
                  Type.tuple([Type.atom("id"), Type.bitstring("absent")]),
                ]),
              ),
            ),
          ),
        ],
      });

      render(componentNode("MyApp.DerivedNoRow"));

      assert.deepStrictEqual(renderedVar("row"), Type.nil());
    });

    it("binds the actor leaf to the acting user", () => {
      LocalDatabase.actorUserId = "r1";

      defineComponent("MyApp.DerivedActorBound", {
        queries: ["rows"],
        derived: [
          derivedEntry("rows", Type.list([Type.alias(ROW)]), [], () =>
            filter(
              Type.alias(ROW),
              Type.list([
                Type.tuple([
                  Type.atom("id"),
                  Type.tuple([
                    Type.atom("=="),
                    Type.tuple([Type.atom("actor")]),
                  ]),
                ]),
              ]),
            ),
          ),
        ],
      });

      render(componentNode("MyApp.DerivedActorBound"));

      assert.deepStrictEqual(names(renderedVar("rows")), ["banana"]);
    });

    // A count has no rows behind it, so carried rows cannot re-derive one - the number the render
    // answered with is held until this client can count for itself.
    describe("a count the page carried", () => {
      const defineCounting = (moduleName) =>
        defineComponent(moduleName, {
          queries: ["total"],
          derived: [
            derivedEntry("total", Type.atom("integer"), ["wanted"], (wanted) =>
              count(
                filter(
                  Type.alias(ROW),
                  Type.list([Type.tuple([Type.atom("a"), wanted])]),
                ),
              ),
            ),
          ],
          props: [declaration("wanted")],
        });

      const renderCounting = (moduleName) =>
        render(
          componentNode(moduleName, [propDom("wanted", Type.boolean(false))]),
        );

      it("counts locally once the whole pot is complete", () => {
        defineCounting("MyApp.DerivedComplete");

        LocalDatabase.syncCounts = {"MyApp.DerivedComplete/total/false": 42};
        LocalDatabase.markSynced("all");

        renderCounting("MyApp.DerivedComplete");

        assert.deepStrictEqual(renderedVar("total"), Type.integer(1));
      });

      // The page scope covers the page this client connected on, and nothing else - a component
      // on any other page is only promised its rows at "all".
      it("counts locally at the page marker on the page it connected with", () => {
        defineCounting("MyApp.DerivedConnectPage");

        GlobalRegistry.set("connectPageModule", "MyApp.DerivedConnectPage");
        LocalDatabase.syncCounts = {"MyApp.DerivedConnectPage/total/false": 42};
        LocalDatabase.markSynced("page");

        renderCounting("MyApp.DerivedConnectPage");

        assert.deepStrictEqual(renderedVar("total"), Type.integer(1));
      });

      it("keeps carrying at the page marker for a page reached since", () => {
        defineCounting("MyApp.DerivedNavigatedTo");

        GlobalRegistry.set("connectPageModule", "MyApp.SomeOtherPage");
        LocalDatabase.syncCounts = {"MyApp.DerivedNavigatedTo/total/false": 42};
        LocalDatabase.markSynced("page");

        renderCounting("MyApp.DerivedNavigatedTo");

        assert.deepStrictEqual(renderedVar("total"), Type.integer(42));
      });

      // Two instances of one component answer two counts, and the arguments their fields were
      // computed from are what tell them apart.
      it("reads the count of the instance that asked", () => {
        defineCounting("MyApp.DerivedTwoInstances");

        LocalDatabase.syncCounts = {
          "MyApp.DerivedTwoInstances/total/false": 42,
          "MyApp.DerivedTwoInstances/total/true": 7,
        };

        renderCounting("MyApp.DerivedTwoInstances");

        assert.deepStrictEqual(renderedVar("total"), Type.integer(42));
      });

      // Nothing carried is not zero carried: a count the page never answered is one this client
      // has to work out for itself, however incomplete its answer.
      it("counts locally when the page carried nothing for it", () => {
        defineCounting("MyApp.DerivedNothingCarried");

        renderCounting("MyApp.DerivedNothingCarried");

        assert.deepStrictEqual(renderedVar("total"), Type.integer(1));
      });

      // Two arguments are two values, not their concatenation: 1 and 23 must not read the key
      // 12 and 3 wrote.
      it("separates the arguments of a field reading two fields", () => {
        defineComponent("MyApp.DerivedTwoArgs", {
          queries: ["total"],
          derived: [
            derivedEntry(
              "total",
              Type.atom("integer"),
              ["from", "to"],
              (_from, _to) => count(Type.alias(ROW)),
            ),
          ],
          props: [declaration("from"), declaration("to")],
        });

        LocalDatabase.syncCounts = {
          "MyApp.DerivedTwoArgs/total/1,23": 42,
          "MyApp.DerivedTwoArgs/total/123": 7,
        };

        render(
          componentNode("MyApp.DerivedTwoArgs", [
            propDom("from", Type.integer(1)),
            propDom("to", Type.integer(23)),
          ]),
        );

        assert.deepStrictEqual(renderedVar("total"), Type.integer(42));
      });

      it("leaves a field holding rows alone", () => {
        defineRipe("MyApp.DerivedNotCounting");

        LocalDatabase.syncCounts = {"MyApp.DerivedNotCounting/ripe/": 42};

        render(componentNode("MyApp.DerivedNotCounting"));

        assert.deepStrictEqual(names(renderedVar("ripe")), [
          "banana",
          "cherry",
        ]);
      });
    });

    describe("includes", () => {
      const PROJECT = "MyApp.DerivedProject";
      const TASK = "MyApp.DerivedTask";

      beforeEach(() => {
        globalThis.Hologram.sync.model[PROJECT] = {
          attributes: {id: "uuid", name: "string"},
          relationships: {tasks: {toMany: true, type: TASK}},
          serverOnly: [],
        };

        globalThis.Hologram.sync.model[TASK] = {
          attributes: {done: "boolean", id: "uuid", title: "string"},
          relationships: {project: {toMany: false, type: PROJECT}},
          serverOnly: [],
        };

        Model.reset();

        LocalDatabase.putRow(TASK, {
          done: false,
          id: "t1",
          project_id: null,
          title: "Buy milk",
          title$sort: "buy milk",
        });

        LocalDatabase.putRow(TASK, {
          done: true,
          id: "t2",
          project_id: null,
          title: "Call Ann",
          title$sort: "call ann",
        });

        LocalDatabase.putRow(TASK, {
          done: false,
          id: "t3",
          project_id: null,
          title: "Draft memo",
          title$sort: "draft memo",
        });
      });

      it("boxes the entities an included relationship embeds", () => {
        LocalDatabase.putRow(PROJECT, {id: "p1", name: "Board"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t3"]);

        defineComponent("MyApp.DerivedIncluding", {
          queries: ["projects"],
          derived: [
            derivedEntry("projects", Type.list([Type.alias(PROJECT)]), [], () =>
              include(Type.alias(PROJECT), Type.atom("tasks")),
            ),
          ],
        });

        render(componentNode("MyApp.DerivedIncluding"));

        const tasks = fieldOf(renderedVar("projects").data[0], "tasks");

        assert.equal(tasks.data.length, 2);

        assert.deepStrictEqual(
          fieldOf(tasks.data[0], "__struct__"),
          Type.alias(TASK),
        );
      });

      // A relationship the query did not ask about is not one it found empty - which is what the
      // sentinel says, and what a read of it reports.
      it("leaves a relationship the query did not include unasked-for", () => {
        defineComponent("MyApp.DerivedNotIncluding", {
          queries: ["tasks"],
          derived: [
            derivedEntry("tasks", Type.list([Type.alias(TASK)]), [], () =>
              Type.alias(TASK),
            ),
          ],
        });

        render(componentNode("MyApp.DerivedNotIncluding"));

        const project = fieldOf(renderedVar("tasks").data[0], "project");

        assert.deepStrictEqual(
          fieldOf(project, "__struct__"),
          Type.alias("Hologram.Entity.NotIncluded"),
        );
      });
    });
  });

  describe("checks", () => {
    it("raises on a value of another type", () => {
      defineComponent("MyApp.WrongType", {
        derived: [
          derivedEntry("label", Type.atom("string"), [], () => Type.integer(3)),
        ],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.WrongType")),
        "Hologram.MisuseError",
        "derived field :label in MyApp.WrongType is declared :string, but computed 3",
      );
    });

    it("takes nil for any type", () => {
      defineComponent("MyApp.Nil", {
        derived: [
          derivedEntry("label", Type.atom("string"), [], () => Type.nil()),
        ],
      });

      render(componentNode("MyApp.Nil"));

      assert.deepStrictEqual(renderedVar("label"), Type.nil());
    });

    it("takes an integer for a float", () => {
      defineComponent("MyApp.Ratio", {
        derived: [
          derivedEntry("ratio", Type.atom("float"), [], () => Type.integer(1)),
        ],
      });

      render(componentNode("MyApp.Ratio"));

      assert.deepStrictEqual(renderedVar("ratio"), Type.integer(1));
    });

    it("takes anything for a list type of what is no entity type", () => {
      defineComponent("MyApp.Tags", {
        derived: [
          derivedEntry("tags", Type.list([Type.atom("string")]), [], () =>
            Type.list([Type.integer(1)]),
          ),
        ],
      });

      render(componentNode("MyApp.Tags"));

      assert.deepStrictEqual(renderedVar("tags"), Type.list([Type.integer(1)]));
    });

    it("takes a value of each type with a test of its own", () => {
      assert.deepStrictEqual(
        [
          computedValue("MyApp.Atom", Type.atom("atom"), Type.atom("a")),
          computedValue(
            "MyApp.Boolean",
            Type.atom("boolean"),
            Type.boolean(true),
          ),
          computedValue(
            "MyApp.List",
            Type.atom("list"),
            Type.list([Type.integer(1)]),
          ),
          computedValue("MyApp.Map", Type.atom("map"), Type.map()),
          computedValue("MyApp.Row", Type.alias(ROW), rowStruct("a")),
          computedValue(
            "MyApp.Rows",
            Type.list([Type.alias(ROW)]),
            Type.list([rowStruct("a")]),
          ),
        ],
        [
          Type.atom("a"),
          Type.boolean(true),
          Type.list([Type.integer(1)]),
          Type.map(),
          rowStruct("a"),
          Type.list([rowStruct("a")]),
        ],
      );
    });

    it("takes anything for a module type that is no entity type", () => {
      assert.deepStrictEqual(
        computedValue(
          "MyApp.ModuleType",
          Type.alias("MyApp.Other"),
          Type.integer(1),
        ),
        Type.integer(1),
      );
    });

    it("takes anything for a type that is no atom", () => {
      assert.deepStrictEqual(
        computedValue(
          "MyApp.TupleType",
          Type.tuple([Type.atom("a")]),
          Type.integer(1),
        ),
        Type.integer(1),
      );
    });

    it("raises on a value that is no row of the entity type declared", () => {
      defineComponent("MyApp.NoRow", {
        derived: [
          derivedEntry("row", Type.alias(ROW), [], () => Type.integer(1)),
        ],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.NoRow")),
        "Hologram.MisuseError",
        "derived field :row in MyApp.NoRow is declared Hologram.Test.Fixtures.Entity.Module2, but computed 1",
      );
    });

    it("raises on a set holding what is no row of the entity type declared", () => {
      defineComponent("MyApp.NoRows", {
        derived: [
          derivedEntry("rows", Type.list([Type.alias(ROW)]), [], () =>
            Type.list([Type.integer(1)]),
          ),
        ],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.NoRows")),
        "Hologram.MisuseError",
        "derived field :rows in MyApp.NoRows is declared [Hologram.Test.Fixtures.Entity.Module2], but computed [1]",
      );
    });

    it("raises on a prop from a context that doesn't hold it", () => {
      const contextKey = Type.tuple([
        Type.alias("MyApp.NoTheme"),
        Type.atom("theme"),
      ]);

      defineComponent("MyApp.NoTheme", {
        derived: [
          derivedEntry(
            "label",
            Type.atom("string"),
            ["theme"],
            (theme) => theme,
          ),
        ],
        props: [
          declaration("theme", [[Type.atom("from_context"), contextKey]]),
        ],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.NoTheme")),
        "Hologram.MisuseError",
        "derived field :label in MyApp.NoTheme reads :theme, which is not set - the context has no such key",
      );
    });

    it("raises when init stores two derived fields before they are computed, naming the smallest key", () => {
      defineComponent("MyApp.StoredTwice", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (step) => step,
            true,
          ),
          derivedEntry(
            "triple",
            Type.atom("integer"),
            ["step"],
            (step) => step,
            true,
          ),
        ],
        init: (_props, component) => {
          const derived = fieldOf(component, "derived");

          return putState(
            putState(component, "copy_b", fieldOf(derived, "double")),
            "copy_a",
            fieldOf(derived, "triple"),
          );
        },
        state: [
          declaration("copy_a"),
          declaration("copy_b"),
          declaration("step", [[Type.atom("default"), Type.integer(1)]]),
        ],
      });

      assertBoxedError(
        () => render(statefulNode("MyApp.StoredTwice")),
        "Hologram.StateError",
        "init/2 of MyApp.StoredTwice stored derived field :triple in state :copy_a before it was computed - it reads state, so it's computed after init",
      );
    });

    it("raises on a prop that is not set", () => {
      defineComponent("MyApp.Unset", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["count"],
            (value) => value,
          ),
        ],
        props: [declaration("count")],
      });

      assertBoxedError(
        () => render(componentNode("MyApp.Unset")),
        "Hologram.MisuseError",
        "derived field :double in MyApp.Unset reads :count, which is not set - give it a default or pass it",
      );
    });

    it("raises on a state entry that is not set", () => {
      defineComponent("MyApp.UnsetState", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (value) => value,
            true,
          ),
        ],
        state: [declaration("step")],
      });

      assertBoxedError(
        () => render(statefulNode("MyApp.UnsetState")),
        "Hologram.MisuseError",
        "derived field :double in MyApp.UnsetState reads :step, which is not set - give it a default or set it in init/2",
      );
    });
  });

  describe("page", () => {
    const definePage = () => {
      defineComponent("MyApp.Page", {
        derived: [
          derivedEntry(
            "label",
            Type.atom("string"),
            ["name", "suffix"],
            (name, suffix) => concat(name, suffix),
            true,
          ),
        ],
        state: [
          declaration("suffix", [[Type.atom("default"), Type.bitstring("!")]]),
        ],
      });

      defineFunction("MyApp.Page", "__layout_module__", 0, () =>
        Type.alias("MyApp.Layout"),
      );
      defineFunction("MyApp.Page", "__layout_props__", 0, () => Type.list());
      defineFunction("MyApp.Page", "__params__", 0, () =>
        Type.list([declaration("name")]),
      );

      defineComponent("MyApp.Layout", {props: [declaration("label")]});

      ComponentRegistry.putEntry(
        Type.bitstring("page"),
        Type.map([
          [Type.atom("module"), Type.alias("MyApp.Page")],
          [
            Type.atom("struct"),
            Type.componentStruct({
              state: Type.map([[Type.atom("suffix"), Type.bitstring("!")]]),
            }),
          ],
        ]),
      );
    };

    it("computes the fields from its params and state", () => {
      definePage();

      Renderer.renderPage(
        Type.alias("MyApp.Page"),
        Type.map([[Type.atom("name"), Type.bitstring("ada")]]),
      );

      assert.deepStrictEqual(
        fieldOf(renderedVarsByModule["MyApp.Page"], "label"),
        Type.bitstring("ada!"),
      );
    });

    it("hands the fields to the layout as props", () => {
      definePage();

      Renderer.renderPage(
        Type.alias("MyApp.Page"),
        Type.map([[Type.atom("name"), Type.bitstring("ada")]]),
      );

      assert.deepStrictEqual(
        fieldOf(renderedVarsByModule["MyApp.Layout"], "label"),
        Type.bitstring("ada!"),
      );
    });

    it("raises on a param that is not set", () => {
      definePage();

      assertBoxedError(
        () => Renderer.renderPage(Type.alias("MyApp.Page"), Type.map()),
        "Hologram.MisuseError",
        "derived field :label in MyApp.Page reads :name, which is not set - pass it as a param of the page",
      );
    });

    it("marks the page's fields current", () => {
      definePage();

      Renderer.renderPage(
        Type.alias("MyApp.Page"),
        Type.map([[Type.atom("name"), Type.bitstring("ada")]]),
      );

      assert.isTrue(ComponentRegistry.isDerivedCurrent(Type.bitstring("page")));
    });

    it("leaves a component the render didn't reach not current", () => {
      definePage();
      defineComponent("MyApp.OffPage", {});

      render(statefulNode("MyApp.OffPage"));

      Renderer.renderPage(
        Type.alias("MyApp.Page"),
        Type.map([[Type.atom("name"), Type.bitstring("ada")]]),
      );

      assert.isFalse(ComponentRegistry.isDerivedCurrent(CID));
    });

    it("holds the fields in the page struct", () => {
      definePage();

      Renderer.renderPage(
        Type.alias("MyApp.Page"),
        Type.map([[Type.atom("name"), Type.bitstring("ada")]]),
      );

      assert.deepStrictEqual(
        fieldOf(
          ComponentRegistry.getComponentStruct(Type.bitstring("page")),
          "derived",
        ),
        Type.map([[Type.atom("label"), Type.bitstring("ada!")]]),
      );
    });
  });

  describe("an action", () => {
    const action = Type.actionStruct({
      name: Type.atom("pick"),
      params: Type.map(),
      target: CID,
    });

    // A page the component isn't on, so its render doesn't reach the component.
    const renderOtherPage = () => {
      defineComponent("MyApp.OtherPage", {});

      defineFunction("MyApp.OtherPage", "__layout_module__", 0, () =>
        Type.alias("MyApp.OtherLayout"),
      );
      defineFunction("MyApp.OtherPage", "__layout_props__", 0, () =>
        Type.list(),
      );
      defineFunction("MyApp.OtherPage", "__params__", 0, () => Type.list());

      defineComponent("MyApp.OtherLayout", {});

      ComponentRegistry.putEntry(
        Type.bitstring("page"),
        Type.map([
          [Type.atom("module"), Type.alias("MyApp.OtherPage")],
          [Type.atom("struct"), Type.componentStruct()],
        ]),
      );

      Renderer.renderPage(Type.alias("MyApp.OtherPage"), Type.map());
    };

    // The registry keeps a component that left the page, and a delayed action can still reach it.
    it("is handed the derived fields computed from its state when no render reached it since its last action", () => {
      defineComponent("MyApp.Doubled", {
        derived: [
          derivedEntry(
            "double",
            Type.atom("integer"),
            ["step"],
            (step) => Type.integer(step.value * 2n),
            true,
          ),
        ],
        state: [declaration("step", [[Type.atom("default"), Type.integer(1)]])],
      });

      render(statefulNode("MyApp.Doubled"));

      let actionStruct = null;

      sinon
        .stub(Interpreter, "callNamedFunction")
        .callsFake((_module, _fun, args) => {
          actionStruct = args.data[2];

          return putState(actionStruct, "step", Type.integer(5));
        });

      sinon.stub(Hologram, "render").callsFake(() => null);

      Hologram.executeAction(action);
      Hologram.executeAction(action);

      assert.deepStrictEqual(
        fieldOf(fieldOf(actionStruct, "derived"), "double"),
        Type.integer(10),
      );
    });

    it("is handed the derived fields as the rows stand when a row changed before a render that didn't reach it", () => {
      defineRipe("MyApp.RipeOffPage");

      render(statefulNode("MyApp.RipeOffPage"));

      LocalDatabase.putRow(ROW, rowNamed("r2", true, "apple"));

      renderOtherPage();

      // The render took in the row change.
      SyncStream.rowsChangedSinceRender = false;

      let actionStruct = null;

      sinon
        .stub(Interpreter, "callNamedFunction")
        .callsFake((_module, _fun, args) => {
          actionStruct = args.data[2];

          return actionStruct;
        });

      sinon.stub(Hologram, "render").callsFake(() => null);

      Hologram.executeAction(action);

      assert.deepStrictEqual(
        names(fieldOf(fieldOf(actionStruct, "derived"), "ripe")),
        ["banana", "apple", "cherry"],
      );
    });

    it("is handed the derived fields as the rows stand when a frame changed them since the last render", () => {
      defineRipe("MyApp.RipeAction");

      render(statefulNode("MyApp.RipeAction"));

      LocalDatabase.putRow(ROW, rowNamed("r2", true, "apple"));
      SyncStream.rowsChangedSinceRender = true;

      let actionStruct = null;

      sinon
        .stub(Interpreter, "callNamedFunction")
        .callsFake((_module, _fun, args) => {
          actionStruct = args.data[2];

          return actionStruct;
        });

      sinon.stub(Hologram, "render").callsFake(() => null);

      Hologram.executeAction(
        Type.actionStruct({
          name: Type.atom("pick"),
          params: Type.map(),
          target: CID,
        }),
      );

      assert.deepStrictEqual(
        names(fieldOf(fieldOf(actionStruct, "derived"), "ripe")),
        ["banana", "apple", "cherry"],
      );
    });
  });

  describe("refreshDerived()", () => {
    it("computes the target's fields again from the rows as they stand", () => {
      defineComponent("MyApp.Refreshed", {
        queries: ["ripe"],
        derived: [
          derivedEntry("ripe", Type.list([Type.alias(ROW)]), [], ripeRows),
        ],
      });

      render(statefulNode("MyApp.Refreshed"));

      LocalDatabase.putRow(ROW, rowNamed("r2", true, "apple"));

      Renderer.refreshDerived(CID);

      assert.deepStrictEqual(names(fieldOf(registeredDerived(), "ripe")), [
        "banana",
        "apple",
        "cherry",
      ]);
    });
  });
});
