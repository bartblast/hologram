"use strict";

import {assert, defineRuntimeGlobals} from "../../support/helpers.mjs";

import Elixir_Hologram_Auth from "../../../../assets/js/elixir/hologram/auth.mjs";
import LocalDatabase from "../../../../assets/js/local_database.mjs";
import Model from "../../../../assets/js/model.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// The client half of the permission check: the rules come from the build, the grant rows from
// the pot. Hologram.Policy.Evaluator is the reference, and the consistency suite pins the two
// against each other - these cover the client's own boundary work as well.
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
      folder_id: null,
      id: DOC,
      public: false,
      author_id: null,
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
            id: "uuid",
            priority: "integer",
            public: "boolean",
          },
          policy: policy,
          relationships: {folder: {toMany: false, type: FOLDER}},
          resourceType: "documents",
          serverOnly: [],
          sortKeys: [],
        },
        [FOLDER]: {
          attributes: {id: "uuid", archived: "boolean"},
          policy: folderPolicy,
          relationships: {},
          resourceType: "folders",
          serverOnly: [],
          sortKeys: [],
        },
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
          sortKeys: [],
        },
      },
    };

    Model.reset();
  };

  beforeEach(() => {
    defineModel();
    LocalDatabase.reset();
  });

  it("grants an operation through a rule whose predicates hold", () => {
    defineModel({read: [rule({predicates: [["public", "==", true]]})]});

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document({public: true})),
      Type.boolean(true),
    );
  });

  it("denies an operation whose rule's predicates do not hold", () => {
    defineModel({read: [rule({predicates: [["public", "==", true]]})]});

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document({public: false})),
      Type.boolean(false),
    );
  });

  // An operation the type declares no rule for grants nothing, which is what makes the deny
  // the default rather than the exception.
  it("denies an operation the type declares no rule for", () => {
    defineModel({read: [rule()]});

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("delete"), document()),
      Type.boolean(false),
    );
  });

  it("grants when any one of several rules matches", () => {
    defineModel({
      read: [
        rule({predicates: [["public", "==", true]]}),
        rule({predicates: [["priority", ">=", 3]]}),
      ],
    });

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document({priority: 5})),
      Type.boolean(true),
    );
  });

  // An ordering comparison never matches a missing value - the rule the database applies, where
  // a comparison with NULL is unknown rather than true.
  it("denies an ordering comparison against a missing value", () => {
    defineModel({read: [rule({predicates: [["priority", ">=", 3]]})]});

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document({priority: null})),
      Type.boolean(false),
    );
  });

  // The operator matters: comparing null with a number coerces it to zero, so an ordering test
  // that only tries >= would pass whether the rule is honoured or not.
  it("denies an ordering comparison a coercion would have granted", () => {
    defineModel({read: [rule({predicates: [["priority", "<", 3]]})]});

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document({priority: null})),
      Type.boolean(false),
    );
  });

  it("denies an ordering comparison against a missing rule value", () => {
    defineModel({read: [rule({predicates: [["priority", ">=", null]]})]});

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document({priority: 5})),
      Type.boolean(false),
    );
  });

  it("reads the acting user's id from the user entity", () => {
    defineModel({
      read: [rule({predicates: [["author_id", "==", {actor: true}]]})],
    });

    const user = Model.box(GRANT, {id: ALICE});

    assert.deepStrictEqual(
      can(user, Type.atom("read"), document({author_id: ALICE})),
      Type.boolean(true),
    );
  });

  it("reads the acting user's id from a bare id", () => {
    defineModel({
      read: [rule({predicates: [["author_id", "==", {actor: true}]]})],
    });

    assert.deepStrictEqual(
      can(
        Type.bitstring(ALICE),
        Type.atom("read"),
        document({author_id: ALICE}),
      ),
      Type.boolean(true),
    );
  });

  // A rule referencing the acting user is skipped for a visitor rather than evaluated with
  // nobody - evaluating it would let a row whose reference is missing match everyone.
  it("skips an actor-referencing rule for an anonymous session", () => {
    defineModel({
      read: [rule({predicates: [["author_id", "==", {actor: true}]]})],
    });

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document({author_id: null})),
      Type.boolean(false),
    );
  });

  it("skips a grant-referencing rule for an anonymous session", () => {
    defineModel({read: [rule({to: [["own", ["viewer"]]]})]});

    LocalDatabase.putRow(
      GRANT,
      grantRow({resource_id: DOC, resource_type: "documents", user_id: null}),
    );

    assert.deepStrictEqual(
      can(Type.nil(), Type.atom("read"), document()),
      Type.boolean(false),
    );
  });

  describe("grant references", () => {
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
});
