"use strict";

import {
  assert,
  assertBoxedError,
  assertBoxedStrictEqual,
  defineRuntimeGlobals,
} from "../../support/helpers.mjs";

import Bitstring from "../../../../assets/js/bitstring.mjs";
import Elixir_Hologram_Entity from "../../../../assets/js/elixir/hologram/entity.mjs";
import HologramRuntimeError from "../../../../assets/js/errors/runtime_error.mjs";
import Model from "../../../../assets/js/model.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// IMPORTANT!
// The tests mirroring the Elixir tests of Hologram.Entity.generate_id/0 are NOT in this file.
// The port delegates to Utils.uuidv7(), so the mirrored tests live in test/javascript/utils_test.mjs (describe "uuidv7()").
// This file tests only the boxing wiring of that port.
//
// The new/2 describe mirrors the corresponding describe of test/elixir/hologram/entity_test.exs,
// case for case and with the same refusal messages. What differs is the entity type: these are
// baked model entries standing for the Elixir fixtures rather than the fixtures themselves.

describe("Elixir_Hologram_Entity", () => {
  const SERVER_ONLY = "Hologram.Entity.ServerOnly";

  const ACCOUNT = "MyApp.Account";
  const DOC = "MyApp.Doc";
  const ITEM = "MyApp.Item";
  const EMPTY = "MyApp.Empty";
  const NOTIFY = "MyApp.Jobs.Notify";
  const POST = "MyApp.Post";

  const newEntity = Elixir_Hologram_Entity["new/1"];
  const newEntityWithValues = Elixir_Hologram_Entity["new/2"];
  const boxedDate = (year, month, day) =>
    Type.struct("Date", [
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("day"), Type.integer(day)],
      [Type.atom("month"), Type.integer(month)],
      [Type.atom("year"), Type.integer(year)],
    ]);

  const boxedDateTime = (year, month, day, hour = 0, offset = 0) =>
    Type.struct("DateTime", [
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("day"), Type.integer(day)],
      [Type.atom("hour"), Type.integer(hour)],
      [
        Type.atom("microsecond"),
        Type.tuple([Type.integer(0), Type.integer(0)]),
      ],
      [Type.atom("minute"), Type.integer(0)],
      [Type.atom("month"), Type.integer(month)],
      [Type.atom("second"), Type.integer(0)],
      [Type.atom("std_offset"), Type.integer(0)],
      [Type.atom("time_zone"), Type.bitstring("Etc/UTC")],
      [Type.atom("utc_offset"), Type.integer(offset)],
      [Type.atom("year"), Type.integer(year)],
      [Type.atom("zone_abbr"), Type.bitstring("UTC")],
    ]);

  // Arguments in the order a clock reads them, so a call says what it looks like it says. The
  // second was hardcoded to zero until 2026-09-06, which quietly made a three-argument call name
  // a microsecond while reading as though it named a second.
  const boxedTime = (hour, minute = 0, second = 0, microsecond = 0) =>
    Type.struct("Time", [
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("hour"), Type.integer(hour)],
      [
        Type.atom("microsecond"),
        Type.tuple([Type.integer(microsecond), Type.integer(6)]),
      ],
      [Type.atom("minute"), Type.integer(minute)],
      [Type.atom("second"), Type.integer(second)],
    ]);

  const validate = Elixir_Hologram_Entity["validate/1"];
  const validateChanges = Elixir_Hologram_Entity["validate/2"];

  const systemAttributes = {
    created_at: "datetime",
    id: "uuid",
    updated_at: "datetime",
  };

  // One entry per shape the mirrored cases need: a type declaring nothing, one declaring a
  // default and an optional attribute, one declaring relationships of both cardinalities, and a
  // job, whose three framework-owned attributes no caller may set.
  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [ACCOUNT]: {
          attributes: {
            ...systemAttributes,
            handle: "string",
            public: "boolean",
            rank: "integer",
          },
          constraints: {rank: {optional: true}},
          defaults: {public: Type.boolean(false)},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
        },
        [DOC]: {
          attributes: {
            ...systemAttributes,
            api_token: "string",
            due_on: "date",
            published_at: "datetime",
            state: "enum",
            title: "string",
            weight: "float",
          },
          constraints: {
            due_on: {optional: true},
            published_at: {optional: true},
            weight: {optional: true},
          },
          defaults: {},
          enumValues: {state: ["draft", "live"]},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: ["api_token"],
        },
        [EMPTY]: {
          attributes: {...systemAttributes},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
        },
        [NOTIFY]: {
          attributes: {
            ...systemAttributes,
            actor_id: "uuid",
            error: "string",
            status: "enum",
          },
          constraints: {},
          defaults: {status: Type.atom("queued")},
          enumValues: {status: ["queued", "running", "done", "failed"]},
          frameworkAttributes: ["actor_id", "error", "status"],
          relationships: {},
          serverOnly: ["error"],
        },
        [ITEM]: {
          attributes: {
            ...systemAttributes,
            bio: "string",
            count: "integer",
            country_code: "string",
            email: "string",
            handle: "string",
            held_at: "datetime",
            percent: "integer",
            priority: "integer",
            rating: "float",
            opens_at: "time",
            released_on: "date",
            slug: "string",
            username: "string",
          },
          constraints: {
            bio: {max_length: 10, optional: true},
            count: {max: Type.integer(10), min: Type.integer(1)},
            country_code: {length: 2, optional: true},
            email: {
              format: {opts: Type.list([]), source: "@"},
              optional: true,
            },
            handle: {
              format: {opts: Type.list([]), source: "^[a-z_]+$"},
              min_length: 3,
              optional: true,
            },
            held_at: {min: boxedDateTime(2026, 1, 1), optional: true},
            percent: {in: {first: 0, last: 100, step: 5}, optional: true},
            priority: {in: {first: 1, last: 5, step: 1}, optional: true},
            rating: {
              max: Type.float(5.0),
              min: Type.integer(0),
              optional: true,
            },
            opens_at: {
              max: boxedTime(20),
              min: boxedTime(8),
              optional: true,
            },
            released_on: {max: boxedDate(2030, 12, 31), optional: true},
            slug: {optional: true, unique: true},
            username: {max_length: 8, min_length: 3, optional: true},
          },
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
        },
        [POST]: {
          attributes: {...systemAttributes},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {
            author: {optional: false, toMany: false, type: ACCOUNT},
            editor: {optional: true, toMany: false, type: ACCOUNT},
            tags: {optional: false, toMany: true, type: EMPTY},
          },
          serverOnly: [],
        },
      },
    };

    Model.reset();
  });

  const field = (struct, name) =>
    struct.data[Type.encodeMapKey(Type.atom(name))][1];

  const structField = field;

  describe("generate_id/0", () => {
    it("returns a boxed version 7 UUID string", () => {
      const result = Elixir_Hologram_Entity["generate_id/0"]();

      assert.isTrue(Type.isBitstring(result));

      assert.match(
        Bitstring.toText(result),
        /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    });
  });

  describe("new/2", () => {
    it("returns a struct of the given entity type with a generated id and nil system timestamps", () => {
      const entity = newEntity(Type.alias(EMPTY));

      assert.deepEqual(field(entity, "__struct__"), Type.alias(EMPTY));

      assert.match(
        Bitstring.toText(field(entity, "id")),
        /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );

      assert.deepEqual(field(entity, "created_at"), Type.nil());
      assert.deepEqual(field(entity, "updated_at"), Type.nil());
    });

    it("applies declared defaults to absent attributes", () => {
      const entity = newEntity(Type.alias(ACCOUNT));

      assert.deepEqual(field(entity, "public"), Type.boolean(false));
      assert.deepEqual(field(entity, "handle"), Type.nil());
      assert.deepEqual(field(entity, "rank"), Type.nil());
    });

    it("keeps given attribute values over declared defaults", () => {
      const values = Type.map([[Type.atom("public"), Type.boolean(true)]]);
      const entity = newEntityWithValues(Type.alias(ACCOUNT), values);

      assert.deepEqual(field(entity, "public"), Type.boolean(true));
    });

    it("accepts values as a map", () => {
      const values = Type.map([[Type.atom("handle"), Type.bitstring("bart")]]);
      const entity = newEntityWithValues(Type.alias(ACCOUNT), values);

      assertBoxedStrictEqual(field(entity, "handle"), Type.bitstring("bart"));
    });

    it("accepts values as a keyword list", () => {
      const values = Type.keywordList([
        [Type.atom("handle"), Type.bitstring("blast")],
      ]);

      const entity = newEntityWithValues(Type.alias(ACCOUNT), values);

      assertBoxedStrictEqual(field(entity, "handle"), Type.bitstring("blast"));
    });

    it("keeps a given id", () => {
      const values = Type.map([[Type.atom("id"), Type.bitstring("id_1")]]);
      const entity = newEntityWithValues(Type.alias(ACCOUNT), values);

      assertBoxedStrictEqual(field(entity, "id"), Type.bitstring("id_1"));
    });

    it("sets given to-one relationship references", () => {
      const values = Type.map([
        [Type.atom("author_id"), Type.bitstring("id_2")],
      ]);

      const entity = newEntityWithValues(Type.alias(POST), values);

      assertBoxedStrictEqual(
        field(entity, "author_id"),
        Type.bitstring("id_2"),
      );
      assert.deepEqual(field(entity, "editor_id"), Type.nil());
    });

    it("builds a job queued, with nothing recorded of a run", () => {
      const job = newEntity(Type.alias(NOTIFY));

      assert.deepEqual(field(job, "status"), Type.atom("queued"));
      assert.deepEqual(field(job, "actor_id"), Type.nil());
      assert.deepEqual(field(job, "error"), Type.nil());
    });

    // What Model.box leaves in place of a relationship, so a row built here reads like one that
    // arrived: the sentinel naming it, and the reference field of a to-one beside it.
    it("builds the relationship fields the way a synced row carries them", () => {
      const entity = newEntity(Type.alias(POST));

      assert.deepEqual(field(entity, "tags"), Model.notIncluded("tags"));
      assert.deepEqual(field(entity, "author"), Model.notIncluded("author"));
      assert.deepEqual(field(entity, "author_id"), Type.nil());
    });

    it("carries the framework's own state empty", () => {
      const entity = newEntity(Type.alias(EMPTY));

      assert.deepEqual(field(entity, "__meta__"), Model.emptyMetadata());
    });

    it("raises on a role grant", () => {
      assertBoxedError(
        () => newEntity(Type.alias("Hologram.Auth.RoleGrant")),
        "ArgumentError",
        "role grants are written only through grant_role/revoke_role",
      );
    });

    it("raises on an assigned relationship value", () => {
      const values = Type.map([[Type.atom("author"), Type.bitstring("id_2")]]);

      assertBoxedError(
        () => newEntityWithValues(Type.alias(POST), values),
        "ArgumentError",
        `relationship :author of ${POST} cannot be assigned at construction - set a to-one reference via the :author_id field, to-many edges via add_relationship`,
      );
    });

    it("raises on an assigned job status", () => {
      const values = Type.map([[Type.atom("status"), Type.atom("done")]]);

      assertBoxedError(
        () => newEntityWithValues(Type.alias(NOTIFY), values),
        "ArgumentError",
        `:status of ${NOTIFY} is set by the framework - a job is enqueued as queued, and the worker records the rest`,
      );
    });

    it("raises on an assigned job actor", () => {
      const values = Type.map([
        [
          Type.atom("actor_id"),
          Type.bitstring("018f4c11-1111-7111-8111-111111111111"),
        ],
      ]);

      assertBoxedError(
        () => newEntityWithValues(Type.alias(NOTIFY), values),
        "ArgumentError",
        `:actor_id of ${NOTIFY} is set by the framework - a job is enqueued as queued, and the worker records the rest`,
      );
    });

    // The model lists them in the order the server's own search walks, so a construction naming
    // two of them is refused for the same one on both tiers.
    it("raises for the framework attribute the model lists first", () => {
      const values = Type.map([
        [Type.atom("error"), Type.bitstring("boom")],
        [Type.atom("status"), Type.atom("done")],
      ]);

      assertBoxedError(
        () => newEntityWithValues(Type.alias(NOTIFY), values),
        "ArgumentError",
        `:error of ${NOTIFY} is set by the framework - a job is enqueued as queued, and the worker records the rest`,
      );
    });

    it("raises on an undeclared field", () => {
      const values = Type.map([[Type.atom("zzz"), Type.integer(1)]]);

      assertBoxedError(
        () => newEntityWithValues(Type.alias(ACCOUNT), values),
        "KeyError",
        "key :zzz not found",
      );
    });

    // A type this build never told the client about is one it cannot construct - which is what a
    // bundle older than the server looks like from here.
    it("raises for a type this build does not carry", () => {
      assert.throw(
        () => newEntity(Type.alias("MyApp.Unknown")),
        HologramRuntimeError,
        "entity type MyApp.Unknown is not part of this build's data model",
      );
    });

    it("raises on values that are neither a map nor a keyword list", () => {
      assertBoxedError(
        () => newEntityWithValues(Type.alias(ACCOUNT), Type.atom("nope")),
        "ArgumentError",
        ":nope is not a map or a keyword list of entity field values",
      );
    });
  });

  // Mirrors the corresponding describes of test/elixir/hologram/entity_test.exs, plus the cases
  // that file leaves to validator_test.exs - one per admitted attribute type, since the type
  // check is the port's own rather than a delegation.
  //
  // The constraint checks are NOT here. The cases needing them - a value outside a bound, a
  // string of the wrong length, several reasons accumulating on one field - land with the next
  // commit, which is what turns valueErrors from a type check into the full fold.
  describe("validate/1", () => {
    const doc = (overrides = {}) =>
      newEntityWithValues(
        Type.alias(DOC),
        Type.map(
          Object.entries({
            api_token: Type.bitstring("t"),
            state: Type.atom("draft"),
            title: Type.bitstring("Draft copy"),
            ...overrides,
          }).map(([name, value]) => [Type.atom(name), value]),
        ),
      );

    it("returns :ok for a valid entity struct", () => {
      assert.deepEqual(validate(doc()), Type.atom("ok"));
    });

    it("reports violations grouped by field name", () => {
      const entity = doc({state: Type.integer(1), title: Type.nil()});

      assert.deepEqual(
        validate(entity),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [
              Type.atom("state"),
              Type.list([
                Type.tuple([
                  Type.atom("values"),
                  Type.list([Type.atom("draft"), Type.atom("live")]),
                ]),
              ]),
            ],
            [Type.atom("title"), Type.list([Type.atom("required")])],
          ]),
        ]),
      );
    });

    it("reports a missing required reference", () => {
      const post = newEntity(Type.alias(POST));

      assert.deepEqual(
        validate(post),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [Type.atom("author_id"), Type.list([Type.atom("required")])],
          ]),
        ]),
      );
    });

    it("accepts a to-one reference holding a canonical entity id", () => {
      const values = Type.map([
        [
          Type.atom("author_id"),
          Type.bitstring("018f4c11-1111-7111-8111-111111111111"),
        ],
      ]);

      assert.deepEqual(
        validate(newEntityWithValues(Type.alias(POST), values)),
        Type.atom("ok"),
      );
    });

    it("reports a to-one reference that is not a canonical entity id", () => {
      const values = Type.map([
        [Type.atom("author_id"), Type.bitstring("nope")],
      ]);

      assert.deepEqual(
        validate(newEntityWithValues(Type.alias(POST), values)),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [
              Type.atom("author_id"),
              Type.list([Type.tuple([Type.atom("type"), Type.atom("uuid")])]),
            ],
          ]),
        ]),
      );
    });

    // Ruled 2026-08-28: a sentinel is not a value that failed a check, it is the absence of this
    // client's permission to see one, so it is passed over. What the client can still judge is a
    // server-only attribute that is required and simply empty, which the case below pins.
    it("passes over a server-only value the client may not have", () => {
      const entity = doc();
      const sentinel = Type.struct(SERVER_ONLY, [
        [Type.atom("attribute"), Type.atom("api_token")],
      ]);

      const withSentinel = Type.map([
        ...Object.values(entity.data).map(([key, value]) =>
          key.value === "api_token" ? [key, sentinel] : [key, value],
        ),
      ]);

      assert.deepEqual(validate(withSentinel), Type.atom("ok"));
    });

    it("reports a required server-only attribute the struct leaves empty", () => {
      assert.deepEqual(
        validate(doc({api_token: Type.nil()})),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [Type.atom("api_token"), Type.list([Type.atom("required")])],
          ]),
        ]),
      );
    });

    // The system attributes carry no declaration to judge and a relationship is followed rather
    // than validated, so neither reaches the checks - which a created_at holding an integer
    // proves, where a struct that merely looked right would prove nothing.
    it("judges neither the system attributes nor the relationships", () => {
      const values = Type.map([
        [Type.atom("created_at"), Type.integer(1)],
        [
          Type.atom("author_id"),
          Type.bitstring("018f4c11-1111-7111-8111-111111111111"),
        ],
      ]);

      assert.deepEqual(
        validate(newEntityWithValues(Type.alias(POST), values)),
        Type.atom("ok"),
      );
    });

    it("reports a boolean, a date, a datetime, a float, an integer and a string of the wrong type", () => {
      const cases = [
        ["public", Type.integer(1), "boolean"],
        ["rank", Type.bitstring("5"), "integer"],
        ["handle", Type.integer(5), "string"],
      ];

      for (const [name, value, attributeType] of cases) {
        const values = Type.map([
          [Type.atom("handle"), Type.bitstring("bart")],
          [Type.atom(name), value],
        ]);

        assert.deepEqual(
          validate(newEntityWithValues(Type.alias(ACCOUNT), values)),
          Type.tuple([
            Type.atom("error"),
            Type.map([
              [
                Type.atom(name),
                Type.list([
                  Type.tuple([Type.atom("type"), Type.atom(attributeType)]),
                ]),
              ],
            ]),
          ]),
          `expected a type violation for ${name}`,
        );
      }
    });

    it("reports an integer outside what its column can hold", () => {
      const values = Type.map([
        [Type.atom("handle"), Type.bitstring("bart")],
        [Type.atom("rank"), Type.integer(9223372036854775808n)],
      ]);

      assert.deepEqual(
        validate(newEntityWithValues(Type.alias(ACCOUNT), values)),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [
              Type.atom("rank"),
              Type.list([
                Type.tuple([Type.atom("type"), Type.atom("integer")]),
              ]),
            ],
          ]),
        ]),
      );
    });

    it("reports a string that is not valid text", () => {
      const values = Type.map([
        [Type.atom("handle"), Bitstring.fromBytes([255])],
      ]);

      assert.deepEqual(
        validate(newEntityWithValues(Type.alias(ACCOUNT), values)),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [
              Type.atom("handle"),
              Type.list([Type.tuple([Type.atom("type"), Type.atom("string")])]),
            ],
          ]),
        ]),
      );
    });

    // Map.take omits a key the struct lacks, so the server reports such a field as required. A
    // struct from new/2 or from a boxed row carries every field, so this is the shape an app
    // reaches by dropping one - and reading it as undefined would crash where the server answers.
    it("reports a declared field the struct does not carry as required", () => {
      const entity = newEntityWithValues(
        Type.alias(ACCOUNT),
        Type.map([[Type.atom("handle"), Type.bitstring("bart")]]),
      );

      const withoutHandle = Type.map(
        Object.values(entity.data).filter(([key]) => key.value !== "handle"),
      );

      assert.deepEqual(
        validate(withoutHandle),
        Type.tuple([
          Type.atom("error"),
          Type.map([[Type.atom("handle"), Type.list([Type.atom("required")])]]),
        ]),
      );
    });

    it("raises for something that is not an entity struct", () => {
      assertBoxedError(
        () => validate(Type.atom("nope")),
        "ArgumentError",
        ":nope is not an entity struct",
      );
    });
  });

  describe("validate/2", () => {
    it("returns :ok for valid changes given as a keyword list", () => {
      const changes = Type.keywordList([
        [Type.atom("handle"), Type.bitstring("bart")],
      ]);

      assert.deepEqual(
        validateChanges(Type.alias(ACCOUNT), changes),
        Type.atom("ok"),
      );
    });

    it("does not require absent fields", () => {
      assert.deepEqual(
        validateChanges(Type.alias(ACCOUNT), Type.map([])),
        Type.atom("ok"),
      );
    });

    it("reports violations grouped by field name", () => {
      const changes = Type.map([
        [Type.atom("handle"), Type.integer(5)],
        [Type.atom("public"), Type.integer(1)],
      ]);

      assert.deepEqual(
        validateChanges(Type.alias(ACCOUNT), changes),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [
              Type.atom("handle"),
              Type.list([Type.tuple([Type.atom("type"), Type.atom("string")])]),
            ],
            [
              Type.atom("public"),
              Type.list([
                Type.tuple([Type.atom("type"), Type.atom("boolean")]),
              ]),
            ],
          ]),
        ]),
      );
    });

    it("reports nil for a non-optional attribute as required", () => {
      const changes = Type.map([[Type.atom("handle"), Type.nil()]]);

      assert.deepEqual(
        validateChanges(Type.alias(ACCOUNT), changes),
        Type.tuple([
          Type.atom("error"),
          Type.map([[Type.atom("handle"), Type.list([Type.atom("required")])]]),
        ]),
      );
    });

    it("accepts nil for an optional attribute", () => {
      const changes = Type.map([[Type.atom("rank"), Type.nil()]]);

      assert.deepEqual(
        validateChanges(Type.alias(ACCOUNT), changes),
        Type.atom("ok"),
      );
    });

    // A form never produces a sentinel, so a present pair is judged like any other - the write is
    // what refuses a client naming a server-only field, by name rather than by value.
    it("judges a server-only pair like any other", () => {
      const changes = Type.map([[Type.atom("api_token"), Type.bitstring("t")]]);

      assert.deepEqual(
        validateChanges(Type.alias(DOC), changes),
        Type.atom("ok"),
      );
    });

    it("reports a to-many relationship name as unknown", () => {
      const changes = Type.map([[Type.atom("tags"), Type.list([])]]);

      assert.deepEqual(
        validateChanges(Type.alias(POST), changes),
        Type.tuple([
          Type.atom("error"),
          Type.map([[Type.atom("tags"), Type.list([Type.atom("unknown")])]]),
        ]),
      );
    });

    it("reports an undeclared name as unknown", () => {
      const changes = Type.map([[Type.atom("zzz"), Type.integer(1)]]);

      assert.deepEqual(
        validateChanges(Type.alias(ACCOUNT), changes),
        Type.tuple([
          Type.atom("error"),
          Type.map([[Type.atom("zzz"), Type.list([Type.atom("unknown")])]]),
        ]),
      );
    });

    it("reports a system attribute as unknown", () => {
      const changes = Type.map([[Type.atom("created_at"), Type.nil()]]);

      assert.deepEqual(
        validateChanges(Type.alias(ACCOUNT), changes),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [Type.atom("created_at"), Type.list([Type.atom("unknown")])],
          ]),
        ]),
      );
    });
  });

  // Mirrors the constraint cases of test/elixir/hologram/entity/validator_test.exs (describe
  // "validate/2") over the same declarations, and the accumulate case of entity_test.exs.
  describe("validate/2 - the declared constraints", () => {
    const item = (overrides) =>
      validateChanges(
        Type.alias(ITEM),
        Type.map(
          Object.entries(overrides).map(([name, value]) => [
            Type.atom(name),
            value,
          ]),
        ),
      );

    const violation = (name, reason) =>
      Type.tuple([
        Type.atom("error"),
        Type.map([[Type.atom(name), Type.list([reason])]]),
      ]);

    it("accepts values sitting on the declared bounds", () => {
      assert.deepEqual(item({count: Type.integer(1)}), Type.atom("ok"));
      assert.deepEqual(item({count: Type.integer(10)}), Type.atom("ok"));
      assert.deepEqual(item({rating: Type.float(0.0)}), Type.atom("ok"));
      assert.deepEqual(item({rating: Type.float(5.0)}), Type.atom("ok"));
      assert.deepEqual(item({percent: Type.integer(0)}), Type.atom("ok"));
      assert.deepEqual(item({percent: Type.integer(100)}), Type.atom("ok"));

      assert.deepEqual(
        item({held_at: boxedDateTime(2026, 1, 1)}),
        Type.atom("ok"),
      );

      assert.deepEqual(item({opens_at: boxedTime(8)}), Type.atom("ok"));
      assert.deepEqual(item({opens_at: boxedTime(20)}), Type.atom("ok"));

      assert.deepEqual(
        item({released_on: boxedDate(2030, 12, 31)}),
        Type.atom("ok"),
      );
    });

    it("reports a value below the declared minimum", () => {
      assert.deepEqual(
        item({count: Type.integer(0)}),
        violation("count", Type.tuple([Type.atom("min"), Type.integer(1)])),
      );
    });

    it("reports a value above the declared maximum", () => {
      assert.deepEqual(
        item({count: Type.integer(11)}),
        violation("count", Type.tuple([Type.atom("max"), Type.integer(10)])),
      );
    });

    // The one case the encoding decision rests on: rating declares an integer minimum beside a
    // float maximum, so the two bounds reach the checks as different kinds of number and the
    // reason carries back the literal that was written.
    it("compares a float against bounds written as an integer and as a float", () => {
      assert.deepEqual(
        item({rating: Type.float(-0.5)}),
        violation("rating", Type.tuple([Type.atom("min"), Type.integer(0)])),
      );

      assert.deepEqual(
        item({rating: Type.float(5.5)}),
        violation("rating", Type.tuple([Type.atom("max"), Type.float(5.0)])),
      );
    });

    it("reports a datetime before the declared minimum", () => {
      assert.deepEqual(
        item({held_at: boxedDateTime(2025, 12, 31)}),
        violation(
          "held_at",
          Type.tuple([Type.atom("min"), boxedDateTime(2026, 1, 1)]),
        ),
      );
    });

    // An instant asks both readers, so a non-integer in either half refuses it.
    it("reports an instant field that is not an integer as a type violation", () => {
      const instantWith = (overrides) =>
        Type.struct("DateTime", [
          [Type.atom("calendar"), Type.alias("Calendar.ISO")],
          [Type.atom("day"), overrides.day ?? Type.integer(1)],
          [Type.atom("hour"), overrides.hour ?? Type.integer(12)],
          [
            Type.atom("microsecond"),
            overrides.microsecond ??
              Type.tuple([Type.integer(0), Type.integer(0)]),
          ],
          [Type.atom("minute"), Type.integer(0)],
          [Type.atom("month"), overrides.month ?? Type.integer(6)],
          [Type.atom("second"), Type.integer(0)],
          [Type.atom("std_offset"), Type.integer(0)],
          [Type.atom("time_zone"), Type.bitstring("Etc/UTC")],
          [Type.atom("utc_offset"), Type.integer(0)],
          [Type.atom("year"), overrides.year ?? Type.integer(2026)],
          [Type.atom("zone_abbr"), Type.bitstring("UTC")],
        ]);

      const instantViolation = violation(
        "held_at",
        Type.tuple([Type.atom("type"), Type.atom("datetime")]),
      );

      assert.deepEqual(
        item({held_at: instantWith({month: Type.float(6.5)})}),
        instantViolation,
      );

      assert.deepEqual(
        item({held_at: instantWith({hour: Type.float(12.0)})}),
        instantViolation,
      );

      assert.deepEqual(
        item({held_at: instantWith({year: Type.bitstring("2026")})}),
        instantViolation,
      );

      // The date half is fine and the clock half is fine - only the microsecond pair is not.
      assert.deepEqual(
        item({
          held_at: instantWith({
            microsecond: Type.tuple([Type.float(0.5), Type.integer(6)]),
          }),
        }),
        instantViolation,
      );

      assert.deepEqual(item({held_at: instantWith({})}), Type.atom("ok"));
    });

    // Both halves of an instant, each alone - a valid clock does not excuse an impossible date,
    // and the other way round.
    it("reports an instant the calendar never reaches as a type violation", () => {
      const typeViolation = violation(
        "held_at",
        Type.tuple([Type.atom("type"), Type.atom("datetime")]),
      );

      assert.deepEqual(
        item({held_at: boxedDateTime(2026, 13, 40)}),
        typeViolation,
      );
      assert.deepEqual(
        item({held_at: boxedDateTime(2026, 2, 30)}),
        typeViolation,
      );
      assert.deepEqual(
        item({held_at: boxedDateTime(2026, 1, 1, 25)}),
        typeViolation,
      );
      assert.deepEqual(
        item({held_at: boxedDateTime(2028, 2, 29)}),
        Type.atom("ok"),
      );
    });

    // A zone is not a calendar question, so the four zone fields are never read - an instant an
    // hour east of UTC is a real instant and reaches the constraint pass like any other.
    it("accepts an instant carrying a time zone offset", () => {
      assert.deepEqual(
        item({held_at: boxedDateTime(2026, 6, 1, 12, 3600)}),
        Type.atom("ok"),
      );
    });

    // The instant is what is compared, not the wall clock: 2026-01-01T00:00 at an offset of one
    // hour east is 2025-12-31T23:00 UTC, which is before the bound.
    it("compares a datetime by its instant rather than by its wall clock", () => {
      assert.deepEqual(
        item({held_at: boxedDateTime(2026, 1, 1, 0, 3600)}),
        violation(
          "held_at",
          Type.tuple([Type.atom("min"), boxedDateTime(2026, 1, 1)]),
        ),
      );
    });

    // Mirrors the Elixir refusal: an impossible date is not a date, so it carries {:type, :date}
    // rather than a reason of its own.
    it("reports a date the calendar never reaches as a type violation", () => {
      assert.deepEqual(
        item({released_on: boxedDate(2026, 13, 40)}),
        violation(
          "released_on",
          Type.tuple([Type.atom("type"), Type.atom("date")]),
        ),
      );
    });

    it("accepts the last day of a leap February and refuses the day after", () => {
      assert.deepEqual(
        item({released_on: boxedDate(2024, 2, 29)}),
        Type.atom("ok"),
      );

      assert.deepEqual(
        item({released_on: boxedDate(2024, 2, 30)}),
        violation(
          "released_on",
          Type.tuple([Type.atom("type"), Type.atom("date")]),
        ),
      );

      assert.deepEqual(
        item({released_on: boxedDate(2026, 2, 29)}),
        violation(
          "released_on",
          Type.tuple([Type.atom("type"), Type.atom("date")]),
        ),
      );
    });

    it("reports a date after the declared maximum", () => {
      assert.deepEqual(
        item({released_on: boxedDate(2031, 1, 1)}),
        violation(
          "released_on",
          Type.tuple([Type.atom("max"), boxedDate(2030, 12, 31)]),
        ),
      );
    });

    // Calendar.ISO's own guards are is_integer before they are ranges, so a struct literal holding
    // a float, a string or an atom is refused rather than compared. Asked of the BOXED term: a
    // float 6.0 converts to an integer JS number, so checking the number would let it through here
    // while the server refuses it.
    it("reports a temporal field that is not an integer as a type violation", () => {
      const dateAt = (year, month, day) =>
        Type.struct("Date", [
          [Type.atom("calendar"), Type.alias("Calendar.ISO")],
          [Type.atom("day"), day],
          [Type.atom("month"), month],
          [Type.atom("year"), year],
        ]);

      const dateViolation = violation(
        "released_on",
        Type.tuple([Type.atom("type"), Type.atom("date")]),
      );

      const int = Type.integer;

      assert.deepEqual(
        item({released_on: dateAt(int(2026), Type.float(6.5), int(15))}),
        dateViolation,
      );

      // A float whose value is whole - the case a Number.isInteger check would wave through.
      assert.deepEqual(
        item({released_on: dateAt(int(2026), Type.float(6.0), int(15))}),
        dateViolation,
      );

      assert.deepEqual(
        item({released_on: dateAt(Type.bitstring("2026"), int(6), int(15))}),
        dateViolation,
      );

      assert.deepEqual(
        item({released_on: dateAt(int(2026), Type.atom("june"), int(15))}),
        dateViolation,
      );
    });

    // The same rule on a time, including both halves of the microsecond pair and a microsecond
    // that is not a pair at all - which the server answers by its clause head failing to match.
    it("reports a time field that is not an integer as a type violation", () => {
      const timeWith = (hour, microsecond) =>
        Type.struct("Time", [
          [Type.atom("calendar"), Type.alias("Calendar.ISO")],
          [Type.atom("hour"), hour],
          [Type.atom("microsecond"), microsecond],
          [Type.atom("minute"), Type.integer(0)],
          [Type.atom("second"), Type.integer(0)],
        ]);

      const pair = Type.tuple([Type.integer(0), Type.integer(6)]);

      const timeViolation = violation(
        "opens_at",
        Type.tuple([Type.atom("type"), Type.atom("time")]),
      );

      assert.deepEqual(
        item({opens_at: timeWith(Type.float(11.5), pair)}),
        timeViolation,
      );
      assert.deepEqual(
        item({opens_at: timeWith(Type.float(11.0), pair)}),
        timeViolation,
      );

      assert.deepEqual(
        item({
          opens_at: timeWith(
            Type.integer(11),
            Type.tuple([Type.float(0.5), Type.integer(6)]),
          ),
        }),
        timeViolation,
      );

      assert.deepEqual(
        item({
          opens_at: timeWith(
            Type.integer(11),
            Type.tuple([Type.integer(0), Type.float(6.0)]),
          ),
        }),
        timeViolation,
      );

      assert.deepEqual(
        item({opens_at: timeWith(Type.integer(11), Type.integer(0))}),
        timeViolation,
      );
    });

    // Mirrors Calendar.ISO.valid_time?/4, whose is_microsecond guard judges the PRECISION beside
    // the amount - a check over the clock fields alone would pass both of the last two cases.
    it("reports a time the clock never reaches as a type violation", () => {
      const typeViolation = violation(
        "opens_at",
        Type.tuple([Type.atom("type"), Type.atom("time")]),
      );

      const timeAtPrecision = (precision) =>
        Type.struct("Time", [
          [Type.atom("calendar"), Type.alias("Calendar.ISO")],
          [Type.atom("hour"), Type.integer(11)],
          [
            Type.atom("microsecond"),
            Type.tuple([Type.integer(0), Type.integer(precision)]),
          ],
          [Type.atom("minute"), Type.integer(0)],
          [Type.atom("second"), Type.integer(0)],
        ]);

      assert.deepEqual(item({opens_at: boxedTime(24)}), typeViolation);
      assert.deepEqual(item({opens_at: boxedTime(11, 60)}), typeViolation);
      assert.deepEqual(item({opens_at: boxedTime(11, 0, 60)}), typeViolation);

      assert.deepEqual(
        item({opens_at: boxedTime(11, 0, 0, 1000000)}),
        typeViolation,
      );

      assert.deepEqual(item({opens_at: timeAtPrecision(7)}), typeViolation);
      assert.deepEqual(item({opens_at: timeAtPrecision(6)}), Type.atom("ok"));
    });

    // The last microsecond of the day is a real time, so it reaches the CONSTRAINT pass and is
    // refused by the declared maximum - which a type violation would have suppressed.
    it("accepts the clock's last instant, which the declared maximum then refuses", () => {
      assert.deepEqual(
        item({opens_at: boxedTime(23, 59, 59, 999999)}),
        violation("opens_at", Type.tuple([Type.atom("max"), boxedTime(20)])),
      );
    });

    // A time of day is compared by the clock it names and nothing else - there is no date to
    // fold in and no zone to move it by, which is what separates it from the instant above.
    it("reports a time outside the declared bounds", () => {
      assert.deepEqual(
        item({opens_at: boxedTime(7, 59)}),
        violation("opens_at", Type.tuple([Type.atom("min"), boxedTime(8)])),
      );

      assert.deepEqual(
        item({opens_at: boxedTime(21)}),
        violation("opens_at", Type.tuple([Type.atom("max"), boxedTime(20)])),
      );
    });

    // The microsecond is part of the clock, so a value one of them past the maximum is past it.
    it("compares a time by its microsecond as well as by its second", () => {
      assert.deepEqual(
        item({opens_at: boxedTime(20, 0, 0, 1)}),
        violation("opens_at", Type.tuple([Type.atom("max"), boxedTime(20)])),
      );
    });

    it("reports a value outside the declared range", () => {
      assert.deepEqual(
        item({priority: Type.integer(6)}),
        violation(
          "priority",
          Type.tuple([Type.atom("in"), Type.range(1, 5, 1)]),
        ),
      );
    });

    it("honors the step of a stepped range", () => {
      assert.deepEqual(item({percent: Type.integer(5)}), Type.atom("ok"));

      assert.deepEqual(
        item({percent: Type.integer(7)}),
        violation(
          "percent",
          Type.tuple([Type.atom("in"), Type.range(0, 100, 5)]),
        ),
      );
    });

    it("reports a string that is not the declared exact length", () => {
      assert.deepEqual(
        item({country_code: Type.bitstring("pl")}),
        Type.atom("ok"),
      );

      assert.deepEqual(
        item({country_code: Type.bitstring("pol")}),
        violation(
          "country_code",
          Type.tuple([Type.atom("length"), Type.integer(2)]),
        ),
      );
    });

    it("reports a string shorter than the declared minimum length", () => {
      assert.deepEqual(
        item({username: Type.bitstring("ab")}),
        violation(
          "username",
          Type.tuple([Type.atom("min_length"), Type.integer(3)]),
        ),
      );
    });

    it("reports a string longer than the declared maximum length", () => {
      assert.deepEqual(
        item({username: Type.bitstring("abcdefghi")}),
        violation(
          "username",
          Type.tuple([Type.atom("max_length"), Type.integer(8)]),
        ),
      );
    });

    // Counted in code points rather than in the UTF-16 units JavaScript reports: an emoji outside
    // the Basic Multilingual Plane is two units and one character, and the server counts one.
    it("counts string lengths in code points", () => {
      assert.deepEqual(
        item({country_code: Type.bitstring("ab")}),
        Type.atom("ok"),
      );

      assert.deepEqual(
        item({country_code: Type.bitstring("\u{1F600}\u{1F600}")}),
        Type.atom("ok"),
      );

      assert.deepEqual(
        item({country_code: Type.bitstring("\u{1F600}")}),
        violation(
          "country_code",
          Type.tuple([Type.atom("length"), Type.integer(2)]),
        ),
      );
    });

    it("reports a string not matching the declared pattern", () => {
      assert.deepEqual(item({email: Type.bitstring("a@b")}), Type.atom("ok"));

      const answer = item({email: Type.bitstring("nope")});
      const [name, reasons] = Object.values(answer.data[1].data)[0];

      assert.deepEqual(name, Type.atom("email"));
      assert.deepEqual(reasons.data[0].data[0], Type.atom("format"));

      assertBoxedStrictEqual(
        structField(reasons.data[0].data[1], "source"),
        Type.bitstring("@"),
      );
    });

    it("accepts a unique string holding exactly the most bytes its index carries", () => {
      assert.deepEqual(
        item({slug: Type.bitstring("a".repeat(2692))}),
        Type.atom("ok"),
      );
    });

    it("reports a unique string one byte over what its index carries", () => {
      assert.deepEqual(
        item({slug: Type.bitstring("a".repeat(2693))}),
        violation(
          "slug",
          Type.tuple([Type.atom("max_bytes"), Type.integer(2692)]),
        ),
      );
    });

    // The index stores bytes, so a two-byte character counts twice - 1346 of them is the bound
    // exactly, and one more is over it while the character count is barely half.
    it("counts a unique string's bytes rather than its characters", () => {
      assert.deepEqual(
        item({slug: Type.bitstring("\u00e0".repeat(1346))}),
        Type.atom("ok"),
      );

      assert.deepEqual(
        item({slug: Type.bitstring("\u00e0".repeat(1347))}),
        violation(
          "slug",
          Type.tuple([Type.atom("max_bytes"), Type.integer(2692)]),
        ),
      );
    });

    it("leaves a string that is not unique unbounded", () => {
      assert.deepEqual(
        item({bio: Type.bitstring("a".repeat(2693))}),
        Type.tuple([
          Type.atom("error"),
          Type.map([
            [
              Type.atom("bio"),
              Type.list([
                Type.tuple([Type.atom("max_length"), Type.integer(10)]),
              ]),
            ],
          ]),
        ]),
      );
    });

    // Sorted the way Elixir sorts the {name, reason} pairs, which is what puts the format reason
    // before the min_length one - the port sorts the boxed tuples rather than spelling the rule.
    it("accumulates multiple reasons per field, in Elixir's own order", () => {
      const answer = item({handle: Type.bitstring("A?")});
      const [name, reasons] = Object.values(answer.data[1].data)[0];

      assert.deepEqual(name, Type.atom("handle"));
      assert.equal(reasons.data.length, 2);
      assert.deepEqual(reasons.data[0].data[0], Type.atom("format"));

      assert.deepEqual(
        reasons.data[1],
        Type.tuple([Type.atom("min_length"), Type.integer(3)]),
      );
    });

    it("suppresses the constraint checks when the value does not match its type", () => {
      assert.deepEqual(
        item({count: Type.bitstring("0")}),
        violation(
          "count",
          Type.tuple([Type.atom("type"), Type.atom("integer")]),
        ),
      );
    });
  });
});
