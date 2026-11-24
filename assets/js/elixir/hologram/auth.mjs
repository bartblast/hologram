"use strict";

import Bitstring from "../../bitstring.mjs";
import Clock from "../../clock.mjs";
import {
  currentBatch,
  isServerOnlySentinel,
  validateChangeNames,
} from "./db.mjs";
import Elixir_Hologram_Entity from "./entity.mjs";
import Interpreter from "../../interpreter.mjs";
import LocalDatabase from "../../local_database.mjs";
import Model from "../../model.mjs";
import Overlay from "../../overlay.mjs";
import QueryKernel from "../../query_kernel.mjs";
import Sha1 from "../../sha1.mjs";
import SortKey from "../../sort_key.mjs";
import StringOrder from "../../string_order.mjs";
import Type from "../../type.mjs";

// Whether the acting user may do something, answered here rather than asked of the server.
//
// Hologram.Policy.Evaluator is the reference this mirrors, and Hologram.Auth is where its
// checker lives on that side. The split is kept: rules are evaluated over plain values, and
// what a rule REFERENCES - a role held somewhere - is answered by reading grant rows. The
// server reads them with SELECT EXISTS, this reads them from the pot - bar a reference or
// delegation through a related row this client does not hold, one its user may not read or of a
// type nobody may read, which this answers as unknown.
//
// What the rows this client holds leave unknown, the server's verdict on the operation answers: its
// can? answer for the session's user over the row as stored, sent with the row (see verdictHolds/4).
// It answers the operation whole, never one part of a rule, so it tells the user nothing can?
// doesn't.
//
// Both halves of what it needs are compile-time facts the bundle carries: the rules in each
// type's model entry, and the name the grant store spells that type by. The rows are ordinary
// synced rows, and a page that checks permissions hands over the ones its own checks asked
// about, so the first render answers what the server answered.
const GRANT_TYPE = "Hologram.Auth.RoleGrant";

// The server's refusal of an update of a grant row, which can? with values gives too.
const GRANT_UPDATE_MESSAGE = `cannot update ${GRANT_TYPE} - a role grant is never changed in place, revoke the role and grant the new one instead`;

// The one spelling Hologram gives entity ids, the server validator's own pattern - without the
// multiline flag, $ matches only at the very end, so a trailing newline is no match here either.
const CANONICAL_ID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// What a condition, a role reference or a delegation holds as when this client cannot tell: a
// related row it would read is one it does not hold - one its user may not read, which the server
// reads as stored, so taking it for a missing one could grant what the server refuses
// (`project.status != :archived` over a project the user may not read) - or the value it would read
// is a server-only attribute's, which no client ever holds. A rule grants only on a definite yes,
// and `and` and `or` keep what they can still decide: false and unknown are false, true or unknown
// is true.
const UNKNOWN = Symbol("unknown");

// The rows and boxed entities a rule reads as the database a change would leave, each with that
// change - the twin of the marker Hologram.Auth.after_row/4 sets. A row read from a marked one is
// marked in turn, and a row with no mark reads as stored, so a bare name keeps the stored value.
const afterChanges = new WeakMap();

// The furthest year a JavaScript Date reaches in both directions.
const MAX_DATE_YEAR = 271820n;

// What every write of a value moves, to a moment only the write knows.
const WRITE_TIMESTAMPS = ["server_updated_at", "updated_at"];

// The sixteen bytes Hologram.Auth.RoleGrant derives every grant id under - drawn once, on
// 2026-09-02, and fixed: change them and every grant in every store is renamed.
const GRANT_ID_NAMESPACE = Uint8Array.from([
  0x8b, 0x2f, 0x65, 0x0d, 0xd0, 0xcf, 0x15, 0x26, 0xdf, 0xec, 0x20, 0x9a, 0x31,
  0xd9, 0xf6, 0x6c,
]);

// Every value compares as the wire spells it, so one comparison serves most types.
//
// Three are the exceptions, and all for the same reason: a rule and the filter mirroring it have
// to admit the same rows. An enum's labels say nothing about its order, so the two compare by
// their positions in the list the type declares. A date and a datetime compare by the day or
// instant they name, which their characters stop telling once a year leaves 0 to 9999, its width
// and sign being the year's own (Model.compareTemporal, which the query kernel orders them by too).
// A string compares by the key derived from it and then by the value behind it, which is the pair
// its ordering sorts by - the key is a bounded prefix, which is what leaves the value something to
// settle.
//
// Which applies is decided by the DECLARED type rather than by the runtime one: on the wire a date
// is a string too, and the reference never folds one, because there it is a struct.
function compare(left, right, ranks = null, type = null) {
  if (ranks) {
    return plainCompare(ranks.get(left), ranks.get(right));
  }

  if (type === "date" || type === "datetime") {
    return ["lt", "eq", "gt"][Model.compareTemporal(left, right) + 1];
  }

  if (type !== "string") {
    return plainCompare(left, right);
  }

  const keyResult = plainCompare(SortKey.compute(left), SortKey.compute(right));

  return keyResult === "eq" ? plainCompare(left, right) : keyResult;
}

function plainCompare(left, right) {
  const leftValue = Model.widened(left, right);
  const rightValue = Model.widened(right, left);

  if (leftValue === rightValue) {
    return "eq";
  }

  if (typeof leftValue === "string" && typeof rightValue === "string") {
    return StringOrder.compare(leftValue, rightValue) < 0 ? "lt" : "gt";
  }

  return leftValue < rightValue ? "lt" : leftValue > rightValue ? "gt" : "eq";
}

// A missing value equals only another missing one. Left to the comparison, null compares as a
// number: it reads as 0 against false, 0 or "", and against any other string, which reads as NaN,
// it is neither less nor greater. Either way it would tie - with every id, string and enum label,
// with false and with 0 - and a rule on a missing value would grant what the server refuses.
function equal(left, right) {
  if (left === null || right === null) {
    return left === right;
  }

  return compare(left, right) === "eq";
}

// The role a grant row holds, and where it holds it, are what a reference names - so a match is
// a comparison against the row's own columns.
function grantExists(rows, userId, roles, entityType, entityIds) {
  return rows.some(
    (row) =>
      row.user_id === userId &&
      roles.includes(row.role) &&
      row.entity_type === entityType &&
      entityIds.includes(row.entity_id),
  );
}

function grantRows() {
  return Object.values(LocalDatabase.getTable(GRANT_TYPE));
}

// What the held rows of a set decide of a quantifier over it, given each one's answer.
function heldAnswer(quantifier, answers) {
  switch (quantifier) {
    case "any":
      return answers.includes(true) ? true : UNKNOWN;

    case "none":
      return answers.includes(true) ? false : UNKNOWN;

    default:
      return answers.includes(false) ? false : UNKNOWN;
  }
}

function holds(fieldValue, operator, value, ranks, type = null) {
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
  // database applies, where a comparison with NULL is unknown rather than true. Neither does a
  // search.
  if (fieldValue === null || value === null) {
    return false;
  }

  switch (operator) {
    // A rule and the filter mirroring it have to admit the same rows, so a search matches the way
    // a query does, by bytes or by folded forms.
    case "contains":
      return SortKey.fold(fieldValue).includes(SortKey.fold(value));

    case "contains_exact":
      return fieldValue.includes(value);

    case "starts_with":
      return SortKey.fold(fieldValue).startsWith(SortKey.fold(value));

    case "starts_with_exact":
      return fieldValue.startsWith(value);

    case "<":
      return compare(fieldValue, value, ranks, type) === "lt";

    case "<=":
      return compare(fieldValue, value, ranks, type) !== "gt";

    case ">":
      return compare(fieldValue, value, ranks, type) === "gt";

    default:
      return compare(fieldValue, value, ranks, type) !== "lt";
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

// Another attribute of the same row, of the row a path leads to, or of a row above inside a
// quantifier, which the rule names rather than carries.
function isAttributeValue(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.hasOwn(value, "attribute")
  );
}

// A name of the row a given number of quantifiers out, as the rules spell one.
function isOuterName(name) {
  return (
    name !== null &&
    typeof name === "object" &&
    !Array.isArray(name) &&
    Object.hasOwn(name, "outer")
  );
}

// Whether some alternative of a disjunction holds: true when one does, UNKNOWN when none does
// but one may, false when none can.
function alternativesHold(
  entityType,
  entity,
  alternatives,
  actorUserId,
  outer,
) {
  let result = false;

  for (const alternative of alternatives) {
    const holds = predicatesHold(
      entityType,
      entity,
      alternative,
      actorUserId,
      outer,
    );

    if (holds === true) {
      return true;
    }

    if (holds === UNKNOWN) {
      result = UNKNOWN;
    }
  }

  return result;
}

// A clause is a triple, a disjunction, a quantifier, or the marker the build sends for a predicate
// reading a server-only attribute, which is UNKNOWN: no client holds the value it compares, and the
// server's verdict on the operation answers the rule (see operationHolds/6).
function clauseHolds(entityType, entity, clause, actorUserId, outer) {
  if (Array.isArray(clause)) {
    return predicateHolds(entityType, entity, clause, actorUserId, outer);
  }

  if (Object.hasOwn(clause, "or")) {
    return alternativesHold(entityType, entity, clause.or, actorUserId, outer);
  }

  if (Object.hasOwn(clause, "quantifier")) {
    return quantifierHolds(entityType, entity, clause, actorUserId, outer);
  }

  if (Object.hasOwn(clause, "hasRole")) {
    return newRowRoleHolds(clause.hasRole, actorUserId, outer);
  }

  if (Object.hasOwn(clause, "can")) {
    return newRowOperationHolds(clause.can, actorUserId, outer);
  }

  return UNKNOWN;
}

// A role asked of the row the row after the change leads to, which the outermost scope holds.
function newRowRoleHolds(
  [relationshipNames, targetType, roles],
  actorUserId,
  outer,
) {
  if (actorUserId === null) {
    return false;
  }

  const {entity, entityType} = outer.at(-1);
  const targetId = chainTargetId(entityType, entity, relationshipNames);

  if (targetId === UNKNOWN) {
    return UNKNOWN;
  }

  return (
    targetId !== null &&
    grantExists(grantRows(), actorUserId, roles, targetType, [targetId])
  );
}

// An operation asked of the row the row after the change leads to. It's judged as that row stands,
// so a chain leading back to the changed row asks about its stored copy.
function newRowOperationHolds(
  [operation, relationshipNames],
  actorUserId,
  outer,
) {
  const {entity, entityType} = outer.at(-1);
  const end = chainRow(entityType, entity, relationshipNames);

  if (end === null || end === UNKNOWN) {
    return end === null ? false : UNKNOWN;
  }

  const change = afterChanges.get(end.row);

  const row =
    end.type === change.type && end.row.id === change.id
      ? LocalDatabase.getRow(end.type, change.id)
      : end.row;

  return row === null ? UNKNOWN : grants(end.type, row, operation, actorUserId);
}

// The row a chain of to-one relationships leads to, with its type, null at the first reference
// that is empty, or UNKNOWN at the first one naming a row this client does not hold. The first
// reference is read off the boxed entity, the later ones off the plain rows before them.
function chainRow(entityType, entity, relationshipNames) {
  const [relationshipName, ...laterNames] = relationshipNames;
  const targetId = entityValue(entityType, entity, `${relationshipName}_id`);

  return linkedRow(
    entityType,
    targetId,
    relationshipName,
    laterNames,
    afterChanges.get(entity),
  );
}

// The chain followed from a plain held row, as chainRow/3 follows it from a boxed entity.
function chainRowFrom(entityType, row, relationshipNames) {
  if (relationshipNames.length === 0) {
    return {row, type: entityType};
  }

  const [relationshipName, ...laterNames] = relationshipNames;
  const referenceField = `${relationshipName}_id`;

  const targetId = undecidedByChange(row, referenceField)
    ? UNKNOWN
    : (row[referenceField] ?? null);

  return linkedRow(
    entityType,
    targetId,
    relationshipName,
    laterNames,
    afterChanges.get(row),
  );
}

// The id the last reference of a chain holds, read off the row the relationships before it lead
// to, null when they lead nowhere, or UNKNOWN when they lead to a row this client does not hold -
// one its user may not read, whose reference the server reads as stored.
function chainTargetId(entityType, entity, relationshipNames) {
  const referenceField = `${relationshipNames.at(-1)}_id`;

  if (relationshipNames.length === 1) {
    return entityValue(entityType, entity, referenceField);
  }

  const end = chainRow(entityType, entity, relationshipNames.slice(0, -1));

  if (end === null || end === UNKNOWN) {
    return end;
  }

  return undecidedByChange(end.row, referenceField)
    ? UNKNOWN
    : (end.row[referenceField] ?? null);
}

// The type a name is declared with - an attribute's, or a derived field's holding a value - or
// null for a reference field, which carries an entity id.
function declaredType(entityType, name) {
  const derived = Model.derivedField(entityType, name);

  return (
    Model.own(Model.entry(entityType).attributes, name) ?? derived?.type ?? null
  );
}

// A derived field's value on a boxed entity, an integer a float field reads widened, the way the
// database casts it.
function derivedValue(entityType, entity, derived) {
  return Model.widenedTo(
    evaluatedDefinition(entityType, entity, derived.definition),
    derived.type,
  );
}

// The value a rule compares against, read off the boxed entity in the spelling the rules were
// baked in - the rules travel wire-spelled, so what they are compared with must be too. A derived
// field is computed from its definition over the row the entity holds, the way the query kernel
// computes it, whatever the struct carries under its name - the reference computes it too. A
// server-only attribute is UNKNOWN: no client is ever sent its value, so whatever a struct holds
// there - the sentinel, or a value an action put in - is not the stored one.
function entityValue(entityType, entity, name) {
  if (
    Model.entry(entityType).serverOnly.has(name) ||
    undecidedByChange(entity, name)
  ) {
    return UNKNOWN;
  }

  const derived = Model.derivedField(entityType, name);

  if (derived) {
    return derivedValue(entityType, entity, derived);
  }

  return storedValue(entityType, entity, name);
}

// What an enum predicate compares by, or null for a name of any other type - an attribute's or a
// derived field's declared values.
function enumRanks(entityType, name) {
  const entry = Model.entry(entityType);
  const derived = Model.derivedField(entityType, name);

  const values =
    entry.attributes[name] === "enum"
      ? entry.enumValues[name]
      : derived?.type === "enum"
        ? derived.values
        : null;

  return values && new Map(values.map((label, index) => [label, index]));
}

// A derived field's definition computed over a boxed entity, the way the query kernel computes it,
// except that what reads a related row this client does not hold is UNKNOWN rather than nil:
// strings joined, nil when one of them is and UNKNOWN when one may be; whether a condition holds;
// the branch an if's condition decides, UNKNOWN when it cannot decide; a name read as a rule reads
// it. A count reads a related set whole, which a client never holds for certain, so it is UNKNOWN -
// the server's verdict on the operation answers a rule whose quantifier's condition reads one.
function evaluatedDefinition(entityType, entity, definition) {
  if ("concat" in definition) {
    const values = definition.concat.map((operand) =>
      evaluatedDefinition(entityType, entity, operand),
    );

    if (values.includes(null)) {
      return null;
    }

    return values.includes(UNKNOWN) ? UNKNOWN : values.join("");
  }

  if ("condition" in definition) {
    return predicatesHold(entityType, entity, definition.condition, null);
  }

  if ("if" in definition) {
    const holds = predicatesHold(entityType, entity, definition.if, null);

    if (holds === UNKNOWN) {
      return UNKNOWN;
    }

    const branch = holds ? definition.then : definition.else;

    return evaluatedDefinition(entityType, entity, branch);
  }

  if ("name" in definition) {
    return nameValue(entityType, entity, definition.name);
  }

  return "value" in definition ? definition.value : UNKNOWN;
}

// A field's value off a held row as the wire spells it - a derived field computed on the row, as a
// boxed entity of it. A server-only attribute is UNKNOWN: a held row carries no value for it.
function fieldValue(entityType, row, name) {
  if (
    Model.entry(entityType).serverOnly.has(name) ||
    undecidedByChange(row, name)
  ) {
    return UNKNOWN;
  }

  const derived = Model.derivedField(entityType, name);

  if (derived === null) {
    return row[name] ?? null;
  }

  return derivedValue(
    entityType,
    boxedAs(entityType, row, afterChanges.get(row)),
    derived,
  );
}

// A held row boxed, carrying the change it's read under. The changed row is its own boxed entity.
function boxedAs(entityType, row, change) {
  if (change === undefined) {
    return Model.box(entityType, row);
  }

  if (change.builtRow === row) {
    return change.entity;
  }

  const boxed = Model.box(entityType, row);

  afterChanges.set(boxed, change);

  return boxed;
}

// Whether the name is a field of the changed row this client can't tell the value of after the
// change: a timestamp, which the write sets to a moment only it knows, or a reference to a row it
// doesn't hold, which reads as stored on the server if no such row exists.
function undecidedByChange(rowOrEntity, name) {
  const change = afterChanges.get(rowOrEntity);

  return (
    change !== undefined &&
    (change.entity === rowOrEntity || change.builtRow === rowOrEntity) &&
    change.undecided.has(name)
  );
}

// The changed row as a held row spells it, built when a hop first lands on it. An attribute is read
// off the struct when a rule asks for it, as the server reads it, so a field no rule reads is never
// unboxed.
function changedRow(change) {
  if (change.builtRow === null) {
    const {entity, type} = change;
    const entry = Model.entry(type);
    const row = referenceRow(type, entity);

    for (const name of Object.keys(entry.attributes)) {
      if (!entry.serverOnly.has(name) && !Object.hasOwn(row, name)) {
        Object.defineProperty(row, name, {
          enumerable: true,
          get: () => storedValue(type, entity, name),
        });
      }
    }

    change.builtRow = row;
    afterChanges.set(row, change);
  }

  return change.builtRow;
}

// Whether the boxed entity holds a server-only attribute's sentinel - what it arrived with, since
// no client ever learns the stored value.
function holdsServerOnlySentinel(entity, name) {
  const entry = entity.data[Type.encodeMapKey(Type.atom(name))];

  return entry !== undefined && isServerOnlySentinel(entry[1]);
}

// The row one to-one relationship's reference names, then the chain after it from there - null for
// an empty reference, UNKNOWN for a row this client does not hold. Under a change, the changed row
// is read as it will be and the rest are marked, so the hops after them read the same state.
function linkedRow(entityType, targetId, relationshipName, laterNames, change) {
  if (targetId === null) {
    return null;
  }

  if (targetId === UNKNOWN) {
    return UNKNOWN;
  }

  const type = Model.relationships(entityType)[relationshipName].type;

  const row =
    change === undefined
      ? LocalDatabase.getRow(type, targetId)
      : rowUnderChange(type, targetId, change);

  return row === null ? UNKNOWN : chainRowFrom(type, row, laterNames);
}

function rowUnderChange(type, id, change) {
  if (type === change.type && id === change.id) {
    return changedRow(change);
  }

  const held = LocalDatabase.getRow(type, id);

  if (held === null) {
    return null;
  }

  const row = {...held};

  afterChanges.set(row, change);

  return row;
}

// Whether the given clauses name the acting user anywhere - inside a disjunction's alternatives
// and a quantifier's condition included.
function namesActor(clauses) {
  return clauses.some((clause) => {
    if (Array.isArray(clause)) {
      return isActorValue(clause[2]);
    }

    if (Object.hasOwn(clause, "or")) {
      return clause.or.some(namesActor);
    }

    // The marker the build sends for what no client decides says nothing about who it asks of.
    return Object.hasOwn(clause, "filter") && namesActor(clause.filter);
  });
}

// The type an attribute is declared on and its name - the entity's own for a bare name, and for a
// path the type its relationships lead to, which decides how the path's value compares.
function nameEnd(entityType, name) {
  if (!Array.isArray(name)) {
    return {name, type: entityType};
  }

  return {
    name: name.at(-1),
    type: Model.pathTarget(entityType, name.slice(0, -1)),
  };
}

// An attribute's value off the boxed entity, or a path's off the row its relationships lead to,
// as the wire spells it - null when they lead nowhere.
function nameValue(entityType, entity, name) {
  if (!Array.isArray(name)) {
    return entityValue(entityType, entity, name);
  }

  const end = chainRow(entityType, entity, name.slice(0, -1));

  if (end === null || end === UNKNOWN) {
    return end;
  }

  return fieldValue(end.type, end.row, name.at(-1));
}

// The actor of a visitor is nobody rather than null - null would equal a missing reference and
// hand a visitor every row that has none - so a predicate asking about the actor answers false
// for a visitor, whichever way it points.
function predicateHolds(
  entityType,
  entity,
  [name, operator, value],
  actorUserId,
  outer,
) {
  if (isActorValue(value) && actorUserId === null) {
    return false;
  }

  const scoped = scopedName(entityType, entity, outer, name);
  const end = nameEnd(scoped.entityType, scoped.name);
  const subject = nameValue(scoped.entityType, scoped.entity, scoped.name);

  const operand = operandValue(entityType, entity, value, actorUserId, outer);

  if (subject === UNKNOWN || operand === UNKNOWN) {
    return UNKNOWN;
  }

  return holds(
    subject,
    operator,
    operand,
    enumRanks(end.type, end.name),
    declaredType(end.type, end.name),
  );
}

// What a rule's operand stands for on this row: the acting user, another attribute of the row read
// off it or of the row a path leads to, or the value itself. An attribute operand compares by the
// predicate's attribute's ranks and type, since two enums compare only when they declare the same
// list, and two temporal values only when they are of one type.
function operandValue(entityType, entity, value, actorUserId, outer) {
  if (isActorValue(value)) {
    return actorUserId;
  }

  if (isAttributeValue(value)) {
    const scoped = scopedName(entityType, entity, outer, value.attribute);

    return nameValue(scoped.entityType, scoped.entity, scoped.name);
  }

  return value;
}

// A clause is a triple array, a disjunction object holding alternatives that are clause lists
// themselves, a quantifier object, or a server-only marker (see clauseHolds/5) - every clause has
// to hold, a disjunction holds when one of its alternatives does. False when a clause does not
// hold, UNKNOWN when none fails but one may, true when all hold. The outer rows are the rows above
// the entity inside a quantifier, nearest first, each with its type - none at the top of a rule.
function predicatesHold(entityType, entity, clauses, actorUserId, outer = []) {
  let result = true;

  for (const clause of clauses) {
    const holds = clauseHolds(entityType, entity, clause, actorUserId, outer);

    if (holds === false) {
      return false;
    }

    if (holds === UNKNOWN) {
      result = UNKNOWN;
    }
  }

  return result;
}

// A quantifier answered over the rows this client holds of the set its source leads to, read on
// the row it is about or on the row above it the source names - a subset of the set the server
// reads, so a held row decides only what one row can: any is true once a held row matches, none
// false once one matches, all false once one fails. Anything else is UNKNOWN, since a row this
// client does not hold may decide it. Over a derived set the held rows decide nothing. A none or
// an all asking about a visitor asks about nobody, which grants nothing.
function quantifierHolds(entityType, entity, clause, actorUserId, outer) {
  if (
    actorUserId === null &&
    clause.quantifier !== "any" &&
    namesActor(clause.filter)
  ) {
    return false;
  }

  const start = Array.isArray(clause.source)
    ? {entity, entityType, hops: clause.source}
    : {...outer[clause.source.outer - 1], hops: clause.source.name};

  // A bounded or filtered set computed over the rows this client holds can hold rows the server's
  // doesn't, so not even a held row decides a quantifier over one.
  if (throughDerivedSet(start.entityType, start.hops)) {
    return UNKNOWN;
  }

  const change = afterChanges.get(start.entity);

  // The held rows of a set the change moves a row into or out of are the stored ones, which could
  // answer a definite no the row after the change doesn't.
  if (change !== undefined && changeReachesSet(start, change)) {
    return UNKNOWN;
  }

  const relatedType = Model.pathTarget(start.entityType, start.hops);
  const innerOuter = [{entity, entityType}, ...outer];

  const related = QueryKernel.chainRows(
    referenceRow(start.entityType, start.entity),
    start.entityType,
    start.hops,
  );

  const answers = related.map((row) =>
    predicatesHold(
      relatedType,
      boxedAs(relatedType, row, change),
      clause.filter,
      actorUserId,
      innerOuter,
    ),
  );

  return heldAnswer(clause.quantifier, answers);
}

// Whether a set read under a change can hold a row the change affects: a hop lands on the changed
// type.
function changeReachesSet({entityType, hops}, change) {
  let type = entityType;

  return hops.some((name) => {
    type = (
      Model.own(Model.relationships(type), name) ??
      Model.own(Model.inverses(type), name)
    ).type;

    return type === change.type;
  });
}

// The boxed entity's id and reference fields as a held row spells them - what a set's rows are
// read from it by.
function referenceRow(entityType, entity) {
  const names = Object.entries(Model.relationships(entityType))
    .filter(([_name, relationship]) => !relationship.toMany)
    .map(([name]) => `${name}_id`);

  return Object.fromEntries(
    ["id", ...names].map((name) => [
      name,
      storedValue(entityType, entity, name),
    ]),
  );
}

// Where a role must be held for a reference to be satisfied. Each shape names a scope the grant
// store keeps apart by its scope columns - an own-scope role is held on the entity itself OR
// on its whole type, which the store spells as a null entity id.
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
      const id = entityValue(entityType, entity, "id");

      return grantExists(rows, actorUserId, roles, entityType, [id, null]);
    }

    // A role held on the row a chain of relationships leads to, named by the id its last
    // reference holds - UNKNOWN when this client does not hold a row the id is read through, for
    // the server's verdict on the operation to answer. In a read rule, one reading a row of a type
    // nobody may read comes with a fifth element, true: no client holds the row the id is read
    // off, so it is UNKNOWN.
    case "rel": {
      const [_kind, relationshipNames, targetType, roles, undecided] =
        reference;

      if (undecided !== undefined) {
        return UNKNOWN;
      }

      const targetId = chainTargetId(entityType, entity, relationshipNames);

      if (targetId === UNKNOWN) {
        return UNKNOWN;
      }

      return (
        targetId !== null &&
        grantExists(rows, actorUserId, roles, targetType, [targetId])
      );
    }

    // The grant store's own rule: a role held on the entity the grant row names, or on its whole
    // type. A type-wide grant row names no entity, so this reference never admits it.
    case "named": {
      const [_kind, targetType, roles] = reference;
      const rowEntityId = entityValue(entityType, entity, "entity_id");

      return (
        rowEntityId !== null &&
        grantExists(rows, actorUserId, roles, targetType, [rowEntityId, null])
      );
    }

    default: {
      const [_kind, targetType, roles] = reference;

      return grantExists(rows, actorUserId, roles, targetType, [null]);
    }
  }
}

// Whether a rule holds: true when its conditions, one of its role references and its delegation
// all hold, false when one of them can't, and UNKNOWN when none fails but one may - for the
// server's verdict on the operation to answer (see operationHolds/6).
//
// A visitor's rules are evaluated rather than skipped, so a disjunction can still answer through
// an alternative that names nobody. A role is held by somebody, so a visitor holds none, and the
// grant rows are not read. A delegating rule is evaluated as any other, because the type it
// delegates to answers its own actor-referencing rules the same way.
//
// Given the row after a change, a rule reading it is judged by its clauses as written, with that row
// one level above the rule's own.
function ruleHolds(rule, entityType, entity, actorUserId, after = null) {
  const exact = after !== null && Object.hasOwn(rule, "new");

  let result = predicatesHold(
    entityType,
    entity,
    exact ? rule.new.predicates : rule.predicates,
    actorUserId,
    exact ? [after] : [],
  );

  if (result === false) {
    return false;
  }

  if (rule.to !== null) {
    if (actorUserId === null) {
      return false;
    }

    const held = someHolds(rule.to, (reference) =>
      referenceHolds(reference, entityType, entity, actorUserId),
    );

    if (held === false) {
      return false;
    }

    if (held === UNKNOWN) {
      result = UNKNOWN;
    }
  }

  if (rule.via !== null) {
    const held = viaHolds(rule, entityType, entity, actorUserId);

    if (held === false) {
      return false;
    }

    if (held === UNKNOWN) {
      result = UNKNOWN;
    }
  }

  return result;
}

// Whether the given answer holds for one of the given items: true when it holds for one, UNKNOWN
// when it holds for none but may for one, false when it can for none.
function someHolds(items, answer) {
  let result = false;

  for (const item of items) {
    const held = answer(item);

    if (held === true) {
      return true;
    }

    if (held === UNKNOWN) {
      result = UNKNOWN;
    }
  }

  return result;
}

// The row a name is read on and the name itself: the entity's own for a name of its row, and that
// row's for a name of a row above.
function scopedName(entityType, entity, outer, name) {
  if (!isOuterName(name)) {
    return {entity, entityType, name};
  }

  return {...outer[name.outer - 1], name: name.name};
}

// Whether the boxed entity holds what the given base row does in every stored field. A server-only
// attribute is in no base row, so it counts as unchanged while the entity still holds its sentinel.
function storedAsBase(entityType, entity, row) {
  const entry = Model.entry(entityType);

  const names = [
    ...Object.keys(entry.attributes),
    ...Object.keys(referenceRow(entityType, entity)),
  ];

  return names.every((name) =>
    entry.serverOnly.has(name)
      ? holdsServerOnlySentinel(entity, name)
      : storedValue(entityType, entity, name) === (row[name] ?? null),
  );
}

// A stored field's value off the boxed entity, as the wire spells it - an attribute by its declared
// type, a reference field as the uuid it holds.
function storedValue(entityType, entity, name) {
  const attributeType = Model.entry(entityType).attributes[name] ?? "uuid";
  const key = Type.encodeMapKey(Type.atom(name));
  const entry = entity.data[key];

  return entry ? Model.unbox(entry[1], attributeType) : null;
}

// Whether a chain of relationships read from a row of the given type runs through a derived field
// holding rows.
function throughDerivedSet(entityType, names) {
  let type = entityType;

  for (const name of names) {
    if (Model.derivedField(type, name) !== null) {
      return true;
    }

    type = (
      Model.own(Model.relationships(type), name) ??
      Model.own(Model.inverses(type), name)
    ).type;
  }

  return false;
}

// The acting user as rules read it, taken from the user entity or the id itself - the twin of
// acting_user_id/1 in Hologram.Auth. It is null, a visitor, for nil and for an id in any spelling
// but the canonical lowercase uuid an entity id is. A session's user id may be any string, integer
// or atom, and one naming no user entity is anonymous to the rules. Read as somebody holding
// nothing, it would pass an inequality on the acting user for every row it doesn't own.
function unboxActorUserId(userOrId) {
  const term = Type.isMap(userOrId)
    ? (userOrId.data[Type.encodeMapKey(Type.atom("id"))]?.[1] ?? Type.nil())
    : userOrId;

  return Type.isBitstring(term) ? canonicalId(Model.unbox(term, "uuid")) : null;
}

// The given plain value when it is an id Hologram generates, and null otherwise.
function canonicalId(value) {
  return typeof value === "string" && CANONICAL_ID.test(value) ? value : null;
}

// The server's verdict on an operation whose rules the rows this client holds leave open - a
// quantifier they can't decide, a predicate reading a server-only attribute, a condition, role
// reference or delegation reading a related row this client does not hold, which its user may not
// read, or a read rule's clause, role reference or delegation reading a row of a type nobody may
// read - as the row's last frame carried it. The entry is the operation's verdict key and the types
// its rules read. The server works verdicts out for the session's user over the row as stored, so
// any other question is UNKNOWN: one about another user or a visitor, one about a struct whose
// stored fields differ from the row's - changed in an action and not written yet - and one asked
// while a write of this client's that the server has not answered names a type the operation's
// rules read, since that write may have moved the answer. So is one about a row that came with no
// verdict.
//
// An answer can settle a batch before the frame carrying its round arrives, and between the two
// the verdict predates the write again: the answer files the write's values into the base row,
// which keeps the verdicts the server worked out before it. A verdict answers its operation whole,
// so in that gap it can grant over values it was never worked out for - those of the row itself
// or of a row its rules read - and an action can write what the server then refuses and rolls
// back. The gap closes itself: a write moving a verdict brings the new one with its frame, and
// a write that moves none sends none, since the verdict held stands. A rule the held rows decide
// never reads it in between.
function verdictHolds(entityType, entity, entry, actorUserId) {
  // The server works a session's verdicts out for its user as rules read it, a visitor for an id
  // naming no user entity.
  if (actorUserId !== LocalDatabase.actorEntityId) {
    return UNKNOWN;
  }

  if (entry.reads.some((type) => Overlay.namesType(type))) {
    return UNKNOWN;
  }

  const id = storedValue(entityType, entity, "id");
  const row = id === null ? null : LocalDatabase.baseRow(entityType, id);

  if (row === null || !storedAsBase(entityType, entity, row)) {
    return UNKNOWN;
  }

  const verdict = row.$verdicts?.[entry.verdict];

  return typeof verdict === "boolean" ? verdict : UNKNOWN;
}

// Delegation asks the RELATED entity's policy for the operation the rule names, of the row its
// chain of relationships leads to, so it needs that row and its rules. An empty reference leads
// nowhere, which holds nothing on the server either. A row this client does not hold, one its user
// may not read, is UNKNOWN, for the server's verdict on the operation to answer: a client cannot
// ask the server mid-render. In a read rule, a delegation whose chain passes a row of a type
// nobody may read comes with a third element, true, and is UNKNOWN. A held row answers as its own
// operation does, its verdict included (see grants/4).
function viaHolds(rule, entityType, entity, actorUserId) {
  const [operation, relationshipNames, undecided] = rule.via;

  if (undecided !== undefined) {
    return UNKNOWN;
  }

  const end = chainRow(entityType, entity, relationshipNames);

  if (end === null) {
    return false;
  }

  if (end === UNKNOWN) {
    return UNKNOWN;
  }

  return grants(end.type, end.row, operation, actorUserId);
}

// The rules the build baked under the given key, or none. Only the policy's own keys count: it is
// a plain object, so a name like constructor would otherwise read a property of Object.prototype.
function policyRules(entry, key) {
  const policy = Model.readPolicy(entry.policy);

  return Object.hasOwn(policy, key) ? policy[key] : [];
}

// The verdict entry the build baked under the given key, or undefined - a hand-built entry may
// carry none. Only the entry's own keys count, as for the rules.
function verdictEntry(entry, key) {
  const verdicts = entry.verdicts ?? {};

  return Object.hasOwn(verdicts, key) ? verdicts[key] : undefined;
}

// Whether one of the given rules of an operation holds: true or false when the rows this client
// holds decide it, and otherwise the server's verdict on the operation when the build baked one
// under the key, which is UNKNOWN in turn for a struct, a user or a write it can't speak for.
function operationHolds(entry, entityType, entity, key, rules, actorUserId) {
  const held = someHolds(rules, (rule) =>
    ruleHolds(rule, entityType, entity, actorUserId),
  );

  if (held !== UNKNOWN) {
    return held;
  }

  const verdict = verdictEntry(entry, key);

  return verdict === undefined
    ? UNKNOWN
    : verdictHolds(entityType, entity, verdict, actorUserId);
}

// Whether the given operation, as its key, holds for a plain row of the given type - what a
// delegation asks of the row its chain leads to.
function grants(entityType, row, operation, actorUserId) {
  const entry = globalThis.Hologram.sync?.model?.[entityType];

  if (!entry) {
    return false;
  }

  const rules = policyRules(entry, operation);
  const boxed = Model.box(entityType, row);

  return operationHolds(
    entry,
    entityType,
    boxed,
    operation,
    rules,
    actorUserId,
  );
}

// The fields an {:update, field} or {:update, fields} ask names, or null for any other operation.
// The names are not validated here - Model.validateOperation refuses an unknown one, or an empty
// list, in the server's words. For a type with no baked entry only the empty list is refused, since
// telling an unknown field from a real one takes the entry.
function askedFields(operation) {
  if (!Type.isTuple(operation) || operation.data.length !== 2) {
    return null;
  }

  const [name, fields] = operation.data;

  if (!Type.isAtom(name) || name.value !== "update") {
    return null;
  }

  if (Type.isAtom(fields)) {
    return [fields];
  }

  return Type.isProperList(fields) ? fields.data : null;
}

// Whether some update rule covering each of the given fields holds: a field's own key's rules,
// then the rules covering the whole row - Hologram.Policy.field_rules/2 as the server reads it. A
// field's key is the one Policy.operation_key/1 gives {:update, field} - a hand-ported pair, so a
// change there is a change here. A rule covering the whole row is matched once however many
// fields ask it.
//
// A field the held rows leave open is answered by the server's verdict under its key, which answers
// its lines and the whole row's together. A field whose own lines hold no item only the server
// decides and read no related row a reader may not hold has none, and the whole row's verdict
// answers it: when the whole-row rules hold the field is covered. When they don't, the answer is
// no, which can deny where a line of the field's own would grant on the server - one delegating to
// a create the held row's rules leave open, or to a held row whose rules leave it open and whose
// own verdict can't speak, like one the browser created - never grant wrongly.
function coversFields(entry, entityType, entity, fields, actorUserId) {
  const matched = new Map();

  const holds = (rule) => {
    if (!matched.has(rule)) {
      matched.set(rule, ruleHolds(rule, entityType, entity, actorUserId));
    }

    return matched.get(rule);
  };

  const wholeRowRules = policyRules(entry, "update");

  return fields.every((field) => {
    const key = `update:${field.value}`;
    const rules = policyRules(entry, key).concat(wholeRowRules);
    const held = someHolds(rules, holds);

    if (held !== UNKNOWN) {
      return held;
    }

    return verdictAnswers(
      entry,
      entityType,
      entity,
      [key, "update"],
      actorUserId,
    );
  });
}

// Whether the first verdict entry baked under the given keys grants the row.
function verdictAnswers(entry, entityType, entity, keys, actorUserId) {
  const verdict = keys
    .map((key) => verdictEntry(entry, key))
    .find((found) => found !== undefined);

  return (
    verdict !== undefined &&
    verdictHolds(entityType, entity, verdict, actorUserId) === true
  );
}

function readsRowAfterChange(rule) {
  return Object.hasOwn(rule, "new");
}

// What the given rules' answer for one specific change comes to. A verdict speaks for a rule's
// planned form, which says nothing about one change, so it answers what the held rows leave open
// only when none of the rules reads the row after the change, and they all ask what it answers.
function changeRulesAnswer(
  held,
  rules,
  entry,
  entityType,
  entity,
  keys,
  actorUserId,
) {
  return held === UNKNOWN && !rules.some(readsRowAfterChange)
    ? verdictAnswers(entry, entityType, entity, keys, actorUserId)
    : held;
}

// Whether the server's verdict on the whole-row update rules grants the row. It speaks for one
// specific change only when none of them reads the row after the change, whatever the field's own
// rules read.
function wholeRowVerdictGrants(entry, entityType, entity, rules, actorUserId) {
  return (
    rules.length > 0 &&
    !rules.some(readsRowAfterChange) &&
    verdictAnswers(entry, entityType, entity, ["update"], actorUserId)
  );
}

// Whether some update rule covering each of the given field names holds on the row after a change:
// false when one can't be covered, UNKNOWN when none fails but one may.
function coversChange(entry, entityType, entity, fields, after, actorUserId) {
  const matched = new Map();

  const holds = (rule) => {
    if (!matched.has(rule)) {
      matched.set(
        rule,
        ruleHolds(rule, entityType, entity, actorUserId, after),
      );
    }

    return matched.get(rule);
  };

  const wholeRowRules = policyRules(entry, "update");
  let result = true;

  for (const field of fields) {
    const key = `update:${field}`;
    const rules = policyRules(entry, key).concat(wholeRowRules);

    const answer = changeRulesAnswer(
      someHolds(rules, holds),
      rules,
      entry,
      entityType,
      entity,
      [key, "update"],
      actorUserId,
    );

    const held =
      answer === UNKNOWN &&
      wholeRowVerdictGrants(
        entry,
        entityType,
        entity,
        wholeRowRules,
        actorUserId,
      )
        ? true
        : answer;

    if (held === false) {
      return false;
    }

    if (held === UNKNOWN) {
      result = UNKNOWN;
    }
  }

  return result;
}

// The value a name of the row after the change holds when the call alone says so, or UNKNOWN.
function statedName(name, stated) {
  return isOuterName(name) &&
    name.outer === 1 &&
    typeof name.name === "string" &&
    stated.has(name.name)
    ? stated.get(name.name)
    : UNKNOWN;
}

// What a clause's operand is when the call alone says so: a value written in the rule, or a name
// the call states. The acting user is the session's, which the call doesn't state.
function statedOperand(value, stated) {
  if (isActorValue(value)) {
    return UNKNOWN;
  }

  if (isAttributeValue(value)) {
    return statedName(value.attribute, stated);
  }

  if (Array.isArray(value)) {
    return value.some((item) => statedOperand(item, stated) === UNKNOWN)
      ? UNKNOWN
      : value;
  }

  return value;
}

// A float this large is a whole number, which a write spells as bare digits, and the server can read
// those back as the float next to it. An integer past 2^53 is a BigInt here, and travels exactly.
function isBigWholeFloat(value) {
  return Array.isArray(value)
    ? value.some(isBigWholeFloat)
    : typeof value === "number" &&
        Number.isInteger(value) &&
        !Number.isSafeInteger(value);
}

// Whether a triple holds by the call alone: it compares names the call states with each other or
// with a value written in the rule. Anything else reads what only the server knows for certain.
function statedTripleHolds(entityType, [name, operator, value], stated) {
  const subject = statedName(name, stated);
  const operand = statedOperand(value, stated);

  if (subject === UNKNOWN || operand === UNKNOWN) {
    return UNKNOWN;
  }

  if (isBigWholeFloat(subject) || isBigWholeFloat(operand)) {
    return UNKNOWN;
  }

  return holds(
    subject,
    operator,
    operand,
    enumRanks(entityType, name.name),
    declaredType(entityType, name.name),
  );
}

function statedClausesHold(entityType, clauses, stated) {
  let result = true;

  for (const clause of clauses) {
    let held = UNKNOWN;

    if (Array.isArray(clause)) {
      held = statedTripleHolds(entityType, clause, stated);
    } else if (Object.hasOwn(clause, "or")) {
      held = someHolds(clause.or, (alternative) =>
        statedClausesHold(entityType, alternative, stated),
      );
    }

    if (held === false) {
      return false;
    }

    if (held === UNKNOWN) {
      result = UNKNOWN;
    }
  }

  return result;
}

// Whether a rule holds by the call alone. A role or a delegation reads what only the server knows
// for certain, so a rule with one holds at most UNKNOWN.
function statedRuleHolds(rule, entityType, stated) {
  const clauses = Object.hasOwn(rule, "new")
    ? rule.new.predicates
    : rule.predicates;

  const result = statedClausesHold(entityType, clauses, stated);

  if (result === false) {
    return false;
  }

  return rule.to === null && rule.via === null ? result : UNKNOWN;
}

// Whether a date or a datetime is one this client can neither validate nor compare: its year, or
// the instant its offset moves it to, is past what a JavaScript Date holds.
function isFarDate(value, type) {
  if ((type !== "date" && type !== "datetime") || !Type.isMap(value)) {
    return false;
  }

  const year = value.data[Type.encodeMapKey(Type.atom("year"))]?.[1];

  if (year === undefined || !Type.isInteger(year)) {
    return false;
  }

  if (year.value > MAX_DATE_YEAR || year.value < -MAX_DATE_YEAR) {
    return true;
  }

  try {
    return Model.unbox(value, type).includes("NaN");
  } catch {
    return true;
  }
}

// The values a call states that a rule can read as they are, as a held row spells them, the names
// of the invalid ones, and the names this client can't be sure of. An invalid value reads as stored
// on the server, and a reference to a row reads as stored when no such row exists, which this
// client can't tell, so neither is stated. Nor is a value with a format, since the browser's regex
// engine doesn't always answer as the server's does, or a date past what a JavaScript Date holds.
function statedValues(entityType, values) {
  const validation = Elixir_Hologram_Entity["validate/2"](
    Type.alias(entityType),
    Type.map(
      Object.entries(values).map(([name, value]) => [Type.atom(name), value]),
    ),
  );

  const invalid = Type.isAtom(validation)
    ? []
    : Object.values(validation.data[1].data).map(([name]) => name.value);

  const {attributes, constraints} = Model.entry(entityType);
  const stated = new Map();
  const unsure = [];

  for (const [name, value] of Object.entries(values)) {
    if (
      Object.hasOwn(constraints?.[name] ?? {}, "format") ||
      isFarDate(value, attributes[name])
    ) {
      unsure.push(name);
    } else if (
      !invalid.includes(name) &&
      (Object.hasOwn(attributes, name) || Type.isNil(value))
    ) {
      stated.set(name, Model.unbox(value, attributes[name] ?? "uuid"));
    }
  }

  return {invalid, stated, unsure};
}

// The refusal of an update, in the words of the server's Writer.
function deniedUpdateMessage(entityType, id, uncovered, invalid) {
  const spell = (fields) =>
    fields.map((field) => Interpreter.inspect(Type.atom(field))).join(", ");

  const invalidFields = uncovered.filter((field) => invalid.includes(field));

  let hint = "";

  if (invalidFields.length === 1) {
    hint = ` (the value given for ${spell(invalidFields)} is invalid, so its rule read the stored value)`;
  } else if (invalidFields.length > 1) {
    hint = ` (the values given for ${spell(invalidFields)} are invalid, so their rules read the stored values)`;
  }

  return `not allowed to update ${entityType} ${Interpreter.inspect(Type.bitstring(id))} - no allow line that holds covers ${spell(uncovered)}${hint}`;
}

// Refuses an update the values it states can't pass, whatever the server holds, before it leaves
// this client. What the rows and grants here say is never grounds for a refusal: they can be out of
// date, and a client's write isn't refused for what it read. A type with no rule reading the row
// after the change on a changed field writes as it did. A field the call alone leaves open sends
// the write on, since only the server can name every field it refuses. The given function answers
// which counters' moves can't be on the row as this client holds it: the refusal stands whatever
// the server holds, and they only decide whether it says their value was invalid.
export function refuseDeniedChange(
  entityType,
  id,
  values,
  deltas,
  edgeNames,
  unmovable,
) {
  const model = globalThis.Hologram.sync?.model ?? {};
  const entry = Object.hasOwn(model, entityType) ? model[entityType] : null;

  if (entry === null || entry.policy === undefined) {
    return;
  }

  const names = [...Object.keys(values), ...Object.keys(deltas)];

  const fields = [
    ...new Set([...changedFieldNames(entityType, names), ...edgeNames]),
  ];

  const rulesOf = (field) =>
    policyRules(entry, `update:${field}`).concat(policyRules(entry, "update"));

  const readsChange = fields.some((field) =>
    rulesOf(field).some(readsRowAfterChange),
  );

  if (!readsChange) {
    return;
  }

  const {invalid, stated, unsure} = statedValues(entityType, values);
  const answers = new Map();

  const holdsByCall = (rule) => {
    if (!answers.has(rule)) {
      answers.set(rule, statedRuleHolds(rule, entityType, stated));
    }

    return answers.get(rule);
  };

  const fieldAnswers = fields.map((field) => [
    field,
    someHolds(rulesOf(field), holdsByCall),
  ]);

  if (fieldAnswers.some(([_field, answer]) => answer === UNKNOWN)) {
    return;
  }

  const uncovered = fieldAnswers
    .filter(([_field, answer]) => answer === false)
    .map(([field]) => field)
    .sort(StringOrder.compare);

  // Whether a refused field's value is invalid is part of what the refusal says.
  if (uncovered.some((field) => unsure.includes(field))) {
    return;
  }

  if (uncovered.length > 0) {
    raiseAccessDenied(
      deniedUpdateMessage(
        entityType,
        id,
        uncovered,
        changedFieldNames(entityType, [...invalid, ...unmovable()]),
      ),
    );
  }
}

// The given names of a write's values as allow lines name them, a to-one by its relationship - the
// twin of Hologram.Policy.changed_field_names/2.
function changedFieldNames(entityType, names) {
  const references = new Map(
    Object.entries(Model.relationships(entityType))
      .filter(([_name, relationship]) => !relationship.toMany)
      .map(([name]) => [`${name}_id`, name]),
  );

  return names.map((name) => references.get(name) ?? name);
}

function changeOperationMessage(operation) {
  return `can? with values takes :update, the name of an allow :update line, or {:update, field} / {:update, fields} - got ${Interpreter.inspect(operation)}`;
}

// What the operation answers for one specific change, three-valued - the twin of evaluate_change/5
// in Hologram.Auth.
function changeAnswer(
  entry,
  entityType,
  entity,
  operation,
  names,
  after,
  actorUserId,
) {
  if (Type.isAtom(operation) && operation.value === "update") {
    const fields = changedFieldNames(entityType, names);

    return coversChange(entry, entityType, entity, fields, after, actorUserId);
  }

  const asked = askedFields(operation);

  if (asked !== null) {
    Model.validateOperation(entityType, operation);

    const fields = asked.map((field) => field.value);

    return coversChange(entry, entityType, entity, fields, after, actorUserId);
  }

  if (isImproperFieldsAsk(operation)) {
    Model.validateOperation(entityType, operation);
  }

  if (!Type.isAtom(operation)) {
    Interpreter.raiseMisuseError(changeOperationMessage(operation));
  }

  Model.validateOperation(entityType, operation);

  if ((entry.formerUpdateNames ?? []).includes(operation.value)) {
    return false;
  }

  if (!(entry.updateNames ?? []).includes(operation.value)) {
    Interpreter.raiseMisuseError(changeOperationMessage(operation));
  }

  const rules = policyRules(entry, operation.value);

  return changeRulesAnswer(
    someHolds(rules, (rule) =>
      ruleHolds(rule, entityType, entity, actorUserId, after),
    ),
    rules,
    entry,
    entityType,
    entity,
    [operation.value],
    actorUserId,
  );
}

// The struct's fields no longer hold the stored values once it carries recorded changes, and those
// are what a rule's bare names read.
function refuseRecordedChanges(entityType, entity) {
  const metadata = entity.data[Type.encodeMapKey(Type.atom("__meta__"))]?.[1];

  const clean =
    metadata !== undefined &&
    Type.isMap(metadata) &&
    ["attribute_ops", "relationship_ops"].every((name) => {
      const ops = metadata.data[Type.encodeMapKey(Type.atom(name))]?.[1];

      return (
        ops !== undefined &&
        Type.isMap(ops) &&
        Object.keys(ops.data).length === 0
      );
    });

  if (!clean) {
    const id =
      entity.data[Type.encodeMapKey(Type.atom("id"))]?.[1] ?? Type.nil();

    Interpreter.raiseMisuseError(
      `can? with values asks about a row as stored - ${entityType} ${Interpreter.inspect(id)} carries recorded changes, so its fields no longer hold the stored values`,
    );
  }
}

// The pairs of a change's values, the last of a repeated name winning as a map's does, refused in the
// server's words unless they're a keyword list or a map that isn't a struct.
function changePairs(values) {
  const listed =
    Type.isProperList(values) && Type.isKeywordList(values)
      ? values.data.map((pair) => pair.data)
      : Type.isMap(values)
        ? Object.values(values.data)
        : null;

  const pairs = listed && [
    ...new Map(
      listed.map((pair) => [Type.encodeMapKey(pair[0]), pair]),
    ).values(),
  ];

  const struct = pairs?.some(
    ([name, value]) =>
      Type.isAtom(name) && name.value === "__struct__" && Type.isAtom(value),
  );

  if (pairs === null || struct) {
    Interpreter.raiseMisuseError(
      `can? takes the values of a change as a keyword list or a map - got ${Interpreter.inspect(values)}`,
    );
  }

  return pairs;
}

// The values of a change by name, refused in the server's words unless they name what an update can
// set.
function changeValues(entityType, pairs) {
  validateChangeNames(entityType, pairs);

  return new Map(pairs.map(([name, value]) => [name.value, value]));
}

// What can? with values answers for a type the build carries no entry for, which holds no line: no,
// once the operation and the values are ones the server wouldn't refuse.
function refuseChangeWithoutEntry(entityType, operation, pairs) {
  const nonAtomPairs = pairs.filter(([name]) => !Type.isAtom(name));

  if (pairs.length === 0 || nonAtomPairs.length > 0) {
    validateChangeNames(entityType, nonAtomPairs);
  }

  if (Type.isAtom(operation) && operation.value === "update") {
    return;
  }

  const asked = askedFields(operation);

  const notAtom = asked?.find((field) => !Type.isAtom(field));

  if (notAtom !== undefined) {
    Interpreter.raiseMisuseError(
      `unknown field ${Interpreter.inspect(notAtom)} in ${Interpreter.inspect(operation)} for ${entityType} - a field is named by an atom`,
    );
  }

  if (asked !== null && asked.length > 0) {
    return;
  }

  if (asked !== null || isImproperFieldsAsk(operation)) {
    Model.validateOperation(entityType, operation);
  }

  if (Type.isAtom(operation)) {
    Model.validateOperation(entityType, operation);
  }

  Interpreter.raiseMisuseError(changeOperationMessage(operation));
}

// An {:update, fields} ask whose list is improper, which the server refuses as an unknown operation.
function isImproperFieldsAsk(operation) {
  return (
    Type.isTuple(operation) &&
    operation.data.length === 2 &&
    Type.isAtom(operation.data[0]) &&
    operation.data[0].value === "update" &&
    Type.isList(operation.data[1])
  );
}

// The references among the given values naming a row this client doesn't hold, other than the one
// the entity already holds, which the store vouches for.
function unheldReferences(entityType, entity, changes) {
  return Object.entries(Model.relationships(entityType))
    .filter(([_name, relationship]) => !relationship.toMany)
    .flatMap(([name, relationship]) => {
      const field = `${name}_id`;

      if (!changes.has(field)) {
        return [];
      }

      const id = Model.unbox(changes.get(field), "uuid");

      return id === null ||
        id === storedValue(entityType, entity, field) ||
        LocalDatabase.getRow(relationship.type, id) !== null
        ? []
        : [field];
    });
}

// Whether a temporal value is in a calendar other than ISO, which the server asks about the value
// and this client can't, so neither its validation nor its comparison speaks for the server's.
function hasOtherCalendar(value, type) {
  const struct = {date: "Date", datetime: "DateTime", time: "Time"}[type];

  if (struct === undefined || !Type.isStruct(value, struct)) {
    return false;
  }

  const calendar = value.data[Type.encodeMapKey(Type.atom("calendar"))]?.[1];

  return (
    calendar !== undefined &&
    !Interpreter.isStrictlyEqual(calendar, Type.alias("Calendar.ISO"))
  );
}

// Whether a date's year is past what a number holds exactly, so the browser's validator can refuse
// a date the server accepts.
function hasInexactYear(value, type) {
  const struct = {date: "Date", datetime: "DateTime"}[type];

  if (struct === undefined || !Type.isStruct(value, struct)) {
    return false;
  }

  const year = value.data[Type.encodeMapKey(Type.atom("year"))]?.[1];

  return (
    year !== undefined &&
    Type.isInteger(year) &&
    !Number.isSafeInteger(Number(year.value))
  );
}

// Whether a validation reason is one both tiers give alike. A format goes through two regex engines,
// and a bound on a date past what a JavaScript Date holds compares nothing here.
function isSureRefusal(reason) {
  const kind = Type.isTuple(reason) ? reason.data[0].value : reason.value;

  return !["format", "max", "min"].includes(kind);
}

// Whether this client can't judge the given value of the attribute as the server does: a date past
// what a JavaScript Date holds, or a non-ASCII value of an attribute with a format, on which the
// browser's regex engine can answer differently.
function isUnjudgedValue(entityType, name, value) {
  const {attributes, constraints} = Model.entry(entityType);

  if (isFarDate(value, attributes[name])) {
    return true;
  }

  return (
    Object.hasOwn(constraints?.[name] ?? {}, "format") &&
    Bitstring.isText(value) &&
    [...Bitstring.toText(value)].some((char) => char.codePointAt(0) > 127)
  );
}

// The scope a rule reads the row after a change through: the entity with the given values on it,
// bar one failing its declaration, which can't be on the row and so reads as stored.
function rowAfterChange(entityType, entity, changes) {
  const validation = Elixir_Hologram_Entity["validate/2"](
    Type.alias(entityType),
    Type.map([...changes].map(([name, value]) => [Type.atom(name), value])),
  );

  const refusals = Type.isAtom(validation)
    ? []
    : Object.values(validation.data[1].data);

  const invalid = new Set(refusals.map(([name]) => name.value));

  // A value refused for a reason both tiers judge alike reads as stored on both.
  const surelyInvalid = new Set(
    refusals
      .filter(([_name, reasons]) => reasons.data.some(isSureRefusal))
      .map(([name]) => name.value),
  );

  const valid = new Map([...changes].filter(([name]) => !invalid.has(name)));

  const data = {...entity.data};

  for (const [name, value] of valid) {
    const key = Type.atom(name);

    data[Type.encodeMapKey(key)] = [key, value];
  }

  const boxed = {...entity, data};
  const {attributes} = Model.entry(entityType);

  const change = {
    builtRow: null,
    entity: boxed,
    id: storedValue(entityType, entity, "id"),
    type: entityType,
    undecided: new Set([
      ...WRITE_TIMESTAMPS,
      ...unheldReferences(entityType, entity, valid),
      ...[...changes]
        .filter(
          ([name, value]) =>
            hasOtherCalendar(value, attributes[name]) ||
            hasInexactYear(value, attributes[name]) ||
            (!surelyInvalid.has(name) &&
              isUnjudgedValue(entityType, name, value)),
        )
        .map(([name]) => name),
    ]),
  };

  afterChanges.set(boxed, change);

  return {entity: boxed, entityType};
}

// The key an entity operation is baked under: an atom as its name, a per-role grant lifecycle
// operation as the two names joined by a colon. Policy.operation_key/1 is the twin on the server
// (rendered by Compiler.render_policy/2), and the two must agree - a field of an update is keyed
// the same way, in coversFields.
//
// A grant lifecycle tuple naming a LIST of roles is refused: the DSL takes one as sugar for a line
// per role, so no rule is keyed by it - and can? asks about one role at a time.
function operationKey(operation) {
  if (Type.isAtom(operation)) {
    return operation.value;
  }

  if (Type.isTuple(operation) && operation.data.length === 2) {
    const [name, role] = operation.data;

    if (Type.isAtom(name) && Type.isAtom(role)) {
      return `${name.value}:${role.value}`;
    }

    if (
      Type.isAtom(name) &&
      ["grant_role", "revoke_role"].includes(name.value) &&
      Type.isList(role)
    ) {
      Interpreter.raiseMisuseError(
        `can? asks about one role - ${Interpreter.inspect(operation)} names several`,
      );
    }
  }

  Interpreter.raiseMisuseError(
    "can? takes an operation atom, a {:grant_role, role} / {:revoke_role, role} tuple or an {:update, field} / {:update, fields} tuple",
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
  //
  // :global in place of the entity is the global form, which is trusted-only. Options never go
  // here, so a list is refused as it is on the server.
  "grant_role/3": (userOrId, role, entity) => {
    if (isGlobalScope(entity)) {
      return Elixir_Hologram_Auth["grant_role/2"](userOrId, role);
    }

    if (Type.isList(entity)) {
      Interpreter.raiseMisuseError(
        misplacedOptionsMessage("grant_role", entity),
      );
    }

    const userId = validateUserId(userOrId);
    const {entityType, entityId} = entityReference(entity, "granted");
    const roleName = validateDeclaredRole(entityType, role);
    const actorUserId = LocalDatabase.actorEntityId;

    if (actorUserId === null) {
      raiseAccessDenied(signedInWriteMessage("granted"));
    }

    const gateResource = Type.struct(entityType, [
      [Type.atom("id"), Type.bitstring(entityId)],
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
          entityId,
          actorUserId,
          roleName,
          "grant_role",
        ),
      );
    }

    const id = grantId(userId, entityType, entityId, roleName);

    if (LocalDatabase.getRow(GRANT_TYPE, id) !== null) {
      return Type.atom("ok");
    }

    const batch = currentBatch("grant_role");

    batch.append(
      grantEntry(userId, entityType, entityId, roleName, actorUserId),
    );

    return Type.atom("ok");
  },

  // Hologram.Auth.has_role?/2 as a browser runs it: the same refusal for a module that is no global
  // role, then the global grant rows this client holds - a user's own always travel to it. The
  // modules carrying the role come baked with the build, expanded there as the rules are.
  "has_role?/2": (userOrId, role) => {
    const roles = expandedGlobalRoles(role);
    const userId = unboxActorUserId(userOrId);

    if (userId === null) {
      return Type.boolean(false);
    }

    return Type.boolean(grantExists(grantRows(), userId, roles, null, [null]));
  },

  // Hologram.Auth.has_role?/3 as a browser runs it: the role is validated against the type's baked
  // roles with the server's sentence, expanded through the baked expansion, and looked for among
  // the grant rows this client holds - on the row and type-wide for a struct, type-wide alone for
  // an entity type module. The rows are read through the overlay, so a grant or revocation an
  // action made answers here before it is sent.
  "has_role?/3": (userOrId, role, entity) => {
    const entityType = roleScopeType(entity);
    const roleName = validateDeclaredRole(entityType, role);
    const entityIds = roleScopeIds(entityType, entity);
    const roles =
      globalThis.Hologram.sync.model[entityType].expandedRoles[roleName];
    const userId = unboxActorUserId(userOrId);

    if (userId === null) {
      return Type.boolean(false);
    }

    return Type.boolean(
      grantExists(grantRows(), userId, roles, entityType, entityIds),
    );
  },

  // Ported to refuse the claim, and otherwise the plain verb.
  "grant_role/4": (userOrId, role, entity, opts) => {
    refuseTrustClaim(opts, "grant_role");

    return Elixir_Hologram_Auth["grant_role/3"](userOrId, role, entity);
  },

  "revoke_role/2": (_userOrId, _role) => {
    raiseAccessDenied(trustedWriteMessage("global", "revoked"));
  },

  // Hologram.Auth.revoke_role/3 as a browser runs it: the same arguments, the same gate in the
  // same place - one's own row needs no permission, anyone else's is the per-role question - and
  // then, where the server deletes whatever it finds, the browser appends a delete of the row it
  // holds, carrying the row's revisions as what it was based on. The fold hides the row at once.
  // A row the client does not hold answers :ok and writes nothing, as the server's own no-op does:
  // whoever may revoke a grant may read it, and everyone reads their own, so "not held" is "not
  // there" for anyone the gate lets through. The server replays the gate when the batch lands.
  //
  // :global and a list in place of the entity are handled as in grant_role/3.
  "revoke_role/3": (userOrId, role, entity) => {
    if (isGlobalScope(entity)) {
      return Elixir_Hologram_Auth["revoke_role/2"](userOrId, role);
    }

    if (Type.isList(entity)) {
      Interpreter.raiseMisuseError(
        misplacedOptionsMessage("revoke_role", entity),
      );
    }

    const userId = validateUserId(userOrId);
    const {entityType, entityId} = entityReference(entity, "revoked");
    const roleName = validateDeclaredRole(entityType, role);
    const actorUserId = LocalDatabase.actorEntityId;

    if (actorUserId === null) {
      raiseAccessDenied(signedInWriteMessage("revoked"));
    }

    if (actorUserId !== userId) {
      const gateResource = Type.struct(entityType, [
        [Type.atom("id"), Type.bitstring(entityId)],
      ]);

      const allowed = Elixir_Hologram_Auth["can?/3"](
        Type.bitstring(actorUserId),
        Type.tuple([Type.atom("revoke_role"), role]),
        gateResource,
      );

      if (!Type.isTrue(allowed)) {
        raiseAccessDenied(
          unqualifiedRoleMessage(
            entityType,
            entityId,
            actorUserId,
            roleName,
            "revoke_role",
          ),
        );
      }
    }

    const held = LocalDatabase.getRow(
      GRANT_TYPE,
      deriveGrantId(userId, entityType, entityId, roleName),
    );

    if (held === null) {
      return Type.atom("ok");
    }

    const batch = currentBatch("revoke_role");

    // The delete carries the grant it revokes: the server's gate is asked about the grant the
    // write states, so a row it no longer holds is refused or confirmed the same as one it does.
    batch.append({
      based_on: {...(held["$revisions"] ?? {})},
      data: {
        entity_id: entityId,
        entity_type: entityType,
        role: roleName,
        user_id: userId,
      },
      id: held.id,
      op: "delete",
      stamp: Clock.stamp(),
      type: GRANT_TYPE,
    });

    return Type.atom("ok");
  },

  // Ported to refuse the claim, and otherwise the plain verb.
  "revoke_role/4": (userOrId, role, entity, opts) => {
    refuseTrustClaim(opts, "revoke_role");

    return Elixir_Hologram_Auth["revoke_role/3"](userOrId, role, entity);
  },

  "can?/3": (userOrId, operation, entity) => {
    const entityType = Interpreter.moduleExName(
      entity.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
    );

    const actorUserId = unboxActorUserId(userOrId);
    const fields = askedFields(operation);
    const operationName = fields === null ? operationKey(operation) : null;

    // An entry absent from a build is a type that declares NO policy - the build ships an entry
    // for every policied type, whether a page reaches it or not, precisely so this read can mean
    // that. And a policy-less type is denied by the server's own default, so no is not a fallback
    // here: it is the server's answer.
    const entry = globalThis.Hologram.sync?.model?.[entityType];

    // The build also ships an entry for every type declaring a role, so a type with no entry
    // carries no allow line name and no role either. The server's refusals of an unknown name,
    // role or tuple, or of an update list naming no field, are made here without the entry. A
    // field is the one thing the entry is needed to tell apart from a typo, so an update naming
    // one answers no.
    if (!entry) {
      if (fields === null || fields.length === 0) {
        Model.validateOperation(entityType, operation);
      }

      return Type.boolean(false);
    }

    // The server's own refusal for an atom that is neither a framework operation nor a name a line
    // of the type carries - a typo or a renamed name fails here, at the line that asks, rather
    // than answering no as if the rules had been consulted.
    Model.validateOperation(entityType, operation);

    if (fields !== null) {
      return Type.boolean(
        coversFields(entry, entityType, entity, fields, actorUserId),
      );
    }

    const rules = policyRules(entry, operationName);

    // An operation with no rules grants nothing, which is what makes the default deny. A rule grants
    // only on a definite yes.
    return Type.boolean(
      operationHolds(
        entry,
        entityType,
        entity,
        operationName,
        rules,
        actorUserId,
      ) === true,
    );
  },

  // Whether the user may make one specific change - the twin of Hologram.Auth.can?/4. No is what an
  // answer neither the held rows nor a verdict can give comes to.
  "can?/4": (userOrId, operation, entity, values) => {
    const entityType = Interpreter.moduleExName(
      entity.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
    );

    refuseRecordedChanges(entityType, entity);

    const pairs = changePairs(values);

    if (entityType === GRANT_TYPE) {
      Interpreter.raiseMisuseError(GRANT_UPDATE_MESSAGE);
    }

    const model = globalThis.Hologram.sync?.model ?? {};
    const entry = Object.hasOwn(model, entityType) ? model[entityType] : null;

    if (!entry) {
      refuseChangeWithoutEntry(entityType, operation, pairs);

      return Type.boolean(false);
    }

    const changes = changeValues(entityType, pairs);
    const after = rowAfterChange(entityType, entity, changes);

    return Type.boolean(
      changeAnswer(
        entry,
        entityType,
        entity,
        operation,
        [...changes.keys()],
        after,
        unboxActorUserId(userOrId),
      ) === true,
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
// A grant's id is a function of the grant - this user, this entity, this role - so a grant made
// here and the same grant made anywhere else are one row, and nothing about it is reconciled
// after the fact. UUIDv5 (RFC 9562): SHA-1 over the namespace and the name, the name being the
// four parts joined with a newline, each spelled as the store spells it - ids as they are, the
// entity type's label, a role name or a global role module without its "Elixir." prefix, and
// "" for a part that is null. Hashed as UTF-8, which is what the server hashes.
export function deriveGrantId(userId, entityType, entityId, role) {
  const name = [userId, entityType, entityId, role]
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

// The batch entry a grant is written as: the store's five columns, and the id derived from four
// of them, which is what makes this row and the server's insert of the same grant one row. The
// granter and the holder are apart, because a grant is written for somebody as often as for
// oneself.
export function grantEntry(
  userId,
  entityType,
  entityId,
  roleName,
  actorUserId,
) {
  return {
    data: {
      entity_id: entityId,
      entity_type: entityType,
      granted_by_id: actorUserId,
      role: roleName,
      user_id: userId,
    },
    id: grantId(userId, entityType, entityId, roleName),
    op: "create",
    stamp: Clock.stamp(),
    type: GRANT_TYPE,
  };
}

// The id the store files a grant under, named from the type itself - a fact about the grant
// rather than a value minted for it, so it can be asked for before anything is built.
export function grantId(userId, entityType, entityId, roleName) {
  return deriveGrantId(userId, entityType, entityId, roleName);
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

// The refusal that teaches: which roles the acting user holds that reach the entity, what those
// may grant (or revoke) there, and the line that would cover it if the omission was not intended.
export function unqualifiedRoleMessage(
  entityType,
  entityId,
  actorUserId,
  role,
  operation,
) {
  const verb = operation === "grant_role" ? "grant" : "revoke";
  const entity = `${entityType} "${entityId}"`;
  const held = heldRoleNames(actorUserId, entityType, entityId);

  if (held.length === 0) {
    return `the acting user holds no role on ${entity} that may ${verb} ${inspectRole(role)}`;
  }

  const covered = coveredRoleNames(
    entityType,
    entityId,
    actorUserId,
    operation,
  );
  const holder = held.length === 1 ? inspectRole(held[0]) : inspectRoles(held);

  return (
    `the acting user holds ${joinRoleNames(held)} on ${entity}, ` +
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
  return `${scope} roles are ${verb} only by server code claiming trust: true or running outside a session`;
}

function isGlobalScope(entity) {
  return Type.isAtom(entity) && entity.value === "global";
}

// IMPORTANT!
// A hand port of Hologram.Auth's sentence for options in the entity's place. Always update both
// tiers together.
function misplacedOptionsMessage(verb, entity) {
  return `${verb} takes an entity, an entity type or :global as its third argument, got: ${Interpreter.inspect(entity)} - options go fourth`;
}

// The options a grant verb takes on the server. Its one option claims the server's authority, which
// a client can't, so it raises what trust/1 raises here. No options is the plain verb.
function refuseTrustClaim(opts, verb) {
  if (Type.isList(opts) && opts.data.length === 0) {
    return;
  }

  if (Type.isList(opts) && Type.isKeywordList(opts) && opts.data.length === 1) {
    const [key, value] = opts.data[0].data;

    if (key.value === "trust" && Type.isTrue(value)) {
      Interpreter.raiseMisuseError(
        "trust is the server's authority - a client cannot claim it",
      );
    }
  }

  Interpreter.raiseMisuseError(
    `${verb} takes trust: true as its only option, got: ${Interpreter.inspect(opts)}`,
  );
}

function raiseAccessDenied(message) {
  Interpreter.raiseError("Hologram.AccessDeniedError", message);
}

// The struct or entity type module a grant names as its scope, taken apart the way the server
// takes it apart: a struct gives the type and a validated id, a module is a type-wide grant -
// trusted-only, so refused here outright.
function entityReference(entity, verb) {
  if (Type.isAlias(entity)) {
    raiseAccessDenied(trustedWriteMessage("type-wide", verb));
  }

  const entityType = Interpreter.moduleExName(
    entity.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
  );

  const idEntry = entity.data[Type.encodeMapKey(Type.atom("id"))];
  const entityId = validateId(idEntry ? idEntry[1] : Type.nil(), "entity");

  return {entityType, entityId};
}

// IMPORTANT!
// The two refusals below are hand ports of Hologram.Auth's unknown global role sentences. The one
// listing the defined roles is pinned string for string by the has_role?/2 tests on both tiers.
// The one for a build defining no global role is pinned here only, because the server's test
// model always defines some. Always update both tiers together.
//
// The modules carrying the given global role, from the baked map whose keys are the defined global
// roles - so a module that is none is refused here, with the server's sentence. The keys are module
// names without their "Elixir." prefix, which sorts them the way the server sorts the modules.
function expandedGlobalRoles(role) {
  const expanded = globalThis.Hologram.sync?.expandedRoles ?? {};
  const label = Type.isAlias(role) ? Interpreter.moduleExName(role) : null;

  if (label !== null && Object.hasOwn(expanded, label)) {
    return expanded[label];
  }

  const defined = Object.keys(expanded).sort();

  if (defined.length === 0) {
    Interpreter.raiseMisuseError(
      `unknown global role ${Interpreter.inspect(role)} - no module is defined with use Hologram.Role`,
    );
  }

  Interpreter.raiseMisuseError(
    `unknown global role ${Interpreter.inspect(role)} - defined global roles are: ${defined.join(", ")}`,
  );
}

// The entity ids a role check matches grant rows by: a struct's own row and the type-wide grant
// beside it - the scope a rule naming the type's own role reads, so a struct with no id matches the
// type-wide grant alone - or the type-wide grant alone for an entity type module. Read only after
// the role is validated, which is what guarantees the type's entry is baked.
function roleScopeIds(entityType, entity) {
  if (Type.isAlias(entity)) {
    return [null];
  }

  return [entityValue(entityType, entity, "id"), null];
}

// The entity type a role check asks about: the struct's own, or the entity type module itself.
function roleScopeType(entity) {
  if (Type.isAlias(entity)) {
    return Interpreter.moduleExName(entity);
  }

  return Interpreter.moduleExName(
    entity.data[Type.encodeMapKey(Type.atom("__struct__"))][1],
  );
}

function validateDeclaredRole(entityType, role) {
  const declared = globalThis.Hologram.sync?.model?.[entityType]?.roles ?? [];
  const roleName = Type.isAtom(role) ? role.value : null;

  if (roleName === null || !declared.includes(roleName)) {
    Interpreter.raiseMisuseError(
      `unknown role ${Interpreter.inspect(role)} for ${entityType} - declared roles are: ${declared.map((name) => `:${name}`).join(", ")}`,
    );
  }

  return roleName;
}

// An id the server would accept: the canonical lowercase spelling, and nothing else - the
// validator's own regex, since the two tiers compare ids as strings.
function validateId(term, subject) {
  const value = Type.isBitstring(term) ? Bitstring.toText(term) : null;

  if (value === null || !CANONICAL_ID.test(value)) {
    Interpreter.raiseMisuseError(
      `invalid ${subject} id ${Interpreter.inspect(term)} - entity ids are canonical lowercase 8-4-4-4-12 UUID strings`,
    );
  }

  return value;
}

// A map with no id is no user, and is refused as itself, the way the server refuses it - in the same
// words as long as the two inspect it alike.
function validateUserId(userOrId) {
  const entry = Type.isMap(userOrId)
    ? userOrId.data[Type.encodeMapKey(Type.atom("id"))]
    : null;

  const term = entry ? entry[1] : userOrId;

  return validateId(term, "user");
}

function coveredDescription(covered, role) {
  if (covered.length === 0) {
    return `no role there, ${inspectRole(role)} included`;
  }

  return `${joinRoleNames(covered)} but not ${inspectRole(role)}`;
}

// The declared roles the acting user may grant (or revoke) on the entity - the same question
// the gate asked, once per role.
function coveredRoleNames(entityType, entityId, actorUserId, operation) {
  const entry = globalThis.Hologram.sync?.model?.[entityType];
  const entity = Type.struct(entityType, [
    [Type.atom("id"), Type.bitstring(entityId)],
  ]);

  return (entry?.roles ?? []).filter((name) =>
    Type.isTrue(
      Elixir_Hologram_Auth["can?/3"](
        Type.bitstring(actorUserId),
        Type.tuple([Type.atom(operation), Type.atom(name)]),
        entity,
      ),
    ),
  );
}

// The roles the acting user holds that reach the entity, as the gate reads them: on the row
// itself or on its whole type, and the global roles held app-wide. Own names first, then role
// modules, each alphabetical - the order the server sorts them in.
function heldRoleNames(actorUserId, entityType, entityId) {
  return grantRows()
    .filter(
      (row) =>
        row.user_id === actorUserId &&
        ((row.entity_type === entityType &&
          (row.entity_id === entityId || row.entity_id === null)) ||
          (row.entity_type === null && row.entity_id === null)),
    )
    .map((row) => row.role)
    .sort(
      (left, right) =>
        Number(isRoleModule(left)) - Number(isRoleModule(right)) ||
        StringOrder.compare(left, right),
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
