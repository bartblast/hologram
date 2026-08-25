"use strict";

import {assert, defineRuntimeGlobals} from "./support/helpers.mjs";

import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Model from "../../assets/js/model.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();

// The boxed forms asserted here are the ones Hologram.Compiler.Encoder.encode_term! writes for
// the same values, which is what a template already reads when the server hands it a row - a
// client that built them any other way would answer one way for a synced row and another for a
// rendered one.
describe("Model", () => {
  const TASK = "MyApp.Task";

  // One attribute of every admitted type, a server-only one, and both relationship
  // cardinalities - the shape the build bakes for a type this client can hold.
  //
  // Neither relationship target has an entry of its own, deliberately: a build carries a type
  // when a query reaches it, so a relationship nothing queries through points at a name the model
  // does not hold. Boxing reads the reference field and leaves the sentinel, asking the target
  // nothing - and a query that DID include one would have put it in the model by including it.
  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [TASK]: {
          attributes: {
            done: "boolean",
            due_on: "date",
            id: "uuid",
            internal_notes: "string",
            position: "integer",
            status: "enum",
            title: "string",
            updated_at: "datetime",
            weight: "float",
          },
          enumValues: {status: ["open", "done"]},
          relationships: {
            project: {toMany: false, type: "MyApp.Project"},
            tags: {toMany: true, type: "MyApp.Tag"},
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
          [Type.atom("attribute_changes"), Type.map([])],
          [Type.atom("claim"), Type.nil()],
          [Type.atom("relationship_ops"), Type.map([])],
          [
            Type.atom("revisions"),
            Type.map([
              [Type.atom("position"), Type.integer(3)],
              [Type.atom("title"), Type.integer(5)],
            ]),
          ],
        ]),
      );
    });

    it("boxes a row carrying no revisions with an empty metadata", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(
        field(boxed, "__meta__"),
        Type.map([
          [Type.atom("__struct__"), Type.alias("Hologram.Entity.Metadata")],
          [Type.atom("attribute_changes"), Type.map([])],
          [Type.atom("claim"), Type.nil()],
          [Type.atom("relationship_ops"), Type.map([])],
          [Type.atom("revisions"), Type.map([])],
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

  describe("entry()", () => {
    it("returns the type's attributes and relationships", () => {
      const entry = Model.entry(TASK);

      assert.equal(entry.attributes.title, "string");
      assert.deepEqual(entry.relationships.tags, {
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

  describe("relationships()", () => {
    it("returns the type's relationships with their cardinality and target", () => {
      assert.deepEqual(Model.relationships(TASK), {
        project: {toMany: false, type: "MyApp.Project"},
        tags: {toMany: true, type: "MyApp.Tag"},
      });
    });
  });
});
