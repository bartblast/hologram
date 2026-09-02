"use strict";

import Bitstring from "../../bitstring.mjs";
import Clock from "../../clock.mjs";
import {currentBatch} from "./db.mjs";
import Interpreter from "../../interpreter.mjs";
import LocalDatabase from "../../local_database.mjs";
import Model from "../../model.mjs";
import Sha1 from "../../sha1.mjs";
import SortKey from "../../sort_key.mjs";
import Type from "../../type.mjs";

// Whether the acting user may do something, answered here rather than asked of the server.
//
// Hologram.Policy.Evaluator is the reference this mirrors, and Hologram.Auth is where its
// checker lives on that side. The split is kept: rules are evaluated over plain values, and
// what a rule REFERENCES - a role held somewhere - is answered by reading grant rows. The
// server reads them with SELECT EXISTS, this reads them from the pot.
//
// Both halves of what it needs are compile-time facts the bundle carries: the rules in each
// type's model entry, and the name the grant store spells that type by. The rows are ordinary
// synced rows, and a page that checks permissions hands over the ones its own checks asked
// about, so the first render answers what the server answered.
const GRANT_TYPE = "Hologram.Auth.RoleGrant";

// The sixteen bytes Hologram.Auth.RoleGrant derives every grant id under - drawn once, on
// 2026-09-02, and fixed: change them and every grant in every store is renamed.
const GRANT_ID_NAMESPACE = Uint8Array.from([
  0x8b, 0x2f, 0x65, 0x0d, 0xd0, 0xcf, 0x15, 0x26, 0xdf, 0xec, 0x20, 0x9a, 0x31,
  0xd9, 0xf6, 0x6c,
]);

// A rule that references the acting user is skipped for a visitor rather than evaluated with
// nobody - evaluating it would let a row whose reference is missing match everyone. A delegating
// rule is still evaluated, because the type it delegates to skips its own actor rules in turn.
function actorGated(rule) {
  return (
    rule.to !== null ||
    rule.predicates.some(([_name, _operator, value]) => isActorValue(value))
  );
}

// Every value compares as the wire spells it - dates and datetimes as their strings, whose
// character order IS their instant order - so one comparison serves most types.
//
// Two are the exceptions, and both for the same reason: a rule and the filter mirroring it have
// to admit the same rows. An enum's labels say nothing about its order, so the two compare by
// their positions in the list the type declares. A string compares by the key derived from it and
// then by the value behind it, which is the pair its ordering sorts by - the key is a bounded
// prefix, which is what leaves the value something to settle.
//
// Which of the two applies is decided by the DECLARED type rather than by the runtime one: on the
// wire a date is a string too, and the reference never folds one, because there it is a struct.
function compare(left, right, ranks = null, foldsKey = false) {
  if (ranks) {
    return plainCompare(ranks.get(left), ranks.get(right));
  }

  if (!foldsKey) {
    return plainCompare(left, right);
  }

  const keyResult = plainCompare(SortKey.compute(left), SortKey.compute(right));

  return keyResult === "eq" ? plainCompare(left, right) : keyResult;
}

function plainCompare(left, right) {
  if (left === right) {
    return "eq";
  }

  return left < right ? "lt" : left > right ? "gt" : "eq";
}

function equal(left, right) {
  return compare(left, right) === "eq";
}

// The role a grant row holds, and where it holds it, are what a reference names - so a match is
// a comparison against the row's own columns.
function grantExists(rows, userId, roles, resourceType, resourceIds) {
  return rows.some(
    (row) =>
      row.user_id === userId &&
      roles.includes(row.role) &&
      row.resource_type === resourceType &&
      resourceIds.includes(row.resource_id),
  );
}

function grantRows() {
  return Object.values(LocalDatabase.getTable(GRANT_TYPE));
}

function holds(fieldValue, operator, value, ranks, foldsKey = false) {
  if (operator === "==") {
    return equal(fieldValue, value);
  }

  if (operator === "!=") {
    return !equal(fieldValue, value);
  }

  if (operator === "in") {
    return value.some((element) => equal(fieldValue, element));
  }

  if (operator === "not_in") {
    return !value.some((element) => equal(fieldValue, element));
  }

  // An ordering comparison never matches a missing value, on either side - the same rule the
  // database applies, where a comparison with NULL is unknown rather than true.
  if (fieldValue === null || value === null) {
    return false;
  }

  switch (operator) {
    case "<":
      return compare(fieldValue, value, ranks, foldsKey) === "lt";

    case "<=":
      return compare(fieldValue, value, ranks, foldsKey) !== "gt";

    case ">":
      return compare(fieldValue, value, ranks, foldsKey) === "gt";

    default:
      return compare(fieldValue, value, ranks, foldsKey) !== "lt";
  }
}

function isActorValue(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    value.actor === true
  );
}

// The value a rule compares against, read off the boxed entity in the spelling the rules were
// baked in - the rules travel wire-spelled, so what they are compared with must be too.
function entityValue(entityType, entity, name) {
  const attributeType = Model.entry(entityType).attributes[name] ?? "uuid";
  const key = Type.encodeMapKey(Type.atom(name));
  const entry = entity.data[key];

  return entry ? Model.unbox(entry[1], attributeType) : null;
}

// What an enum predicate compares by, or null for an attribute of any other type - a name
// matching no attribute definition is a reference field, which carries an entity id.
function enumRanks(entityType, name) {
  const entry = Model.entry(entityType);

  if (entry.attributes[name] !== "enum") {
    return null;
  }

  return new Map(entry.enumValues[name].map((label, index) => [label, index]));
}

function predicatesHold(entityType, entity, predicates, actorUserId) {
  return predicates.every(([name, operator, value]) =>
    holds(
      entityValue(entityType, entity, name),
      operator,
      isActorValue(value) ? actorUserId : value,
      enumRanks(entityType, name),
      Model.entry(entityType).attributes[name] === "string",
    ),
  );
}

// Where a role must be held for a reference to be satisfied. Each shape names a scope the grant
// store keeps apart by its resource columns - an own-scope role is held on the entity itself OR
// on its whole type, which the store spells as a null resource id.
function referenceHolds(reference, entityType, entity, actorUserId) {
  const rows = grantRows();
  const [kind] = reference;

  switch (kind) {
    case "global": {
      const [_kind, roles] = reference;

      return grantExists(rows, actorUserId, roles, null, [null]);
    }

    case "own": {
      const [_kind, roles] = reference;
      const resourceType = Model.entry(entityType).resourceType;
      const id = entityValue(entityType, entity, "id");

      return grantExists(rows, actorUserId, roles, resourceType, [id, null]);
    }

    case "rel": {
      const [_kind, relationshipName, resourceType, roles] = reference;
      const targetId = entityValue(
        entityType,
        entity,
        `${relationshipName}_id`,
      );

      return (
        targetId !== null &&
        grantExists(rows, actorUserId, roles, resourceType, [targetId])
      );
    }

    // The grant store's own rule: a role held on the resource the grant row names.
    case "resource": {
      const [_kind, resourceType, roles] = reference;
      const rowResourceId = entityValue(entityType, entity, "resource_id");

      return (
        rowResourceId !== null &&
        grantExists(rows, actorUserId, roles, resourceType, [rowResourceId])
      );
    }

    default: {
      const [_kind, resourceType, roles] = reference;

      return grantExists(rows, actorUserId, roles, resourceType, [null]);
    }
  }
}

function ruleMatches(rule, entityType, entity, actorUserId) {
  if (actorUserId === null && actorGated(rule)) {
    return false;
  }

  if (!predicatesHold(entityType, entity, rule.predicates, actorUserId)) {
    return false;
  }

  if (
    rule.to !== null &&
    !rule.to.some((reference) =>
      referenceHolds(reference, entityType, entity, actorUserId),
    )
  ) {
    return false;
  }

  return rule.via === null || viaHolds(rule, entityType, entity, actorUserId);
}

// The acting user, as a bare id: a check takes the user entity or the id itself, and nobody at
// all for a visitor.
function unboxActorUserId(userOrId) {
  if (Type.isNil(userOrId)) {
    return null;
  }

  if (Type.isMap(userOrId)) {
    const entry = userOrId.data[Type.encodeMapKey(Type.atom("id"))];

    return entry ? Model.unbox(entry[1], "uuid") : null;
  }

  return Model.unbox(userOrId, "uuid");
}

// Delegation asks the RELATED entity's policy for the same operation, so it needs that row and
// its rules. A client holds neither for a type its build never syncs, and cannot ask the server
// mid-render - so the answer is no, the way it is for any rule the rows do not satisfy.
function viaHolds(rule, entityType, entity, actorUserId) {
  const relationship = Model.entry(entityType).relationships[rule.via];
  const targetId = entityValue(entityType, entity, `${rule.via}_id`);

  if (!relationship || targetId === null) {
    return false;
  }

  const target = LocalDatabase.getRow(relationship.type, targetId);

  return (
    target !== null && grants(relationship.type, target, rule, actorUserId)
  );
}

function grants(entityType, row, rule, actorUserId) {
  const entry = globalThis.Hologram.sync?.model?.[entityType];

  if (!entry) {
    return false;
  }

  const rules = entry.policy[rule.operation] ?? [];
  const boxed = Model.box(entityType, row);

  return rules.some((related) =>
    ruleMatches(
      {...related, operation: rule.operation},
      entityType,
      boxed,
      actorUserId,
    ),
  );
}

// The key a policy operation is baked under: an atom as its name, a per-role grant lifecycle
// operation as the two names joined by a colon. Policy.operation_key/1 is the twin on the server
// (rendered by Compiler.render_policy/2), and the two must agree.
//
// A tuple naming a LIST of roles is refused: the DSL takes one as sugar for a line per role, so
// no rule is keyed by it - and can? asks about one role at a time.
function operationKey(operation) {
  if (Type.isAtom(operation)) {
    return operation.value;
  }

  if (Type.isTuple(operation) && operation.data.length === 2) {
    const [name, role] = operation.data;

    if (Type.isAtom(name) && Type.isAtom(role)) {
      return `${name.value}:${role.value}`;
    }

    if (Type.isAtom(name) && Type.isList(role)) {
      Interpreter.raiseArgumentError(
        `can? asks about one role - ${Interpreter.inspect(operation)} names several`,
      );
    }
  }

  Interpreter.raiseArgumentError(
    "can? takes an operation atom or a {:grant_role, role} / {:revoke_role, role} tuple",
  );
}

const Elixir_Hologram_Auth = {
  // A global grant is trusted-only on the server, and a client is never the trusted tier - so the
  // server's sentence for an acting user is the browser's sentence unconditionally.
  "grant_role/2": (_userOrId, _role) => {
    raiseAccessDenied(trustedWriteMessage("global", "granted"));
  },

  // Hologram.Auth.grant_role/3 as a browser runs it: the same arguments, the same checks in the
  // same order, and the same gate - can?/3, over the rules and grant rows this client holds. What
  // differs is the end: the server inserts, the browser appends a create of the grant row to the
  // running batch, and the row is readable at once through the overlay. The id is derived from
  // the grant, so this row and the server's are one row; a grant the client already holds under
  // that id answers :ok and writes nothing, which is the server's idempotency mirrored where the
  // client can see it. The server replays every check when the batch lands and a refusal rolls
  // the row back.
  "grant_role/3": (userOrId, resource, role) => {
    const userId = validateUserId(userOrId);
    const {entityType, resourceId} = resourceReference(resource, "granted");
    const roleName = validateDeclaredRole(entityType, role);
    const actorUserId = LocalDatabase.actorUserId;

    if (actorUserId === null) {
      raiseAccessDenied(signedInWriteMessage("granted"));
    }

    const gateResource = Type.struct(entityType, [
      [Type.atom("id"), Type.bitstring(resourceId)],
    ]);

    const allowed = Elixir_Hologram_Auth["can?/3"](
      Type.bitstring(actorUserId),
      Type.tuple([Type.atom("grant_role"), role]),
      gateResource,
    );

    if (!Type.isTrue(allowed)) {
      raiseAccessDenied(
        unqualifiedRoleMessage(
          entityType,
          resourceId,
          actorUserId,
          roleName,
          "grant_role",
        ),
      );
    }

    const resourceType =
      globalThis.Hologram.sync.model[entityType].resourceType;
    const id = deriveGrantId(userId, resourceType, resourceId, roleName);

    if (LocalDatabase.getRow(GRANT_TYPE, id) !== null) {
      return Type.atom("ok");
    }

    const batch = currentBatch("grant_role");

    batch.append({
      claim: null,
      data: {
        granted_by_id: actorUserId,
        resource_id: resourceId,
        resource_type: resourceType,
        role: roleName,
        user_id: userId,
      },
      id: id,
      op: "create",
      stamp: Clock.stamp(),
      type: GRANT_TYPE,
    });

    return Type.atom("ok");
  },

  "can?/3": (userOrId, operation, entity) => {
    const entityType = Interpreter.moduleExName(
      entity.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
    );

    const actorUserId = unboxActorUserId(userOrId);
    const operationName = operationKey(operation);

    // An entry absent from a permission-checking build is a type that declares NO policy - the
    // build ships an entry for every policied type, checked or not, precisely so this read can
    // mean that. And a policy-less type is denied by the server's own default, so no is not a
    // fallback here: it is the server's answer.
    const entry = globalThis.Hologram.sync?.model?.[entityType];

    if (!entry) {
      return Type.boolean(false);
    }

    const rules = entry.policy[operationName] ?? [];

    // An operation with no rules grants nothing, which is what makes the default deny.
    return Type.boolean(
      rules.some((rule) =>
        ruleMatches(
          {...rule, operation: operationName},
          entityType,
          entity,
          actorUserId,
        ),
      ),
    );
  },
};

// IMPORTANT!
// The twin of Hologram.Auth.RoleGrant.derive_id/4, and the two are held to the same vectors -
// test/elixir/hologram/auth/role_grant_test.exs (describe "derive_id/4") and the deriveGrantId()
// describe in test/javascript/elixir/hologram/auth_test.mjs. Always update both together: the
// server recomputes this from a grant write's columns and refuses an id that disagrees, so a
// drift here is a refused grant, never a silent one.
//
// A grant's id is a function of the grant - this user, this resource, this role - so a grant made
// here and the same grant made anywhere else are one row, and nothing about it is reconciled
// after the fact. UUIDv5 (RFC 9562): SHA-1 over the namespace and the name, the name being the
// four parts joined with a newline, each spelled as the store spells it - ids as they are, the
// resource type's label, a role name or a global role module without its "Elixir." prefix, and
// "" for a part that is null. Hashed as UTF-8, which is what the server hashes.
export function deriveGrantId(userId, resourceType, resourceId, role) {
  const name = [userId, resourceType, resourceId, role]
    .map((part) => part ?? "")
    .join("\n");

  const nameBytes = new TextEncoder().encode(name);
  const input = new Uint8Array(GRANT_ID_NAMESPACE.length + nameBytes.length);

  input.set(GRANT_ID_NAMESPACE);
  input.set(nameBytes, GRANT_ID_NAMESPACE.length);

  const bytes = Sha1.digest(input).slice(0, 16);

  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  const hex = Array.from(bytes, (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");

  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

// IMPORTANT!
// The three builders below are hand ports of Hologram.Auth's refusal sentences -
// unqualified_role_message/5, signed_in_write_message/1 and trusted_write_message/2 - and the
// tests in test/javascript/elixir/hologram/auth_test.mjs mirror test/elixir/hologram/auth_test.exs
// string for string. Always update both together: a grant refused in the browser reads the same
// as one refused by the server, so a developer sees one sentence wherever the gate fires.
//
// One sentence the browser cannot say: "<role> extends <held>, so it holds more." The model entry
// carries a type's role NAMES and not their extends chains, so for a type whose roles extend, the
// browser's message is that one sentence shorter than the server's.

// The refusal that teaches: which roles the acting user holds that reach the resource, what those
// may grant (or revoke) there, and the line that would cover it if the omission was not intended.
export function unqualifiedRoleMessage(
  entityType,
  resourceId,
  actorUserId,
  role,
  operation,
) {
  const verb = operation === "grant_role" ? "grant" : "revoke";
  const resource = `${entityType} "${resourceId}"`;
  const held = heldRoleNames(actorUserId, entityType, resourceId);

  if (held.length === 0) {
    return `the acting user holds no role on ${resource} that may ${verb} ${inspectRole(role)}`;
  }

  const covered = coveredRoleNames(
    entityType,
    resourceId,
    actorUserId,
    operation,
  );
  const holder = held.length === 1 ? inspectRole(held[0]) : inspectRoles(held);

  return (
    `the acting user holds ${joinRoleNames(held)} on ${resource}, ` +
    `which may ${verb} ${coveredDescription(covered, role)}. ` +
    `Declare \`allow {:${operation}, ${inspectRole(role)}}, to: ${holder}\` on ${entityType} if that is intended.`
  );
}

// A role is granted (or revoked) only by a signed-in user: what the server's verb reads as trusted
// code, a batch reads as an anonymous session, and so does the browser.
export function signedInWriteMessage(verb) {
  return `a role is ${verb} only by a signed-in user - nobody is signed in`;
}

// The two grant shapes trusted code writes - type-wide and global - which a browser never may.
export function trustedWriteMessage(scope, verb) {
  return `${scope} roles are ${verb} only by trusted code running without an acting user`;
}

function raiseAccessDenied(message) {
  Interpreter.raiseError("Hologram.AccessDeniedError", message);
}

// The struct or entity type module a grant names as its resource, taken apart the way the server
// takes it apart: a struct gives the type and a validated id, a module is a type-wide grant -
// trusted-only, so refused here outright.
function resourceReference(resource, verb) {
  if (Type.isAlias(resource)) {
    raiseAccessDenied(trustedWriteMessage("type-wide", verb));
  }

  const entityType = Interpreter.moduleExName(
    resource.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
  );

  const idEntry = resource.data[Type.encodeMapKey(Type.atom("id"))];
  const resourceId = validateId(idEntry ? idEntry[1] : Type.nil(), "resource");

  return {entityType, resourceId};
}

function validateDeclaredRole(entityType, role) {
  const declared = globalThis.Hologram.sync?.model?.[entityType]?.roles ?? [];
  const roleName = Type.isAtom(role) ? role.value : null;

  if (roleName === null || !declared.includes(roleName)) {
    Interpreter.raiseArgumentError(
      `unknown role ${Interpreter.inspect(role)} for ${entityType} - declared roles are: ${declared.map((name) => `:${name}`).join(", ")}`,
    );
  }

  return roleName;
}

// An id the server would accept: the canonical lowercase spelling, and nothing else - the
// validator's own regex, since the two tiers compare ids as strings.
function validateId(term, subject) {
  const value = Type.isBitstring(term) ? Bitstring.toText(term) : null;

  if (
    value === null ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    )
  ) {
    Interpreter.raiseArgumentError(
      `invalid ${subject} id ${Interpreter.inspect(term)} - entity ids are canonical lowercase 8-4-4-4-12 UUID strings`,
    );
  }

  return value;
}

function validateUserId(userOrId) {
  const term = Type.isMap(userOrId)
    ? (userOrId.data[Type.encodeMapKey(Type.atom("id"))]?.[1] ?? Type.nil())
    : userOrId;

  return validateId(term, "user");
}

function coveredDescription(covered, role) {
  if (covered.length === 0) {
    return `no role there, ${inspectRole(role)} included`;
  }

  return `${joinRoleNames(covered)} but not ${inspectRole(role)}`;
}

// The declared roles the acting user may grant (or revoke) on the resource - the same question
// the gate asked, once per role.
function coveredRoleNames(entityType, resourceId, actorUserId, operation) {
  const entry = globalThis.Hologram.sync?.model?.[entityType];
  const resource = Type.struct(entityType, [
    [Type.atom("id"), Type.bitstring(resourceId)],
  ]);

  return (entry?.roles ?? []).filter((name) =>
    Type.isTrue(
      Elixir_Hologram_Auth["can?/3"](
        Type.bitstring(actorUserId),
        Type.tuple([Type.atom(operation), Type.atom(name)]),
        resource,
      ),
    ),
  );
}

// The roles the acting user holds that reach the resource, as the gate reads them: on the row
// itself or on its whole type, and the global roles held app-wide. Own names first, then role
// modules, each alphabetical - the order the server sorts them in.
function heldRoleNames(actorUserId, entityType, resourceId) {
  const resourceType =
    globalThis.Hologram.sync?.model?.[entityType]?.resourceType;

  return grantRows()
    .filter(
      (row) =>
        row.user_id === actorUserId &&
        ((row.resource_type === resourceType &&
          (row.resource_id === resourceId || row.resource_id === null)) ||
          (row.resource_type === null && row.resource_id === null)),
    )
    .map((row) => row.role)
    .sort(
      (left, right) =>
        Number(isRoleModule(left)) - Number(isRoleModule(right)) ||
        left.localeCompare(right),
    );
}

// A role as inspect/1 spells it: an own role is an atom, a global role is a module.
function inspectRole(name) {
  return isRoleModule(name) ? name : `:${name}`;
}

function inspectRoles(names) {
  return `[${names.map(inspectRole).join(", ")}]`;
}

function isRoleModule(name) {
  return /^[A-Z]/.test(name);
}

function joinRoleNames(names) {
  return names.map(inspectRole).join(" and ");
}

export default Elixir_Hologram_Auth;
