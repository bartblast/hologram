"use strict";

import Interpreter from "../../interpreter.mjs";
import LocalDatabase from "../../local_database.mjs";
import Model from "../../model.mjs";
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

export default Elixir_Hologram_Auth;
