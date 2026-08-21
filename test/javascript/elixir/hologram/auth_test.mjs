"use strict";

import {assert, defineRuntimeGlobals} from "../../support/helpers.mjs";

import Elixir_Hologram_Auth from "../../../../assets/js/elixir/hologram/auth.mjs";
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
          },
          enumValues: {status: ["draft", "review", "published"]},
          policy: policy,
          relationships: {folder: {toMany: false, type: FOLDER}},
          resourceType: "documents",
          serverOnly: [],
        },
        [FOLDER]: {
          attributes: {id: "uuid", archived: "boolean"},
          policy: folderPolicy,
          relationships: {},
          resourceType: "folders",
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
});
