"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Model from "../../assets/js/model.mjs";
import QuerySpelling from "../../assets/js/query_spelling.mjs";
import Stage from "../../assets/js/elixir/hologram/query/stage.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

const count = Stage["count/1"];
const include = Stage["include/2"];
const one = Stage["one/1"];
const skip = Stage["skip/2"];
const sort = Stage["sort/2"];
const take = Stage["take/2"];

const typeName = (number) => `Hologram.Test.Fixtures.Entity.Module${number}`;

const module = (number) => Type.alias(typeName(number));

// A filter's name and value pairs, a name given as a string being the attribute's.
const pairs = (entries) =>
  Type.list(
    entries.map(([name, value]) =>
      Type.tuple([typeof name === "string" ? Type.atom(name) : name, value]),
    ),
  );

const filter = (query, entries) => Stage["filter/2"](query, pairs(entries));

const operator = (name, operand) => Type.tuple([Type.atom(name), operand]);

const outer = (levels, name) =>
  Type.tuple([Type.atom("outer"), Type.integer(levels), name]);

const quantified = (hops, entries) =>
  Type.tuple([Type.list(hops.map((hop) => Type.atom(hop))), pairs(entries)]);

const placeholder = (name) =>
  Type.struct("Hologram.Query.Placeholder", [
    [Type.atom("name"), Type.atom(name)],
  ]);

const date = (year, month, day) =>
  Type.struct("Date", [
    [Type.atom("calendar"), Type.alias("Calendar.ISO")],
    [Type.atom("day"), Type.integer(day)],
    [Type.atom("month"), Type.integer(month)],
    [Type.atom("year"), Type.integer(year)],
  ]);

const datetime = (year, month, day, hour, minute, second, amount, precision) =>
  Type.struct("DateTime", [
    [Type.atom("calendar"), Type.alias("Calendar.ISO")],
    [Type.atom("day"), Type.integer(day)],
    [Type.atom("hour"), Type.integer(hour)],
    [
      Type.atom("microsecond"),
      Type.tuple([Type.integer(amount), Type.integer(precision)]),
    ],
    [Type.atom("minute"), Type.integer(minute)],
    [Type.atom("month"), Type.integer(month)],
    [Type.atom("second"), Type.integer(second)],
    [Type.atom("std_offset"), Type.integer(0)],
    [Type.atom("time_zone"), Type.bitstring("Etc/UTC")],
    [Type.atom("utc_offset"), Type.integer(0)],
    [Type.atom("year"), Type.integer(year)],
    [Type.atom("zone_abbr"), Type.bitstring("UTC")],
  ]);

const time = (hour, minute, second) =>
  Type.struct("Time", [
    [Type.atom("calendar"), Type.alias("Calendar.ISO")],
    [Type.atom("hour"), Type.integer(hour)],
    [Type.atom("microsecond"), Type.tuple([Type.integer(0), Type.integer(0)])],
    [Type.atom("minute"), Type.integer(minute)],
    [Type.atom("second"), Type.integer(second)],
  ]);

const spell = (query) => QuerySpelling.spell(Stage["normalize/1"](query));

// Each spelling here built through the stages is asserted letter for letter in the server's suite
// too (the spell_query/1 tests in test/elixir/hologram/sync/carry_test.exs), over the same query
// built by the server's stages: the two tiers agreeing is what lets a page's carried answer be
// found by its query. The rest are client-only: terms changed by hand after normalizing or not
// built by the stages at all, shapes the server never spells, and an integer past what a Number
// holds exactly, which the server spells in full. The models are the server's fixtures as the
// build bakes them, cut to what the queries read, with a derived field's definition a stand-in,
// since nothing here evaluates it.
describe("QuerySpelling", () => {
  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [typeName(2)]: {
          attributes: {a: "boolean", b: "integer", c: "string", id: "uuid"},
          enumValues: {},
          relationships: {},
          serverOnly: [],
        },
        [typeName(10)]: {
          attributes: {
            count: "integer",
            held_at: "datetime",
            id: "uuid",
            rating: "float",
            released_on: "date",
          },
          enumValues: {},
          relationships: {},
          serverOnly: [],
        },
        [typeName(17)]: {
          attributes: {id: "uuid", label: "string", priority: "enum"},
          enumValues: {priority: ["low", "medium", "high"]},
          relationships: {},
          serverOnly: [],
        },
        [typeName(22)]: {
          attributes: {id: "uuid", opens_at: "time"},
          enumValues: {},
          relationships: {},
          serverOnly: [],
        },
        [typeName(26)]: {
          attributes: {id: "uuid", name: "string"},
          enumValues: {},
          inverses: {
            messages: {
              forward: "channel",
              reference: true,
              sort: [["position", "asc"]],
              toMany: true,
              type: typeName(28),
            },
          },
          relationships: {},
          serverOnly: [],
        },
        [typeName(28)]: {
          attributes: {body: "string", id: "uuid", position: "integer"},
          enumValues: {},
          relationships: {
            channel: {toMany: false, type: typeName(26)},
            labels: {toMany: true, type: typeName(29)},
          },
          serverOnly: [],
        },
        [typeName(29)]: {
          attributes: {id: "uuid", name: "string"},
          enumValues: {},
          relationships: {},
          serverOnly: [],
        },
        [typeName(38)]: {
          attributes: {id: "uuid", pinned: "boolean"},
          derived: {
            sibling_count: {
              definition: {value: 0},
              kind: "scalar",
              type: "integer",
              values: null,
            },
          },
          enumValues: {},
          relationships: {},
          serverOnly: [],
        },
      },
    };

    Model.reset();
  });

  afterEach(() => {
    delete globalThis.Hologram.sync;
    Model.reset();
  });

  describe("spell()", () => {
    it("spells a count with no filter", () => {
      const query = count(module(2));

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // A boolean is spelled as text, the way an enum declaring true is held here.
    it("spells a boolean as text and nil as null", () => {
      const query = count(
        filter(module(2), [
          ["a", Type.boolean(true)],
          ["b", Type.nil()],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["a","==","true"],["b","==",null]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a string with its quotes and backslashes escaped and the rest as it is", () => {
      const query = count(
        filter(module(2), [["c", Type.bitstring('say "hi" \\ żółw')]]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","say \"hi\" \\ żółw"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells an integer, a float, a date and a datetime as the client holds them", () => {
      const query = count(
        filter(module(10), [
          ["count", Type.integer(3)],
          ["rating", Type.float(2.5)],
          ["released_on", date(2026, 1, 2)],
          ["held_at", datetime(2026, 1, 2, 3, 4, 5, 120000, 2)],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["count","==",3],["held_at","==","2026-01-02T03:04:05.120000Z"],["rating","==",float:4004000000000000],["released_on","==","2026-01-02"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // 2.0 and 2 are one Number here, so the server has to spell the two alike.
    it("spells a whole float as an integer", () => {
      const query = count(
        filter(module(10), [["rating", operator(">=", Type.float(2.0))]]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating",">=",2]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells an enum value as the client holds it", () => {
      const query = count(
        filter(module(17), [["priority", Type.atom("high")]]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module17","filter":[["priority","==","high"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a time at full precision", () => {
      const query = count(filter(module(22), [["opens_at", time(9, 30, 0)]]));

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module22","filter":[["opens_at","==","09:30:00.000000"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a reference as its id", () => {
      const query = count(
        filter(module(28), [
          [
            "channel_id",
            Type.bitstring("0190e4c1-0000-7000-8000-000000000001"),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[["channel_id","==","0190e4c1-0000-7000-8000-000000000001"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // The clauses are sorted by their spelling rather than kept in the normalizer's order, which the
    // server's normalizer doesn't share.
    it("spells one filter written in two orders alike", () => {
      const oneOrder = count(
        filter(module(2), [
          ["a", Type.boolean(true)],
          ["c", Type.bitstring("x")],
        ]),
      );

      const otherOrder = count(
        filter(module(2), [
          ["c", Type.bitstring("x")],
          ["a", Type.boolean(true)],
        ]),
      );

      assert.equal(
        spell(oneOrder),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["a","==","true"],["c","==","x"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );

      assert.equal(
        spell(otherOrder),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["a","==","true"],["c","==","x"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // A membership list keeps the order it was written in, as both normalizers keep it.
    it("spells a membership list and a range", () => {
      const query = count(
        filter(module(2), [
          ["c", Type.list([Type.bitstring("y"), Type.bitstring("x")])],
          ["b", Type.range(1, 3, 1)],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["b","<=",3],["b",">=",1],["c","in",["y","x"]]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // The server's normalizer orders 9 before 10, and the spelling orders "10" before "9".
    it("sorts a disjunction's alternatives by their spelling", () => {
      const query = count(
        filter(module(28), [
          [
            "or",
            Type.list([
              pairs([["position", Type.integer(9)]]),
              pairs([["position", Type.integer(10)]]),
            ]),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"or":[[["position","==",10]],[["position","==",9]]]}],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a path", () => {
      const query = count(
        filter(module(28), [
          [
            Type.list([Type.atom("channel"), Type.atom("name")]),
            Type.bitstring("general"),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[[["channel","name"],"==","general"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells an attribute compared with another", () => {
      const query = count(
        filter(module(28), [
          [
            "body",
            Type.tuple([
              Type.atom("attribute"),
              Type.list([Type.atom("channel"), Type.atom("name")]),
            ]),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[["body","==",{"attribute":["channel","name"]}]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a quantifier reading the row one level out", () => {
      const query = count(
        filter(module(28), [
          [
            "any",
            quantified(
              ["labels"],
              [
                [
                  "name",
                  Type.tuple([
                    Type.atom("attribute"),
                    outer(1, Type.atom("body")),
                  ]),
                ],
              ],
            ),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"filter":[["name","==",{"attribute":{"name":"body","outer":1}}]],"quantifier":"any","source":["labels"]}],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells an include and the view bounds", () => {
      const query = skip(
        take(include(module(28), Type.atom("labels")), Type.integer(5)),
        Type.integer(2),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{"labels":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module29","filter":[],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}},"skip":2,"sort":[["id","asc"]],"take":5}`,
      );
    });

    it("spells an include in the order its relationship declares", () => {
      const query = count(include(module(26), Type.atom("messages")));

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[],"include":{"messages":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{},"skip":null,"sort":[["position","asc"],["id","asc"]],"take":null}},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a sort", () => {
      const query = sort(module(2), Type.atom("c"));

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[],"include":{},"skip":null,"sort":[["c","asc"],["id","asc"]],"take":null}`,
      );
    });

    // The server's normalizer orders 9 before 10, and the spelling orders "10" before "9".
    it("sorts clauses by their spelling rather than as the normalizer does", () => {
      const query = count(
        filter(module(2), [
          [
            "b",
            Type.list([
              operator("!=", Type.integer(10)),
              operator("!=", Type.integer(9)),
            ]),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["b","!=",10],["b","!=",9]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // The server's normalizer orders a disjunction before a predicate, and the spelling the other
    // way round.
    it("sorts a disjunction among the clauses by its spelling", () => {
      const query = count(
        filter(module(28), [
          ["position", Type.integer(1)],
          [
            "or",
            Type.list([
              pairs([["body", Type.bitstring("a")]]),
              pairs([["body", Type.bitstring("b")]]),
            ]),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[["position","==",1],{"or":[[["body","==","a"]],[["body","==","b"]]]}],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("sorts the clauses of a disjunction's alternative by their spelling", () => {
      const query = count(
        filter(module(28), [
          [
            "or",
            Type.list([
              pairs([
                ["position", operator("!=", Type.integer(10))],
                ["position", operator("!=", Type.integer(9))],
              ]),
              pairs([["body", Type.bitstring("b")]]),
            ]),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"or":[[["body","==","b"]],[["position","!=",10],["position","!=",9]]]}],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("sorts the clauses of a quantifier's condition by their spelling", () => {
      const query = count(
        filter(module(28), [
          [
            "any",
            quantified(
              ["labels"],
              [
                ["name", Type.bitstring("x")],
                [
                  "or",
                  Type.list([
                    pairs([["name", Type.bitstring("y")]]),
                    pairs([["name", Type.bitstring("z")]]),
                  ]),
                ],
              ],
            ),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[{"filter":[["name","==","x"],{"or":[[["name","==","y"]],[["name","==","z"]]]}],"quantifier":"any","source":["labels"]}],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells all over a set", () => {
      const query = count(
        filter(module(26), [
          [
            "all",
            quantified(
              ["messages"],
              [["position", operator(">", Type.integer(0))]],
            ),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[{"filter":[["position",">",0]],"quantifier":"all","source":["messages"]}],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells none over a set and a source starting on the row one level out", () => {
      const query = count(
        filter(module(26), [
          [
            "none",
            quantified(
              ["messages"],
              [
                [
                  "any",
                  Type.tuple([
                    outer(1, Type.list([Type.atom("messages")])),
                    pairs([["body", Type.bitstring("x")]]),
                  ]),
                ],
              ],
            ),
          ],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[{"filter":[{"filter":[["body","==","x"]],"quantifier":"any","source":{"name":["messages"],"outer":1}}],"quantifier":"none","source":["messages"]}],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a to-one include with no order and what it includes in turn", () => {
      const query = count(
        include(module(28), pairs([["channel", Type.atom("messages")]])),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{"channel":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module26","filter":[],"include":{"messages":{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module28","filter":[],"include":{},"skip":null,"sort":[["position","asc"],["id","asc"]],"take":null}},"skip":null,"sort":[],"take":null}},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells an included derived value as null", () => {
      const query = count(include(module(38), Type.atom("sibling_count")));

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module38","filter":[],"include":{"sibling_count":null},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a query answering one row", () => {
      const query = one(filter(module(2), [["c", Type.bitstring("x")]]));

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"one","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","x"]],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}`,
      );
    });

    it("spells nil in a membership list as null", () => {
      const query = count(
        filter(module(2), [
          ["c", Type.list([Type.bitstring("x"), Type.nil()])],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","in",["x",null]]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // Negative zero is a Number that prints as 0.
    it("spells a negative number with its sign and negative zero as 0", () => {
      const query = count(
        filter(module(10), [
          ["count", operator(">", Type.integer(-3))],
          ["rating", operator("<", Type.float(-0))],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["count",">",-3],["rating","<",0]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // A float attribute takes an integer too, which is the same Number here.
    it("spells an integer compared with a float attribute as the whole float would be", () => {
      const query = count(filter(module(10), [["rating", Type.integer(2)]]));

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","==",2]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a whole float past what a JavaScript Number holds exactly by its bits", () => {
      const query = count(
        filter(module(10), [["rating", Type.float(9007199254740992)]]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","==",float:4340000000000000]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    // A character past U+FFFF is two code units, which JavaScript's own comparison sorts below
    // U+FFFD, and the server, comparing by code point, above it.
    it("sorts clauses by code point", () => {
      const query = count(
        filter(module(2), [
          ["c", Type.bitstring("😀")],
          ["c", Type.bitstring("\ufffd")],
        ]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==","` +
          "\ufffd" +
          String.raw`"],["c","==","😀"]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells the largest whole float a JavaScript Number holds exactly as an integer", () => {
      const query = count(
        filter(module(10), [["rating", Type.float(9007199254740991)]]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","==",9007199254740991]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a negative fraction by its bits", () => {
      const query = count(
        filter(module(10), [["rating", operator("<", Type.float(-2.5))]]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module10","filter":[["rating","<",float:c004000000000000]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a placeholder by its name", () => {
      const query = filter(module(2), [["c", placeholder("search")]]);

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==",{"placeholder":"search"}]],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}`,
      );
    });

    // What the server spells never starts with an exclamation mark, so a shape this doesn't know
    // can't match a key the server builds.
    it("spells a value of a shape it doesn't know so that no server spelling matches it", () => {
      const term = {
        ...Stage["normalize/1"](module(2)),
        filter: [["c", "==", undefined]],
      };

      assert.equal(
        QuerySpelling.spell(term),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==",!undefined]],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}`,
      );
    });

    // A derived field's query reads a set reached from a row, which the server spells as a shape
    // it doesn't know too.
    it("spells a term with a source so that no server spelling matches it", () => {
      const term = {
        ...Stage["normalize/1"](module(2)),
        source: {chain: ["messages"], owner: typeName(26)},
      };

      assert.isTrue(QuerySpelling.spell(term).startsWith("!"));
    });

    // The server spells the same integer in full, so the two miss each other: the Number here
    // isn't the integer the server holds.
    it("spells an integer past what a Number holds exactly by its bits", () => {
      const query = count(
        filter(module(2), [["b", Type.integer(9007199254740993n)]]),
      );

      assert.equal(
        spell(query),
        String.raw`{"cardinality":"count","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["b","==",float:4340000000000000]],"include":{},"skip":null,"sort":[],"take":null}`,
      );
    });

    it("spells a term of a shape it doesn't know so that no server spelling matches it", () => {
      assert.equal(QuerySpelling.spell([1]), "![1]");
    });

    it("spells a value JSON can't write so that no server spelling matches it", () => {
      const term = {
        ...Stage["normalize/1"](module(2)),
        filter: [["c", "==", 1n]],
      };

      assert.equal(
        QuerySpelling.spell(term),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[["c","==",![object BigInt]]],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}`,
      );
    });

    it("spells a clause holding more than a disjunction so that no server spelling matches it", () => {
      const term = {
        ...Stage["normalize/1"](module(2)),
        filter: [{extra: 1, or: [[["c", "==", "x"]]]}],
      };

      assert.equal(
        QuerySpelling.spell(term),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[!{"extra":1,"or":[[["c","==","x"]]]}],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}`,
      );
    });

    it("spells a quantifier clause holding more than its condition so that no server spelling matches it", () => {
      const term = {
        ...Stage["normalize/1"](module(2)),
        filter: [{extra: 1, filter: [], quantifier: "any", source: ["labels"]}],
      };

      assert.equal(
        QuerySpelling.spell(term),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[!{"extra":1,"filter":[],"quantifier":"any","source":["labels"]}],"include":{},"skip":null,"sort":[["id","asc"]],"take":null}`,
      );
    });

    // The stages always set both bounds, so a missing one is a term they didn't build.
    it("spells a missing bound so that no server spelling matches it", () => {
      const term = {...Stage["normalize/1"](module(2)), take: undefined};

      assert.equal(
        QuerySpelling.spell(term),
        String.raw`{"cardinality":"set","entity":"Hologram.Test.Fixtures.Entity.Module2","filter":[],"include":{},"skip":null,"sort":[["id","asc"]],"take":!undefined}`,
      );
    });
  });
});
