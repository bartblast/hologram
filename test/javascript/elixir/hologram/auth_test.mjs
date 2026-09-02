"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
  sinon,
} from "../../support/helpers.mjs";

import Elixir_Hologram_Auth, {
  deriveGrantId,
  grantEntry,
  grantId,
  signedInWriteMessage,
  trustedWriteMessage,
  unqualifiedRoleMessage,
} from "../../../../assets/js/elixir/hologram/auth.mjs";
import Batches from "../../../../assets/js/batches.mjs";
import Clock from "../../../../assets/js/clock.mjs";
import Elixir_Hologram_DB from "../../../../assets/js/elixir/hologram/db.mjs";
import LocalDatabase from "../../../../assets/js/local_database.mjs";
import Model from "../../../../assets/js/model.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors test/elixir/hologram/policy/evaluator_test.exs, case for case and in the same order:
// that suite pins the evaluator the server checks permissions with, and this one pins the client
// against it. What differs is where the two halves come from - rules from the build's model
// entry, grant rows from the pot - so the reference's injected checker becomes a row present or
// absent here.
//
// The cases this side alone has (unboxing, the store's own spelling of a type, rows the client
// does not hold) follow the mirrored ones, in their own group.
describe("Elixir_Hologram_Auth", () => {
  const DOCUMENT = "MyApp.Document";
  const FOLDER = "MyApp.Folder";
  const GRANT = "Hologram.Auth.RoleGrant";
  const USER = "MyApp.User";

  const ALICE = "018f4571-a1b2-7c3d-8e4f-000000000001";
  const BOB = "018f4571-a1b2-7c3d-8e4f-000000000002";
  const DOC = "018f4571-a1b2-7c3d-8e4f-00000000000a";
  const FOLDER_ID = "018f4571-a1b2-7c3d-8e4f-00000000000b";

  const can = Elixir_Hologram_Auth["can?/3"];

  const rule = (overrides = {}) => ({
    predicates: [],
    to: null,
    via: null,
    ...overrides,
  });

  const document = (overrides = {}) =>
    Model.box(DOCUMENT, {
      author_id: null,
      folder_id: null,
      held_at: null,
      id: DOC,
      priority: null,
      public: false,
      released_on: null,
      status: null,
      title: null,
      ...overrides,
    });

  const grantRow = (overrides) => ({
    id: `grant-${Object.values(overrides).join("-")}`,
    resource_id: null,
    resource_type: null,
    role: "viewer",
    user_id: ALICE,
    ...overrides,
  });

  const defineModel = (policy = {}, folderPolicy = {}) => {
    globalThis.Hologram.sync = {
      model: {
        [DOCUMENT]: {
          attributes: {
            author_id: "uuid",
            held_at: "datetime",
            id: "uuid",
            priority: "integer",
            public: "boolean",
            released_on: "date",
            status: "enum",
            title: "string",
          },
          enumValues: {status: ["draft", "review", "published"]},
          policy: policy,
          relationships: {folder: {toMany: false, type: FOLDER}},
          resourceType: "documents",
          roles: ["editor", "owner", "viewer"],
          serverOnly: [],
        },
        [FOLDER]: {
          attributes: {id: "uuid", archived: "boolean"},
          policy: folderPolicy,
          relationships: {},
          resourceType: "folders",
          roles: [],
          serverOnly: [],
        },
        // USER has no entry of its own, and that is what a real build looks like: the model
        // carries a type when a QUERY reaches it, and the grants window is a bare RoleGrant
        // query. Nothing here asks the target anything - the relationship is what makes user_id
        // a reference field rather than an attribute, which is the shape a grant row has.
        [GRANT]: {
          attributes: {
            id: "uuid",
            resource_id: "uuid",
            resource_type: "enum",
            role: "enum",
          },
          policy: {},
          relationships: {user: {toMany: false, type: USER}},
          resourceType: "hologram_role_grant",
          roles: [],
          serverOnly: [],
        },
      },
    };

    Model.reset();
  };

  beforeEach(() => {
    defineModel();
    LocalDatabase.reset();
  });

  // Mirrors "grants?/5" - which rule of which operation is asked at all.
  describe("grants?/5", () => {
    it("returns false for an operation with no rules", () => {
      defineModel({});

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("read"), document({public: true})),
        Type.boolean(false),
      );
    });

    it("returns true when any rule of the operation matches", () => {
      defineModel({
        read: [
          rule({predicates: [["priority", ">=", 3]]}),
          rule({predicates: [["public", "==", true]]}),
        ],
      });

      assert.deepStrictEqual(
        can(
          Type.nil(),
          Type.atom("read"),
          document({priority: 1, public: true}),
        ),
        Type.boolean(true),
      );
    });

    it("returns false when no rule of the operation matches", () => {
      defineModel({
        read: [
          rule({predicates: [["priority", ">=", 3]]}),
          rule({predicates: [["public", "==", true]]}),
        ],
      });

      assert.deepStrictEqual(
        can(
          Type.nil(),
          Type.atom("read"),
          document({priority: 1, public: false}),
        ),
        Type.boolean(false),
      );
    });

    it("returns false for an operation other than the rules' one", () => {
      defineModel({read: [rule({predicates: [["public", "==", true]]})]});

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("delete"), document({public: true})),
        Type.boolean(false),
      );
    });

    it("answers a per-role operation keyed by a tuple", () => {
      defineModel({"grant_role:viewer": [rule({to: [["own", ["editor"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({
          resource_id: DOC,
          resource_type: "documents",
          role: "editor",
        }),
      );

      const operation = (role) =>
        Type.tuple([Type.atom("grant_role"), Type.atom(role)]);

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), operation("viewer"), document()),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), operation("editor"), document()),
        Type.boolean(false),
      );
    });
  });

  // Mirrors "rule_matches?/4" - whether one rule holds, which is where the value semantics live.
  describe("rule_matches?/4", () => {
    const reads = (rules, entity, userOrId = Type.nil()) => {
      defineModel({read: rules});

      return can(userOrId, Type.atom("read"), entity);
    };

    it("requires every predicate of the rule to hold", () => {
      const rules = [
        rule({
          predicates: [
            ["public", "==", true],
            ["priority", ">=", 3],
          ],
        }),
      ];

      assert.deepStrictEqual(
        reads(rules, document({priority: 3, public: true})),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(rules, document({priority: 1, public: true})),
        Type.boolean(false),
      );
    });

    it("matches a rule without predicates", () => {
      assert.deepStrictEqual(reads([rule()], document()), Type.boolean(true));
    });

    it("evaluates equality with nil as a regular value", () => {
      const rules = [rule({predicates: [["priority", "==", null]]})];

      assert.deepStrictEqual(reads(rules, document()), Type.boolean(true));

      assert.deepStrictEqual(
        reads(rules, document({priority: 1})),
        Type.boolean(false),
      );
    });

    it("evaluates inequality with nil as a regular value", () => {
      const rules = [rule({predicates: [["priority", "!=", 1]]})];

      assert.deepStrictEqual(reads(rules, document()), Type.boolean(true));

      assert.deepStrictEqual(
        reads(rules, document({priority: 1})),
        Type.boolean(false),
      );
    });

    it("evaluates membership with nil as a regular element", () => {
      assert.deepStrictEqual(
        reads(
          [rule({predicates: [["priority", "in", [null, 3]]]})],
          document(),
        ),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", "in", [1, 3]]]})], document()),
        Type.boolean(false),
      );
    });

    it("evaluates negated membership with nil as a regular element", () => {
      assert.deepStrictEqual(
        reads(
          [rule({predicates: [["priority", "not_in", [1, 3]]]})],
          document(),
        ),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(
          [rule({predicates: [["priority", "not_in", [null, 3]]]})],
          document(),
        ),
        Type.boolean(false),
      );
    });

    it("evaluates ordering comparisons", () => {
      const entity = document({priority: 3});

      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", ">=", 3]]})], entity),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", "<=", 3]]})], entity),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", ">", 3]]})], entity),
        Type.boolean(false),
      );

      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", "<", 3]]})], entity),
        Type.boolean(false),
      );
    });

    // The operators matter: comparing null with a number coerces it to zero in JavaScript, so a
    // check that only tried >= would pass whether the rule is honoured or not.
    it("never matches ordering comparisons against a missing value", () => {
      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", ">=", 3]]})], document()),
        Type.boolean(false),
      );

      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", "<=", 3]]})], document()),
        Type.boolean(false),
      );

      assert.deepStrictEqual(
        reads([rule({predicates: [["priority", "<", 3]]})], document()),
        Type.boolean(false),
      );

      assert.deepStrictEqual(
        reads(
          [rule({predicates: [["priority", ">=", null]]})],
          document({priority: 3}),
        ),
        Type.boolean(false),
      );
    });

    // Temporal values compare as the strings the wire spells them with, whose character order IS
    // their calendar order - which is what lets one comparison serve every type.
    it("orders temporal values by their calendar semantics", () => {
      const entity = document({
        held_at: "2026-07-17T12:00:00.000000Z",
        released_on: "2026-07-17",
      });

      assert.deepStrictEqual(
        reads(
          [
            rule({
              predicates: [["held_at", ">", "2026-01-01T00:00:00.000000Z"]],
            }),
          ],
          entity,
        ),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(
          [rule({predicates: [["released_on", "<", "2027-01-01"]]})],
          entity,
        ),
        Type.boolean(true),
      );
    });

    // Declared order, not label order: "published" is the LAST declared value of
    // ["draft", "review", "published"] while it sorts before "review" as a string, so a label
    // comparison would answer the other way.
    it("orders enum values by their declared position", () => {
      const rules = [rule({predicates: [["status", ">=", "review"]]})];

      assert.deepStrictEqual(
        reads(rules, document({status: "published"})),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(rules, document({status: "draft"})),
        Type.boolean(false),
      );
    });

    // A rule and the filter mirroring it have to admit the same rows, so a string compares here
    // the way a query compares it - by its derived key, then by the value behind it.
    it("compares a string attribute by its sort key", () => {
      const rules = [rule({predicates: [["title", ">=", "m"]]})];

      assert.deepStrictEqual(
        reads(rules, document({title: "Mango"})),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(rules, document({title: "Łódź"})),
        Type.boolean(false),
      );
    });

    it("settles a string bound that shares a key by the value itself", () => {
      const rules = [rule({predicates: [["title", ">", "Zebra"]]})];

      assert.deepStrictEqual(
        reads(rules, document({title: "zebra"})),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(rules, document({title: "Zebra"})),
        Type.boolean(false),
      );
    });

    // The key folds case and diacritics, and `==` must not: what a bound reaches and what a
    // value equals are two different questions.
    it("keeps string equality exact", () => {
      const rules = [rule({predicates: [["title", "==", "Zebra"]]})];

      assert.deepStrictEqual(
        reads(rules, document({title: "Zebra"})),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(rules, document({title: "zebra"})),
        Type.boolean(false),
      );
    });

    it("never matches an enum comparison against an unset value", () => {
      assert.deepStrictEqual(
        reads([rule({predicates: [["status", ">=", "draft"]]})], document()),
        Type.boolean(false),
      );
    });

    it("substitutes the actor in predicate values", () => {
      const rules = [rule({predicates: [["author_id", "==", {actor: true}]]})];
      const entity = document({author_id: ALICE});

      assert.deepStrictEqual(
        reads(rules, entity, Type.bitstring(ALICE)),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(rules, entity, Type.bitstring(BOB)),
        Type.boolean(false),
      );
    });

    // A rule referencing the acting user is skipped for a visitor rather than evaluated with
    // nobody - evaluating it would let a row whose reference is missing match everyone.
    it("skips a rule referencing the actor for an anonymous session", () => {
      assert.deepStrictEqual(
        reads(
          [rule({predicates: [["author_id", "==", {actor: true}]]})],
          document({author_id: null}),
        ),
        Type.boolean(false),
      );
    });

    it("skips a rule with grant references for an anonymous session", () => {
      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: DOC, resource_type: "documents", role: "owner"}),
      );

      assert.deepStrictEqual(
        reads([rule({to: [["own", ["owner"]]]})], document()),
        Type.boolean(false),
      );
    });

    it("grants when one of the rule's grant references is held", () => {
      const rules = [
        rule({
          to: [
            ["own", ["owner"]],
            ["type", "documents", ["admin"]],
          ],
        }),
      ];

      assert.deepStrictEqual(
        reads(rules, document(), Type.bitstring(ALICE)),
        Type.boolean(false),
      );

      LocalDatabase.putRow(
        GRANT,
        grantRow({
          resource_id: null,
          resource_type: "documents",
          role: "admin",
        }),
      );

      assert.deepStrictEqual(
        reads(rules, document(), Type.bitstring(ALICE)),
        Type.boolean(true),
      );
    });

    it("requires the predicates to hold alongside the grant references", () => {
      const rules = [
        rule({predicates: [["priority", ">=", 3]], to: [["own", ["owner"]]]}),
      ];

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: DOC, resource_type: "documents", role: "owner"}),
      );

      assert.deepStrictEqual(
        reads(rules, document({priority: 3}), Type.bitstring(ALICE)),
        Type.boolean(true),
      );

      assert.deepStrictEqual(
        reads(rules, document({priority: 1}), Type.bitstring(ALICE)),
        Type.boolean(false),
      );
    });

    it("delegates for a via requirement", () => {
      defineModel(
        {read: [rule({via: "folder"})]},
        {read: [rule({predicates: [["archived", "==", false]]})]},
      );

      LocalDatabase.putRow(FOLDER, {archived: false, id: FOLDER_ID});

      assert.deepStrictEqual(
        can(
          Type.bitstring(ALICE),
          Type.atom("read"),
          document({folder_id: FOLDER_ID}),
        ),
        Type.boolean(true),
      );

      LocalDatabase.putRow(FOLDER, {archived: true, id: FOLDER_ID});

      assert.deepStrictEqual(
        can(
          Type.bitstring(ALICE),
          Type.atom("read"),
          document({folder_id: FOLDER_ID}),
        ),
        Type.boolean(false),
      );
    });

    // A delegating rule is still evaluated for a visitor, because the type it delegates to skips
    // its own actor-referencing rules in turn.
    it("evaluates a delegating rule for an anonymous session", () => {
      defineModel({read: [rule({via: "folder"})]}, {read: [rule()]});

      LocalDatabase.putRow(FOLDER, {archived: false, id: FOLDER_ID});

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("read"), document({folder_id: FOLDER_ID})),
        Type.boolean(true),
      );
    });
  });

  // What the reference has no counterpart for: it takes plain structs and an injected checker,
  // where this takes boxed terms and reads rows the client may or may not hold.
  describe("grant references over pot rows", () => {
    it("grants through a role held on the entity itself", () => {
      defineModel({read: [rule({to: [["own", ["viewer"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: DOC, resource_type: "documents"}),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(true),
      );
    });

    // An own-scope role is held on the entity OR on its whole type, which the store spells as a
    // grant naming no resource.
    it("grants through a role held on the entity's whole type", () => {
      defineModel({read: [rule({to: [["own", ["viewer"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: null, resource_type: "documents"}),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(true),
      );
    });

    it("denies when the role is held by another user", () => {
      defineModel({read: [rule({to: [["own", ["viewer"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: DOC, resource_type: "documents", user_id: BOB}),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(false),
      );
    });

    it("denies when the role is held on another entity", () => {
      defineModel({read: [rule({to: [["own", ["viewer"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: FOLDER_ID, resource_type: "documents"}),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(false),
      );
    });

    // Ids are unique across types in practice but not by rule - what a grant is held ON is the
    // pair of type and id, so the type has to match too.
    it("denies when the role is held on another type's entity of the same id", () => {
      defineModel({read: [rule({to: [["own", ["viewer"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: DOC, resource_type: "folders"}),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(false),
      );
    });

    it("denies when the held role is not one the rule names", () => {
      defineModel({read: [rule({to: [["own", ["owner"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({
          resource_id: DOC,
          resource_type: "documents",
          role: "viewer",
        }),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(false),
      );
    });

    it("grants through a role held on a whole other type", () => {
      defineModel({read: [rule({to: [["type", "folders", ["admin"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: null, resource_type: "folders", role: "admin"}),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(true),
      );
    });

    it("grants through a global role", () => {
      defineModel({read: [rule({to: [["global", ["MyApp.Roles.Admin"]]]})]});

      LocalDatabase.putRow(GRANT, grantRow({role: "MyApp.Roles.Admin"}));

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(true),
      );
    });

    it("grants through a role held on a related entity", () => {
      defineModel({
        read: [rule({to: [["rel", "folder", "folders", ["admin"]]]})],
      });

      LocalDatabase.putRow(
        GRANT,
        grantRow({
          resource_id: FOLDER_ID,
          resource_type: "folders",
          role: "admin",
        }),
      );

      assert.deepStrictEqual(
        can(
          Type.bitstring(ALICE),
          Type.atom("read"),
          document({folder_id: FOLDER_ID}),
        ),
        Type.boolean(true),
      );
    });

    it("denies a related-entity role when the relationship is unset", () => {
      defineModel({
        read: [rule({to: [["rel", "folder", "folders", ["admin"]]]})],
      });

      LocalDatabase.putRow(
        GRANT,
        grantRow({
          resource_id: FOLDER_ID,
          resource_type: "folders",
          role: "admin",
        }),
      );

      assert.deepStrictEqual(
        can(
          Type.bitstring(ALICE),
          Type.atom("read"),
          document({folder_id: null}),
        ),
        Type.boolean(false),
      );
    });

    it("grants when any one of several references is held", () => {
      defineModel({
        read: [
          rule({
            to: [
              ["own", ["owner"]],
              ["type", "folders", ["admin"]],
            ],
          }),
        ],
      });

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: null, resource_type: "folders", role: "admin"}),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("read"), document()),
        Type.boolean(true),
      );
    });

    // Every predicate must hold AND a reference must be held - the two are conjunction, not
    // alternatives.
    it("denies when the reference is held but a predicate fails", () => {
      defineModel({
        read: [
          rule({
            predicates: [["public", "==", true]],
            to: [["own", ["viewer"]]],
          }),
        ],
      });

      LocalDatabase.putRow(
        GRANT,
        grantRow({resource_id: DOC, resource_type: "documents"}),
      );

      assert.deepStrictEqual(
        can(
          Type.bitstring(ALICE),
          Type.atom("read"),
          document({public: false}),
        ),
        Type.boolean(false),
      );
    });
  });

  describe("delegation", () => {
    it("grants when the related entity's own rules grant the operation", () => {
      defineModel(
        {read: [rule({via: "folder"})]},
        {read: [rule({predicates: [["archived", "==", false]]})]},
      );

      LocalDatabase.putRow(FOLDER, {archived: false, id: FOLDER_ID});

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("read"), document({folder_id: FOLDER_ID})),
        Type.boolean(true),
      );
    });

    it("denies when the related entity's own rules deny the operation", () => {
      defineModel(
        {read: [rule({via: "folder"})]},
        {read: [rule({predicates: [["archived", "==", false]]})]},
      );

      LocalDatabase.putRow(FOLDER, {archived: true, id: FOLDER_ID});

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("read"), document({folder_id: FOLDER_ID})),
        Type.boolean(false),
      );
    });

    // A client holds neither the row nor the rules of a type its build never syncs, and cannot
    // ask the server mid-render - so the answer is no, as it is for any rule the rows do not
    // satisfy.
    it("denies when the related row is not in the database", () => {
      defineModel(
        {read: [rule({via: "folder"})]},
        {read: [rule({predicates: [["archived", "==", false]]})]},
      );

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("read"), document({folder_id: FOLDER_ID})),
        Type.boolean(false),
      );
    });

    it("denies when the relationship is unset", () => {
      defineModel(
        {read: [rule({via: "folder"})]},
        {read: [rule({predicates: [["archived", "==", false]]})]},
      );

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("read"), document({folder_id: null})),
        Type.boolean(false),
      );
    });
  });

  // A case this side alone has - the reference always holds every type. An entry absent from a
  // permission-checking build is a type declaring NO policy (the build ships an entry for every
  // policied type, checked or not), and a policy-less type is denied by the server's own
  // default - so no is the server's answer, not a fallback.
  describe("a type the model does not carry", () => {
    it("denies without asking the model for an entry", () => {
      const unmodelled = Type.map([
        [Type.atom("__struct__"), Type.alias("MyApp.Unpolicied")],
        [Type.atom("id"), Type.bitstring(DOC)],
      ]);

      assert.deepStrictEqual(
        can(Type.nil(), Type.atom("read"), unmodelled),
        Type.boolean(false),
      );
    });
  });

  // Cases this side alone has - the reference takes the operation as a term and keys the policy
  // map by it, while this side has to spell the key the build baked it under.
  describe("the operation's key", () => {
    it("asks by the bare key for the bare grant lifecycle operation", () => {
      defineModel({grant_role: [rule({to: [["own", ["editor"]]]})]});

      LocalDatabase.putRow(
        GRANT,
        grantRow({
          resource_id: DOC,
          resource_type: "documents",
          role: "editor",
        }),
      );

      assert.deepStrictEqual(
        can(Type.bitstring(ALICE), Type.atom("grant_role"), document()),
        Type.boolean(true),
      );
    });

    it("raises on a tuple naming several roles", () => {
      const operation = Type.tuple([
        Type.atom("grant_role"),
        Type.list([Type.atom("editor"), Type.atom("viewer")]),
      ]);

      assertBoxedError(
        () => can(Type.bitstring(ALICE), operation, document()),
        "ArgumentError",
        "can? asks about one role - {:grant_role, [:editor, :viewer]} names several",
      );
    });

    it("raises on an operation that is neither an atom nor a role tuple", () => {
      const operation = Type.tuple([
        Type.atom("grant_role"),
        Type.bitstring("viewer"),
      ]);

      assertBoxedError(
        () => can(Type.bitstring(ALICE), operation, document()),
        "ArgumentError",
        "can? takes an operation atom or a {:grant_role, role} / {:revoke_role, role} tuple",
      );
    });
  });
});

// IMPORTANT!
// Each test here has a related Elixir test in test/elixir/hologram/auth/role_grant_test.exs
// (describe "derive_id/4"), and the three pinned vectors are the same strings on both sides.
// Always update both together.
describe("deriveGrantId()", () => {
  const USER_ID = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e12";
  const OTHER_USER_ID = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e13";
  const RESOURCE_ID = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10";
  const RESOURCE_TYPE = "test_fixtures_policy_module2";

  it("answers the same id for the same grant", () => {
    assert.equal(
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
    );
  });

  it("answers a different id for a different role on the same resource", () => {
    assert.notEqual(
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "admin"),
    );
  });

  it("answers a different id for the same role held by a different user", () => {
    assert.notEqual(
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
      deriveGrantId(OTHER_USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
    );
  });

  it("answers a version 5 id under the RFC variant, in the canonical spelling", () => {
    assert.match(
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
      /^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
  });

  it("derives a type-wide grant, which names no resource id", () => {
    assert.notEqual(
      deriveGrantId(USER_ID, RESOURCE_TYPE, null, "member"),
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
    );
  });

  // The vectors the server pins, from the same inputs. The third carries a role name outside
  // ASCII: the name is hashed as UTF-8, and a twin reading UTF-16 code units would pass the first
  // two and diverge on this one.
  it("answers the vectors the server twin is held to", () => {
    assert.equal(
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "member"),
      "8cd330ce-decd-5e5b-bff7-1cd078a0ec62",
    );

    assert.equal(
      deriveGrantId(USER_ID, null, null, "Hologram.Test.Fixtures.Role.Module1"),
      "f0fd8d8d-3d3f-5dd8-9027-2441a5a93040",
    );

    assert.equal(
      deriveGrantId(USER_ID, RESOURCE_TYPE, RESOURCE_ID, "café"),
      "2ba31948-266d-5bb1-8452-451bca95d31c",
    );
  });
});

// The pair every grant the browser writes goes through: what the row is, and what it is called.
// Both are taken over the grant the deriveGrantId() vectors above pin, so the id asserted here is
// the one the server derives for the same four parts.
describe("a grant written into a batch", () => {
  const ENTITY_TYPE = "MyApp.Document";
  const GRANT_ID = "8cd330ce-decd-5e5b-bff7-1cd078a0ec62";
  const NOW_MS = 1_756_100_000_123;
  const RESOURCE_TYPE = "test_fixtures_policy_module2";
  const STAMP = NOW_MS * 1024;

  const ACTOR_ID = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e11";
  const RESOURCE_ID = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10";
  const USER_ID = "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e12";

  let timers;

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [ENTITY_TYPE]: {
          attributes: {id: "uuid"},
          policy: {},
          relationships: {},
          resourceType: RESOURCE_TYPE,
          roles: ["member"],
          serverOnly: [],
        },
      },
    };

    Model.reset();
    Clock.reset();
    timers = sinon.useFakeTimers(NOW_MS);
  });

  afterEach(() => {
    timers.restore();
  });

  describe("grantEntry()", () => {
    // The granter and the holder are apart here on purpose: a grant is written for somebody as
    // often as for oneself, and only one of the two is part of the id.
    it("builds the create the grant store's row is written as", () => {
      assert.deepStrictEqual(
        grantEntry(USER_ID, ENTITY_TYPE, RESOURCE_ID, "member", ACTOR_ID),
        {
          claim: null,
          data: {
            granted_by_id: ACTOR_ID,
            resource_id: RESOURCE_ID,
            resource_type: RESOURCE_TYPE,
            role: "member",
            user_id: USER_ID,
          },
          id: GRANT_ID,
          op: "create",
          stamp: STAMP,
          type: "Hologram.Auth.RoleGrant",
        },
      );
    });
  });

  describe("grantId()", () => {
    it("names the row from the type's own resource type", () => {
      assert.equal(
        grantId(USER_ID, ENTITY_TYPE, RESOURCE_ID, "member"),
        GRANT_ID,
      );
    });
  });
});

// IMPORTANT!
// Each test here mirrors a message test in test/elixir/hologram/auth_test.exs (the grant_role/3
// and revoke_role/3 describes) string for string, with the fixtures' names swapped for this
// file's model. Always update both together. What the browser cannot mirror is the "extends"
// sentence - the model entry carries role names and not their chains - which is why no test here
// holds a role that extends another.
// Shared by the describes below: a model with one resource type declaring three roles, its gate
// rules given per test, and the grant store.
const GATED_DOCUMENT = "MyApp.Document";
const GATED_GRANT = "Hologram.Auth.RoleGrant";
const GATED_ALICE = "018f4571-a1b2-7c3d-8e4f-000000000001";
const GATED_BOB = "018f4571-a1b2-7c3d-8e4f-000000000002";
const GATED_DOC = "018f4571-a1b2-7c3d-8e4f-0000000000d1";

const gateRule = (to) => ({predicates: [], to: to, via: null});

const gatedGrantRow = (overrides) => ({
  id: `grant-${Object.values(overrides).join("-")}`,
  resource_id: null,
  resource_type: null,
  role: "viewer",
  user_id: GATED_ALICE,
  ...overrides,
});

const defineGates = (policy) => {
  globalThis.Hologram.sync = {
    model: {
      [GATED_DOCUMENT]: {
        attributes: {id: "uuid"},
        policy: policy,
        relationships: {},
        resourceType: "documents",
        roles: ["editor", "owner", "viewer"],
        serverOnly: [],
      },
      [GATED_GRANT]: {
        attributes: {
          id: "uuid",
          resource_id: "uuid",
          resource_type: "enum",
          role: "enum",
        },
        policy: {},
        relationships: {},
        resourceType: "hologram_role_grant",
        roles: [],
        serverOnly: [],
      },
    },
  };

  Model.reset();
};

describe("unqualifiedRoleMessage()", () => {
  const DOCUMENT = GATED_DOCUMENT;
  const GRANT = GATED_GRANT;
  const ALICE = GATED_ALICE;
  const DOC = GATED_DOC;
  const rule = gateRule;
  const grantRow = gatedGrantRow;

  beforeEach(() => {
    defineGates({});
    LocalDatabase.reset();
  });

  it("names the resource when the acting user holds no role there", () => {
    assert.equal(
      unqualifiedRoleMessage(DOCUMENT, DOC, ALICE, "editor", "grant_role"),
      `the acting user holds no role on MyApp.Document "${DOC}" that may grant :editor`,
    );
  });

  it("names what the held role may grant instead", () => {
    defineGates({"grant_role:viewer": [rule([["own", ["editor"]]])]});

    LocalDatabase.putRow(
      GRANT,
      grantRow({resource_id: DOC, resource_type: "documents", role: "editor"}),
    );

    assert.equal(
      unqualifiedRoleMessage(DOCUMENT, DOC, ALICE, "owner", "grant_role"),
      `the acting user holds :editor on MyApp.Document "${DOC}", ` +
        "which may grant :viewer but not :owner. " +
        "Declare `allow {:grant_role, :owner}, to: :editor` on MyApp.Document if that is intended.",
    );
  });

  it("says the held role may grant no role there", () => {
    LocalDatabase.putRow(
      GRANT,
      grantRow({resource_id: DOC, resource_type: "documents", role: "viewer"}),
    );

    assert.equal(
      unqualifiedRoleMessage(DOCUMENT, DOC, ALICE, "editor", "grant_role"),
      `the acting user holds :viewer on MyApp.Document "${DOC}", ` +
        "which may grant no role there, :editor included. " +
        "Declare `allow {:grant_role, :editor}, to: :viewer` on MyApp.Document if that is intended.",
    );
  });

  it("joins several held roles and lists them in the declaration", () => {
    LocalDatabase.putRow(
      GRANT,
      grantRow({resource_id: DOC, resource_type: "documents", role: "viewer"}),
    );
    LocalDatabase.putRow(
      GRANT,
      grantRow({resource_id: DOC, resource_type: "documents", role: "editor"}),
    );

    assert.equal(
      unqualifiedRoleMessage(DOCUMENT, DOC, ALICE, "owner", "grant_role"),
      `the acting user holds :editor and :viewer on MyApp.Document "${DOC}", ` +
        "which may grant no role there, :owner included. " +
        "Declare `allow {:grant_role, :owner}, to: [:editor, :viewer]` on MyApp.Document if that is intended.",
    );
  });

  it("counts a type-wide grant and a global role, modules after own names", () => {
    LocalDatabase.putRow(
      GRANT,
      grantRow({resource_id: null, resource_type: "documents", role: "editor"}),
    );
    LocalDatabase.putRow(GRANT, grantRow({role: "MyApp.Roles.Admin"}));

    assert.equal(
      unqualifiedRoleMessage(DOCUMENT, DOC, ALICE, "owner", "grant_role"),
      `the acting user holds :editor and MyApp.Roles.Admin on MyApp.Document "${DOC}", ` +
        "which may grant no role there, :owner included. " +
        "Declare `allow {:grant_role, :owner}, to: [:editor, MyApp.Roles.Admin]` on MyApp.Document if that is intended.",
    );
  });

  it("leaves out a role held on another resource", () => {
    LocalDatabase.putRow(
      GRANT,
      grantRow({
        resource_id: "018f4571-a1b2-7c3d-8e4f-0000000000d2",
        resource_type: "documents",
        role: "editor",
      }),
    );

    assert.equal(
      unqualifiedRoleMessage(DOCUMENT, DOC, ALICE, "editor", "grant_role"),
      `the acting user holds no role on MyApp.Document "${DOC}" that may grant :editor`,
    );
  });

  it("speaks of revoking for the revoke gate", () => {
    defineGates({"revoke_role:viewer": [rule([["own", ["editor"]]])]});

    LocalDatabase.putRow(
      GRANT,
      grantRow({resource_id: DOC, resource_type: "documents", role: "editor"}),
    );

    assert.equal(
      unqualifiedRoleMessage(DOCUMENT, DOC, ALICE, "owner", "revoke_role"),
      `the acting user holds :editor on MyApp.Document "${DOC}", ` +
        "which may revoke :viewer but not :owner. " +
        "Declare `allow {:revoke_role, :owner}, to: :editor` on MyApp.Document if that is intended.",
    );
  });
});

describe("signedInWriteMessage()", () => {
  it("spells the verb into the sentence", () => {
    assert.equal(
      signedInWriteMessage("granted"),
      "a role is granted only by a signed-in user - nobody is signed in",
    );
  });
});

describe("trustedWriteMessage()", () => {
  it("spells the scope and the verb into the sentence", () => {
    assert.equal(
      trustedWriteMessage("type-wide", "revoked"),
      "type-wide roles are revoked only by trusted code running without an acting user",
    );
  });
});

// IMPORTANT!
// Mirrors test/elixir/hologram/auth_test.exs (describe "grant_role/3") where the browser can -
// the argument refusals and the gate are the same sentences - and adds what only this side has:
// the row in the batch, its visibility before anything is sent, and the action it must run in.
// Always update both together.
describe("grant_role/3", () => {
  const grant = Elixir_Hologram_Auth["grant_role/3"];
  const can = Elixir_Hologram_Auth["can?/3"];

  const NOW_MS = 1_756_100_000_123;
  const STAMP = NOW_MS * 1024;

  const document = () =>
    Type.struct(GATED_DOCUMENT, [[Type.atom("id"), Type.bitstring(GATED_DOC)]]);

  let timers;

  beforeEach(() => {
    defineGates({"grant_role:viewer": [gateRule([["own", ["editor"]]])]});
    Batches.reset();
    Clock.reset();
    LocalDatabase.reset();
    LocalDatabase.actorUserId = GATED_ALICE;
    LocalDatabase.putRow(
      GATED_GRANT,
      gatedGrantRow({
        resource_id: GATED_DOC,
        resource_type: "documents",
        role: "editor",
      }),
    );
    timers = sinon.useFakeTimers(NOW_MS);
    Batches.open("grants");
  });

  afterEach(() => {
    timers.restore();
    Batches.reset();
    LocalDatabase.actorUserId = null;
  });

  it("appends a create of the grant row with the acting user as its granter", () => {
    const result = grant(
      Type.bitstring(GATED_BOB),
      document(),
      Type.atom("viewer"),
    );

    assert.deepStrictEqual(result, Type.atom("ok"));

    assert.deepStrictEqual(Batches.current().writes, [
      {
        claim: null,
        data: {
          granted_by_id: GATED_ALICE,
          resource_id: GATED_DOC,
          resource_type: "documents",
          role: "viewer",
          user_id: GATED_BOB,
        },
        id: deriveGrantId(GATED_BOB, "documents", GATED_DOC, "viewer"),
        op: "create",
        stamp: STAMP,
        type: GATED_GRANT,
      },
    ]);
  });

  it("takes the user as a struct as well as a bare id", () => {
    const user = Type.struct("MyApp.User", [
      [Type.atom("id"), Type.bitstring(GATED_BOB)],
    ]);

    grant(user, document(), Type.atom("viewer"));

    assert.equal(Batches.current().writes[0].data.user_id, GATED_BOB);
  });

  // The pending row is readable through the overlay, so a check that reads grants sees it the
  // moment the verb returns - before anything is sent.
  it("makes the grant visible to can?/3 before anything is sent", () => {
    defineGates({
      "grant_role:viewer": [gateRule([["own", ["editor"]]])],
      read: [gateRule([["own", ["viewer"]]])],
    });

    assert.deepStrictEqual(
      can(Type.bitstring(GATED_BOB), Type.atom("read"), document()),
      Type.boolean(false),
    );

    grant(Type.bitstring(GATED_BOB), document(), Type.atom("viewer"));

    assert.deepStrictEqual(
      can(Type.bitstring(GATED_BOB), Type.atom("read"), document()),
      Type.boolean(true),
    );
  });

  it("answers :ok and appends nothing for a grant the client already holds", () => {
    LocalDatabase.putRow(GATED_GRANT, {
      id: deriveGrantId(GATED_BOB, "documents", GATED_DOC, "viewer"),
      resource_id: GATED_DOC,
      resource_type: "documents",
      role: "viewer",
      user_id: GATED_BOB,
    });

    const result = grant(
      Type.bitstring(GATED_BOB),
      document(),
      Type.atom("viewer"),
    );

    assert.deepStrictEqual(result, Type.atom("ok"));
    assert.deepStrictEqual(Batches.current().writes, []);
  });

  it("raises on a role the resource type does not declare", () => {
    assertBoxedError(
      () =>
        grant(Type.bitstring(GATED_BOB), document(), Type.atom("publisher")),
      "ArgumentError",
      "unknown role :publisher for MyApp.Document - declared roles are: :editor, :owner, :viewer",
    );
  });

  it("raises the teaching message for a role the acting user may not grant", () => {
    assertBoxedError(
      () => grant(Type.bitstring(GATED_BOB), document(), Type.atom("owner")),
      "Hologram.AccessDeniedError",
      `the acting user holds :editor on MyApp.Document "${GATED_DOC}", ` +
        "which may grant :viewer but not :owner. " +
        "Declare `allow {:grant_role, :owner}, to: :editor` on MyApp.Document if that is intended.",
    );
  });

  // The server asks the gate before it writes, and answers a held grant with :ok only after the
  // gate passed - so a browser holding the row still refuses an actor who may not grant it.
  it("asks the gate before it looks for a grant already held", () => {
    LocalDatabase.putRow(GATED_GRANT, {
      id: deriveGrantId(GATED_BOB, "documents", GATED_DOC, "owner"),
      resource_id: GATED_DOC,
      resource_type: "documents",
      role: "owner",
      user_id: GATED_BOB,
    });

    assertBoxedError(
      () => grant(Type.bitstring(GATED_BOB), document(), Type.atom("owner")),
      "Hologram.AccessDeniedError",
      `the acting user holds :editor on MyApp.Document "${GATED_DOC}", ` +
        "which may grant :viewer but not :owner. " +
        "Declare `allow {:grant_role, :owner}, to: :editor` on MyApp.Document if that is intended.",
    );
  });

  it("raises on a type-wide grant", () => {
    assertBoxedError(
      () =>
        grant(
          Type.bitstring(GATED_BOB),
          Type.alias(GATED_DOCUMENT),
          Type.atom("viewer"),
        ),
      "Hologram.AccessDeniedError",
      "type-wide roles are granted only by trusted code running without an acting user",
    );
  });

  it("raises when nobody is signed in", () => {
    LocalDatabase.actorUserId = null;

    assertBoxedError(
      () => grant(Type.bitstring(GATED_BOB), document(), Type.atom("viewer")),
      "Hologram.AccessDeniedError",
      "a role is granted only by a signed-in user - nobody is signed in",
    );
  });

  it("raises on a user id that is not an entity id", () => {
    assertBoxedError(
      () => grant(Type.bitstring("nope"), document(), Type.atom("viewer")),
      "ArgumentError",
      'invalid user id "nope" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings',
    );
  });

  it("raises outside an action", () => {
    Batches.reset();

    assertBoxedError(
      () => grant(Type.bitstring(GATED_BOB), document(), Type.atom("viewer")),
      "ArgumentError",
      "grant_role was called outside an action - a client write happens inside an action, whose writes ship together when it returns",
    );
  });
});

describe("grant_role/2", () => {
  it("raises - a global grant is trusted-only", () => {
    assertBoxedError(
      () =>
        Elixir_Hologram_Auth["grant_role/2"](
          Type.bitstring(GATED_BOB),
          Type.alias("MyApp.Roles.Admin"),
        ),
      "Hologram.AccessDeniedError",
      "global roles are granted only by trusted code running without an acting user",
    );
  });
});

// IMPORTANT!
// Mirrors test/elixir/hologram/auth_test.exs (describe "revoke_role/3") where the browser can -
// the argument refusals and the gate are the same sentences - and adds what only this side has:
// the delete in the batch carrying the row's revisions, the row gone from can?/3's view before
// anything is sent, and a row the client does not hold. Always update both together.
describe("revoke_role/3", () => {
  const revoke = Elixir_Hologram_Auth["revoke_role/3"];
  const can = Elixir_Hologram_Auth["can?/3"];

  const NOW_MS = 1_756_100_000_123;
  const STAMP = NOW_MS * 1024;
  const REVISIONS = {resource_id: 7, resource_type: 7, role: 7, user_id: 7};

  const document = () =>
    Type.struct(GATED_DOCUMENT, [[Type.atom("id"), Type.bitstring(GATED_DOC)]]);

  const heldRow = (userId, role) => ({
    $revisions: REVISIONS,
    id: deriveGrantId(userId, "documents", GATED_DOC, role),
    resource_id: GATED_DOC,
    resource_type: "documents",
    role: role,
    user_id: userId,
  });

  let timers;

  beforeEach(() => {
    defineGates({
      read: [gateRule([["own", ["viewer"]]])],
      "revoke_role:viewer": [gateRule([["own", ["editor"]]])],
    });
    Batches.reset();
    Clock.reset();
    LocalDatabase.reset();
    LocalDatabase.actorUserId = GATED_ALICE;
    LocalDatabase.putRow(GATED_GRANT, heldRow(GATED_ALICE, "editor"));
    LocalDatabase.putRow(GATED_GRANT, heldRow(GATED_BOB, "viewer"));
    timers = sinon.useFakeTimers(NOW_MS);
    Batches.open("grants");
  });

  afterEach(() => {
    timers.restore();
    Batches.reset();
    LocalDatabase.actorUserId = null;
  });

  it("appends a delete of the held row carrying its revisions and its grant", () => {
    const result = revoke(
      Type.bitstring(GATED_BOB),
      document(),
      Type.atom("viewer"),
    );

    assert.deepStrictEqual(result, Type.atom("ok"));

    assert.deepStrictEqual(Batches.current().writes, [
      {
        based_on: REVISIONS,
        claim: null,
        data: {
          resource_id: GATED_DOC,
          resource_type: "documents",
          role: "viewer",
          user_id: GATED_BOB,
        },
        id: deriveGrantId(GATED_BOB, "documents", GATED_DOC, "viewer"),
        op: "delete",
        stamp: STAMP,
        type: GATED_GRANT,
      },
    ]);
  });

  it("hides the grant from can?/3 before anything is sent", () => {
    assert.deepStrictEqual(
      can(Type.bitstring(GATED_BOB), Type.atom("read"), document()),
      Type.boolean(true),
    );

    revoke(Type.bitstring(GATED_BOB), document(), Type.atom("viewer"));

    assert.deepStrictEqual(
      can(Type.bitstring(GATED_BOB), Type.atom("read"), document()),
      Type.boolean(false),
    );
  });

  // Carol holds nothing. The gate passes (the actor may revoke viewer), and then there is no row.
  it("answers :ok and appends nothing for a role the user does not hold", () => {
    const CAROL = "018f4571-a1b2-7c3d-8e4f-000000000003";

    const result = revoke(
      Type.bitstring(CAROL),
      document(),
      Type.atom("viewer"),
    );

    assert.deepStrictEqual(result, Type.atom("ok"));
    assert.deepStrictEqual(Batches.current().writes, []);
  });

  // No rule lets an editor revoke editor - the row is the acting user's own, which is how a
  // member leaves.
  it("revokes the acting user's own row without asking the gate", () => {
    revoke(Type.bitstring(GATED_ALICE), document(), Type.atom("editor"));

    assert.equal(Batches.current().writes.length, 1);
    assert.equal(
      Batches.current().writes[0].id,
      deriveGrantId(GATED_ALICE, "documents", GATED_DOC, "editor"),
    );
  });

  it("raises the teaching message for another user's row the acting user may not revoke", () => {
    LocalDatabase.putRow(GATED_GRANT, heldRow(GATED_BOB, "owner"));

    assertBoxedError(
      () => revoke(Type.bitstring(GATED_BOB), document(), Type.atom("owner")),
      "Hologram.AccessDeniedError",
      `the acting user holds :editor on MyApp.Document "${GATED_DOC}", ` +
        "which may revoke :viewer but not :owner. " +
        "Declare `allow {:revoke_role, :owner}, to: :editor` on MyApp.Document if that is intended.",
    );
  });

  // The server authorizes before it looks for the row, so a row the client does not hold is still
  // refused to an actor who may not revoke it - never a silent :ok.
  it("asks the gate before it looks for the row", () => {
    assertBoxedError(
      () => revoke(Type.bitstring(GATED_BOB), document(), Type.atom("owner")),
      "Hologram.AccessDeniedError",
      `the acting user holds :editor on MyApp.Document "${GATED_DOC}", ` +
        "which may revoke :viewer but not :owner. " +
        "Declare `allow {:revoke_role, :owner}, to: :editor` on MyApp.Document if that is intended.",
    );
  });

  it("raises on a type-wide revocation", () => {
    assertBoxedError(
      () =>
        revoke(
          Type.bitstring(GATED_BOB),
          Type.alias(GATED_DOCUMENT),
          Type.atom("viewer"),
        ),
      "Hologram.AccessDeniedError",
      "type-wide roles are revoked only by trusted code running without an acting user",
    );
  });

  it("raises when nobody is signed in", () => {
    LocalDatabase.actorUserId = null;

    assertBoxedError(
      () => revoke(Type.bitstring(GATED_BOB), document(), Type.atom("viewer")),
      "Hologram.AccessDeniedError",
      "a role is revoked only by a signed-in user - nobody is signed in",
    );
  });

  it("raises outside an action", () => {
    Batches.reset();

    assertBoxedError(
      () => revoke(Type.bitstring(GATED_BOB), document(), Type.atom("viewer")),
      "ArgumentError",
      "revoke_role was called outside an action - a client write happens inside an action, whose writes ship together when it returns",
    );
  });
});

describe("revoke_role/2", () => {
  it("raises - a global revocation is trusted-only", () => {
    assertBoxedError(
      () =>
        Elixir_Hologram_Auth["revoke_role/2"](
          Type.bitstring(GATED_BOB),
          Type.alias("MyApp.Roles.Admin"),
        ),
      "Hologram.AccessDeniedError",
      "global roles are revoked only by trusted code running without an acting user",
    );
  });
});

// What db_test.mjs's batch entries only imply, asserted as the answer a page would get: a row the
// browser has just made carries its creator's roles, so a check gated on one passes from the local
// database alone, before anything is sent. The unit twin of the feature that grants on a row the
// same action created.
describe("a creator's own grant", () => {
  const NOTE = "MyApp.Note";

  const NOTE_ID = "018f4571-a1b2-7c3d-8e4f-0000000000c1";
  const OWNER = "018f4571-a1b2-7c3d-8e4f-0000000000c2";

  const can = Elixir_Hologram_Auth["can?/3"];
  const create = Elixir_Hologram_DB["create/1"];

  const mayGrantMember = (entity) =>
    can(
      Type.bitstring(OWNER),
      Type.tuple([Type.atom("grant_role"), Type.atom("member")]),
      entity,
    );

  const note = () => Model.box(NOTE, {id: NOTE_ID, title: "alpha"});

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [NOTE]: {
          attributes: {id: "uuid", title: "string"},
          constraints: {},
          creatorRoles: ["owner"],
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          policy: {"grant_role:member": [gateRule([["own", ["owner"]]])]},
          relationships: {},
          resourceType: "notes",
          roles: ["member", "owner"],
          serverOnly: [],
        },
        [GATED_GRANT]: {
          attributes: {
            id: "uuid",
            resource_id: "uuid",
            resource_type: "enum",
            role: "enum",
          },
          policy: {},
          relationships: {},
          resourceType: "hologram_role_grant",
          roles: [],
          serverOnly: [],
        },
      },
    };

    Model.reset();
    Batches.reset();
    Clock.reset();
    LocalDatabase.reset();
    LocalDatabase.actorUserId = null;
    Batches.open("notes");
  });

  afterEach(() => {
    Batches.reset();
    LocalDatabase.actorUserId = null;
  });

  it("lets the creator do what the role it takes gates", () => {
    LocalDatabase.actorUserId = OWNER;

    const created = create(note()).data[1];

    assert.deepStrictEqual(mayGrantMember(created), Type.boolean(true));
  });

  // No acting user, no grants - so the same row made by nobody gates the same check shut.
  it("leaves a row made with nobody signed in ungated", () => {
    const created = create(note()).data[1];

    assert.deepStrictEqual(mayGrantMember(created), Type.boolean(false));
  });
});
