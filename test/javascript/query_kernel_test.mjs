"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import Batch from "../../assets/js/batch.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import LocalDatabase from "../../assets/js/local_database.mjs";
import Model from "../../assets/js/model.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import QueryKernel from "../../assets/js/query_kernel.mjs";

defineRuntimeGlobals();

// Mirrors the predicate cases of test/elixir/hologram/query/interpreter_test.exs, case for case
// and in the same order - that suite proves the reference answers what the database answers, and
// this one proves the client answers what the reference does. The rows here hold what the wire
// spells rather than what Postgres returns: dates and datetimes as canonical strings.
describe("QueryKernel", () => {
  const matches = QueryKernel.matches;

  const rows = {
    ada: {count: 1, id: "r1", priority: 1, username: "ada"},
    bob: {count: 2, id: "r2", priority: 3, username: "bob"},
    cleo: {count: 3, id: "r3", priority: null, username: "cleo"},
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

  describe("matches() - disjunctions", () => {
    it("matches either alternative", () => {
      const filter = [{or: [[["priority", "==", 1]], [["count", "==", 2]]]}];

      assert.deepEqual(matching(filter), ["ada", "bob"]);
    });

    it("matches a conjunction inside an alternative", () => {
      const filter = [
        {
          or: [
            [
              ["count", ">=", 2],
              ["priority", "==", 3],
            ],
            [["username", "==", "ada"]],
          ],
        },
      ];

      assert.deepEqual(matching(filter), ["ada", "bob"]);
    });

    it("matches a grouped disjunction inside a conjunction", () => {
      const filter = [
        ["count", ">=", 2],
        {or: [[["priority", "==", 1]], [["username", "==", "cleo"]]]},
      ];

      assert.deepEqual(matching(filter), ["cleo"]);
    });

    it("matches a nested disjunction", () => {
      const filter = [
        {
          or: [
            [["count", "==", 1]],
            [
              ["count", ">=", 2],
              {or: [[["priority", "==", 3]], [["username", "==", "cleo"]]]},
            ],
          ],
        },
      ];

      assert.deepEqual(matching(filter), ["ada", "bob", "cleo"]);
    });

    // An ordering comparison passes over a missing value, and the other alternative still holds -
    // null means inside a disjunction what it means outside one.
    it("passes an unset value to the other alternative", () => {
      const filter = [{or: [[["priority", ">", 1]], [["count", "==", 3]]]}];

      assert.deepEqual(matching(filter), ["bob", "cleo"]);
    });

    it("matches an unset value through equality in an alternative", () => {
      const filter = [{or: [[["priority", "==", null]], [["count", "==", 1]]]}];

      assert.deepEqual(matching(filter), ["ada", "cleo"]);
    });

    it("matches a disjunction beside the conjuncts around it", () => {
      const filter = [
        ["count", ">=", 2],
        {or: [[["priority", "==", 3]], [["username", "==", "cleo"]]]},
      ];

      assert.deepEqual(matching(filter), ["bob", "cleo"]);
    });

    it("matches nothing when no alternative holds", () => {
      const filter = [{or: [[["priority", "==", 5]], [["count", "==", 9]]]}];

      assert.deepEqual(matching(filter), []);
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

    it("matches against a placeholder inside an alternative", () => {
      const filter = [
        {
          or: [
            [["priority", "==", {placeholder: "priority"}]],
            [["count", "==", 2]],
          ],
        },
      ];

      const context = {bindings: {priority: 1}};

      assert.deepEqual(matching(filter, context), ["ada", "bob"]);
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
          skip: null,
          sort: [["id", "asc"]],
          take: null,
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
          },
          [USER]: {
            attributes: {email: "string", id: "uuid"},
            enumValues: {},
            relationships: {manager: {toMany: false, type: USER}},
            serverOnly: [],
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
          sort: [
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
          sort: [
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
          sort: [
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
          sort: [
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
          sort: [
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
          sort: [
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
          sort: [
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
          sort: [
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
          sort: [
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
          sort: [
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

      it("takes at most as many rows as take sets", () => {
        assert.deepEqual(titles(QueryKernel.run(term({take: 2}))), [
          "ada",
          "bob",
        ]);
      });

      it("skips as many rows as skip sets", () => {
        assert.deepEqual(titles(QueryKernel.run(term({skip: 1}))), [
          "bob",
          "cleo",
        ]);
      });

      it("skips before it takes", () => {
        const bounded = term({skip: 1, take: 1});

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
        const counting = term({cardinality: "count", take: 1});

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
            skip: null,
            sort: [["id", "asc"]],
            take: null,
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

      it("matches a disjunction in a to-many include's own filter", () => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 1, title: "apple"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 2, title: "banana"});
        LocalDatabase.putRow(TASK, {id: "t3", position: 3, title: "cherry"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t2", "t3"]);

        const filter = [
          {or: [[["title", "==", "apple"]], [["title", "==", "cherry"]]]},
        ];

        const include = {tasks: subTerm({filter: filter})};

        const [node] = QueryKernel.run(projectTerm(include));

        assert.deepEqual(titles(node.includes.tasks), ["apple", "cherry"]);
      });

      it("orders and bounds a to-many include by its own clauses", () => {
        LocalDatabase.putRow(TASK, {id: "t1", position: 3, title: "cherry"});
        LocalDatabase.putRow(TASK, {id: "t2", position: 1, title: "apple"});
        LocalDatabase.putRow(TASK, {id: "t3", position: 2, title: "banana"});
        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1", "t2", "t3"]);

        const include = {
          tasks: subTerm({
            sort: [
              ["position", "asc"],
              ["id", "asc"],
            ],
            take: 2,
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

      it("fills what an include includes, three levels down", () => {
        LocalDatabase.putRow(TASK, {
          id: "t1",
          owner_id: "u2",
          position: 1,
          title: "ada",
        });

        LocalDatabase.putRow(USER, {
          email: "bob@example.com",
          id: "u2",
          manager_id: "u1",
        });

        LocalDatabase.replaceFacts(PROJECT, "tasks", "p1", ["t1"]);

        const include = {
          tasks: subTerm({
            include: {
              owner: subTerm({
                entity: USER,
                include: {manager: subTerm({entity: USER})},
              }),
            },
          }),
        };

        const [node] = QueryKernel.run(projectTerm(include));
        const [task] = node.includes.tasks;

        assert.equal(task.includes.owner.includes.manager.row.id, "u1");
      });

      it("leaves a node's includes empty when the query asked for none", () => {
        const [node] = QueryKernel.run(projectTerm({}));

        assert.deepEqual(node.includes, {});
      });
    });
  });

  // Mirrors the interpreter's "run/3 - inverse includes" describe case for case, then the cases only
  // a client has: writes it has not sent yet, folded into what an inverse reads.
  describe("run() - inverse includes", () => {
    const CHANNEL = "MyApp.Channel";
    const LABEL = "MyApp.Label";
    const MESSAGE = "MyApp.Message";
    const TOPIC = "MyApp.Topic";

    const node = (entity, include = {}, overrides = {}) =>
      Object.assign(
        {
          cardinality: "set",
          entity,
          filter: [],
          include,
          skip: null,
          sort: [["id", "asc"]],
          take: null,
        },
        overrides,
      );

    // The term as normalization leaves it: the declared order, then the id.
    const messagesTerm = (overrides = {}) =>
      node(
        MESSAGE,
        {},
        Object.assign(
          {
            sort: [
              ["position", "asc"],
              ["id", "asc"],
            ],
          },
          overrides,
        ),
      );

    const bodies = (nodes) => nodes.map((each) => each.row.body);

    const byName = (nodes, read) =>
      Object.fromEntries(nodes.map((each) => [each.row.name, read(each)]));

    const pushed = (...writes) => {
      const batch = new Batch("messages");

      for (const write of writes) {
        batch.append(write);
      }

      Overlay.push(batch);

      return batch;
    };

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [CHANNEL]: {
            attributes: {id: "uuid", name: "string"},
            enumValues: {},
            inverses: {
              messages: {
                forward: "channel",
                reference: true,
                sort: [["position", "asc"]],
                toMany: true,
                type: MESSAGE,
              },
              topic: {
                forward: "channel",
                reference: true,
                sort: [],
                toMany: false,
                type: TOPIC,
              },
            },
            relationships: {},
            serverOnly: [],
          },
          [LABEL]: {
            attributes: {id: "uuid", name: "string"},
            enumValues: {},
            inverses: {
              messages: {
                forward: "labels",
                reference: false,
                sort: [],
                toMany: true,
                type: MESSAGE,
              },
            },
            relationships: {},
            serverOnly: [],
          },
          [MESSAGE]: {
            attributes: {body: "string", id: "uuid", position: "integer"},
            enumValues: {},
            relationships: {
              channel: {optional: true, toMany: false, type: CHANNEL},
              labels: {toMany: true, type: LABEL},
            },
            serverOnly: [],
          },
          [TOPIC]: {
            attributes: {id: "uuid", summary: "string"},
            enumValues: {},
            relationships: {
              channel: {optional: true, toMany: false, type: CHANNEL},
            },
            serverOnly: [],
          },
        },
      };

      LocalDatabase.reset();
      Model.reset();
      Overlay.reset();

      LocalDatabase.putRow(CHANNEL, {id: "c1", name: "general"});
      LocalDatabase.putRow(CHANNEL, {id: "c2", name: "random"});
    });

    afterEach(() => {
      Overlay.reset();
    });

    const message = (id, channelId, body, position) =>
      LocalDatabase.putRow(MESSAGE, {
        body,
        channel_id: channelId,
        id,
        position,
      });

    it("fills an inverse set with the related rows naming the row, in the declared order", () => {
      message("m1", "c1", "second", 2);
      message("m2", "c1", "first", 1);
      message("m3", "c2", "elsewhere", 1);

      const nodes = QueryKernel.run(node(CHANNEL, {messages: messagesTerm()}));

      assert.deepEqual(
        byName(nodes, (each) => bodies(each.includes.messages)),
        {general: ["first", "second"], random: ["elsewhere"]},
      );
    });

    it("breaks a tie in the declared order by id", () => {
      message("m2", "c1", "b", 1);
      message("m1", "c1", "a", 1);

      const [general] = QueryKernel.run(
        node(CHANNEL, {messages: messagesTerm()}),
      );

      assert.deepEqual(
        general.includes.messages.map((each) => each.row.id),
        ["m1", "m2"],
      );
    });

    it("puts an inverse set through the include's own clauses", () => {
      message("m1", "c1", "one", 1);
      message("m2", "c1", "two", 2);
      message("m3", "c1", "three", 3);

      const include = {
        messages: messagesTerm({
          filter: [["position", ">", 1]],
          sort: [
            ["position", "desc"],
            ["id", "asc"],
          ],
          take: 1,
        }),
      };

      const [general] = QueryKernel.run(node(CHANNEL, include));

      assert.deepEqual(bodies(general.includes.messages), ["three"]);
    });

    it("leaves a related row whose reference is nil out of every inverse", () => {
      message("m1", "c1", "kept", 1);
      message("m2", null, "orphan", 1);

      const nodes = QueryKernel.run(node(CHANNEL, {messages: messagesTerm()}));

      assert.deepEqual(
        byName(nodes, (each) => bodies(each.includes.messages)),
        {general: ["kept"], random: []},
      );
    });

    it("fills an inverse of a to-many with the related rows its ids name", () => {
      LocalDatabase.putRow(LABEL, {id: "l1", name: "urgent"});
      LocalDatabase.putRow(LABEL, {id: "l2", name: "later"});
      message("m1", null, "tagged", 1);
      message("m2", null, "both", 2);
      message("m3", null, "untagged", 3);
      LocalDatabase.replaceFacts(LABEL, "messages", "l1", ["m1", "m2"]);
      LocalDatabase.replaceFacts(LABEL, "messages", "l2", ["m2"]);

      const nodes = QueryKernel.run(node(LABEL, {messages: node(MESSAGE)}, {}));

      assert.deepEqual(
        byName(nodes, (each) => bodies(each.includes.messages).sort()),
        {later: ["both"], urgent: ["both", "tagged"]},
      );
    });

    it("fills a single inverse with the row naming it, or nil", () => {
      LocalDatabase.putRow(TOPIC, {
        channel_id: "c1",
        id: "t1",
        summary: "welcome",
      });

      const nodes = QueryKernel.run(
        node(CHANNEL, {topic: node(TOPIC, {}, {sort: []})}),
      );

      assert.deepEqual(
        byName(nodes, (each) => each.includes.topic?.row.summary ?? null),
        {general: "welcome", random: null},
      );
    });

    it("nests an include under an inverse set", () => {
      LocalDatabase.putRow(LABEL, {id: "l1", name: "urgent"});
      message("m1", "c1", "tagged", 1);
      LocalDatabase.replaceFacts(MESSAGE, "labels", "m1", ["l1"]);

      const include = {
        messages: messagesTerm({include: {labels: node(LABEL)}}),
      };

      const [general] = QueryKernel.run(node(CHANNEL, include));
      const [included] = general.includes.messages;

      assert.deepEqual(
        included.includes.labels.map((each) => each.row.name),
        ["urgent"],
      );
    });

    it("reads an inverse below the root, matched to the row including it", () => {
      LocalDatabase.putRow(TOPIC, {
        channel_id: "c1",
        id: "t1",
        summary: "welcome",
      });
      message("m1", "c1", "in general", 1);
      message("m2", "c2", "in random", 1);

      const include = {
        channel: node(
          CHANNEL,
          {messages: messagesTerm(), topic: node(TOPIC, {}, {sort: []})},
          {sort: []},
        ),
      };

      const nodes = QueryKernel.run(
        node(MESSAGE, include, {filter: [["body", "==", "in general"]]}),
      );

      assert.equal(nodes.length, 1);
      assert.equal(
        nodes[0].includes.channel.includes.topic.row.summary,
        "welcome",
      );

      assert.deepEqual(bodies(nodes[0].includes.channel.includes.messages), [
        "in general",
      ]);
    });

    // A row the session may not read never reaches the client, and an id naming a row it does
    // not hold is passed over - the browser's side of the server's read rules.
    it("passes over an id naming a row the client does not hold", () => {
      LocalDatabase.putRow(LABEL, {id: "l1", name: "urgent"});
      message("m1", null, "shown", 1);
      LocalDatabase.replaceFacts(LABEL, "messages", "l1", ["m1", "m_hidden"]);

      const [urgent] = QueryKernel.run(node(LABEL, {messages: node(MESSAGE)}));

      assert.deepEqual(bodies(urgent.includes.messages), ["shown"]);
    });

    it("reads a pending move of a related row under the row it moved to", () => {
      message("m1", "c1", "moving", 1);

      pushed({
        data: {channel_id: "c2"},
        id: "m1",
        op: "update",
        stamp: 1_756_100_000_123 * 1024,
        type: MESSAGE,
      });

      const nodes = QueryKernel.run(node(CHANNEL, {messages: messagesTerm()}));

      assert.deepEqual(
        byName(nodes, (each) => bodies(each.includes.messages)),
        {general: [], random: ["moving"]},
      );
    });

    it("reads a pending edge of a related row through an inverse of a to-many", () => {
      LocalDatabase.putRow(LABEL, {id: "l1", name: "urgent"});
      message("m1", null, "added", 1);
      message("m2", null, "removed", 2);
      LocalDatabase.replaceFacts(LABEL, "messages", "l1", ["m2"]);

      pushed(
        {
          id: "m1",
          op: "add_relationship",
          relationship: "labels",
          target_id: "l1",
          type: MESSAGE,
        },
        {
          id: "m2",
          op: "delete_relationship",
          relationship: "labels",
          target_id: "l1",
          type: MESSAGE,
        },
      );

      const [urgent] = QueryKernel.run(node(LABEL, {messages: node(MESSAGE)}));

      assert.deepEqual(bodies(urgent.includes.messages), ["added"]);
    });

    it("drops a related row a pending delete takes away from an inverse of a to-many", () => {
      LocalDatabase.putRow(LABEL, {id: "l1", name: "urgent"});
      message("m1", null, "deleted", 1);
      message("m2", null, "kept", 2);
      LocalDatabase.replaceFacts(LABEL, "messages", "l1", ["m1", "m2"]);

      pushed({id: "m1", op: "delete", type: MESSAGE});

      const [urgent] = QueryKernel.run(node(LABEL, {messages: node(MESSAGE)}));

      assert.deepEqual(bodies(urgent.includes.messages), ["kept"]);
    });

    it("drops a related row a pending delete takes away", () => {
      message("m1", "c1", "deleted", 1);

      pushed({id: "m1", op: "delete", type: MESSAGE});

      const [general] = QueryKernel.run(
        node(CHANNEL, {messages: messagesTerm()}),
      );

      assert.deepEqual(general.includes.messages, []);
    });
  });

  // Mirrors the interpreter's "run/3 - comparing attributes" describe case for case.
  describe("matches() - comparing attributes", () => {
    const BOOKING = "MyApp.Booking";

    const accounts = {
      ada: {count: 1, id: "a1", priority: 3, rating: 1.5, username: "ada"},
      bob: {count: 5, id: "a2", priority: 5, rating: 4.5, username: "bob"},
      cleo: {
        count: 9,
        id: "a3",
        priority: null,
        rating: null,
        username: "cleo",
      },
      dan: {count: 2, id: "a4", priority: 1, rating: 2.0, username: "dan"},
    };

    const namesMatching = (filter, context) =>
      Object.values(accounts)
        .filter((row) => matches(row, filter, context))
        .map((row) => row.username);

    const idsMatching = (rows, filter, entityType = null) =>
      rows
        .filter((row) => matches(row, filter, {}, entityType))
        .map((row) => row.id);

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [BOOKING]: {
            attributes: {id: "uuid", level: "enum", priority: "enum"},
            enumValues: {
              level: ["low", "medium", "high"],
              priority: ["low", "medium", "high"],
            },
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
    });

    it("matches rows whose attribute is below another", () => {
      assert.deepEqual(
        namesMatching([["count", "<", {attribute: "priority"}]]),
        ["ada"],
      );
    });

    it("matches rows whose attribute is at or above another", () => {
      assert.deepEqual(
        namesMatching([["count", ">=", {attribute: "priority"}]]),
        ["bob", "dan"],
      );
    });

    it("matches rows whose attributes are equal", () => {
      assert.deepEqual(
        namesMatching([["count", "==", {attribute: "priority"}]]),
        ["bob"],
      );
    });

    it("matches rows whose attributes differ, a missing one included", () => {
      assert.deepEqual(
        namesMatching([["count", "!=", {attribute: "priority"}]]),
        ["ada", "cleo", "dan"],
      );
    });

    // Cleo has no priority, so no spelling of the comparison reaches her. A missing value reads as
    // 0 here and sorts after a number on the server, so each tier would let one pair of spellings
    // through if it compared the missing value at all - the four keep the two suites alike.
    it("passes over a row missing either side of an ordering comparison", () => {
      assert.deepEqual(
        namesMatching([["count", "<=", {attribute: "priority"}]]),
        ["ada", "bob"],
      );

      assert.deepEqual(
        namesMatching([["priority", ">=", {attribute: "count"}]]),
        ["ada", "bob"],
      );

      assert.deepEqual(
        namesMatching([["count", ">=", {attribute: "priority"}]]),
        ["bob", "dan"],
      );

      assert.deepEqual(
        namesMatching([["priority", "<=", {attribute: "count"}]]),
        ["bob", "dan"],
      );
    });

    it("matches two missing attributes as equal", () => {
      const rows = [
        {ends_on: null, id: "unset", starts_on: null},
        {ends_on: null, id: "half_set", starts_on: "2026-03-01"},
        {ends_on: "2026-03-01", id: "both_set", starts_on: "2026-03-01"},
      ];

      assert.deepEqual(
        idsMatching(rows, [["starts_on", "==", {attribute: "ends_on"}]]),
        ["unset", "both_set"],
      );

      assert.deepEqual(
        idsMatching(rows, [["starts_on", "!=", {attribute: "ends_on"}]]),
        ["half_set"],
      );
    });

    it("compares two dates", () => {
      const rows = [
        {ends_on: "2026-03-01", id: "reversed", starts_on: "2026-03-05"},
        {ends_on: "2026-03-05", id: "ordered", starts_on: "2026-03-01"},
      ];

      assert.deepEqual(
        idsMatching(rows, [["ends_on", "<", {attribute: "starts_on"}]]),
        ["reversed"],
      );
    });

    it("compares an integer with a float", () => {
      assert.deepEqual(namesMatching([["count", "<", {attribute: "rating"}]]), [
        "ada",
      ]);

      assert.deepEqual(
        namesMatching([["count", "==", {attribute: "rating"}]]),
        ["dan"],
      );
    });

    // Declared order, not label order: "high" is after "medium" in the declared list and before it
    // as a string, so a label comparison would match nothing here.
    it("compares two enums by their declared position", () => {
      const rows = [
        {id: "above", level: "high", priority: "medium"},
        {id: "below", level: "low", priority: "medium"},
        {id: "level", level: "medium", priority: "medium"},
      ];

      assert.deepEqual(
        idsMatching(rows, [["level", ">", {attribute: "priority"}]], BOOKING),
        ["above"],
      );

      assert.deepEqual(
        idsMatching(rows, [["level", "<=", {attribute: "priority"}]], BOOKING),
        ["below", "level"],
      );
    });

    // Mango and mango share a key, so the values settle it - and Łódź folds to lodz, before m.
    it("compares two strings by their keys, then by their values", () => {
      const rows = [
        {
          bio: "mango",
          bio_sort: "mango",
          id: "Mango",
          username: "Mango",
          username_sort: "mango",
        },
        {
          bio: "apple",
          bio_sort: "apple",
          id: "Zebra",
          username: "Zebra",
          username_sort: "zebra",
        },
        {
          bio: "m",
          bio_sort: "m",
          id: "Łódź",
          username: "Łódź",
          username_sort: "lodz",
        },
      ];

      assert.deepEqual(
        idsMatching(rows, [["username", "<", {attribute: "bio"}]]),
        ["Mango", "Łódź"],
      );

      assert.deepEqual(
        idsMatching(rows, [["username", ">", {attribute: "bio"}]]),
        ["Zebra"],
      );
    });

    it("matches an attribute comparison inside an alternative", () => {
      const filter = [
        {
          or: [
            [["count", "<", {attribute: "priority"}]],
            [["username", "==", "cleo"]],
          ],
        },
      ];

      assert.deepEqual(namesMatching(filter), ["ada", "cleo"]);
    });

    it("binds a placeholder beside an attribute comparison", () => {
      const filter = [
        ["count", ">=", {attribute: "priority"}],
        ["username", "==", {placeholder: "name"}],
      ];

      assert.deepEqual(namesMatching(filter, {bindings: {name: "dan"}}), [
        "dan",
      ]);
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

    // Compared as labels, "high" sorts before "medium" and would drop out - so only the ranks the
    // alternative's predicate is collected for keep it.
    it("compares an enum inside an alternative by its declared position", () => {
      const filter = [
        {or: [[["priority", ">=", "medium"]], [["title", "==", "d"]]]},
      ];

      assert.deepEqual(titlesMatching(filter), ["a", "b", "d"]);
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

  // Mirrors the reference's "run/3 - comparing strings" case for case: a bound is a position in
  // the list `sort` renders, and the key beside the value is what puts it there.
  describe("matches() - comparing strings", () => {
    const rows = [
      {id: "t1", title: "Zürich", title_sort: "zurich"},
      {id: "t2", title: "Łódź", title_sort: "lodz"},
      {id: "t3", title: "apple", title_sort: "apple"},
      {id: "t4", title: "Mango", title_sort: "mango"},
      {id: "t5", title: "Zebra", title_sort: "zebra"},
      {id: "t6", title: "zebra", title_sort: "zebra"},
    ];

    const titlesMatching = (filter) =>
      rows
        .filter((row) => matches(row, filter))
        .map((row) => row.title)
        .sort();

    it("matches values at or after a bound by their key", () => {
      assert.deepStrictEqual(titlesMatching([["title", ">=", "m"]]), [
        "Mango",
        "Zebra",
        "Zürich",
        "zebra",
      ]);
    });

    it("matches values before a bound by their key", () => {
      assert.deepStrictEqual(titlesMatching([["title", "<", "m"]]), [
        "apple",
        "Łódź",
      ]);
    });

    it("settles a bound that shares a key by the value itself", () => {
      assert.deepStrictEqual(titlesMatching([["title", ">", "Zebra"]]), [
        "Zürich",
        "zebra",
      ]);
    });

    it("passes over an unset string", () => {
      const row = {id: "t7", title: null, title_sort: null};

      assert.isFalse(matches(row, [["title", ">=", "a"]]));
    });

    // No key beside the value means the attribute is not a string, so the comparison is the
    // ordinary one - an integer never grows a companion.
    it("compares a value carrying no key raw", () => {
      const row = {id: "t8", position: 7};

      assert.isTrue(matches(row, [["position", ">=", 3]]));
      assert.isFalse(matches(row, [["position", ">=", 9]]));
    });
  });

  // A row the session may not read never reaches its database, so a row the database lacks covers
  // both a row that is not there and one the session may not see.
  describe("matches() - paths", () => {
    const CHANNEL = "MyApp.Channel";
    const MESSAGE = "MyApp.Message";
    const ORG = "MyApp.Org";

    const messages = [
      {channel_id: "c1", created_on: "2026-02-01", id: "m1"},
      {channel_id: "c2", created_on: "2025-12-01", id: "m2"},
      {channel_id: null, created_on: "2026-02-01", id: "m3"},
      {channel_id: "gone", created_on: "2026-02-01", id: "m4"},
    ];

    const idsMatching = (filter, context = {}, rows = messages) =>
      rows
        .filter((row) => matches(row, filter, context, MESSAGE))
        .map((row) => row.id);

    beforeEach(() => {
      globalThis.Hologram.sync = {
        model: {
          [CHANNEL]: {
            attributes: {
              archived: "boolean",
              id: "uuid",
              kind: "enum",
              name: "string",
              opened_on: "date",
              rank: "integer",
              weight: "integer",
            },
            // Out of alphabetical order, so only the declared positions answer a comparison.
            enumValues: {kind: ["public", "group", "dm"]},
            relationships: {org: {toMany: false, type: ORG}},
            serverOnly: [],
          },
          [MESSAGE]: {
            attributes: {created_on: "date", id: "uuid"},
            enumValues: {},
            relationships: {channel: {toMany: false, type: CHANNEL}},
            serverOnly: [],
          },
          [ORG]: {
            attributes: {id: "uuid", name: "string"},
            enumValues: {},
            relationships: {},
            serverOnly: [],
          },
        },
      };

      Model.reset();
      LocalDatabase.reset();

      LocalDatabase.putRow(CHANNEL, {
        archived: false,
        id: "c1",
        kind: "group",
        name: "Mango",
        name_sort: "mango",
        opened_on: "2026-01-01",
        org_id: "o1",
        rank: 5,
        weight: 9,
      });

      LocalDatabase.putRow(CHANNEL, {
        archived: true,
        id: "c2",
        kind: "dm",
        name: "apple",
        name_sort: "apple",
        opened_on: null,
        org_id: null,
        rank: 1,
        weight: 0,
      });

      LocalDatabase.putRow(ORG, {id: "o1", name: "acme", name_sort: "acme"});
    });

    afterEach(() => {
      LocalDatabase.reset();
    });

    it("matches a value one hop away", () => {
      assert.deepStrictEqual(
        idsMatching([[["channel", "archived"], "==", false]]),
        ["m1"],
      );
    });

    it("matches a value two hops away", () => {
      assert.deepStrictEqual(
        idsMatching([[["channel", "org", "name"], "==", "acme"]]),
        ["m1"],
      );
    });

    it("compares a path's enum by its declared position", () => {
      assert.deepStrictEqual(
        idsMatching([[["channel", "kind"], ">=", "group"]]),
        ["m1", "m2"],
      );
    });

    it("compares a path's date", () => {
      assert.deepStrictEqual(
        idsMatching([[["channel", "opened_on"], "<", "2026-06-01"]]),
        ["m1"],
      );
    });

    it("compares a path's string by its sort key", () => {
      assert.deepStrictEqual(idsMatching([[["channel", "name"], ">=", "M"]]), [
        "m1",
      ]);
    });

    it("compares a path with an attribute of the row", () => {
      assert.deepStrictEqual(
        idsMatching([
          ["created_on", ">", {attribute: ["channel", "opened_on"]}],
        ]),
        ["m1"],
      );
    });

    // m3 and m4 read nothing on either side - equal, the way two missing attributes of a row are,
    // and never ordered.
    it("compares two paths", () => {
      assert.deepStrictEqual(
        idsMatching([
          [["channel", "rank"], "==", {attribute: ["channel", "weight"]}],
        ]),
        ["m3", "m4"],
      );

      assert.deepStrictEqual(
        idsMatching([
          [["channel", "rank"], "<", {attribute: ["channel", "weight"]}],
        ]),
        ["m1"],
      );
    });

    it("binds a placeholder on a path", () => {
      const context = {bindings: {kind: "dm"}};

      assert.deepStrictEqual(
        idsMatching(
          [[["channel", "kind"], "==", {placeholder: "kind"}]],
          context,
        ),
        ["m2"],
      );
    });

    it("matches a path inside an alternative", () => {
      const filter = [
        {
          or: [
            [[["channel", "archived"], "==", true]],
            [["channel_id", "==", null]],
          ],
        },
      ];

      assert.deepStrictEqual(idsMatching(filter), ["m2", "m3"]);
    });

    // m3 has no channel, so a path through it reads as missing, and each operator answers for it
    // what it answers for an attribute that holds nothing.
    it("passes a path through an empty relationship to the nil rules", () => {
      const held = messages.filter((row) => row.id !== "m4");

      assert.deepStrictEqual(
        idsMatching([[["channel", "archived"], "!=", false]], {}, held),
        ["m2", "m3"],
      );

      assert.deepStrictEqual(
        idsMatching([[["channel", "archived"], "==", null]], {}, held),
        ["m3"],
      );

      assert.deepStrictEqual(
        idsMatching([[["channel", "archived"], "not_in", [false]]], {}, held),
        ["m2", "m3"],
      );

      assert.deepStrictEqual(
        idsMatching([[["channel", "rank"], ">", 0]], {}, held),
        ["m1", "m2"],
      );
    });

    // m4 names a channel this database does not hold - a fill arrives in pieces - so the path reads
    // as missing there too.
    it("reads a reference to a row the database does not hold as missing", () => {
      const unheld = messages.filter((row) => row.id === "m4");

      assert.deepStrictEqual(
        idsMatching([[["channel", "archived"], "==", null]], {}, unheld),
        ["m4"],
      );

      assert.deepStrictEqual(
        idsMatching([[["channel", "archived"], "==", false]], {}, unheld),
        [],
      );
    });

    it("runs a filter through a path over the rows it holds", () => {
      for (const row of messages) {
        LocalDatabase.putRow(MESSAGE, row);
      }

      const term = {
        cardinality: "set",
        entity: MESSAGE,
        filter: [[["channel", "org", "name"], "==", "acme"]],
        include: {},
        skip: null,
        sort: [["id", "asc"]],
        take: null,
      };

      assert.deepStrictEqual(
        QueryKernel.run(term).map((node) => node.row.id),
        ["m1"],
      );
    });

    it("throws on a path when no entity type is given", () => {
      assert.throws(
        () => matches(messages[0], [[["channel", "archived"], "==", false]]),
        HologramRuntimeError,
        "a filter with a path needs the entity type of the rows it matches",
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

    it("matches an alternative naming who is asking", () => {
      const filter = [
        {or: [[["id", "==", {actor: true}]], [["username", "==", "bob"]]]},
      ];

      assert.deepEqual(matching(filter, {actorUserId: "r1"}), ["ada", "bob"]);
    });

    // The alternative asking about the visitor answers nothing, and the other one still answers.
    it("passes a visitor to the alternative that names nobody", () => {
      const filter = [
        {or: [[["id", "==", {actor: true}]], [["username", "==", "bob"]]]},
      ];

      assert.deepEqual(matching(filter, {actorUserId: null}), ["bob"]);
    });

    it("matches nothing for a visitor when every alternative names them", () => {
      const filter = [
        {or: [[["id", "==", {actor: true}]], [["id", "!=", {actor: true}]]]},
      ];

      assert.deepEqual(matching(filter, {actorUserId: null}), []);
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

  // Mirrors "triples/1" in test/elixir/hologram/query/stage_test.exs.
  describe("triples()", () => {
    it("returns the predicates of a flat filter unchanged", () => {
      const filter = [
        ["a", "==", true],
        ["b", ">=", 3],
      ];

      assert.deepEqual(QueryKernel.triples(filter), filter);
    });

    it("walks nested disjunctions", () => {
      const filter = [
        {
          or: [
            [["a", "==", true], {or: [[["b", "==", 1]], [["b", "==", 2]]]}],
            [["c", "==", "x"]],
          ],
        },
      ];

      assert.deepEqual(QueryKernel.triples(filter), [
        ["a", "==", true],
        ["b", "==", 1],
        ["b", "==", 2],
        ["c", "==", "x"],
      ]);
    });

    it("walks the alternatives of a disjunction in order", () => {
      const filter = [
        {
          or: [
            [["a", "==", true]],
            [
              ["b", ">=", 3],
              ["c", "==", "x"],
            ],
          ],
        },
        ["d", "==", 1],
      ];

      assert.deepEqual(QueryKernel.triples(filter), [
        ["a", "==", true],
        ["b", ">=", 3],
        ["c", "==", "x"],
        ["d", "==", 1],
      ]);
    });
  });
});
