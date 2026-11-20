"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Model from "../../assets/js/model.mjs";
import QueryCheck from "../../assets/js/query_check.mjs";

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
    attributes: {id: "uuid", label: "string", token: "string"},
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
