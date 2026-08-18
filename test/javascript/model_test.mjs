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

  describe("box()", () => {
    it("names the struct by its entity type", () => {
      const boxed = Model.box(TASK, row());

      assert.deepEqual(field(boxed, "__struct__"), Type.alias(TASK));
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

  describe("entry()", () => {
    it("returns the type's attributes and relationships", () => {
      const entry = Model.entry(TASK);

      assert.equal(entry.attributes.title, "string");
      assert.deepEqual(entry.relationships.tags, {
        toMany: true,
        type: "MyApp.Tag",
      });
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
