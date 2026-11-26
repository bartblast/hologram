"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Model from "../../assets/js/model.mjs";
import QueryCheck from "../../assets/js/query_check.mjs";
import derivedModel from "./support/fixtures/derived_model.mjs";

defineRuntimeGlobals();

// Mirrors the server_only_refusal/1 cases of
// test/elixir/hologram/component/derived/query_check_test.exs.
describe("QueryCheck", () => {
  const DEAD = "MyApp.Dead";
  const OWNER = "MyApp.Owner";
  const SECRET = "MyApp.Secret";

  const SERVER_ONLY_TAIL =
    " - the client never holds those values, so it could not evaluate the reference locally. Drop the reference, or read the rows through the trusted backend API.";

  const entry = (overrides) => ({
    attributes: {id: "id", label: "string", token: "string"},
    derived: {},
    inverses: {},
    policy: {read: [{predicates: [], to: null, via: null}]},
    relationships: {},
    serverOnly: [],
    ...overrides,
  });

  const term = (entity, overrides = {}) => ({
    cardinality: "set",
    entity,
    filter: [],
    include: {},
    skip: null,
    sort: [],
    take: null,
    ...overrides,
  });

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [DEAD]: entry({policy: {}}),
        [OWNER]: entry({
          derived: {secretSet: {kind: "set", entity: SECRET}},
          inverses: {ownedSecrets: {type: SECRET}},
          relationships: {
            secret: {kind: "to_one", type: SECRET},
            secrets: {kind: "to_many", type: SECRET},
          },
        }),
        [SECRET]: entry({
          relationships: {owner: {kind: "to_one", type: OWNER}},
          serverOnly: ["token"],
        }),
      },
    };

    Model.reset();
  });

  afterEach(() => {
    Model.reset();
  });

  describe("unsyncedRefusal()", () => {
    const LONELY = "MyApp.Lonely";

    const syncing = (...types) => {
      globalThis.Hologram.sync.syncedTypes = types;
    };

    const tail = (types) =>
      `reads ${types.join(", ")}, which browser code never names, so sync never sends ${types.length === 1 ? "its rows" : "their rows"} - name the entity type, or the relationship or derived field leading to it, as written in browser code, like include(project) or %Project{}`;

    beforeEach(() => {
      globalThis.Hologram.sync.model[LONELY] = entry({});

      globalThis.Hologram.sync.model[OWNER].derived = {
        ...globalThis.Hologram.sync.model[OWNER].derived,
        secretLabel: {
          definition: {name: ["secret", "label"]},
          kind: "scalar",
        },
        lonelyCount: {
          definition: {
            query: {
              ...term(LONELY, {cardinality: "count"}),
              source: {chain: ["lonelies"], owner: OWNER},
            },
          },
          kind: "scalar",
        },
      };

      globalThis.Hologram.sync.model[OWNER].relationships.lonelies = {
        kind: "to_many",
        type: LONELY,
      };

      Model.reset();
    });

    it("checks nothing for a bundle without the list of synced types", () => {
      assert.isNull(QueryCheck.unsyncedRefusal(term(DEAD)));
    });

    it("passes a query reading only synced types", () => {
      syncing(OWNER, SECRET);

      const query = term(OWNER, {
        filter: [[["secret", "token"], "==", "x"]],
        include: {secrets: term(SECRET)},
      });

      assert.isNull(QueryCheck.unsyncedRefusal(query));
    });

    it("refuses a query on a type sync doesn't send", () => {
      syncing(OWNER);

      assert.strictEqual(
        QueryCheck.unsyncedRefusal(term(SECRET)),
        tail([SECRET]),
      );
    });

    it("refuses a type a query includes", () => {
      syncing(OWNER);

      const query = term(OWNER, {include: {secrets: term(SECRET)}});

      assert.strictEqual(QueryCheck.unsyncedRefusal(query), tail([SECRET]));
    });

    it("refuses a type a path goes through", () => {
      syncing(OWNER);

      const query = term(OWNER, {filter: [[["secret", "label"], "==", "x"]]});

      assert.strictEqual(QueryCheck.unsyncedRefusal(query), tail([SECRET]));
    });

    it("refuses a type a quantifier's set goes through", () => {
      syncing(OWNER);

      const filter = [{quantifier: "any", source: ["secrets"], filter: []}];

      assert.strictEqual(
        QueryCheck.unsyncedRefusal(term(OWNER, {filter})),
        tail([SECRET]),
      );
    });

    it("refuses the rows of a derived set a quantifier reads", () => {
      syncing(OWNER);

      const filter = [{quantifier: "any", source: ["secretSet"], filter: []}];

      assert.strictEqual(
        QueryCheck.unsyncedRefusal(term(OWNER, {filter})),
        tail([SECRET]),
      );
    });

    it("refuses a type a derived field the query filters on reads", () => {
      syncing(OWNER);

      const query = term(OWNER, {filter: [["secretLabel", "==", "x"]]});

      assert.strictEqual(QueryCheck.unsyncedRefusal(query), tail([SECRET]));
    });

    it("refuses the types a derived field the query includes reads, sorted", () => {
      syncing(OWNER);

      const query = term(OWNER, {
        include: {lonelyCount: null, secretLabel: null},
      });

      assert.strictEqual(
        QueryCheck.unsyncedRefusal(query),
        tail([LONELY, SECRET]),
      );
    });

    it("refuses a type a derived field the query sorts on reads", () => {
      syncing(OWNER, SECRET);

      const query = term(OWNER, {sort: [["lonelyCount", "asc"]]});

      assert.strictEqual(QueryCheck.unsyncedRefusal(query), tail([LONELY]));
    });
  });

  // The types the server lists for the same terms over the same fixtures
  // (Hologram.Query.Window.entity_types/1), named as the derived model fixture names them.
  describe("unsyncedRefusal() over the build's derived fields", () => {
    const readTypes = (query) => {
      const refusal = QueryCheck.unsyncedRefusal(query);

      return refusal.match(/^reads (.+?), which/)[1].split(", ");
    };

    beforeEach(() => {
      globalThis.Hologram.sync = {model: derivedModel, syncedTypes: []};
      Model.reset();
    });

    it("reads what a derived field naming its own row one level out reads", () => {
      const query = term("MyApp.Message", {
        filter: [["later_count", ">", 1]],
      });

      assert.deepStrictEqual(readTypes(query), [
        "MyApp.Channel",
        "MyApp.Message",
      ]);
    });

    it("reads what an included derived field's source leads to", () => {
      const query = term("MyApp.Room", {include: {unread_count: null}});

      assert.deepStrictEqual(readTypes(query), ["MyApp.Post", "MyApp.Room"]);
    });

    it("reads what a derived field naming its own row two levels out reads", () => {
      const query = term("MyApp.Team", {sort: [["named_tag_count", "asc"]]});

      assert.deepStrictEqual(readTypes(query), [
        "MyApp.Note",
        "MyApp.Tag",
        "MyApp.Team",
      ]);
    });

    it("reads what a derived field's branches read, through another derived field", () => {
      const query = term("MyApp.Member", {filter: [["level", "==", "busy"]]});

      assert.deepStrictEqual(readTypes(query), [
        "MyApp.Channel",
        "MyApp.Member",
        "MyApp.Message",
      ]);
    });

    it("reads what a concatenation's parts read", () => {
      const query = term("MyApp.Member", {include: {display_name: null}});

      assert.deepStrictEqual(readTypes(query), [
        "MyApp.Channel",
        "MyApp.Member",
      ]);
    });

    it("reads what a condition's comparison with another row reads", () => {
      const query = term("MyApp.Member", {
        filter: [["named_after_channel", "==", true]],
      });

      assert.deepStrictEqual(readTypes(query), [
        "MyApp.Channel",
        "MyApp.Member",
      ]);
    });

    it("tells a type the bundle's model doesn't hold as unsynced", () => {
      const query = term("MyApp.Nope", {filter: [["x", "==", 1]]});

      assert.deepStrictEqual(readTypes(query), ["MyApp.Nope"]);
    });
  });

  describe("refusal()", () => {
    it("passes a query naming no server-only attribute", () => {
      assert.isNull(
        QueryCheck.refusal(term(SECRET, {filter: [["label", "==", "x"]]})),
      );
    });

    // The server refuses it on its render: a deploy changing only the rules can leave an open
    // tab's type with none, and that tab answers from the rows it holds rather than failing.
    it("passes a query reading a type no rule lets anyone read", () => {
      assert.isNull(QueryCheck.refusal(term(DEAD)));
    });

    it("refuses a filter on a server-only attribute", () => {
      assert.strictEqual(
        QueryCheck.refusal(term(SECRET, {filter: [["token", "==", "x"]]})),
        `filters or sorts on server_only attributes (MyApp.Secret :token)${SERVER_ONLY_TAIL}`,
      );
    });

    it("refuses a server-only attribute inside a disjunction", () => {
      const filter = [
        {or: [[["token", "==", "x"]], [["label", "==", "shown"]]]},
      ];

      assert.match(
        QueryCheck.refusal(term(SECRET, {filter})),
        /\(MyApp\.Secret :token\)/,
      );
    });

    it("refuses a comparison with a server-only attribute", () => {
      const filter = [["label", "==", {attribute: "token"}]];

      assert.match(
        QueryCheck.refusal(term(SECRET, {filter})),
        /\(MyApp\.Secret :token\)/,
      );
    });

    it("refuses a server-only attribute a path leads to", () => {
      const filter = [[["secret", "token"], "==", "x"]];

      assert.match(
        QueryCheck.refusal(term(OWNER, {filter})),
        /\(MyApp\.Secret :token\)/,
      );
    });

    it("refuses a server-only attribute a quantifier's condition reads", () => {
      const filter = [
        {
          quantifier: "any",
          source: ["secrets"],
          filter: [["token", "==", "x"]],
        },
      ];

      assert.match(
        QueryCheck.refusal(term(OWNER, {filter})),
        /\(MyApp\.Secret :token\)/,
      );
    });

    it("follows a quantifier over a derived field holding rows", () => {
      const filter = [
        {
          quantifier: "any",
          source: ["secretSet"],
          filter: [["token", "==", "x"]],
        },
      ];

      assert.match(
        QueryCheck.refusal(term(OWNER, {filter})),
        /\(MyApp\.Secret :token\)/,
      );
    });

    it("follows a quantifier over an inverse", () => {
      const filter = [
        {
          quantifier: "any",
          source: ["ownedSecrets"],
          filter: [["token", "==", "x"]],
        },
      ];

      assert.match(
        QueryCheck.refusal(term(OWNER, {filter})),
        /\(MyApp\.Secret :token\)/,
      );
    });

    it("refuses a server-only attribute an outer name reads", () => {
      const filter = [
        {
          quantifier: "any",
          source: ["owner"],
          filter: [["label", "==", {attribute: {outer: 1, name: "token"}}]],
        },
      ];

      assert.match(
        QueryCheck.refusal(term(SECRET, {filter})),
        /\(MyApp\.Secret :token\)/,
      );
    });

    it("refuses a sort on a server-only attribute, every name of a type listed once", () => {
      globalThis.Hologram.sync.model[SECRET].serverOnly = ["label", "token"];
      Model.reset();

      const query = term(SECRET, {
        filter: [["token", "==", "x"]],
        sort: [
          ["label", "asc"],
          ["token", "asc"],
          ["id", "asc"],
        ],
      });

      assert.strictEqual(
        QueryCheck.refusal(query),
        `filters or sorts on server_only attributes (MyApp.Secret :label, :token)${SERVER_ONLY_TAIL}`,
      );
    });

    // An include holds no filter of its own, so the term is put together by hand to show where the
    // references of a term it includes go.
    it("lists the queried type first, then the types its paths lead to, then its includes", () => {
      globalThis.Hologram.sync.model[OWNER].serverOnly = ["token"];
      Model.reset();

      const query = term(OWNER, {
        filter: [
          [["secret", "token"], "==", "x"],
          ["token", "==", "y"],
        ],
        include: {secrets: term(SECRET, {filter: [["token", "==", "z"]]})},
      });

      assert.strictEqual(
        QueryCheck.refusal(query),
        `filters or sorts on server_only attributes (MyApp.Owner :token, MyApp.Secret :token, MyApp.Secret :token)${SERVER_ONLY_TAIL}`,
      );
    });
  });
});
