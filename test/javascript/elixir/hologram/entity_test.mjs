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
  const EMPTY = "MyApp.Empty";
  const NOTIFY = "MyApp.Jobs.Notify";
  const POST = "MyApp.Post";

  const newEntity = Elixir_Hologram_Entity["new/1"];
  const newEntityWithValues = Elixir_Hologram_Entity["new/2"];
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
});
