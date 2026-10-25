"use strict";

import {
  assert,
  assertBoxedError,
  contextFixture,
  defineRuntimeGlobals,
} from "../../../support/helpers.mjs";

import Elixir_Hologram_Query_Stage from "../../../../../assets/js/elixir/hologram/query/stage.mjs";
import HologramBoxedError from "../../../../../assets/js/errors/boxed_error.mjs";
import Model from "../../../../../assets/js/model.mjs";
import Type from "../../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors the corresponding describes of test/elixir/hologram/query/stage_test.exs, case for case
// and with the same raise messages. What differs is the term: these stages build the plain term
// the client's kernel evaluates, where the Elixir ones build a boxed map keyed by atoms.
describe("Elixir_Hologram_Query_Stage", () => {
  const BOOKING = "MyApp.Booking";
  const ITEM = "MyApp.Item";
  const PROJECT = "MyApp.Project";
  const TASK = "MyApp.Task";
  const USER = "MyApp.User";
  const VAULT = "MyApp.Vault";

  const booking = Type.alias(BOOKING);
  const project = Type.alias(PROJECT);
  const task = Type.alias(TASK);
  const user = Type.alias(USER);

  const addRelationship = Elixir_Hologram_Query_Stage["add_relationship/3"];
  const authorize = Elixir_Hologram_Query_Stage["authorize/2"];
  const count = Elixir_Hologram_Query_Stage["count/1"];
  const deleteRelationship =
    Elixir_Hologram_Query_Stage["delete_relationship/3"];
  const decrement = Elixir_Hologram_Query_Stage["decrement/3"];
  const increment = Elixir_Hologram_Query_Stage["increment/3"];
  const filter = Elixir_Hologram_Query_Stage["filter/2"];
  const include = Elixir_Hologram_Query_Stage["include/3"];
  const limit = Elixir_Hologram_Query_Stage["limit/2"];
  const normalize = Elixir_Hologram_Query_Stage["normalize/1"];
  const offset = Elixir_Hologram_Query_Stage["offset/2"];
  const one = Elixir_Hologram_Query_Stage["one/1"];
  const orderBy = Elixir_Hologram_Query_Stage["order_by/2"];
  const trust = Elixir_Hologram_Query_Stage["trust/1"];
  const putAttribute = Elixir_Hologram_Query_Stage["put_attribute/2"];
  const putAttributeValue = Elixir_Hologram_Query_Stage["put_attribute/3"];

  const baseTerm = (entityType) => ({
    cardinality: "set",
    entity: entityType,
    filter: [],
    include: {},
    limit: null,
    offset: null,
    orderBy: [],
  });

  const freshTerm = baseTerm(TASK);

  // An or: entry's value - a list of predicate lists, each given as the pairs predicates/1 takes.
  const disjunction = (...alternatives) =>
    Type.list(alternatives.map(predicates));

  // An entity struct as a stage meets one: what a query read, boxed the way every result is.
  const entity = (entityType, row = {}) =>
    Model.box(entityType, {id: "t1", ...row});

  const edgeOps = (struct) =>
    field(field(struct, "__meta__"), "relationship_ops");

  const ops = (struct) => field(field(struct, "__meta__"), "attribute_ops");

  const field = (struct, name) =>
    struct.data[Type.encodeMapKey(Type.atom(name))][1];

  const predicates = (pairs) =>
    Type.list(
      pairs.map(([name, value]) => Type.tuple([Type.atom(name), value])),
    );

  // A builder's sub-builder is an ordinary Elixir function, so it arrives boxed - what the port
  // calls through the interpreter is what these build.
  const subBuilder = (build) =>
    Type.anonymousFunction(
      1,
      [
        {
          params: (_context) => [Type.variablePattern("related_query")],
          guards: [],
          body: (context) => build(context.vars.related_query),
        },
      ],
      contextFixture(),
    );

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        // The pairs an attribute comparison is checked over, a type of its own rather than more
        // attributes on TASK, whose known-name lists four assertions already pin.
        [BOOKING]: {
          attributes: {
            capacity: "integer",
            check_in: "date",
            check_out: "date",
            created_at: "datetime",
            guests: "integer",
            held_at: "datetime",
            id: "uuid",
            level: "enum",
            name: "string",
            note: "string",
            priority: "enum",
            rating: "float",
            tier: "enum",
            updated_at: "datetime",
          },
          enumValues: {
            level: ["low", "medium", "high"],
            priority: ["low", "medium", "high"],
            tier: ["low", "high"],
          },
          relationships: {
            assignee: {toMany: false, type: USER},
            owner: {toMany: false, type: USER},
          },
          serverOnly: [],
        },
        // A counter type of its own rather than another attribute on TASK, whose known-name lists
        // four assertions already pin: count is a counter, priority is an optional integer and so
        // is not, and bio is there to be refused for its type.
        [ITEM]: {
          attributes: {
            bio: "string",
            count: "integer",
            created_at: "datetime",
            id: "uuid",
            priority: "integer",
            updated_at: "datetime",
          },
          constraints: {priority: {optional: true}},
          enumValues: {},
          relationships: {},
          serverOnly: [],
        },
        [PROJECT]: {
          attributes: {id: "uuid", name: "string"},
          operations: [
            "archive",
            "create",
            "delete",
            "grant_role",
            "publish",
            "read",
            "read_roles",
            "revoke_role",
            "update",
          ],
          relationships: {
            owner: {toMany: false, type: "MyApp.User"},
            tasks: {toMany: true, type: TASK},
          },
          serverOnly: [],
        },
        [TASK]: {
          attributes: {
            created_at: "datetime",
            done: "boolean",
            due_on: "date",
            id: "uuid",
            position: "integer",
            starts_at: "time",
            status: "enum",
            title: "string",
          },
          enumValues: {status: ["open", "blocked", "done"]},
          relationships: {},
          serverOnly: [],
        },
        // A counter the client is never shown, which reads back as the sentinel rather than as a
        // number it happens not to have.
        [VAULT]: {
          attributes: {balance: "integer", id: "uuid"},
          enumValues: {},
          relationships: {},
          serverOnly: ["balance"],
        },
        // A path ends at one of these - an enum, an integer, a boolean and a date pair beside the
        // string and the id the user stages read.
        [USER]: {
          attributes: {
            active: "boolean",
            email: "string",
            ends_on: "date",
            id: "uuid",
            level: "enum",
            logins: "integer",
            starts_on: "date",
          },
          enumValues: {level: ["low", "medium", "high"]},
          relationships: {
            manager: {toMany: false, type: USER},
            projects: {toMany: true, type: PROJECT},
          },
          serverOnly: [],
        },
      },
    };

    // Model reads an entry once and keeps it, so the model installed above is only what these
    // stages see if the entries another suite left behind go first - and the suites share these
    // type names while spelling them differently.
    Model.reset();
  });

  describe("add_relationship/3", () => {
    const edge = (name, targetId, op) =>
      Type.map([
        [
          Type.tuple([Type.atom(name), Type.bitstring(targetId)]),
          Type.atom(op),
        ],
      ]);

    it("keeps the rest of the metadata", () => {
      const built = putAttribute(
        entity(PROJECT),
        predicates([["name", Type.bitstring("x")]]),
      );

      const result = addRelationship(
        built,
        Type.atom("tasks"),
        Type.bitstring("t1"),
      );

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("name"),
            Type.tuple([Type.atom("put"), Type.bitstring("x")]),
          ],
        ]),
      );

      assert.deepStrictEqual(edgeOps(result), edge("tasks", "t1", "add"));
    });

    it("leaves the relationship's own field as it is", () => {
      const built = entity(PROJECT);

      const result = addRelationship(
        built,
        Type.atom("tasks"),
        Type.bitstring("t1"),
      );

      assert.deepStrictEqual(field(result, "tasks"), field(built, "tasks"));
    });

    it("records an add operation for the edge", () => {
      const result = addRelationship(
        entity(PROJECT),
        Type.atom("tasks"),
        Type.bitstring("t1"),
      );

      assert.deepStrictEqual(edgeOps(result), edge("tasks", "t1", "add"));
    });

    it("records one operation per edge, several edges coexisting", () => {
      const result = addRelationship(
        addRelationship(
          entity(PROJECT),
          Type.atom("tasks"),
          Type.bitstring("t1"),
        ),
        Type.atom("tasks"),
        Type.bitstring("t2"),
      );

      assert.deepStrictEqual(
        edgeOps(result),
        Type.map([
          [
            Type.tuple([Type.atom("tasks"), Type.bitstring("t1")]),
            Type.atom("add"),
          ],
          [
            Type.tuple([Type.atom("tasks"), Type.bitstring("t2")]),
            Type.atom("add"),
          ],
        ]),
      );
    });

    it("replaces a delete operation recorded for the same edge", () => {
      const result = addRelationship(
        deleteRelationship(
          entity(PROJECT),
          Type.atom("tasks"),
          Type.bitstring("t1"),
        ),
        Type.atom("tasks"),
        Type.bitstring("t1"),
      );

      assert.deepStrictEqual(edgeOps(result), edge("tasks", "t1", "add"));
    });

    it("raises on a to-one relationship name", () => {
      assert.throw(
        () =>
          addRelationship(
            entity(PROJECT),
            Type.atom("owner"),
            Type.bitstring("u1"),
          ),
        HologramBoxedError,
        ":owner is a to-one relationship in MyApp.Project - only to-many relationships hold edges - set its reference via put_attribute(:owner_id, id)",
      );
    });

    it("raises on an attribute name", () => {
      assert.throw(
        () =>
          addRelationship(
            entity(PROJECT),
            Type.atom("name"),
            Type.bitstring("t1"),
          ),
        HologramBoxedError,
        ":name is an attribute in MyApp.Project - only to-many relationships hold edges - put it via put_attribute",
      );
    });

    it("raises on an unknown relationship name", () => {
      assert.throw(
        () =>
          addRelationship(
            entity(PROJECT),
            Type.atom("nope"),
            Type.bitstring("t1"),
          ),
        HologramBoxedError,
        "unknown relationship :nope in MyApp.Project - known to-many relationships: :tasks",
      );
    });

    it("raises when the entity is not an entity struct", () => {
      assert.throw(
        () =>
          addRelationship(
            Type.bitstring("x"),
            Type.atom("tasks"),
            Type.bitstring("t1"),
          ),
        HologramBoxedError,
        'add_relationship takes an entity struct, got: "x"',
      );
    });

    it("raises when the target id is not a string", () => {
      assert.throw(
        () =>
          addRelationship(
            entity(PROJECT),
            Type.atom("tasks"),
            Type.integer(123),
          ),
        HologramBoxedError,
        "add_relationship takes a target id string, got: 123",
      );
    });
  });

  describe("delete_relationship/3", () => {
    const edge = (name, targetId, op) =>
      Type.map([
        [
          Type.tuple([Type.atom(name), Type.bitstring(targetId)]),
          Type.atom(op),
        ],
      ]);

    it("records a delete operation for the edge", () => {
      const result = deleteRelationship(
        entity(PROJECT),
        Type.atom("tasks"),
        Type.bitstring("t1"),
      );

      assert.deepStrictEqual(edgeOps(result), edge("tasks", "t1", "delete"));
    });

    it("replaces an add operation recorded for the same edge", () => {
      const result = deleteRelationship(
        addRelationship(
          entity(PROJECT),
          Type.atom("tasks"),
          Type.bitstring("t1"),
        ),
        Type.atom("tasks"),
        Type.bitstring("t1"),
      );

      assert.deepStrictEqual(edgeOps(result), edge("tasks", "t1", "delete"));
    });

    it("raises on a to-one relationship name", () => {
      assert.throw(
        () =>
          deleteRelationship(
            entity(PROJECT),
            Type.atom("owner"),
            Type.bitstring("u1"),
          ),
        HologramBoxedError,
        ":owner is a to-one relationship in MyApp.Project - only to-many relationships hold edges - set its reference via put_attribute(:owner_id, id)",
      );
    });

    it("raises when the entity is not an entity struct", () => {
      assert.throw(
        () =>
          deleteRelationship(
            Type.bitstring("x"),
            Type.atom("tasks"),
            Type.bitstring("t1"),
          ),
        HologramBoxedError,
        'delete_relationship takes an entity struct, got: "x"',
      );
    });

    it("raises when the target id is not a string", () => {
      assert.throw(
        () =>
          deleteRelationship(
            entity(PROJECT),
            Type.atom("tasks"),
            Type.integer(123),
          ),
        HologramBoxedError,
        "delete_relationship takes a target id string, got: 123",
      );
    });
  });

  describe("increment/3", () => {
    const item = (count = 5) => entity(ITEM, {bio: "x", count, priority: null});

    it("records a positive amount as a delta", () => {
      assert.deepStrictEqual(
        ops(increment(item(), Type.atom("count"), Type.integer(2))),
        Type.map([
          [
            Type.atom("count"),
            Type.tuple([Type.atom("increment"), Type.integer(2)]),
          ],
        ]),
      );
    });

    it("previews the result on the struct's field", () => {
      const result = increment(item(), Type.atom("count"), Type.integer(2));

      assert.deepStrictEqual(field(result, "count"), Type.integer(7));
    });

    it("previews a second move on top of the first", () => {
      const result = decrement(
        increment(item(), Type.atom("count"), Type.integer(2)),
        Type.atom("count"),
        Type.integer(1),
      );

      assert.deepStrictEqual(field(result, "count"), Type.integer(6));
    });

    it("moves down by a negative amount", () => {
      assert.deepStrictEqual(
        ops(increment(item(), Type.atom("count"), Type.integer(-2))),
        Type.map([
          [
            Type.atom("count"),
            Type.tuple([Type.atom("increment"), Type.integer(-2)]),
          ],
        ]),
      );
    });

    it("records nothing for a zero amount", () => {
      assert.deepStrictEqual(
        ops(increment(item(), Type.atom("count"), Type.integer(0))),
        Type.map([]),
      );
    });

    it("adds a second increment to the first", () => {
      const result = increment(
        increment(item(), Type.atom("count"), Type.integer(2)),
        Type.atom("count"),
        Type.integer(3),
      );

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("count"),
            Type.tuple([Type.atom("increment"), Type.integer(5)]),
          ],
        ]),
      );
    });

    it("keeps the rest of the metadata", () => {
      const result = increment(
        putAttribute(item(), predicates([["bio", Type.bitstring("y")]])),
        Type.atom("count"),
        Type.integer(1),
      );

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("bio"),
            Type.tuple([Type.atom("put"), Type.bitstring("y")]),
          ],
          [
            Type.atom("count"),
            Type.tuple([Type.atom("increment"), Type.integer(1)]),
          ],
        ]),
      );
    });

    it("folds into a put value recorded before it", () => {
      const result = increment(
        putAttribute(item(), predicates([["count", Type.integer(10)]])),
        Type.atom("count"),
        Type.integer(1),
      );

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("count"),
            Type.tuple([Type.atom("put"), Type.integer(11)]),
          ],
        ]),
      );

      assert.deepStrictEqual(field(result, "count"), Type.integer(11));
    });

    it("raises on an amount that is not an integer", () => {
      assert.throw(
        () => increment(item(), Type.atom("count"), Type.float(1.5)),
        HologramBoxedError,
        "increment takes an integer amount, got: 1.5",
      );

      assert.throw(
        () => increment(item(), Type.atom("count"), Type.bitstring("1")),
        HologramBoxedError,
        'increment takes an integer amount, got: "1"',
      );
    });

    it("raises on an optional integer attribute", () => {
      assert.throw(
        () => increment(item(), Type.atom("priority"), Type.integer(1)),
        HologramBoxedError,
        ":priority in MyApp.Item is optional and can hold nil - increment moves attributes that always hold a number - declare it without optional: true, with a default",
      );
    });

    it("raises on a non-integer attribute", () => {
      assert.throw(
        () => increment(item(), Type.atom("bio"), Type.integer(1)),
        HologramBoxedError,
        ":bio is a :string attribute of MyApp.Item - increment moves integer attributes only",
      );
    });

    it("raises on a relationship", () => {
      assert.throw(
        () => increment(entity(PROJECT), Type.atom("owner"), Type.integer(1)),
        HologramBoxedError,
        ":owner is a relationship in MyApp.Project - increment moves integer attributes only",
      );
    });

    it("raises on a system attribute", () => {
      assert.throw(
        () => increment(item(), Type.atom("id"), Type.integer(1)),
        HologramBoxedError,
        ":id is a system attribute of MyApp.Item - it is managed automatically and can't be moved",
      );
    });

    it("raises on an unknown name", () => {
      assert.throw(
        () => increment(item(), Type.atom("nope"), Type.integer(1)),
        HologramBoxedError,
        "unknown attribute :nope in MyApp.Item - known counters: :count",
      );
    });

    it("raises when the entity is not an entity struct", () => {
      assert.throw(
        () =>
          increment(Type.bitstring("x"), Type.atom("count"), Type.integer(1)),
        HologramBoxedError,
        'increment takes an entity struct, got: "x"',
      );
    });

    it("raises when the struct's field holds nil", () => {
      assert.throw(
        () =>
          increment(
            entity(ITEM, {bio: "x", count: null, priority: null}),
            Type.atom("count"),
            Type.integer(1),
          ),
        HologramBoxedError,
        ":count in MyApp.Item holds nil - a counter always holds a number, so there is nothing for increment to move - read the row first, or give the attribute a default",
      );
    });

    // Not the same refusal: reading the row is what the message above tells a caller to do, and no
    // read produces this value on this tier.
    it("raises when the counter is one the client is never shown", () => {
      assert.throw(
        () => increment(entity(VAULT), Type.atom("balance"), Type.integer(1)),
        HologramBoxedError,
        ":balance of MyApp.Vault is server-only - a browser cannot write it, set it in a command or a job",
      );
    });

    it("raises when the put value it would fold into is not an integer", () => {
      assert.throw(
        () =>
          increment(
            putAttribute(item(), predicates([["count", Type.nil()]])),
            Type.atom("count"),
            Type.integer(1),
          ),
        HologramBoxedError,
        ":count in MyApp.Item carries a put value that is not an integer (nil) - increment cannot move it",
      );
    });
  });

  describe("decrement/3", () => {
    const item = (count = 5) => entity(ITEM, {bio: "x", count, priority: null});

    it("records a positive amount as a negative delta", () => {
      assert.deepStrictEqual(
        ops(decrement(item(), Type.atom("count"), Type.integer(2))),
        Type.map([
          [
            Type.atom("count"),
            Type.tuple([Type.atom("increment"), Type.integer(-2)]),
          ],
        ]),
      );
    });

    it("subtracts from a recorded increment", () => {
      const result = decrement(
        increment(item(), Type.atom("count"), Type.integer(5)),
        Type.atom("count"),
        Type.integer(2),
      );

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("count"),
            Type.tuple([Type.atom("increment"), Type.integer(3)]),
          ],
        ]),
      );
    });

    it("drops a delta that nets to zero", () => {
      const result = decrement(
        increment(item(), Type.atom("count"), Type.integer(2)),
        Type.atom("count"),
        Type.integer(2),
      );

      assert.deepStrictEqual(ops(result), Type.map([]));
    });

    it("raises on an amount that is not a positive integer", () => {
      for (const [amount, spelled] of [
        [Type.integer(-1), "-1"],
        [Type.integer(0), "0"],
        [Type.float(1.5), "1.5"],
      ]) {
        assert.throw(
          () => decrement(item(), Type.atom("count"), amount),
          HologramBoxedError,
          `decrement takes a positive integer amount, got: ${spelled}`,
        );
      }
    });

    it("raises on a non-integer attribute", () => {
      assert.throw(
        () => decrement(item(), Type.atom("bio"), Type.integer(1)),
        HologramBoxedError,
        ":bio is a :string attribute of MyApp.Item - decrement moves integer attributes only",
      );
    });
  });

  describe("put_attribute/2", () => {
    it("accepts a map of values", () => {
      const result = putAttribute(
        entity(TASK),
        Type.map([[Type.atom("position"), Type.integer(7)]]),
      );

      assert.deepStrictEqual(field(result, "position"), Type.integer(7));

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("position"),
            Type.tuple([Type.atom("put"), Type.integer(7)]),
          ],
        ]),
      );
    });

    it("keeps the rest of the metadata", () => {
      const built = entity(TASK);
      const metadata = field(built, "__meta__");

      metadata.data[Type.encodeMapKey(Type.atom("claim"))] = [
        Type.atom("claim"),
        Type.atom("trust"),
      ];

      const result = putAttribute(
        built,
        predicates([["title", Type.bitstring("x")]]),
      );

      assert.deepStrictEqual(
        field(field(result, "__meta__"), "claim"),
        Type.atom("trust"),
      );
    });

    it("merges into the changes already recorded, the later value replacing the earlier", () => {
      const result = putAttribute(
        putAttribute(
          entity(TASK),
          predicates([
            ["done", Type.boolean(true)],
            ["title", Type.bitstring("y")],
          ]),
        ),
        predicates([["title", Type.bitstring("z")]]),
      );

      assert.deepStrictEqual(field(result, "title"), Type.bitstring("z"));

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("done"),
            Type.tuple([Type.atom("put"), Type.boolean(true)]),
          ],
          [
            Type.atom("title"),
            Type.tuple([Type.atom("put"), Type.bitstring("z")]),
          ],
        ]),
      );
    });

    it("sets a to-one reference field", () => {
      const result = putAttribute(
        entity(PROJECT),
        predicates([["owner_id", Type.bitstring("u1")]]),
      );

      assert.deepStrictEqual(field(result, "owner_id"), Type.bitstring("u1"));
    });

    it("sets the values on the struct and records them as changes", () => {
      const result = putAttribute(
        entity(TASK),
        predicates([
          ["done", Type.boolean(true)],
          ["title", Type.bitstring("y")],
        ]),
      );

      assert.deepStrictEqual(field(result, "done"), Type.boolean(true));
      assert.deepStrictEqual(field(result, "title"), Type.bitstring("y"));
    });

    it("takes the later value when one list names an attribute twice", () => {
      const result = putAttribute(
        entity(TASK),
        predicates([
          ["title", Type.bitstring("first")],
          ["title", Type.bitstring("second")],
        ]),
      );

      assert.deepStrictEqual(field(result, "title"), Type.bitstring("second"));

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("title"),
            Type.tuple([Type.atom("put"), Type.bitstring("second")]),
          ],
        ]),
      );
    });

    it("leaves the struct it was given alone", () => {
      const built = entity(TASK, {title: "Draft copy"});

      putAttribute(built, predicates([["title", Type.bitstring("Ship it")]]));

      assert.deepStrictEqual(
        field(built, "title"),
        Type.bitstring("Draft copy"),
      );
    });

    it("raises on a system attribute name", () => {
      assert.throw(
        () =>
          putAttribute(entity(TASK), predicates([["id", Type.bitstring("x")]])),
        HologramBoxedError,
        ":id is a system attribute of MyApp.Task - it is managed automatically and can't be put",
      );
    });

    it("raises on a to-many relationship name", () => {
      assert.throw(
        () =>
          putAttribute(entity(PROJECT), predicates([["tasks", Type.list()]])),
        HologramBoxedError,
        ":tasks is a relationship in MyApp.Project - only attributes can be put - add its edges via add_relationship",
      );
    });

    it("raises on a to-one relationship name", () => {
      assert.throw(
        () =>
          putAttribute(entity(PROJECT), predicates([["owner", Type.nil()]])),
        HologramBoxedError,
        ":owner is a relationship in MyApp.Project - only attributes can be put - set its reference via :owner_id",
      );
    });

    it("raises on an unknown name", () => {
      assert.throw(
        () =>
          putAttribute(
            entity(PROJECT),
            predicates([["nope", Type.integer(1)]]),
          ),
        HologramBoxedError,
        "unknown attribute :nope in MyApp.Project - known attributes: :name, :owner_id",
      );
    });

    it("raises when the entity is not an entity struct", () => {
      assert.throw(
        () => putAttribute(Type.bitstring("x"), predicates([])),
        HologramBoxedError,
        'put_attribute takes an entity struct, got: "x"',
      );

      assert.throw(
        () => putAttribute(task, predicates([])),
        HologramBoxedError,
        "put_attribute takes an entity struct, got: MyApp.Task",
      );
    });

    it("raises when the values are neither a keyword list nor a map", () => {
      assert.throw(
        () =>
          putAttribute(
            entity(TASK),
            Type.list([Type.integer(1), Type.integer(2)]),
          ),
        HologramBoxedError,
        "put_attribute takes a keyword list or a map of attribute values, got: [1, 2]",
      );
    });
  });

  describe("put_attribute/3", () => {
    it("sets the value on the struct and records it as a change", () => {
      const result = putAttributeValue(
        entity(TASK),
        Type.atom("done"),
        Type.boolean(true),
      );

      assert.deepStrictEqual(field(result, "done"), Type.boolean(true));

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("done"),
            Type.tuple([Type.atom("put"), Type.boolean(true)]),
          ],
        ]),
      );
    });

    it("raises on an unknown name", () => {
      assert.throw(
        () =>
          putAttributeValue(entity(TASK), Type.atom("nope"), Type.integer(1)),
        HologramBoxedError,
        "unknown attribute :nope in MyApp.Task - known attributes: :done, :due_on, :position, :starts_at, :status, :title",
      );
    });
  });

  describe("authorize/2", () => {
    const claim = (struct) => field(field(struct, "__meta__"), "claim");

    it("keeps the rest of the metadata", () => {
      const result = authorize(
        addRelationship(
          putAttribute(
            entity(PROJECT),
            predicates([["name", Type.bitstring("x")]]),
          ),
          Type.atom("tasks"),
          Type.bitstring("t1"),
        ),
        Type.atom("archive"),
      );

      assert.deepStrictEqual(
        ops(result),
        Type.map([
          [
            Type.atom("name"),
            Type.tuple([Type.atom("put"), Type.bitstring("x")]),
          ],
        ]),
      );

      assert.deepStrictEqual(
        edgeOps(result),
        Type.map([
          [
            Type.tuple([Type.atom("tasks"), Type.bitstring("t1")]),
            Type.atom("add"),
          ],
        ]),
      );

      assert.deepStrictEqual(
        claim(result),
        Type.tuple([Type.atom("authorize"), Type.atom("archive")]),
      );
    });

    it("records the claim for the operation", () => {
      const result = authorize(entity(TASK), Type.atom("update"));

      assert.deepStrictEqual(
        claim(result),
        Type.tuple([Type.atom("authorize"), Type.atom("update")]),
      );
    });

    it("records an operation an allow line on the entity type names", () => {
      const result = authorize(entity(PROJECT), Type.atom("archive"));

      assert.deepStrictEqual(
        claim(result),
        Type.tuple([Type.atom("authorize"), Type.atom("archive")]),
      );
    });

    it("raises when the entity is not an entity struct", () => {
      assert.throw(
        () => authorize(Type.bitstring("x"), Type.atom("archive")),
        HologramBoxedError,
        'authorize takes an entity struct, got: "x"',
      );
    });

    it("raises when the operation is not an atom", () => {
      assert.throw(
        () => authorize(entity(TASK), Type.bitstring("archive")),
        HologramBoxedError,
        'authorize takes an operation atom, got: "archive"',
      );
    });

    it("raises when the struct already carries a claim", () => {
      assert.throw(
        () =>
          authorize(
            authorize(entity(TASK), Type.atom("update")),
            Type.atom("delete"),
          ),
        HologramBoxedError,
        "MyApp.Task already carries a claim ({:authorize, :update}) - a write claims exactly one authority",
      );
    });

    it("raises when the operation is one the entity type never declared", () => {
      assertBoxedError(
        () => authorize(entity(TASK), Type.atom("archive")),
        "ArgumentError",
        "unknown operation :archive for MyApp.Task - its allow lines declare no operation of their own, and the framework's own operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update",
      );
    });
  });

  // The server records a claim here and the client refuses one, so these have no twin in
  // query/stage_test.exs. Trust is the SERVER's authority on either half - a write claiming it is
  // refused by the wire, and a read claiming it would ask this client's copy of the data to
  // answer past the policies that decided what it holds.
  describe("trust/1", () => {
    it("refuses an entity struct", () => {
      assert.throw(
        () => trust(entity(TASK)),
        HologramBoxedError,
        "trust is the server's authority - a client cannot claim it",
      );
    });

    it("refuses a query", () => {
      assert.throw(
        () => trust(task),
        HologramBoxedError,
        "trust is the server's authority - a client cannot claim it",
      );
    });

    it("refuses a query term", () => {
      assert.throw(
        () => trust(filter(task, predicates([["done", Type.boolean(true)]]))),
        HologramBoxedError,
        "trust is the server's authority - a client cannot claim it",
      );
    });
  });

  describe("count/1", () => {
    it("marks the query as counting", () => {
      assert.deepStrictEqual(count(task), {...freshTerm, cardinality: "count"});
    });

    it("composes with other stages", () => {
      const query = count(limit(task, Type.integer(50)));

      assert.equal(query.cardinality, "count");
      assert.equal(query.limit, 50);
    });

    it("raises when cardinality is already marked", () => {
      assert.throw(
        () => count(one(task)),
        HologramBoxedError,
        "cardinality is already set to :one",
      );
    });
  });

  describe("filter/2", () => {
    // A path as the lowering hands it over: its names, in order, as a list of atoms.
    const path = (...names) => Type.list(names.map(Type.atom));

    const pathPredicates = (names, value) =>
      Type.list([Type.tuple([path(...names), value])]);

    const range = (first, last, step = 1) =>
      Type.map([
        [Type.atom("__struct__"), Type.alias("Range")],
        [Type.atom("first"), Type.integer(first)],
        [Type.atom("last"), Type.integer(last)],
        [Type.atom("step"), Type.integer(step)],
      ]);

    const placeholder = (name) =>
      Type.map([
        [Type.atom("__struct__"), Type.alias("Hologram.Query.Placeholder")],
        [Type.atom("name"), Type.atom(name)],
      ]);

    // Another attribute of the row, as a bare name on the right side of a comparison lowers to.
    const attribute = (name) =>
      Type.tuple([Type.atom("attribute"), Type.atom(name)]);

    it("reads a bare value as equality", () => {
      const query = filter(
        task,
        predicates([["title", Type.bitstring("Draft")]]),
      );

      assert.deepStrictEqual(query.filter, [["title", "==", "Draft"]]);
    });

    it("reads every operator tuple", () => {
      const query = filter(
        task,
        predicates([
          ["title", Type.tuple([Type.atom("!="), Type.bitstring("Draft")])],
          ["position", Type.tuple([Type.atom(">="), Type.integer(3)])],
        ]),
      );

      assert.deepStrictEqual(query.filter, [
        ["title", "!=", "Draft"],
        ["position", ">=", 3],
      ]);
    });

    it("appends to prior predicates", () => {
      const first = filter(task, predicates([["done", Type.boolean(false)]]));
      const query = filter(
        first,
        predicates([["title", Type.bitstring("Draft")]]),
      );

      assert.deepStrictEqual(query.filter, [
        ["done", "==", false],
        ["title", "==", "Draft"],
      ]);
    });

    it("reads a bare list as membership", () => {
      const values = Type.list([Type.bitstring("a"), Type.bitstring("b")]);
      const query = filter(task, predicates([["title", values]]));

      assert.deepStrictEqual(query.filter, [["title", "in", ["a", "b"]]]);
    });

    it("reads a list of operator tuples as a conjunction", () => {
      const values = Type.list([
        Type.tuple([Type.atom(">="), Type.integer(3)]),
        Type.tuple([Type.atom("<"), Type.integer(9)]),
      ]);

      const query = filter(task, predicates([["position", values]]));

      assert.deepStrictEqual(query.filter, [
        ["position", ">=", 3],
        ["position", "<", 9],
      ]);
    });

    // A range says the same thing about an integer attribute as its two bounds do.
    it("reads a range as its two bounds", () => {
      const query = filter(task, predicates([["position", range(1, 5)]]));

      assert.deepStrictEqual(query.filter, [
        ["position", ">=", 1],
        ["position", "<=", 5],
      ]);
    });

    it("reads a range given to the membership operator the same way", () => {
      const value = Type.tuple([Type.atom("in"), range(1, 5)]);
      const query = filter(task, predicates([["position", value]]));

      assert.deepStrictEqual(query.filter, [
        ["position", ">=", 1],
        ["position", "<=", 5],
      ]);
    });

    // Values leave in the spelling the rows carry, whatever they were written as.
    it("unboxes values into what the rows hold", () => {
      const date = Type.map([
        [Type.atom("__struct__"), Type.alias("Date")],
        [Type.atom("calendar"), Type.alias("Calendar.ISO")],
        [Type.atom("day"), Type.integer(16)],
        [Type.atom("month"), Type.integer(8)],
        [Type.atom("year"), Type.integer(2026)],
      ]);

      const query = filter(
        task,
        predicates([
          ["due_on", Type.tuple([Type.atom(">="), date])],
          ["status", Type.atom("open")],
        ]),
      );

      assert.deepStrictEqual(query.filter, [
        ["due_on", ">=", "2026-08-16"],
        ["status", "==", "open"],
      ]);
    });

    // The declared `values:` list is the order, so a comparison reads it - `{:>, :open}` means
    // every value declared after :open.
    it("builds an ordering triple for an enum attribute", () => {
      const value = Type.tuple([Type.atom(">"), Type.atom("open")]);
      const query = filter(task, predicates([["status", value]]));

      assert.deepStrictEqual(query.filter, [["status", ">", "open"]]);
    });

    // The derived sort key is the order, so a comparison reads it the way `order_by` does - a
    // bound names a position in the list the attribute sorts into.
    it("builds an ordering triple for a string attribute", () => {
      const value = Type.tuple([Type.atom(">"), Type.bitstring("a")]);
      const query = filter(task, predicates([["title", value]]));

      assert.deepStrictEqual(query.filter, [["title", ">", "a"]]);
    });

    // A time of day is orderable like the other temporal types, and leaves in the one spelling
    // the rows carry - six fractional digits whatever the value was written at.
    it("builds an ordering triple for a time attribute", () => {
      const time = Type.map([
        [Type.atom("__struct__"), Type.alias("Time")],
        [Type.atom("calendar"), Type.alias("Calendar.ISO")],
        [Type.atom("hour"), Type.integer(11)],
        [
          Type.atom("microsecond"),
          Type.tuple([Type.integer(0), Type.integer(0)]),
        ],
        [Type.atom("minute"), Type.integer(0)],
        [Type.atom("second"), Type.integer(0)],
      ]);

      const value = Type.tuple([Type.atom(">"), time]);
      const query = filter(task, predicates([["starts_at", value]]));

      assert.deepStrictEqual(query.filter, [
        ["starts_at", ">", "11:00:00.000000"],
      ]);
    });

    it("filters by the reference field of a to-one relationship", () => {
      const query = filter(
        Type.alias(PROJECT),
        predicates([["owner_id", Type.bitstring("u1")]]),
      );

      assert.deepStrictEqual(query.filter, [["owner_id", "==", "u1"]]);
    });

    it("reads a placeholder as the leaf a binding fills", () => {
      const query = filter(
        task,
        predicates([["title", placeholder("chosen")]]),
      );

      assert.deepStrictEqual(query.filter, [
        ["title", "==", {placeholder: "chosen"}],
      ]);
    });

    it("reads a placeholder under an operator", () => {
      const value = Type.tuple([Type.atom(">="), placeholder("min")]);
      const query = filter(task, predicates([["position", value]]));

      assert.deepStrictEqual(query.filter, [
        ["position", ">=", {placeholder: "min"}],
      ]);
    });

    it("reads a placeholder among the values of a membership list", () => {
      const values = Type.list([placeholder("chosen"), Type.bitstring("b")]);
      const value = Type.tuple([Type.atom("in"), values]);
      const query = filter(task, predicates([["title", value]]));

      assert.deepStrictEqual(query.filter, [
        ["title", "in", [{placeholder: "chosen"}, "b"]],
      ]);
    });

    it("reads the actor leaf", () => {
      const value = Type.tuple([Type.atom("actor")]);
      const query = filter(task, predicates([["id", value]]));

      assert.deepStrictEqual(query.filter, [["id", "==", {actor: true}]]);
    });

    it("reads the actor leaf under an equality operator", () => {
      const value = Type.tuple([Type.atom("!="), Type.atom("actor")]);
      const query = filter(task, predicates([["id", value]]));

      assert.deepStrictEqual(query.filter, [["id", "!=", {actor: true}]]);
    });

    it("reads a bare attribute operand as equality", () => {
      const query = filter(
        booking,
        predicates([["guests", attribute("capacity")]]),
      );

      assert.deepStrictEqual(query.filter, [
        ["guests", "==", {attribute: "capacity"}],
      ]);
    });

    it("reads an attribute operand under each comparison operator", () => {
      for (const operator of ["!=", "<", "<=", "==", ">", ">="]) {
        const value = Type.tuple([Type.atom(operator), attribute("capacity")]);
        const query = filter(booking, predicates([["guests", value]]));

        assert.deepStrictEqual(query.filter, [
          ["guests", operator, {attribute: "capacity"}],
        ]);
      }
    });

    it("reads an attribute operand over a date pair", () => {
      const value = Type.tuple([Type.atom("<"), attribute("check_in")]);
      const query = filter(booking, predicates([["check_out", value]]));

      assert.deepStrictEqual(query.filter, [
        ["check_out", "<", {attribute: "check_in"}],
      ]);
    });

    it("reads an attribute operand over a string pair", () => {
      const value = Type.tuple([Type.atom("<"), attribute("note")]);
      const query = filter(booking, predicates([["name", value]]));

      assert.deepStrictEqual(query.filter, [
        ["name", "<", {attribute: "note"}],
      ]);
    });

    it("reads an attribute operand over an enum pair", () => {
      const value = Type.tuple([Type.atom("<"), attribute("priority")]);
      const query = filter(booking, predicates([["level", value]]));

      assert.deepStrictEqual(query.filter, [
        ["level", "<", {attribute: "priority"}],
      ]);
    });

    it("reads an attribute operand over two reference fields", () => {
      const value = Type.tuple([Type.atom("=="), attribute("owner_id")]);
      const query = filter(booking, predicates([["assignee_id", value]]));

      assert.deepStrictEqual(query.filter, [
        ["assignee_id", "==", {attribute: "owner_id"}],
      ]);
    });

    it("reads a system attribute operand", () => {
      const value = Type.tuple([Type.atom(">"), attribute("created_at")]);
      const query = filter(booking, predicates([["updated_at", value]]));

      assert.deepStrictEqual(query.filter, [
        ["updated_at", ">", {attribute: "created_at"}],
      ]);
    });

    it("reads an integer compared with a float", () => {
      const integerFirst = Type.tuple([Type.atom("<"), attribute("rating")]);
      const floatFirst = Type.tuple([Type.atom(">"), attribute("guests")]);

      assert.deepStrictEqual(
        filter(booking, predicates([["guests", integerFirst]])).filter,
        [["guests", "<", {attribute: "rating"}]],
      );

      assert.deepStrictEqual(
        filter(booking, predicates([["rating", floatFirst]])).filter,
        [["rating", ">", {attribute: "guests"}]],
      );
    });

    it("reads a path to an attribute of the related row", () => {
      const query = filter(
        booking,
        pathPredicates(["owner", "email"], Type.bitstring("ada@example.com")),
      );

      assert.deepStrictEqual(query.filter, [
        [["owner", "email"], "==", "ada@example.com"],
      ]);
    });

    it("reads a path through two relationships", () => {
      const query = filter(
        booking,
        pathPredicates(
          ["owner", "manager", "email"],
          Type.bitstring("ada@example.com"),
        ),
      );

      assert.deepStrictEqual(query.filter, [
        [["owner", "manager", "email"], "==", "ada@example.com"],
      ]);
    });

    it("reads a path operand", () => {
      const operand = Type.tuple([
        Type.atom("attribute"),
        path("assignee", "id"),
      ]);

      const query = filter(booking, predicates([["owner_id", operand]]));

      assert.deepStrictEqual(query.filter, [
        ["owner_id", "==", {attribute: ["assignee", "id"]}],
      ]);
    });

    it("reads an ordering comparison on a path to a string attribute", () => {
      const value = Type.tuple([Type.atom(">="), Type.bitstring("m")]);
      const query = filter(booking, pathPredicates(["owner", "email"], value));

      assert.deepStrictEqual(query.filter, [[["owner", "email"], ">=", "m"]]);
    });

    it("reads a membership on a path", () => {
      const value = Type.tuple([
        Type.atom("in"),
        Type.list([Type.bitstring("a"), Type.bitstring("b")]),
      ]);

      const query = filter(booking, pathPredicates(["owner", "email"], value));

      assert.deepStrictEqual(query.filter, [
        [["owner", "email"], "in", ["a", "b"]],
      ]);
    });

    it("reads an attribute triple between two paths", () => {
      const value = Type.tuple([
        Type.atom("<"),
        Type.tuple([Type.atom("attribute"), path("owner", "starts_on")]),
      ]);

      const query = filter(
        booking,
        pathPredicates(["owner", "ends_on"], value),
      );

      assert.deepStrictEqual(query.filter, [
        [["owner", "ends_on"], "<", {attribute: ["owner", "starts_on"]}],
      ]);
    });

    it("reads an ordering comparison on a path to an enum attribute", () => {
      const value = Type.tuple([Type.atom(">="), Type.atom("medium")]);
      const query = filter(booking, pathPredicates(["owner", "level"], value));

      assert.deepStrictEqual(query.filter, [
        [["owner", "level"], ">=", "medium"],
      ]);
    });

    it("reads an ordering comparison on a path to an integer attribute", () => {
      const value = Type.tuple([Type.atom(">="), Type.integer(3)]);
      const query = filter(booking, pathPredicates(["owner", "logins"], value));

      assert.deepStrictEqual(query.filter, [[["owner", "logins"], ">=", 3]]);
    });

    it("reads a range on a path as its two bounds", () => {
      const query = filter(
        booking,
        pathPredicates(["owner", "logins"], range(1, 3)),
      );

      assert.deepStrictEqual(query.filter, [
        [["owner", "logins"], ">=", 1],
        [["owner", "logins"], "<=", 3],
      ]);
    });

    it("reads the actor leaf on a path to a uuid attribute", () => {
      const query = filter(
        booking,
        pathPredicates(["owner", "id"], Type.tuple([Type.atom("actor")])),
      );

      assert.deepStrictEqual(query.filter, [
        [["owner", "id"], "==", {actor: true}],
      ]);
    });

    it("reads an or entry as a disjunction of its alternatives", () => {
      const value = disjunction(
        [["done", Type.boolean(true)]],
        [
          ["position", Type.tuple([Type.atom(">="), Type.integer(3)])],
          ["title", Type.bitstring("x")],
        ],
      );

      const query = filter(task, predicates([["or", value]]));

      assert.deepStrictEqual(query.filter, [
        {
          or: [
            [["done", "==", true]],
            [
              ["position", ">=", 3],
              ["title", "==", "x"],
            ],
          ],
        },
      ]);
    });

    it("nests a disjunction inside an alternative", () => {
      const inner = disjunction(
        [["position", Type.integer(1)]],
        [["position", Type.integer(2)]],
      );

      const value = disjunction(
        [
          ["done", Type.boolean(true)],
          ["or", inner],
        ],
        [["title", Type.bitstring("x")]],
      );

      const query = filter(task, predicates([["or", value]]));

      assert.deepStrictEqual(query.filter, [
        {
          or: [
            [
              ["done", "==", true],
              {or: [[["position", "==", 1]], [["position", "==", 2]]]},
            ],
            [["title", "==", "x"]],
          ],
        },
      ]);
    });

    it("raises on predicates that are not a list of name and value pairs", () => {
      assert.throw(
        () => filter(task, Type.integer(123)),
        HologramBoxedError,
        "filter predicates must be a list of name and value pairs - a name being an attribute or a path - got: 123",
      );
    });

    it("raises on an unknown attribute", () => {
      assert.throw(
        () => filter(task, predicates([["x", Type.integer(1)]])),
        HologramBoxedError,
        "unknown attribute :x in MyApp.Task - known attributes: :created_at, :done, :due_on, :id, :position, :starts_at, :status, :title",
      );
    });

    // A to-one relationship names a reference the predicate can read instead, and the message
    // says which - a to-many has none to offer.
    it("raises on a one-element list as a predicate name", () => {
      assert.throw(
        () => filter(booking, pathPredicates(["owner"], Type.bitstring("x"))),
        HologramBoxedError,
        'filter predicates must be a list of name and value pairs - a name being an attribute or a path - got: [{[:owner], "x"}]',
      );
    });

    it("raises on a one-element list as an attribute operand", () => {
      const operand = Type.tuple([Type.atom("attribute"), path("name")]);

      assert.throw(
        () => filter(booking, predicates([["note", operand]])),
        HologramBoxedError,
        "invalid attribute operand {:attribute, [:name]} - an attribute is named by an atom, and a path by a list of two or more atoms",
      );
    });

    it("raises on a path compared with itself", () => {
      const value = Type.tuple([
        Type.atom("<"),
        Type.tuple([Type.atom("attribute"), path("owner", "email")]),
      ]);

      assert.throw(
        () => filter(booking, pathPredicates(["owner", "email"], value)),
        HologramBoxedError,
        "operator :< compares attribute owner.email in MyApp.Booking with itself",
      );
    });

    it("raises on a path through a to-many relationship", () => {
      assert.throw(
        () =>
          filter(
            booking,
            pathPredicates(["owner", "projects", "name"], Type.bitstring("x")),
          ),
        HologramBoxedError,
        ":projects is a to-many relationship in MyApp.User - a path in a condition goes through to-one relationships only",
      );
    });

    it("raises on a path through an attribute", () => {
      assert.throw(
        () =>
          filter(
            booking,
            pathPredicates(["owner", "email", "x"], Type.bitstring("x")),
          ),
        HologramBoxedError,
        ":email is an attribute in MyApp.User - a path goes through relationships, and only its last name is an attribute",
      );
    });

    it("raises on a path through an unknown relationship", () => {
      assert.throw(
        () =>
          filter(
            booking,
            pathPredicates(["boss", "email"], Type.bitstring("x")),
          ),
        HologramBoxedError,
        "unknown relationship :boss in MyApp.Booking - known relationships: :assignee, :owner",
      );
    });

    it("raises on a path to an unknown attribute", () => {
      assert.throw(
        () => filter(booking, pathPredicates(["owner", "x"], Type.integer(1))),
        HologramBoxedError,
        "unknown attribute :x in MyApp.User - known attributes: :active, :email, :ends_on, :id, :level, :logins, :manager_id, :starts_on",
      );
    });

    it("raises on an ordering comparison on a path to a boolean attribute", () => {
      const value = Type.tuple([Type.atom(">"), Type.boolean(true)]);

      assert.throw(
        () => filter(booking, pathPredicates(["owner", "active"], value)),
        HologramBoxedError,
        "operator :> requires an orderable attribute - attribute owner.active in MyApp.Booking has type :boolean, and boolean and uuid attributes have no order to compare by",
      );
    });

    it("raises on a comparison against a value the enum a path ends at does not declare", () => {
      const value = Type.tuple([Type.atom(">="), Type.atom("urgent")]);

      assert.throw(
        () => filter(booking, pathPredicates(["owner", "level"], value)),
        HologramBoxedError,
        ":urgent is not a value of attribute owner.level in MyApp.Booking - the values are [:low, :medium, :high]",
      );
    });

    it("raises on a path and an attribute of different types", () => {
      const operand = Type.tuple([
        Type.atom("attribute"),
        path("assignee", "email"),
      ]);

      assert.throw(
        () => filter(booking, predicates([["owner_id", operand]])),
        HologramBoxedError,
        "operator :== compares attribute :owner_id with attribute assignee.email in MyApp.Booking, which have different types (:uuid and :string) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)",
      );
    });

    it("raises on a path through an unknown relationship on a later hop", () => {
      assert.throw(
        () =>
          filter(
            booking,
            pathPredicates(["owner", "boss", "email"], Type.bitstring("x")),
          ),
        HologramBoxedError,
        "unknown relationship :boss in MyApp.User - known relationships: :manager, :projects",
      );
    });

    it("raises on a path to a relationship", () => {
      assert.throw(
        () => filter(booking, pathPredicates(["owner", "manager"], Type.nil())),
        HologramBoxedError,
        ":manager is a relationship in MyApp.User - only attributes can be filtered - filter its reference via :manager_id",
      );
    });

    it("raises on a to-one relationship, naming its reference field", () => {
      assert.throw(
        () =>
          filter(Type.alias(PROJECT), predicates([["owner", Type.integer(1)]])),
        HologramBoxedError,
        ":owner is a relationship in MyApp.Project - only attributes can be filtered - filter its reference via :owner_id",
      );
    });

    it("raises on a to-many relationship", () => {
      assert.throw(
        () =>
          filter(Type.alias(PROJECT), predicates([["tasks", Type.integer(1)]])),
        HologramBoxedError,
        ":tasks is a relationship in MyApp.Project - only attributes can be filtered",
      );
    });

    it("raises on an unknown operator", () => {
      const value = Type.tuple([Type.atom("like"), Type.bitstring("a")]);

      assert.throw(
        () => filter(task, predicates([["title", value]])),
        HologramBoxedError,
        "unknown operator :like in the filter predicate for attribute :title - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in",
      );
    });

    it("raises on an ordering comparison over the id attribute", () => {
      const value = Type.tuple([Type.atom("<"), Type.bitstring("t1")]);

      assert.throw(
        () => filter(task, predicates([["id", value]])),
        HologramBoxedError,
        "operator :< requires an orderable attribute - attribute :id in MyApp.Task has type :uuid, and boolean and uuid attributes have no order to compare by",
      );
    });

    it("raises on an attribute compared with itself", () => {
      const value = Type.tuple([Type.atom("<"), attribute("guests")]);

      assert.throw(
        () => filter(booking, predicates([["guests", value]])),
        HologramBoxedError,
        "operator :< compares attribute :guests in MyApp.Booking with itself",
      );
    });

    it("raises on an attribute operand for a membership operator", () => {
      const value = Type.tuple([Type.atom("in"), attribute("capacity")]);

      assert.throw(
        () => filter(booking, predicates([["guests", value]])),
        HologramBoxedError,
        "operator :in on attribute :guests requires a list operand, got: {:attribute, :capacity}",
      );
    });

    it("raises on an attribute pair of different types", () => {
      const value = Type.tuple([Type.atom("<"), attribute("held_at")]);

      assert.throw(
        () => filter(booking, predicates([["check_in", value]])),
        HologramBoxedError,
        "operator :< compares attribute :check_in with attribute :held_at in MyApp.Booking, which have different types (:date and :datetime) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)",
      );
    });

    it("raises on an enum pair declaring different values", () => {
      const value = Type.tuple([Type.atom("=="), attribute("tier")]);

      assert.throw(
        () => filter(booking, predicates([["level", value]])),
        HologramBoxedError,
        "operator :== compares attribute :level with attribute :tier in MyApp.Booking, which declare different values ([:low, :medium, :high] and [:low, :high]) - two enum attributes compare only when they declare the same values in the same order",
      );
    });

    it("raises on an ordering comparison between reference fields", () => {
      const value = Type.tuple([Type.atom("<"), attribute("owner_id")]);

      assert.throw(
        () => filter(booking, predicates([["assignee_id", value]])),
        HologramBoxedError,
        "operator :< requires an orderable attribute - attribute :assignee_id in MyApp.Booking has type :uuid, and boolean and uuid attributes have no order to compare by",
      );
    });

    it("raises on an unknown attribute operand", () => {
      const value = Type.tuple([Type.atom("=="), attribute("x")]);

      assert.throw(
        () => filter(booking, predicates([["guests", value]])),
        HologramBoxedError,
        "unknown attribute :x in MyApp.Booking - known attributes: :assignee_id, :capacity, :check_in, :check_out, :created_at, :guests, :held_at, :id, :level, :name, :note, :owner_id, :priority, :rating, :tier, :updated_at",
      );
    });

    it("raises on a relationship as an attribute operand", () => {
      const value = Type.tuple([Type.atom("=="), attribute("owner")]);

      assert.throw(
        () => filter(booking, predicates([["assignee_id", value]])),
        HologramBoxedError,
        ":owner is a relationship in MyApp.Booking - only attributes can be filtered - filter its reference via :owner_id",
      );
    });

    it("raises on a comparison against a value the enum does not declare", () => {
      const value = Type.tuple([Type.atom(">"), Type.atom("archived")]);

      assert.throw(
        () => filter(task, predicates([["status", value]])),
        HologramBoxedError,
        ":archived is not a value of attribute :status in MyApp.Task - the values are [:open, :blocked, :done]",
      );
    });

    it("raises on a list operand for an equality operator", () => {
      const value = Type.tuple([
        Type.atom("=="),
        Type.list([Type.bitstring("a")]),
      ]);

      assert.throw(
        () => filter(task, predicates([["title", value]])),
        HologramBoxedError,
        'invalid operand ["a"] for operator :== on attribute :title',
      );
    });

    it("raises on a non-list operand for a membership operator", () => {
      const value = Type.tuple([Type.atom("in"), Type.bitstring("a")]);

      assert.throw(
        () => filter(task, predicates([["title", value]])),
        HologramBoxedError,
        'operator :in on attribute :title requires a list operand, got: "a"',
      );
    });

    it("raises on an empty membership list", () => {
      const value = Type.tuple([Type.atom("in"), Type.list([])]);

      assert.throw(
        () => filter(task, predicates([["title", value]])),
        HologramBoxedError,
        "membership list for attribute :title must not be empty",
      );
    });

    it("raises on an empty filter list", () => {
      assert.throw(
        () => filter(task, predicates([["title", Type.list([])]])),
        HologramBoxedError,
        "filter list for attribute :title must not be empty",
      );
    });

    it("raises on a list mixing plain values and operator tuples", () => {
      const values = Type.list([
        Type.bitstring("a"),
        Type.tuple([Type.atom(">="), Type.integer(3)]),
      ]);

      assert.throw(
        () => filter(task, predicates([["title", values]])),
        HologramBoxedError,
        "use either a membership list of plain values or a list of operator tuples",
      );
    });

    it("raises on a range over a non-integer attribute", () => {
      assert.throw(
        () => filter(task, predicates([["title", range(1, 5)]])),
        HologramBoxedError,
        "requires an integer attribute - attribute :title in MyApp.Task has type :string",
      );
    });

    it("raises on a stepped range", () => {
      assert.throw(
        () => filter(task, predicates([["position", range(0, 100, 5)]])),
        HologramBoxedError,
        "is not supported - membership ranges use step 1",
      );
    });

    it("raises on an empty range", () => {
      assert.throw(
        () => filter(task, predicates([["position", range(5, 1)]])),
        HologramBoxedError,
        "is empty - it would match nothing",
      );
    });

    // The actor leaf carries an entity id, so it compares only against names holding one.
    it("raises on an actor leaf over a non-uuid attribute", () => {
      const value = Type.tuple([Type.atom("actor")]);

      assert.throw(
        () => filter(task, predicates([["title", value]])),
        HologramBoxedError,
        "user_id() requires a uuid attribute - attribute :title in MyApp.Task has type :string",
      );
    });

    it("raises on a disjunction with no alternatives", () => {
      assert.throw(
        () => filter(task, predicates([["or", Type.list([])]])),
        HologramBoxedError,
        "a disjunction takes a list of at least two predicate lists, got: []",
      );
    });

    it("raises on a disjunction with one alternative", () => {
      const value = disjunction([["done", Type.boolean(true)]]);

      assert.throw(
        () => filter(task, predicates([["or", value]])),
        HologramBoxedError,
        "a disjunction takes a list of at least two predicate lists, got: [[done: true]]",
      );
    });

    it("raises on an alternative that is not a list of name and value pairs", () => {
      const value = Type.list([
        predicates([["done", Type.boolean(true)]]),
        Type.list([Type.integer(1)]),
      ]);

      assert.throw(
        () => filter(task, predicates([["or", value]])),
        HologramBoxedError,
        "an alternative of a disjunction is a non-empty list of name and value pairs, got: [1]",
      );
    });

    it("raises on an empty alternative", () => {
      const value = disjunction([["done", Type.boolean(true)]], []);

      assert.throw(
        () => filter(task, predicates([["or", value]])),
        HologramBoxedError,
        "an alternative of a disjunction is a non-empty list of name and value pairs, got: []",
      );
    });

    // The shape decides, not the name, so an or entry holding anything but predicate lists is read
    // as an attribute named or - which this entity type does not declare.
    it("raises on an or entry whose value is not a list of lists as an unknown attribute", () => {
      assert.throw(
        () => filter(task, predicates([["or", Type.boolean(true)]])),
        HologramBoxedError,
        "unknown attribute :or in MyApp.Task - known attributes: :created_at, :done, :due_on, :id, :position, :starts_at, :status, :title",
      );
    });

    it("raises on an unknown attribute inside an alternative", () => {
      const value = disjunction(
        [["x", Type.integer(1)]],
        [["done", Type.boolean(true)]],
      );

      assert.throw(
        () => filter(task, predicates([["or", value]])),
        HologramBoxedError,
        "unknown attribute :x in MyApp.Task - known attributes: :created_at, :done, :due_on, :id, :position, :starts_at, :status, :title",
      );
    });
  });

  describe("include/3", () => {
    it("accepts a sub-builder as a spec value", () => {
      const spec = Type.list([
        Type.tuple([
          Type.atom("tasks"),
          subBuilder((related) =>
            filter(related, predicates([["done", Type.boolean(true)]])),
          ),
        ]),
      ]);

      const query = include(project, spec, Type.nil());

      assert.deepStrictEqual(query.include, {
        tasks: {...freshTerm, filter: [["done", "==", true]]},
      });
    });

    it("accumulates multiple includes", () => {
      const query = include(
        include(project, Type.atom("owner"), Type.nil()),
        Type.atom("tasks"),
        Type.nil(),
      );

      assert.deepStrictEqual(query.include, {
        owner: baseTerm(USER),
        tasks: freshTerm,
      });
    });

    it("embeds a to-many relationship", () => {
      assert.deepStrictEqual(include(project, Type.atom("tasks"), Type.nil()), {
        ...baseTerm(PROJECT),
        include: {tasks: freshTerm},
      });
    });

    it("embeds a to-one relationship", () => {
      const query = include(project, Type.atom("owner"), Type.nil());

      assert.deepStrictEqual(query.include, {owner: baseTerm(USER)});
    });

    it("includes several relationships from a list spec", () => {
      const spec = Type.list([Type.atom("owner"), Type.atom("tasks")]);

      const query = include(project, spec, Type.nil());

      assert.deepStrictEqual(query.include, {
        owner: baseTerm(USER),
        tasks: freshTerm,
      });
    });

    it("includes three levels deep", () => {
      const query = include(
        user,
        Type.atom("manager"),
        subBuilder((levelOne) =>
          include(
            levelOne,
            Type.atom("manager"),
            subBuilder((levelTwo) =>
              include(levelTwo, Type.atom("manager"), Type.nil()),
            ),
          ),
        ),
      );

      assert.deepStrictEqual(query.include, {
        manager: {
          ...baseTerm(USER),
          include: {
            manager: {...baseTerm(USER), include: {manager: baseTerm(USER)}},
          },
        },
      });
    });

    it("merges a repeated include at the second level", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("projects"), Type.atom("tasks")]),
      ]);

      const query = include(include(user, spec, Type.nil()), spec, Type.nil());

      assert.deepStrictEqual(query.include, {
        projects: {...baseTerm(PROJECT), include: {tasks: freshTerm}},
      });
    });

    it("merges a repeated include of a relationship", () => {
      const query = include(
        include(project, Type.atom("tasks"), Type.nil()),
        Type.atom("tasks"),
        Type.nil(),
      );

      assert.deepStrictEqual(query, {
        ...baseTerm(PROJECT),
        include: {tasks: freshTerm},
      });
    });

    it("merges a second include that narrows a nested relationship", () => {
      const narrowedSpec = Type.list([
        Type.tuple([
          Type.atom("projects"),
          Type.list([
            Type.tuple([
              Type.atom("tasks"),
              subBuilder((related) =>
                filter(related, predicates([["done", Type.boolean(true)]])),
              ),
            ]),
          ]),
        ]),
      ]);

      const query = include(
        include(user, Type.atom("projects"), Type.nil()),
        narrowedSpec,
        Type.nil(),
      );

      assert.deepStrictEqual(query.include, {
        projects: {
          ...baseTerm(PROJECT),
          include: {tasks: {...freshTerm, filter: [["done", "==", true]]}},
        },
      });
    });

    it("merges includes repeated in one list spec", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("projects"), Type.atom("owner")]),
        Type.tuple([Type.atom("projects"), Type.atom("tasks")]),
      ]);

      const query = include(user, spec, Type.nil());

      assert.deepStrictEqual(query.include, {
        projects: {
          ...baseTerm(PROJECT),
          include: {owner: baseTerm(USER), tasks: freshTerm},
        },
      });
    });

    it("merges includes whose nested branches differ in clauses", () => {
      const narrowedSpec = Type.list([
        Type.tuple([
          Type.atom("projects"),
          Type.list([
            Type.tuple([
              Type.atom("tasks"),
              subBuilder((related) =>
                filter(related, predicates([["done", Type.boolean(true)]])),
              ),
            ]),
          ]),
        ]),
      ]);

      const ownerSpec = Type.list([
        Type.tuple([Type.atom("projects"), Type.atom("owner")]),
      ]);

      const query = include(
        include(user, narrowedSpec, Type.nil()),
        ownerSpec,
        Type.nil(),
      );

      assert.deepStrictEqual(query.include, {
        projects: {
          ...baseTerm(PROJECT),
          include: {
            owner: baseTerm(USER),
            tasks: {...freshTerm, filter: [["done", "==", true]]},
          },
        },
      });
    });

    it("merges what two includes of a relationship include", () => {
      const ownerSpec = Type.list([
        Type.tuple([Type.atom("projects"), Type.atom("owner")]),
      ]);

      const tasksSpec = Type.list([
        Type.tuple([Type.atom("projects"), Type.atom("tasks")]),
      ]);

      const query = include(
        include(user, ownerSpec, Type.nil()),
        tasksSpec,
        Type.nil(),
      );

      assert.deepStrictEqual(query.include, {
        projects: {
          ...baseTerm(PROJECT),
          include: {owner: baseTerm(USER), tasks: freshTerm},
        },
      });
    });

    it("mixes flat and nested entries", () => {
      const spec = Type.list([
        Type.atom("manager"),
        Type.tuple([Type.atom("projects"), Type.atom("owner")]),
      ]);

      const query = include(user, spec, Type.nil());

      assert.deepStrictEqual(query.include, {
        manager: baseTerm(USER),
        projects: {...baseTerm(PROJECT), include: {owner: baseTerm(USER)}},
      });
    });

    it("nests a list spec", () => {
      const spec = Type.list([
        Type.tuple([
          Type.atom("projects"),
          Type.list([Type.atom("owner"), Type.atom("tasks")]),
        ]),
      ]);

      const query = include(user, spec, Type.nil());

      assert.deepStrictEqual(query.include, {
        projects: {
          ...baseTerm(PROJECT),
          include: {owner: baseTerm(USER), tasks: freshTerm},
        },
      });
    });

    it("nests includes through the sub-builder", () => {
      const query = include(
        user,
        Type.atom("projects"),
        subBuilder((related) =>
          include(related, Type.atom("owner"), Type.nil()),
        ),
      );

      assert.deepStrictEqual(query.include, {
        projects: {...baseTerm(PROJECT), include: {owner: baseTerm(USER)}},
      });
    });

    it("nests traversal from a keyword spec", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("projects"), Type.atom("owner")]),
      ]);

      const query = include(user, spec, Type.nil());

      assert.deepStrictEqual(query.include, {
        projects: {...baseTerm(PROJECT), include: {owner: baseTerm(USER)}},
      });
    });

    it("refines a to-many include with a sub-builder", () => {
      const query = include(
        project,
        Type.atom("tasks"),
        subBuilder((related) =>
          orderBy(
            filter(related, predicates([["done", Type.boolean(false)]])),
            Type.atom("position"),
          ),
        ),
      );

      assert.deepStrictEqual(query.include, {
        tasks: {
          ...freshTerm,
          filter: [["done", "==", false]],
          orderBy: [["position", "asc"]],
        },
      });
    });

    it("raises on a non-function sub-builder", () => {
      assert.throw(
        () => include(project, Type.atom("tasks"), Type.integer(5)),
        HologramBoxedError,
        "include sub-builder for relationship :tasks must be a one-argument function, got: 5",
      );
    });

    it("raises on a repeated include at the second level when one side has clauses", () => {
      const narrowedSpec = Type.list([
        Type.tuple([
          Type.atom("projects"),
          Type.list([
            Type.tuple([
              Type.atom("tasks"),
              subBuilder((related) =>
                filter(related, predicates([["done", Type.boolean(true)]])),
              ),
            ]),
          ]),
        ]),
      ]);

      const spec = Type.list([
        Type.tuple([Type.atom("projects"), Type.atom("tasks")]),
      ]);

      assert.throw(
        () =>
          include(include(user, narrowedSpec, Type.nil()), spec, Type.nil()),
        HologramBoxedError,
        "relationship :tasks is already included",
      );
    });

    it("raises on a repeated include when the included one has clauses", () => {
      const narrowed = include(
        project,
        Type.atom("tasks"),
        subBuilder((related) =>
          filter(related, predicates([["done", Type.boolean(true)]])),
        ),
      );

      assert.throw(
        () => include(narrowed, Type.atom("tasks"), Type.nil()),
        HologramBoxedError,
        "relationship :tasks is already included",
      );
    });

    it("raises on a repeated include when the new one has clauses", () => {
      const included = include(project, Type.atom("tasks"), Type.nil());

      assert.throw(
        () =>
          include(
            included,
            Type.atom("tasks"),
            subBuilder((related) =>
              filter(related, predicates([["done", Type.boolean(true)]])),
            ),
          ),
        HologramBoxedError,
        "relationship :tasks is already included",
      );
    });

    it("raises on a separate sub-builder with a shape spec", () => {
      assert.throw(
        () =>
          include(
            project,
            Type.list([Type.atom("tasks")]),
            subBuilder((related) => related),
          ),
        HologramBoxedError,
        "an include shape spec takes no separate sub-builder - nest it in the spec as a {name, sub_builder} pair",
      );
    });

    it("raises on a sub-builder returning a different entity's term", () => {
      assert.throw(
        () =>
          include(
            project,
            Type.atom("tasks"),
            subBuilder((_related) => filter(project, Type.list([]))),
          ),
        HologramBoxedError,
        "include sub-builder for relationship :tasks must return a query term for MyApp.Task - got a query term for MyApp.Project",
      );
    });

    it("raises on a sub-builder returning a non-term", () => {
      assert.throw(
        () =>
          include(
            project,
            Type.atom("tasks"),
            subBuilder((_related) => Type.integer(123)),
          ),
        HologramBoxedError,
        "include sub-builder for relationship :tasks must return a query term for MyApp.Task, got: 123",
      );
    });

    // The relationship declaration already says how many entities are embedded, so a sub-term
    // marking a cardinality of its own would be saying something the shape cannot honour.
    it("raises on a sub-term carrying a cardinality marker", () => {
      assert.throw(
        () =>
          include(
            project,
            Type.atom("tasks"),
            subBuilder((related) => count(related)),
          ),
        HologramBoxedError,
        "include sub-terms take no cardinality marker - the relationship declaration governs cardinality",
      );
    });

    it("raises on an attribute name", () => {
      assert.throw(
        () => include(project, Type.atom("name"), Type.nil()),
        HologramBoxedError,
        ":name is an attribute in MyApp.Project - only relationships can be included",
      );
    });

    it("raises on an empty include spec", () => {
      assert.throw(
        () => include(project, Type.list([]), Type.nil()),
        HologramBoxedError,
        "include spec must not be empty",
      );
    });

    it("raises on an invalid include spec", () => {
      assert.throw(
        () => include(project, Type.integer(123), Type.nil()),
        HologramBoxedError,
        "include spec must be a relationship name or a shape list, got: 123",
      );
    });

    it("raises on an invalid include spec entry", () => {
      assert.throw(
        () => include(project, Type.list([Type.integer(123)]), Type.nil()),
        HologramBoxedError,
        "invalid include spec entry 123 - use a relationship name, a {name, spec} pair, or a {name, sub_builder} pair",
      );
    });

    it("raises on an unknown relationship", () => {
      assert.throw(
        () => include(project, Type.atom("x"), Type.nil()),
        HologramBoxedError,
        "unknown relationship :x in MyApp.Project - known relationships: :owner, :tasks",
      );
    });

    it("raises on clauses on a to-one include", () => {
      assert.throw(
        () =>
          include(
            project,
            Type.atom("owner"),
            subBuilder((related) =>
              filter(related, predicates([["email", Type.bitstring("x")]])),
            ),
          ),
        HologramBoxedError,
        "to-one relationship :owner takes no clauses - clauses apply to to-many includes",
      );
    });
  });

  describe("limit/2", () => {
    it("accepts zero", () => {
      assert.equal(limit(task, Type.integer(0)).limit, 0);
    });

    it("composes with other stages", () => {
      const query = limit(offset(task, Type.integer(20)), Type.integer(50));

      assert.equal(query.offset, 20);
      assert.equal(query.limit, 50);
    });

    it("sets the limit", () => {
      assert.deepStrictEqual(limit(task, Type.integer(50)), {
        ...freshTerm,
        limit: 50,
      });
    });

    it("raises on a negative limit", () => {
      assert.throw(
        () => limit(task, Type.integer(-5)),
        HologramBoxedError,
        "limit must be a non-negative integer, got: -5",
      );
    });

    it("raises on a non-integer limit", () => {
      assert.throw(
        () => limit(task, Type.float(5.0)),
        HologramBoxedError,
        "limit must be a non-negative integer, got: 5.0",
      );
    });

    it("replaces a prior limit", () => {
      assert.equal(
        limit(limit(task, Type.integer(50)), Type.integer(100)).limit,
        100,
      );
    });
  });

  describe("normalize/1", () => {
    it("appends an ascending id tiebreaker to orderings", () => {
      const query = normalize(orderBy(task, Type.atom("position")));

      assert.deepStrictEqual(query.orderBy, [
        ["position", "asc"],
        ["id", "asc"],
      ]);
    });

    it("defaults an empty ordering to the id order", () => {
      assert.deepStrictEqual(normalize(task), {
        ...freshTerm,
        orderBy: [["id", "asc"]],
      });
    });

    it("drops the ordering from counting queries", () => {
      const query = normalize(count(orderBy(task, Type.atom("position"))));

      assert.deepStrictEqual(query.orderBy, []);
    });

    it("is idempotent", () => {
      const normalized = normalize(
        orderBy(
          include(
            filter(
              project,
              predicates([
                ["name", Type.bitstring("Board")],
                [
                  "or",
                  disjunction(
                    [["name", Type.bitstring("Site")]],
                    [["id", Type.bitstring("p1")]],
                  ),
                ],
              ]),
            ),
            Type.atom("tasks"),
            Type.nil(),
          ),
          Type.atom("name"),
        ),
      );

      assert.deepStrictEqual(normalize(normalized), normalized);
    });

    it("leaves orderings already keyed by id untouched", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("id"), Type.atom("desc")]),
      ]);

      assert.deepStrictEqual(normalize(orderBy(task, spec)).orderBy, [
        ["id", "desc"],
      ]);
    });

    it("sorts the alternatives of a disjunction and the predicates inside them", () => {
      const value = disjunction(
        [["title", Type.bitstring("x")]],
        [
          ["position", Type.integer(1)],
          ["done", Type.boolean(true)],
        ],
      );

      const query = normalize(filter(task, predicates([["or", value]])));

      assert.deepStrictEqual(query.filter, [
        {
          or: [
            [
              ["done", "==", true],
              ["position", "==", 1],
            ],
            [["title", "==", "x"]],
          ],
        },
      ]);
    });

    it("sorts nested disjunctions recursively", () => {
      const inner = disjunction(
        [["status", Type.atom("open")]],
        [["status", Type.atom("done")]],
      );

      const value = disjunction(
        [
          ["position", Type.integer(1)],
          ["or", inner],
        ],
        [["done", Type.boolean(true)]],
      );

      const query = normalize(
        filter(
          task,
          predicates([
            ["title", Type.bitstring("x")],
            ["or", value],
          ]),
        ),
      );

      assert.deepStrictEqual(query.filter, [
        {
          or: [
            [["done", "==", true]],
            [
              {or: [[["status", "==", "done"]], [["status", "==", "open"]]]},
              ["position", "==", 1],
            ],
          ],
        },
        ["title", "==", "x"],
      ]);
    });

    it("normalizes includes nested under a to-one include", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("owner"), Type.atom("projects")]),
      ]);

      const query = normalize(include(project, spec, Type.nil()));

      assert.deepStrictEqual(query.include.owner.orderBy, []);

      assert.deepStrictEqual(query.include.owner.include.projects.orderBy, [
        ["id", "asc"],
      ]);
    });

    it("normalizes to-many sub-terms", () => {
      const query = normalize(
        include(
          project,
          Type.atom("tasks"),
          subBuilder((related) =>
            filter(
              related,
              predicates([
                ["title", Type.bitstring("x")],
                ["done", Type.boolean(true)],
              ]),
            ),
          ),
        ),
      );

      assert.deepStrictEqual(query.include.tasks.filter, [
        ["done", "==", true],
        ["title", "==", "x"],
      ]);

      assert.deepStrictEqual(query.include.tasks.orderBy, [["id", "asc"]]);
    });

    it("skips ordering for to-one includes", () => {
      const query = normalize(include(project, Type.atom("owner"), Type.nil()));

      assert.deepStrictEqual(query.include.owner.orderBy, []);
    });

    it("sorts filter predicates canonically", () => {
      const query = normalize(
        filter(
          task,
          predicates([
            ["title", Type.bitstring("x")],
            ["done", Type.boolean(true)],
          ]),
        ),
      );

      assert.deepStrictEqual(query.filter, [
        ["done", "==", true],
        ["title", "==", "x"],
      ]);
    });
  });

  describe("offset/2", () => {
    it("sets the offset", () => {
      assert.deepStrictEqual(offset(task, Type.integer(20)), {
        ...freshTerm,
        offset: 20,
      });
    });

    it("raises on a negative offset", () => {
      assert.throw(
        () => offset(task, Type.integer(-5)),
        HologramBoxedError,
        "offset must be a non-negative integer, got: -5",
      );
    });

    it("replaces a prior offset", () => {
      assert.equal(
        offset(offset(task, Type.integer(20)), Type.integer(40)).offset,
        40,
      );
    });
  });

  describe("one/1", () => {
    it("marks the query as single-result", () => {
      assert.deepStrictEqual(one(task), {...freshTerm, cardinality: "one"});
    });

    it("raises when cardinality is already marked", () => {
      assert.throw(
        () => one(count(task)),
        HologramBoxedError,
        "cardinality is already set to :count",
      );
    });
  });

  // A stage takes the module a query starts from or the term the stage before it returned, and
  // the term it hands on is what the kernel reads - so what a stage refuses is what the client
  // could not have answered anyway.
  describe("order_by/2", () => {
    it("defaults a bare attribute name to ascending", () => {
      assert.deepStrictEqual(orderBy(task, Type.atom("title")).orderBy, [
        ["title", "asc"],
      ]);
    });

    it("defaults list entries to ascending", () => {
      const spec = Type.list([Type.atom("title"), Type.atom("done")]);

      assert.deepStrictEqual(orderBy(task, spec).orderBy, [
        ["title", "asc"],
        ["done", "asc"],
      ]);
    });

    it("accepts a keyword spec with directions", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("title"), Type.atom("desc")]),
      ]);

      assert.deepStrictEqual(orderBy(task, spec).orderBy, [["title", "desc"]]);
    });

    it("accepts a mixed list of names and direction tuples", () => {
      const spec = Type.list([
        Type.atom("done"),
        Type.tuple([Type.atom("title"), Type.atom("desc")]),
      ]);

      assert.deepStrictEqual(orderBy(task, spec).orderBy, [
        ["done", "asc"],
        ["title", "desc"],
      ]);
    });

    it("replaces prior ordering", () => {
      const query = orderBy(
        orderBy(task, Type.atom("done")),
        Type.atom("title"),
      );

      assert.deepStrictEqual(query.orderBy, [["title", "asc"]]);
    });

    it("orders by a system attribute", () => {
      assert.deepStrictEqual(orderBy(task, Type.atom("created_at")).orderBy, [
        ["created_at", "asc"],
      ]);
    });

    // The declared `values:` list is the order, so nothing about an enum keeps it from being an
    // ordering key - both executors sort by a value's position in that list.
    it("orders by an enum attribute", () => {
      assert.deepStrictEqual(orderBy(task, Type.atom("status")).orderBy, [
        ["status", "asc"],
      ]);
    });

    it("raises on a non-atom spec", () => {
      assert.throw(
        () => orderBy(task, Type.integer(123)),
        HologramBoxedError,
        "order_by spec must be an attribute name or a list, got: 123",
      );
    });

    it("raises on an invalid entry", () => {
      assert.throw(
        () => orderBy(task, Type.list([Type.integer(123)])),
        HologramBoxedError,
        "invalid order_by entry 123 - use an attribute name or an {attribute, :asc | :desc} tuple",
      );
    });

    it("raises on an invalid direction", () => {
      const spec = Type.list([
        Type.tuple([Type.atom("title"), Type.atom("down")]),
      ]);

      assert.throw(
        () => orderBy(task, spec),
        HologramBoxedError,
        "invalid direction :down for attribute :title - use :asc or :desc",
      );
    });

    it("raises on a relationship name", () => {
      assert.throw(
        () => orderBy(Type.alias(PROJECT), Type.atom("tasks")),
        HologramBoxedError,
        ":tasks is a relationship in MyApp.Project - only attributes can be ordered",
      );
    });

    // A reference field is not among the attributes on either tier - a relationship is followed,
    // never ordered by.
    it("raises on a to-one reference field", () => {
      assert.throw(
        () => orderBy(Type.alias(PROJECT), Type.atom("owner_id")),
        HologramBoxedError,
        "unknown attribute :owner_id in MyApp.Project - known attributes: :id, :name",
      );
    });

    it("raises on an unknown attribute", () => {
      assert.throw(
        () => orderBy(task, Type.atom("x")),
        HologramBoxedError,
        "unknown attribute :x in MyApp.Task - known attributes: :created_at, :done, :due_on, :id, :position, :starts_at, :status, :title",
      );
    });
  });

  describe("the query a stage starts from", () => {
    it("carries the stages already applied", () => {
      const query = offset(limit(task, Type.integer(5)), Type.integer(10));

      assert.equal(query.limit, 5);
      assert.equal(query.offset, 10);
      assert.equal(query.entity, TASK);
    });

    it("raises for a value that is neither a module nor a term", () => {
      assert.throw(
        () => limit(Type.bitstring("MyApp.Task"), Type.integer(5)),
        HologramBoxedError,
        '"MyApp.Task" is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive',
      );
    });

    // A type whose rows never reach a client is one this side cannot answer for, so it is
    // refused where the server would refuse a module that is not an entity type at all.
    it("raises for a type this build never told the client about", () => {
      assert.throw(
        () => limit(Type.alias("MyApp.Unknown"), Type.integer(5)),
        HologramBoxedError,
        "MyApp.Unknown is not an entity type module or a query term",
      );
    });
  });
});
