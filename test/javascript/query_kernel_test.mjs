"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import QueryKernel from "../../assets/js/query_kernel.mjs";

defineRuntimeGlobals();

// Mirrors the predicate cases of test/elixir/hologram/query/interpreter_test.exs, case for case
// and in the same order - that suite proves the reference answers what the database answers, and
// this one proves the client answers what the reference does. The rows here hold what the wire
// spells rather than what Postgres returns: dates and datetimes as canonical strings.
describe("QueryKernel", () => {
  const matches = QueryKernel.matches;

  const rows = {
    ada: {id: "r1", priority: 1, username: "ada"},
    bob: {id: "r2", priority: 3, username: "bob"},
    cleo: {id: "r3", priority: null, username: "cleo"},
  };

  const matching = (filter, context) =>
    Object.values(rows)
      .filter((row) => matches(row, filter, context))
      .map((row) => row.username);

  describe("matches() - equality and membership", () => {
    it("matches a value", () => {
      assert.deepEqual(matching([["priority", "==", 3]]), ["bob"]);
    });

    // Null is a value like any other here: an unset attribute is unequal to a set one, so a
    // negated equality names the rows that never had it either.
    it("matches what is unequal, missing values included", () => {
      assert.deepEqual(matching([["priority", "!=", 3]]), ["ada", "cleo"]);
    });

    it("matches an unset attribute", () => {
      assert.deepEqual(matching([["priority", "==", null]]), ["cleo"]);
    });

    it("matches what is set", () => {
      assert.deepEqual(matching([["priority", "!=", null]]), ["ada", "bob"]);
    });

    it("matches membership in a list", () => {
      assert.deepEqual(matching([["priority", "in", [1, 3]]]), ["ada", "bob"]);
    });

    it("matches membership in a list naming an unset value", () => {
      assert.deepEqual(matching([["priority", "in", [null, 3]]]), [
        "bob",
        "cleo",
      ]);
    });

    // A list without null leaves the rows that have no value at all outside it, so excluding
    // the list keeps them.
    it("matches exclusion from a list, missing values included", () => {
      assert.deepEqual(matching([["priority", "not_in", [1]]]), [
        "bob",
        "cleo",
      ]);
    });

    it("matches exclusion from a list naming an unset value", () => {
      assert.deepEqual(matching([["priority", "not_in", [null, 1]]]), ["bob"]);
    });

    it("matches every predicate of a filter and no fewer", () => {
      const filter = [
        ["priority", "!=", null],
        ["username", "==", "bob"],
      ];

      assert.deepEqual(matching(filter), ["bob"]);
    });

    it("matches every row for a filter holding nothing", () => {
      assert.deepEqual(matching([]), ["ada", "bob", "cleo"]);
    });
  });

  describe("matches() - ordering comparisons", () => {
    const dated = {
      first: {
        held_at: "2026-03-01T10:00:00.000000Z",
        rating: 1.5,
        released_on: "2026-03-01",
        username: "ada",
      },
      second: {
        held_at: "2027-06-01T10:00:00.000000Z",
        rating: 4.5,
        released_on: "2027-06-01",
        username: "bob",
      },
      third: {
        held_at: null,
        rating: null,
        released_on: null,
        username: "cleo",
      },
    };

    const matchingDated = (filter) =>
      Object.values(dated)
        .filter((row) => matches(row, filter))
        .map((row) => row.username);

    it("matches values above a bound", () => {
      assert.deepEqual(matchingDated([["rating", ">", 1.5]]), ["bob"]);
    });

    it("matches values at or above a bound", () => {
      assert.deepEqual(matchingDated([["rating", ">=", 1.5]]), ["ada", "bob"]);
    });

    it("matches values below a bound", () => {
      assert.deepEqual(matchingDated([["rating", "<", 4.5]]), ["ada"]);
    });

    it("matches values at or below a bound", () => {
      assert.deepEqual(matchingDated([["rating", "<=", 4.5]]), ["ada", "bob"]);
    });

    // A canonical date is ordered by its characters, which is what makes a comparison here a
    // comparison of strings rather than a parse.
    it("compares dates", () => {
      const filter = [["released_on", ">=", "2027-01-01"]];

      assert.deepEqual(matchingDated(filter), ["bob"]);
    });

    it("compares datetimes", () => {
      const filter = [["held_at", "<", "2027-01-01T00:00:00.000000Z"]];

      assert.deepEqual(matchingDated(filter), ["ada"]);
    });

    // An ordering line has no place to put a value that is not there, so a comparison passes
    // over the rows that have none - unlike the equality family, which counts them.
    it("passes over an unset attribute, whichever way the comparison points", () => {
      assert.deepEqual(matchingDated([["rating", ">", 0]]), ["ada", "bob"]);
      assert.deepEqual(matchingDated([["rating", "<", 100]]), ["ada", "bob"]);
    });
  });

  describe("matches() - placeholders", () => {
    it("matches against the value bound to a placeholder", () => {
      const filter = [["priority", "==", {placeholder: "priority"}]];
      const context = {bindings: {priority: 3}};

      assert.deepEqual(matching(filter, context), ["bob"]);
    });

    it("matches against a list bound to a placeholder", () => {
      const filter = [["priority", "in", {placeholder: "priorities"}]];
      const context = {bindings: {priorities: [1, 3]}};

      assert.deepEqual(matching(filter, context), ["ada", "bob"]);
    });

    it("matches against a placeholder among the values of a list", () => {
      const filter = [["priority", "in", [{placeholder: "priority"}, 1]]];
      const context = {bindings: {priority: 3}};

      assert.deepEqual(matching(filter, context), ["ada", "bob"]);
    });

    // The reference raises on each of these, and in these words - this side is the one whose
    // answer reaches a screen, so answering where the server refuses is the divergence that
    // shows. A LITERAL nil in a term is a value like any other and never comes through here.
    it("refuses a placeholder the bindings do not name", () => {
      const filter = [["priority", "==", {placeholder: "priority"}]];

      assert.throw(
        () => matching(filter, {}),
        HologramRuntimeError,
        "missing value for placeholder :priority",
      );
    });

    it("refuses a nil value bound to a placeholder", () => {
      const filter = [["priority", "==", {placeholder: "priority"}]];
      const context = {bindings: {priority: null}};

      assert.throw(
        () => matching(filter, context),
        HologramRuntimeError,
        "nil value for placeholder :priority - use an explicit nil predicate instead",
      );
    });

    it("refuses a nil element in a list bound to a placeholder", () => {
      const filter = [["priority", "in", {placeholder: "priorities"}]];
      const context = {bindings: {priorities: [null, 3]}};

      assert.throw(
        () => matching(filter, context),
        HologramRuntimeError,
        "nil element in the list for placeholder :priorities - use an explicit nil predicate instead",
      );
    });
  });

  describe("run()", () => {
    const PROJECT = "MyApp.Project";
    const TASK = "MyApp.Task";
    const USER = "MyApp.User";

    const term = (overrides = {}) =>
      Object.assign(
        {
          cardinality: "set",
          entity: TASK,
          filter: [],
          include: {},
          limit: null,
          offset: null,
          orderBy: [["id", "asc"]],
        },
        overrides,
      );

    const titles = (nodes) => nodes.map((node) => node.row.title);

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [PROJECT]: {
            attributes: {id: "uuid", name: "string"},
            enumValues: {},
            relationships: {
              owner: {toMany: false, type: USER},
              tasks: {toMany: true, type: TASK},
            },
            serverOnly: [],
            sortKeys: [],
          },
          [TASK]: {
            attributes: {
              id: "uuid",
              position: "integer",
              priority: "enum",
              title: "string",
            },
            enumValues: {priority: ["low", "medium", "high"]},
            relationships: {owner: {toMany: false, type: USER}},
            serverOnly: [],
            sortKeys: ["title"],
          },
          [USER]: {
            attributes: {email: "string", id: "uuid"},
            enumValues: {},
            relationships: {},
            serverOnly: [],
            sortKeys: [],
          },
        },
      };

      LocalDatabase.reset();
      Model.reset();
    });

    describe("ordering", () => {
      beforeEach(() => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 3, title: "bob"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 2, title: "ada"});
        LocalDatabase.putRow(TASK, {id: "t3", position: 1, title: "cleo"});
      });

      it("orders by an attribute", () => {
        const ordered = term({
          orderBy: [
            ["position", "asc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), [
          "cleo",
          "ada",
          "bob",
        ]);
      });

      it("orders by an attribute descending", () => {
        const ordered = term({
          orderBy: [
            ["position", "desc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), [
          "bob",
          "ada",
          "cleo",
        ]);
      });

      // Ascending puts them last and descending puts them first, which is where the database
      // puts them - a page reading its own rows shows them where the server would have.
      it("places missing values last when ascending", () => {
        LocalDatabase.reset();
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "ada"});
        LocalDatabase.putRow(TASK, {id: "t2", position: null, title: "bob"});

        const ordered = term({
          orderBy: [
            ["position", "asc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), ["ada", "bob"]);
      });

      it("places missing values first when descending", () => {
        LocalDatabase.reset();
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "ada"});
        LocalDatabase.putRow(TASK, {id: "t2", position: null, title: "bob"});

        const ordered = term({
          orderBy: [
            ["position", "desc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), ["bob", "ada"]);
      });

      // The rows tie on the first key, so the second decides between them.
      it("orders by each key in turn", () => {
        LocalDatabase.reset();
        LocalDatabase.putRow(TASK, {id: "t1", position: 7, title: "eve"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 7, title: "dana"});

        const ordered = term({
          orderBy: [
            ["position", "asc"],
            ["title", "asc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), ["dana", "eve"]);
      });

      // The key the ingest derived carries the practical order, which the bytes do not: an
      // uppercase letter sorts before every lowercase one, and a diacritic after all of them.
      it("orders a string by the key derived from it", () => {
        LocalDatabase.reset();

        LocalDatabase.putRow(TASK, {id: "t1", title: "Zoe", title_sort: "zoe"});
        LocalDatabase.putRow(TASK, {id: "t2", title: "ada", title_sort: "ada"});

        LocalDatabase.putRow(TASK, {
          id: "t3",
          title: "Ödön",
          title_sort: "odon",
        });

        LocalDatabase.putRow(TASK, {id: "t4", title: "bob", title_sort: "bob"});

        const ordered = term({
          orderBy: [
            ["title", "asc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), [
          "ada",
          "bob",
          "Ödön",
          "Zoe",
        ]);
      });

      // Two values sharing a key are settled by themselves, the way the database settles them
      // with the column behind the companion.
      it("settles a tie on the derived key by the value itself", () => {
        LocalDatabase.reset();

        LocalDatabase.putRow(TASK, {id: "t1", title: "zoe", title_sort: "zoe"});
        LocalDatabase.putRow(TASK, {id: "t2", title: "Zoe", title_sort: "zoe"});

        const ordered = term({
          orderBy: [
            ["title", "asc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), ["Zoe", "zoe"]);
      });
    });

    describe("ordering enums", () => {
      beforeEach(() => {
        LocalDatabase.reset();
        LocalDatabase.putRow(TASK, {id: "t1", priority: "medium", title: "a"});
        LocalDatabase.putRow(TASK, {id: "t2", priority: "high", title: "b"});
        LocalDatabase.putRow(TASK, {id: "t3", priority: "low", title: "c"});
        LocalDatabase.putRow(TASK, {id: "t4", title: "d"});
      });

      // Declared, alphabetical and reverse-alphabetical are three different sequences for these
      // values, so an order that matches the declared one matches it on purpose.
      it("orders by the declared position, not the label", () => {
        const ordered = term({
          orderBy: [
            ["priority", "asc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), [
          "c",
          "a",
          "b",
          "d",
        ]);
      });

      it("orders by the declared position descending", () => {
        const ordered = term({
          orderBy: [
            ["priority", "desc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), [
          "d",
          "b",
          "a",
          "c",
        ]);
      });

      it("settles a tie on an enum by the next key", () => {
        LocalDatabase.putRow(TASK, {id: "t5", priority: "medium", title: "e"});
        LocalDatabase.putRow(TASK, {id: "t6", priority: "medium", title: "f"});

        const ordered = term({
          orderBy: [
            ["priority", "asc"],
            ["title", "asc"],
            ["id", "asc"],
          ],
        });

        assert.deepEqual(titles(QueryKernel.run(ordered)), [
          "c",
          "a",
          "e",
          "f",
          "b",
          "d",
        ]);
      });
    });

    describe("view bounds", () => {
      beforeEach(() => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "ada"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 2, title: "bob"});
        LocalDatabase.putRow(TASK, {id: "t3", position: 3, title: "cleo"});
      });

      it("takes at most the limit", () => {
        assert.deepEqual(titles(QueryKernel.run(term({limit: 2}))), [
          "ada",
          "bob",
        ]);
      });

      it("skips the offset", () => {
        assert.deepEqual(titles(QueryKernel.run(term({offset: 1}))), [
          "bob",
          "cleo",
        ]);
      });

      it("skips before it takes", () => {
        const bounded = term({limit: 1, offset: 1});

        assert.deepEqual(titles(QueryKernel.run(bounded)), ["bob"]);
      });
    });

    describe("terminals", () => {
      beforeEach(() => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "ada"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 2, title: "bob"});
      });

      it("returns the first row of a single-result query", () => {
        const single = term({cardinality: "one"});

        assert.equal(QueryKernel.run(single).row.title, "ada");
      });

      it("returns nothing for a single-result query matching no row", () => {
        const single = term({
          cardinality: "one",
          filter: [["title", "==", "nobody"]],
        });

        assert.isNull(QueryKernel.run(single));
      });

      it("returns how many rows match", () => {
        const counting = term({
          cardinality: "count",
          filter: [["position", ">", 1]],
        });

        assert.equal(QueryKernel.run(counting), 1);
      });

      // A count counts what the query evaluates to, so a bounded query counts what its bounds
      // leave rather than what its filter matched.
      it("counts what the view bounds leave", () => {
        const counting = term({cardinality: "count", limit: 1});

        assert.equal(QueryKernel.run(counting), 1);
      });
    });

    describe("includes", () => {
      const projectTerm = (include) =>
        term({entity: PROJECT, include: include});

      const subTerm = (overrides = {}) =>
        Object.assign(
          {
            cardinality: "set",
            entity: TASK,
            filter: [],
            include: {},
            limit: null,
            offset: null,
            orderBy: [["id", "asc"]],
          },
          overrides,
        );

      beforeEach(() => {
        LocalDatabase.putRow(PROJECT, {
          id: "p1",
          name: "Website",
          owner_id: "u1",
        });

        LocalDatabase.putRow(USER, {email: "ada@example.com", id: "u1"});
      });

      it("fills a to-one relationship with the row its reference names", () => {
        const [node] = QueryKernel.run(
          projectTerm({owner: subTerm({entity: USER})}),
        );

        assert.equal(node.includes.owner.row.email, "ada@example.com");
      });

      it("fills a to-one relationship holding nothing with nothing", () => {
        LocalDatabase.putRow(PROJECT, {
          id: "p2",
          name: "Launch",
          owner_id: null,
        });

        const nodes = QueryKernel.run(
          projectTerm({owner: subTerm({entity: USER})}),
        );

        assert.isNull(nodes[1].includes.owner);
      });

      it("fills a to-many relationship with the rows the pairs name", () => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "ada"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 2, title: "bob"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t2"]);

        const [node] = QueryKernel.run(projectTerm({tasks: subTerm()}));

        assert.deepEqual(titles(node.includes.tasks), ["ada", "bob"]);
      });

      it("fills a to-many relationship holding no pairs with an empty list", () => {
        const [node] = QueryKernel.run(projectTerm({tasks: subTerm()}));

        assert.deepEqual(node.includes.tasks, []);
      });

      // A fill arrives in pieces, so a parent can be told about a child before the child lands.
      it("passes over a pair naming a row the database does not hold", () => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "ada"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t_missing"]);

        const [node] = QueryKernel.run(projectTerm({tasks: subTerm()}));

        assert.deepEqual(titles(node.includes.tasks), ["ada"]);
      });

      it("matches a to-many include's own filter", () => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "kept"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 2, title: "dropped"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t2"]);

        const include = {
          tasks: subTerm({filter: [["title", "==", "kept"]]}),
        };

        const [node] = QueryKernel.run(projectTerm(include));

        assert.deepEqual(titles(node.includes.tasks), ["kept"]);
      });

      it("orders and bounds a to-many include by its own clauses", () => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 3, title: "cherry"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 1, title: "apple"});
        LocalDatabase.putRow(TASK, {id: "t3", position: 2, title: "banana"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t2", "t3"]);

        const include = {
          tasks: subTerm({
            limit: 2,
            orderBy: [
              ["position", "asc"],
              ["id", "asc"],
            ],
          }),
        };

        const [node] = QueryKernel.run(projectTerm(include));

        assert.deepEqual(titles(node.includes.tasks), ["apple", "banana"]);
      });

      it("fills what an include includes, two levels down", () => {
        LocalDatabase.putRow(TASK, {
          id: "t1",
          owner_id: "u1",
          position: 1,
          title: "ada",
        });

        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1"]);

        const include = {
          tasks: subTerm({include: {owner: subTerm({entity: USER})}}),
        };

        const [node] = QueryKernel.run(projectTerm(include));
        const [task] = node.includes.tasks;

        assert.equal(task.includes.owner.row.id, "u1");
      });

      it("leaves a node's includes empty when the query asked for none", () => {
        const [node] = QueryKernel.run(projectTerm({}));

        assert.deepEqual(node.includes, {});
      });
    });
  });

  // Mirrors the interpreter's "run/3 - comparing enums" describe case for case. The rows hold
  // labels the way the wire spells them, and the type is named so the kernel reads the declared
  // list off the model - which is what makes :high come after :medium rather than before it.
  describe("matches() - comparing enums", () => {
    const TICKET = "MyApp.Ticket";

    const tickets = {
      a: {id: "t1", priority: "medium", title: "a"},
      b: {id: "t2", priority: "high", title: "b"},
      c: {id: "t3", priority: "low", title: "c"},
      d: {id: "t4", priority: null, title: "d"},
    };

    const titlesMatching = (filter, context) =>
      Object.values(tickets)
        .filter((row) => matches(row, filter, context, TICKET))
        .map((row) => row.title);

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [TICKET]: {
            attributes: {id: "uuid", priority: "enum", title: "string"},
            enumValues: {priority: ["low", "medium", "high"]},
            relationships: {},
            serverOnly: [],
            sortKeys: [],
          },
        },
      };

      Model.reset();
    });

    it("matches values at or after a declared value", () => {
      assert.deepEqual(titlesMatching([["priority", ">=", "medium"]]), [
        "a",
        "b",
      ]);
    });

    it("matches values before a declared value", () => {
      assert.deepEqual(titlesMatching([["priority", "<", "medium"]]), ["c"]);
    });

    it("passes over an unset enum", () => {
      assert.deepEqual(titlesMatching([["priority", ">=", "low"]]), [
        "a",
        "b",
        "c",
      ]);
    });

    it("compares a declared value bound to a placeholder", () => {
      const filter = [["priority", ">=", {placeholder: "min"}]];

      assert.deepEqual(titlesMatching(filter, {bindings: {min: "medium"}}), [
        "a",
        "b",
      ]);
    });

    it("refuses a placeholder bound to a value the enum does not declare, as the reference does", () => {
      const filter = [["priority", ">=", {placeholder: "min"}]];

      assert.throw(
        () => titlesMatching(filter, {bindings: {min: "urgent"}}),
        HologramRuntimeError,
        "invalid value :urgent for placeholder :min - expected one of [:low, :medium, :high]",
      );
    });
  });

  describe("matches() - the acting user", () => {
    it("matches against who is asking", () => {
      const filter = [["id", "==", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: "r2"}), ["bob"]);
    });

    it("matches everything but who is asking", () => {
      const filter = [["id", "!=", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: "r2"}), ["ada", "cleo"]);
    });

    // There is nobody to compare against, so nothing answers - the same silence the database
    // gives a statement asking about an actor that is not there, and an unset attribute is no
    // more a match for nobody than a set one is.
    it("matches nothing for a visitor", () => {
      const filter = [["id", "==", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: null}), []);
    });

    // The negated form is where that silence has to be deliberate: nobody is UNEQUAL to every
    // row, so a predicate left to compare against nothing would answer with everything.
    it("matches nothing for a visitor, whichever way the predicate points", () => {
      const filter = [["id", "!=", {actor: true}]];

      assert.deepEqual(matching(filter, {actorUserId: null}), []);
    });

    it("matches nothing for a visitor a row could otherwise answer for", () => {
      const filter = [["priority", "==", {actor: true}]];

      assert.deepEqual(matching(filter, {}), []);
    });
  });
});
