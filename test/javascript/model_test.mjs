"use strict";

import {
  assert,
  assertBoxedStrictEqual,
  defineRuntimeGlobals,
} from "./support/helpers.mjs";

import Erlang_Re from "../../assets/js/erlang/re.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Model from "../../assets/js/model.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

// The boxed forms asserted here are the ones Hologram.Compiler.Encoder.encode_term! writes for
// the same values, which is what a template already reads when the server hands it a row - a
// client that built them any other way would answer one way for a synced row and another for a
// rendered one.
describe("Model", () => {
  const NOTIFY = "MyApp.Jobs.Notify";
  const PROJECT = "MyApp.Project";
  const TASK = "MyApp.Task";

  // One attribute of every admitted type, a server-only one, and both relationship
  // cardinalities - the shape the build bakes for a type this client can hold.
  //
  // The to-many's target has NO entry of its own, deliberately: a build carries a type a page
  // queries or mentions, so a relationship nothing reaches through points at a name the model does
  // not hold. Boxing reads the reference field and leaves the sentinel, asking the target nothing -
  // and a box() test would fail loudly if that ever stopped being true.
  //
  // The to-one's target does have one, because boxResult() boxes the rows behind an include, and
  // a query that included a relationship would have put its type in the model by including it.
  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [PROJECT]: {
          attributes: {id: "uuid", name: "string"},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
        },
        // A job type, whose three framework attributes are the worker's to fill and no client's
        // to write.
        [NOTIFY]: {
          attributes: {
            actor_id: "uuid",
            created_at: "datetime",
            error: "string",
            id: "uuid",
            reason: "enum",
            status: "enum",
          },
          constraints: {},
          defaults: {},
          enumValues: {reason: ["created"], status: ["queued", "running"]},
          frameworkAttributes: ["actor_id", "error", "status"],
          relationships: {},
          serverOnly: ["error"],
        },
        [TASK]: {
          attributes: {
            done: "boolean",
            due_on: "date",
            id: "uuid",
            internal_notes: "string",
            position: "integer",
            starts_at: "time",
            status: "enum",
            title: "string",
            updated_at: "datetime",
            weight: "float",
          },
          constraints: {
            internal_notes: {unique: true},
            position: {in: {first: 0, last: 100, step: 5}},
            title: {
              format: {
                opts: Type.list([
                  Type.atom("caseless"),
                  Type.tuple([Type.atom("newline"), Type.atom("anycrlf")]),
                ]),
                source: "^[a-z ]+$",
              },
              max_length: 32,
              min_length: 3,
            },
            weight: {
              max: Type.float(5.0),
              min: Type.integer(0),
              optional: true,
            },
          },
          defaults: {done: Type.boolean(false), position: Type.integer(7)},
          enumValues: {status: ["open", "done"]},
          frameworkAttributes: [],
          relationships: {
            project: {optional: false, toMany: false, type: "MyApp.Project"},
            tags: {optional: true, toMany: true, type: "MyApp.Tag"},
          },
          serverOnly: ["internal_notes"],
        },
      },
    };

    Model.reset();
  });

  const row = (overrides = {}) =>
    Object.assign(
      {
        done: false,
        due_on: "2026-08-16",
        id: "t1",
        position: 7,
        project_id: "p1",
        starts_at: "11:00:00.000000",
        status: "open",
        title: "Draft copy",
        updated_at: "2026-08-16T15:18:13.022508Z",
        weight: 1.5,
      },
      overrides,
    );

  const field = (boxed, name) =>
    boxed.data[Type.encodeMapKey(Type.atom(name))][1];

  const datetime = (amount, precision) =>
    Type.map([
      [Type.atom("__struct__"), Type.alias("DateTime")],
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("day"), Type.integer(16)],
      [Type.atom("hour"), Type.integer(15)],
      [
        Type.atom("microsecond"),
        Type.tuple([Type.integer(amount), Type.integer(precision)]),
      ],
      [Type.atom("minute"), Type.integer(18)],
      [Type.atom("month"), Type.integer(8)],
      [Type.atom("second"), Type.integer(13)],
      [Type.atom("std_offset"), Type.integer(0)],
      [Type.atom("time_zone"), Type.bitstring("Etc/UTC")],
      [Type.atom("utc_offset"), Type.integer(0)],
      [Type.atom("year"), Type.integer(2026)],
      [Type.atom("zone_abbr"), Type.bitstring("UTC")],
    ]);

  const time = (amount, precision) =>
    Type.map([
      [Type.atom("__struct__"), Type.alias("Time")],
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("hour"), Type.integer(11)],
      [
        Type.atom("microsecond"),
        Type.tuple([Type.integer(amount), Type.integer(precision)]),
      ],
      [Type.atom("minute"), Type.integer(0)],
      [Type.atom("second"), Type.integer(0)],
    ]);

  describe("box()", () => {
    it("names the struct by its entity type", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(field(boxed, "__struct__"), Type.alias(TASK));
    });

    it("boxes the row's revisions into its metadata", () => {
      const boxed = Model.box(TASK, row({$revisions: {position: 3, title: 5}}));

      assert.deepEqual(
        field(boxed, "__meta__"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Entity.Metadata")],
          [Type.atom("attribute_ops"), Type.map([])],
          [Type.atom("claim"), Type.nil()],
          [Type.atom("relationship_ops"), Type.map([])],
          [
            Type.atom("revisions"),
            Type.map([
              [Type.atom("position"), Type.integer(3)],
              [Type.atom("title"), Type.integer(5)],
            ]),
          ],
          [Type.atom("stamp"), Type.nil()],
        ]),
      );
    });

    it("boxes a row carrying no revisions with an empty metadata", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(
        field(boxed, "__meta__"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Entity.Metadata")],
          [Type.atom("attribute_ops"), Type.map([])],
          [Type.atom("claim"), Type.nil()],
          [Type.atom("relationship_ops"), Type.map([])],
          [Type.atom("revisions"), Type.map([])],
          [Type.atom("stamp"), Type.nil()],
        ]),
      );
    });

    it("boxes a boolean, a float, an integer and a string as they are spelled", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(field(boxed, "done"), Type.boolean(false));
      assert.deepEqual(field(boxed, "position"), Type.integer(7));
      assert.deepEqual(field(boxed, "title"), Type.bitstring("Draft copy"));
      assert.deepEqual(field(boxed, "weight"), Type.float(1.5));
    });

    it("boxes a uuid as the string it is", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(field(boxed, "id"), Type.bitstring("t1"));
    });

    it("boxes a date as the struct a template reads", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(
        field(boxed, "due_on"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Date")],
          [Type.atom("calendar"), Type.alias("Calendar.ISO")],
          [Type.atom("day"), Type.integer(16)],
          [Type.atom("month"), Type.integer(8)],
          [Type.atom("year"), Type.integer(2026)],
        ]),
      );
    });

    it("boxes a datetime as the struct a template reads, in UTC", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(
        field(boxed, "updated_at"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("DateTime")],
          [Type.atom("calendar"), Type.alias("Calendar.ISO")],
          [Type.atom("day"), Type.integer(16)],
          [Type.atom("hour"), Type.integer(15)],
          [
            Type.atom("microsecond"),
            Type.tuple([Type.integer(22508), Type.integer(6)]),
          ],
          [Type.atom("minute"), Type.integer(18)],
          [Type.atom("month"), Type.integer(8)],
          [Type.atom("second"), Type.integer(13)],
          [Type.atom("std_offset"), Type.integer(0)],
          [Type.atom("time_zone"), Type.bitstring("Etc/UTC")],
          [Type.atom("utc_offset"), Type.integer(0)],
          [Type.atom("year"), Type.integer(2026)],
          [Type.atom("zone_abbr"), Type.bitstring("UTC")],
        ]),
      );
    });

    it("boxes a datetime carrying no fractional seconds", () => {
      const boxed = Model.box(TASK, row({updated_at: "2026-08-16T15:18:13Z"}));

      assert.deepEqual(
        field(field(boxed, "updated_at"), "microsecond"),
        Type.tuple([Type.integer(0), Type.integer(0)]),
      );
    });

    // The wire can spell more precision than a datetime holds, and Elixir reading the same string
    // keeps the first six digits - so this side keeps the same six, rather than a precision the
    // struct cannot carry.
    it("boxes a datetime carrying more fractional digits than microseconds", () => {
      const boxed = Model.box(
        TASK,
        row({updated_at: "2026-08-16T15:18:13.0225081Z"}),
      );

      assert.deepEqual(
        field(field(boxed, "updated_at"), "microsecond"),
        Type.tuple([Type.integer(22508), Type.integer(6)]),
      );
    });

    it("boxes an enum label as the atom it names", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(field(boxed, "status"), Type.atom("open"));
    });

    // A label beginning with an uppercase letter names a module, which is stored without the
    // prefix every module atom carries.
    it("boxes an enum label naming a module as that module", () => {
      const boxed = Model.box(TASK, row({status: "MyApp.Status.Open"}));

      assert.deepEqual(field(boxed, "status"), Type.alias("MyApp.Status.Open"));
    });

    it("boxes a time as the struct a template reads", () => {
      const boxed = Model.box(TASK, row({starts_at: "11:00:00.022508"}));

      assert.deepEqual(
        field(boxed, "starts_at"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Time")],
          [Type.atom("calendar"), Type.alias("Calendar.ISO")],
          [Type.atom("hour"), Type.integer(11)],
          [
            Type.atom("microsecond"),
            Type.tuple([Type.integer(22508), Type.integer(6)]),
          ],
          [Type.atom("minute"), Type.integer(0)],
          [Type.atom("second"), Type.integer(0)],
        ]),
      );
    });

    it("boxes a time carrying no fractional seconds", () => {
      const boxed = Model.box(TASK, row({starts_at: "11:00:00"}));

      assert.deepEqual(
        field(field(boxed, "starts_at"), "microsecond"),
        Type.tuple([Type.integer(0), Type.integer(0)]),
      );
    });

    it("boxes a time carrying more fractional digits than microseconds", () => {
      const boxed = Model.box(TASK, row({starts_at: "11:00:00.0225081"}));

      assert.deepEqual(
        field(field(boxed, "starts_at"), "microsecond"),
        Type.tuple([Type.integer(22508), Type.integer(6)]),
      );
    });

    it("raises for a time the wire spelled some other way", () => {
      assert.throw(
        () => Model.box(TASK, row({starts_at: "11:00"})),
        HologramRuntimeError,
        "invalid time on the wire: 11:00",
      );
    });

    // Well-formed digits naming no time of day, which Elixir reading the same string refuses as
    // :invalid_time - so this side refuses them too rather than building a struct saying 24:00.
    it("raises for a time whose clock fields are out of range", () => {
      for (const spelling of ["24:00:00", "11:60:00", "11:00:60"]) {
        assert.throw(
          () => Model.box(TASK, row({starts_at: spelling})),
          HologramRuntimeError,
          `invalid time on the wire: ${spelling}`,
        );
      }
    });

    it("boxes the last time of day the clock reaches", () => {
      const boxed = Model.box(TASK, row({starts_at: "23:59:59"}));

      assert.deepEqual(
        field(field(boxed, "starts_at"), "hour"),
        Type.integer(23),
      );
    });

    it("boxes an unset attribute as nil", () => {
      const boxed = Model.box(TASK, row({title: null}));

      assert.deepEqual(field(boxed, "title"), Type.nil());
    });

    // The value never travels and the NAME does: a read of one says which attribute is not this
    // client's to have, where nil would say it is unset.
    it("boxes an attribute the client may not have as the sentinel naming it", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(
        field(boxed, "internal_notes"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Entity.ServerOnly")],
          [Type.atom("attribute"), Type.atom("internal_notes")],
        ]),
      );
    });

    it("boxes a relationship nobody asked for as the sentinel naming it", () => {
      const boxed = Model.box(TASK, row());

      const notIncluded = (name) =>
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Entity.NotIncluded")],
          [Type.atom("relationship"), Type.atom(name)],
        ]);

      assert.deepEqual(field(boxed, "project"), notIncluded("project"));
      assert.deepEqual(field(boxed, "tags"), notIncluded("tags"));
    });

    it("boxes the reference field a to-one relationship is followed through", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(field(boxed, "project_id"), Type.bitstring("p1"));
    });

    it("boxes an unset reference field as nil", () => {
      const boxed = Model.box(TASK, row({project_id: null}));

      assert.deepEqual(field(boxed, "project_id"), Type.nil());
    });

    it("carries an included relationship in place of the sentinel", () => {
      const tag = Type.map([[Type.atom("id"), Type.bitstring("g1")]]);
      const tags = Type.list([tag]);

      const boxed = Model.box(TASK, row(), {tags: tags});

      assert.deepEqual(field(boxed, "tags"), tags);
    });
  });

  describe("boxResult()", () => {
    const node = (overrides = {}) => ({includes: {}, row: row(overrides)});

    const term = (overrides = {}) =>
      Object.assign({cardinality: "set", entity: TASK, include: {}}, overrides);

    it("boxes a count as the number itself", () => {
      assert.deepStrictEqual(
        Model.boxResult(term({cardinality: "count"}), 7),
        Type.integer(7),
      );
    });

    it("boxes a set as a list of structs", () => {
      const boxed = Model.boxResult(term(), [node(), node({id: "t2"})]);

      assert.equal(boxed.data.length, 2);
      assert.deepStrictEqual(field(boxed.data[1], "id"), Type.bitstring("t2"));
    });

    it("boxes a single result as one struct", () => {
      const boxed = Model.boxResult(term({cardinality: "one"}), node());

      assert.deepStrictEqual(
        field(boxed, "title"),
        Type.bitstring("Draft copy"),
      );
    });

    it("boxes a single result that matched nothing as nil", () => {
      assert.deepStrictEqual(
        Model.boxResult(term({cardinality: "one"}), null),
        Type.nil(),
      );
    });

    // The SUB-TERM says what an included node is - a node carries no type of its own - so what is
    // boxed under a relationship's name is whatever type the include named.
    it("boxes an included to-one as its own struct", () => {
      const included = node();
      included.includes = {
        project: {includes: {}, row: {id: "p1", name: "Website"}},
      };

      const boxed = Model.boxResult(
        term({
          include: {
            project: {cardinality: "one", entity: PROJECT, include: {}},
          },
        }),
        [included],
      );

      assert.deepStrictEqual(
        field(field(boxed.data[0], "project"), "name"),
        Type.bitstring("Website"),
      );
    });

    it("boxes a to-one include that matched nothing as nil", () => {
      const included = node();
      included.includes = {project: null};

      const boxed = Model.boxResult(
        term({
          include: {
            project: {cardinality: "one", entity: PROJECT, include: {}},
          },
        }),
        [included],
      );

      assert.deepStrictEqual(field(boxed.data[0], "project"), Type.nil());
    });

    it("boxes an included to-many as a list of structs", () => {
      const included = node();
      included.includes = {
        tags: [{includes: {}, row: {id: "p1", name: "Website"}}],
      };

      const boxed = Model.boxResult(
        term({
          include: {tags: {cardinality: "set", entity: PROJECT, include: {}}},
        }),
        [included],
      );

      assert.equal(field(boxed.data[0], "tags").data.length, 1);
    });

    it("leaves a relationship the term did not include unasked-for", () => {
      const boxed = Model.boxResult(term({cardinality: "one"}), node());

      assert.deepStrictEqual(field(boxed, "tags"), Model.notIncluded("tags"));
    });
  });

  describe("computeSortKeys()", () => {
    it("computes a null sort key for a server-only string, whose value never arrives", () => {
      const attributes = Model.computeSortKeys(TASK, {id: "t1", title: "Łódź"});

      assert.isNull(attributes.internal_notes_sort);
    });

    it("computes a null sort key for an unset value", () => {
      const attributes = Model.computeSortKeys(TASK, {id: "t1", title: null});

      assert.isNull(attributes.title_sort);
    });

    it("computes a sort key for every string attribute", () => {
      const attributes = Model.computeSortKeys(TASK, {
        id: "t1",
        internal_notes: "Ödön",
        title: "Łódź",
      });

      assert.equal(attributes.internal_notes_sort, "odon");
      assert.equal(attributes.title_sort, "lodz");
    });

    it("computes no sort key for an attribute of another type", () => {
      const attributes = Model.computeSortKeys(TASK, {done: false, id: "t1"});

      assert.isUndefined(attributes.done_sort);
      assert.isUndefined(attributes.id_sort);
    });

    it("computes the sort key of a string attribute", () => {
      const attributes = Model.computeSortKeys(TASK, {id: "t1", title: "Łódź"});

      assert.equal(attributes.title_sort, "lodz");
    });

    // Both callers file the object they passed in, so handing back a copy would file a row with
    // no keys on it.
    it("writes into the object it was given and returns it", () => {
      const attributes = {id: "t1", title: "Łódź"};

      assert.strictEqual(Model.computeSortKeys(TASK, attributes), attributes);
      assert.equal(attributes.title_sort, "lodz");
    });
  });

  describe("unbox()", () => {
    it("unboxes a string and a uuid as the text they hold", () => {
      assert.equal(
        Model.unbox(Type.bitstring("Draft copy"), "string"),
        "Draft copy",
      );
      assert.equal(Model.unbox(Type.bitstring("t1"), "uuid"), "t1");
    });

    it("unboxes a boolean, an integer and a float as plain values", () => {
      assert.isFalse(Model.unbox(Type.boolean(false), "boolean"));
      assert.equal(Model.unbox(Type.integer(7), "integer"), 7);
      assert.equal(Model.unbox(Type.float(1.5), "float"), 1.5);
    });

    it("unboxes nil as nothing", () => {
      assert.isNull(Model.unbox(Type.nil(), "string"));
    });

    it("unboxes a date the way the wire spells one", () => {
      const date = Type.map([
        [Type.atom("__struct__"), Type.alias("Date")],
        [Type.atom("calendar"), Type.alias("Calendar.ISO")],
        [Type.atom("day"), Type.integer(6)],
        [Type.atom("month"), Type.integer(8)],
        [Type.atom("year"), Type.integer(2026)],
      ]);

      assert.equal(Model.unbox(date, "date"), "2026-08-06");
    });

    // One spelling per instant is what lets a datetime compare as a plain string, so a value
    // written at any precision leaves here with six fractional digits.
    it("unboxes a datetime at the precision the wire carries", () => {
      assert.equal(
        Model.unbox(datetime(22508, 6), "datetime"),
        "2026-08-16T15:18:13.022508Z",
      );
      assert.equal(
        Model.unbox(datetime(0, 0), "datetime"),
        "2026-08-16T15:18:13.000000Z",
      );
      assert.equal(
        Model.unbox(datetime(5, 1), "datetime"),
        "2026-08-16T15:18:13.500000Z",
      );
    });

    it("unboxes an enum label as the atom names it", () => {
      assert.equal(Model.unbox(Type.atom("open"), "enum"), "open");
    });

    it("unboxes an enum naming a module without the prefix it carries", () => {
      assert.equal(
        Model.unbox(Type.alias("MyApp.Status.Open"), "enum"),
        "MyApp.Status.Open",
      );
    });

    // One spelling per time of day, the same rule a datetime follows and for the same reason -
    // and a time read back from a column is always six digits, so a value written at fewer would
    // not equal the one the server holds.
    it("unboxes a time at the precision the wire carries", () => {
      assert.equal(Model.unbox(time(22508, 6), "time"), "11:00:00.022508");
      assert.equal(Model.unbox(time(0, 0), "time"), "11:00:00.000000");
      assert.equal(Model.unbox(time(5, 1), "time"), "11:00:00.500000");
    });

    // What leaves here goes back through boxing when a result is read, so the pair has to be a
    // round trip - a value that changed shape on the way out would compare against rows fine and
    // render as something else.
    it("round-trips every admitted type through boxing", () => {
      const row = {
        done: false,
        due_on: "2026-08-16",
        id: "t1",
        position: 7,
        status: "open",
        title: "Draft copy",
        updated_at: "2026-08-16T15:18:13.022508Z",
        weight: 1.5,
      };

      const boxed = Model.box(TASK, row);

      for (const [name, attributeType] of Object.entries(
        Model.entry(TASK).attributes,
      )) {
        if (name in row) {
          assert.deepEqual(
            Model.unbox(field(boxed, name), attributeType),
            row[name],
            `round trip failed for ${name}`,
          );
        }
      }
    });
  });

  describe("unboxRow()", () => {
    it("leaves a server-only attribute out rather than unboxing its sentinel", () => {
      const unboxed = Model.unboxRow(TASK, Model.box(TASK, row()));

      assert.notProperty(unboxed, "internal_notes");
    });

    it("spells a settable field holding nothing as null", () => {
      const unboxed = Model.unboxRow(TASK, Model.box(TASK, row({title: null})));

      assert.isNull(unboxed.title);
    });

    it("spells a struct's settable fields the way the wire does", () => {
      const unboxed = Model.unboxRow(TASK, Model.box(TASK, row()));

      assert.deepStrictEqual(unboxed, {
        done: false,
        due_on: "2026-08-16",
        position: 7,
        project_id: "p1",
        starts_at: "11:00:00.000000",
        status: "open",
        title: "Draft copy",
        weight: 1.5,
      });
    });
  });

  describe("emptyMetadata()", () => {
    // Equal to what a row carrying no revisions is boxed with, which is the point: one list of
    // fields answers for a struct that was read and for one built from nothing.
    it("builds the metadata a struct that arrived from nowhere carries", () => {
      assert.deepEqual(
        Model.emptyMetadata(),
        field(Model.box(TASK, row()), "__meta__"),
      );
    });

    // Hologram.Entity.Metadata declares five fields, and a struct short of one answers a read of
    // it with a KeyError where the server's struct answers nil.
    it("carries every field the entity metadata struct declares", () => {
      const metadata = Model.emptyMetadata();

      assert.deepEqual(
        Object.values(metadata.data)
          .map(([key]) => key.value)
          .sort(),
        [
          "__struct__",
          "attribute_ops",
          "claim",
          "relationship_ops",
          "revisions",
          "stamp",
        ],
      );
    });
  });

  describe("entry()", () => {
    it("returns the type's attributes and relationships", () => {
      const entry = Model.entry(TASK);

      assert.equal(entry.attributes.title, "string");
      assert.deepEqual(entry.relationships.tags, {
        optional: true,
        toMany: true,
        type: "MyApp.Tag",
      });
    });

    // In the order the declaration spells them rather than sorted: that order is what an enum
    // attribute is ordered by, so the list is the answer rather than a set of labels.
    it("returns the declared values of an enum attribute", () => {
      const entry = Model.entry(TASK);

      assert.deepEqual(entry.enumValues, {status: ["open", "done"]});
    });

    it("returns the names the client may not have as a set", () => {
      const entry = Model.entry(TASK);

      assert.isTrue(entry.serverOnly.has("internal_notes"));
      assert.isFalse(entry.serverOnly.has("title"));
    });

    // Boxed rather than spelled the way the wire spells values: a default is applied to a struct
    // field, and a struct field holds what the declaration wrote.
    it("returns the declared defaults as the boxed terms they were baked as", () => {
      const entry = Model.entry(TASK);

      assert.deepEqual(entry.defaults, {
        done: Type.boolean(false),
        position: Type.integer(7),
      });
    });

    it("returns the framework-owned attribute names", () => {
      assert.deepEqual(Model.entry(TASK).frameworkAttributes, []);
    });

    it("returns whether a relationship is optional", () => {
      const entry = Model.entry(TASK);

      assert.isFalse(entry.relationships.project.optional);
      assert.isTrue(entry.relationships.tags.optional);
    });

    it("builds a declared range as the struct a membership test walks", () => {
      assert.deepEqual(
        Model.entry(TASK).constraints.position.in,
        Type.range(0, 100, 5),
      );
    });

    // Compiled here because a pattern exists only inside the runtime that compiled it. The
    // options travel with the source, so a caseless pattern stays caseless - and they travel as
    // the TERM they are, because not every one of them is a name: ~r/x/s reads back as
    // [:dotall, {:newline, :anycrlf}], which is the shape the second option here stands for.
    it("compiles a declared format into the regex struct a violation carries", () => {
      const format = Model.entry(TASK).constraints.title.format;

      assert.deepEqual(field(format, "__struct__"), Type.alias("Regex"));
      assertBoxedStrictEqual(
        field(format, "source"),
        Type.bitstring("^[a-z ]+$"),
      );

      assertBoxedStrictEqual(
        field(format, "opts"),
        Type.list([
          Type.atom("caseless"),
          Type.tuple([Type.atom("newline"), Type.atom("anycrlf")]),
        ]),
      );

      const matched = Erlang_Re["run/3"](
        Type.bitstring("ABC"),
        field(format, "re_pattern"),
        Type.list([Type.tuple([Type.atom("capture"), Type.atom("none")])]),
      );

      assert.deepEqual(matched, Type.atom("match"));
    });

    it("keeps bounds, lengths and flags as the build baked them", () => {
      const constraints = Model.entry(TASK).constraints;

      assert.deepEqual(constraints.weight.max, Type.float(5.0));
      assert.deepEqual(constraints.weight.min, Type.integer(0));
      assert.isTrue(constraints.weight.optional);
      assert.equal(constraints.title.max_length, 32);
      assert.equal(constraints.title.min_length, 3);
      assert.isTrue(constraints.internal_notes.unique);
    });

    it("returns nothing for an attribute declaring no constraint", () => {
      assert.isUndefined(Model.entry(TASK).constraints.done);
    });

    // A row of a type this build never told the client about is a row it cannot read - which is
    // what a bundle older than the server looks like from here.
    it("raises for a type this build does not carry", () => {
      assert.throw(
        () => Model.entry("MyApp.Unknown"),
        HologramRuntimeError,
        "entity type MyApp.Unknown is not part of this build's data model",
      );
    });
  });

  describe("notIncluded()", () => {
    // Equal to what boxing leaves in place of a relationship nobody asked for - the same sentinel
    // from both directions, so a struct built here reads like one built from a row.
    it("builds the sentinel naming the relationship nobody asked for", () => {
      assert.deepEqual(
        Model.notIncluded("tags"),
        field(Model.box(TASK, row()), "tags"),
      );
    });
  });

  describe("wireDateTime()", () => {
    it("spells an instant the way a datetime arrives on the wire", () => {
      const milliseconds = Date.UTC(2026, 7, 29, 14, 32, 7, 481);

      assert.equal(
        Model.wireDateTime(milliseconds),
        "2026-08-29T14:32:07.481000Z",
      );
    });

    it("spells a whole second with its fraction, so every value has the same shape", () => {
      const milliseconds = Date.UTC(2026, 7, 29, 14, 32, 7);

      assert.equal(
        Model.wireDateTime(milliseconds),
        "2026-08-29T14:32:07.000000Z",
      );
    });
  });

  describe("settableFields()", () => {
    it("answers the declared attributes and a to-one's reference field, sorted", () => {
      assert.deepStrictEqual(Model.settableFields(TASK), [
        "done",
        "due_on",
        "position",
        "project_id",
        "starts_at",
        "status",
        "title",
        "weight",
      ]);
    });

    it("leaves out the attributes a job's framework fills", () => {
      assert.deepStrictEqual(Model.settableFields(NOTIFY), ["reason"]);
    });
  });

  describe("relationships()", () => {
    it("returns the type's relationships with their cardinality and target", () => {
      assert.deepEqual(Model.relationships(TASK), {
        project: {optional: false, toMany: false, type: "MyApp.Project"},
        tags: {optional: true, toMany: true, type: "MyApp.Tag"},
      });
    });
  });
});
