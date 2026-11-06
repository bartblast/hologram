"use strict";

import Bitstring from "../../bitstring.mjs";
import Clock from "../../clock.mjs";
import {currentBatch} from "./db.mjs";
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
// server reads them with SELECT EXISTS, this reads them from the pot.
//
// Both halves of what it needs are compile-time facts the bundle carries: the rules in each
// type's model entry, and the name the grant store spells that type by. The rows are ordinary
// synced rows, and a page that checks permissions hands over the ones its own checks asked
// about, so the first render answers what the server answered.
const GRANT_TYPE = "Hologram.Auth.RoleGrant";

// What a condition holds as when this client cannot tell: a related row it would read is one it
// does not hold - the server reads the row as stored, so taking it for a missing one could grant
// what the server refuses (`project.status != :archived` over a project nobody synced). A rule
// grants only on a definite yes, and `and` and `or` keep what they can still decide: false and
// unknown are false, true or unknown is true.
const UNKNOWN = Symbol("unknown");

// The sixteen bytes Hologram.Auth.RoleGrant derives every grant id under - drawn once, on
// 2026-09-02, and fixed: change them and every grant in every store is renamed.
const GRANT_ID_NAMESPACE = Uint8Array.from([
  0x8b, 0x2f, 0x65, 0x0d, 0xd0, 0xcf, 0x15, 0x26, 0xdf, 0xec, 0x20, 0x9a, 0x31,
  0xd9, 0xf6, 0x6c,
]);

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

  if (typeof left === "string" && typeof right === "string") {
    return StringOrder.compare(left, right) < 0 ? "lt" : "gt";
  }

  return left < right ? "lt" : left > right ? "gt" : "eq";
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

function clauseHolds(entityType, entity, clause, actorUserId, outer) {
  if (Array.isArray(clause)) {
    return predicateHolds(entityType, entity, clause, actorUserId, outer);
  }

  if (Object.hasOwn(clause, "or")) {
    return alternativesHold(entityType, entity, clause.or, actorUserId, outer);
  }

  return quantifierHolds(entityType, entity, clause, actorUserId, outer);
}

// The row a chain of to-one relationships leads to, with its type, null at the first reference
// that is empty, or UNKNOWN at the first one naming a row this client does not hold. The first
// reference is read off the boxed entity, the later ones off the plain rows before them.
function chainRow(entityType, entity, relationshipNames) {
  const [relationshipName, ...laterNames] = relationshipNames;
  const targetId = entityValue(entityType, entity, `${relationshipName}_id`);

  return linkedRow(entityType, targetId, relationshipName, laterNames);
}

// The chain followed from a plain held row, as chainRow/3 follows it from a boxed entity.
function chainRowFrom(entityType, row, relationshipNames) {
  if (relationshipNames.length === 0) {
    return {row, type: entityType};
  }

  const [relationshipName, ...laterNames] = relationshipNames;
  const targetId = row[`${relationshipName}_id`] ?? null;

  return linkedRow(entityType, targetId, relationshipName, laterNames);
}

// The id the last reference of a chain holds, read off the row the relationships before it lead
// to, or null when they lead nowhere.
function chainTargetId(entityType, entity, relationshipNames) {
  const referenceField = `${relationshipNames.at(-1)}_id`;

  if (relationshipNames.length === 1) {
    return entityValue(entityType, entity, referenceField);
  }

  const end = chainRow(entityType, entity, relationshipNames.slice(0, -1));

  return end === null || end === UNKNOWN
    ? null
    : (end.row[referenceField] ?? null);
}

// The type a name is declared with - an attribute's, or a derived field's holding a value - or
// null for a reference field, which carries an entity id.
function declaredType(entityType, name) {
  const derived = Model.derivedField(entityType, name);

  return Model.entry(entityType).attributes[name] ?? derived?.type ?? null;
}

// The value a rule compares against, read off the boxed entity in the spelling the rules were
// baked in - the rules travel wire-spelled, so what they are compared with must be too. A derived
// field is computed from its definition over the row the entity holds, the way the query kernel
// computes it, whatever the struct carries under its name - the reference computes it too.
function entityValue(entityType, entity, name) {
  const derived = Model.derivedField(entityType, name);

  if (derived) {
    return evaluatedDefinition(entityType, entity, derived.definition);
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
// the server's verdict answers a quantifier whose condition reads one.
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
// boxed entity of it.
function fieldValue(entityType, row, name) {
  const derived = Model.derivedField(entityType, name);

  if (derived === null) {
    return row[name] ?? null;
  }

  return evaluatedDefinition(
    entityType,
    Model.box(entityType, row),
    derived.definition,
  );
}

// The row one to-one relationship's reference names, then the chain after it from there - null for
// an empty reference, UNKNOWN for a row this client does not hold.
function linkedRow(entityType, targetId, relationshipName, laterNames) {
  if (targetId === null) {
    return null;
  }

  const type = Model.relationships(entityType)[relationshipName].type;
  const row = LocalDatabase.getRow(type, targetId);

  return row === null ? UNKNOWN : chainRowFrom(type, row, laterNames);
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

    return namesActor(clause.filter);
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
    declaredType(end.type, end.name) === "string",
  );
}

// What a rule's operand stands for on this row: the acting user, another attribute of the row read
// off it or of the row a path leads to, or the value itself. An attribute operand compares by the
// predicate's attribute's ranks, since two enums compare only when they declare the same list.
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
// themselves, or a quantifier object - every clause has to hold, a disjunction holds when one of
// its alternatives does. False when a clause does not hold, UNKNOWN when none fails but one may,
// true when all hold. The outer rows are the rows above the entity inside a quantifier, nearest
// first, each with its type - none at the top of a rule.
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
// client does not hold may decide it - unless the quantifier is one the server sends its verdict
// on, which then answers. Over a derived set the held rows decide nothing. A none or an all asking
// about a visitor asks about nobody, which grants nothing.
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
    return Object.hasOwn(clause, "verdict")
      ? verdictHolds(entityType, entity, clause, actorUserId)
      : UNKNOWN;
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
      Model.box(relatedType, row),
      clause.filter,
      actorUserId,
      innerOuter,
    ),
  );

  const held = heldAnswer(clause.quantifier, answers);

  return held === UNKNOWN && Object.hasOwn(clause, "verdict")
    ? verdictHolds(entityType, entity, clause, actorUserId)
    : held;
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
    // reference holds.
    case "rel": {
      const [_kind, relationshipNames, targetType, roles] = reference;
      const targetId = chainTargetId(entityType, entity, relationshipNames);

      return (
        targetId !== null &&
        grantExists(rows, actorUserId, roles, targetType, [targetId])
      );
    }

    // The grant store's own rule: a role held on the entity the grant row names.
    case "named": {
      const [_kind, targetType, roles] = reference;
      const rowEntityId = entityValue(entityType, entity, "entity_id");

      return (
        rowEntityId !== null &&
        grantExists(rows, actorUserId, roles, targetType, [rowEntityId])
      );
    }

    default: {
      const [_kind, targetType, roles] = reference;

      return grantExists(rows, actorUserId, roles, targetType, [null]);
    }
  }
}

// A visitor's rules are evaluated rather than skipped, so a disjunction can still answer through
// an alternative that names nobody. A role is held by somebody, so a visitor holds none, and the
// grant rows are not read. A delegating rule is evaluated as any other, because the type it
// delegates to answers its own actor-referencing rules the same way.
function ruleMatches(rule, entityType, entity, actorUserId) {
  if (
    predicatesHold(entityType, entity, rule.predicates, actorUserId) !== true
  ) {
    return false;
  }

  if (
    rule.to !== null &&
    (actorUserId === null ||
      !rule.to.some((reference) =>
        referenceHolds(reference, entityType, entity, actorUserId),
      ))
  ) {
    return false;
  }

  return rule.via === null || viaHolds(rule, entityType, entity, actorUserId);
}

// The row a name is read on and the name itself: the entity's own for a name of its row, and that
// row's for a name of a row above.
function scopedName(entityType, entity, outer, name) {
  if (!isOuterName(name)) {
    return {entity, entityType, name};
  }

  return {...outer[name.outer - 1], name: name.name};
}

// Whether the boxed entity holds what the given base row does in every stored field.
function storedAsBase(entityType, entity, row) {
  const names = [
    ...Object.keys(Model.entry(entityType).attributes),
    ...Object.keys(referenceRow(entityType, entity)),
  ];

  return names.every(
    (name) => storedValue(entityType, entity, name) === (row[name] ?? null),
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

    type = (Model.relationships(type)[name] ?? Model.inverses(type)[name]).type;
  }

  return false;
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

// The server's verdict on a quantifier the held rows leave open, as the row's last frame carried
// it. The server works verdicts out for the session's user over the row as stored, so any other
// question is UNKNOWN: one about another user or a visitor, one about a struct whose stored fields
// differ from the row's - changed in an action and not written yet - and one asked while a write of
// this client's that the server has not answered names a type the quantifier reads, since that
// write may have moved the answer. So is one about a row that came with no verdict.
//
// An answer can settle a batch before the frame carrying its round arrives, and between the two
// the verdict predates the write again. The window closes itself: a write moving a verdict re-runs
// the windows over the row, whose frame brings the new one, and a write that moves none sends
// none, since the verdict held stands. Held rows still refute it in between.
function verdictHolds(entityType, entity, clause, actorUserId) {
  if (actorUserId !== (LocalDatabase.actorUserId ?? null)) {
    return UNKNOWN;
  }

  if (clause.reads.some((type) => Overlay.namesType(type))) {
    return UNKNOWN;
  }

  const id = storedValue(entityType, entity, "id");
  const row = id === null ? null : LocalDatabase.baseRow(entityType, id);

  if (row === null || !storedAsBase(entityType, entity, row)) {
    return UNKNOWN;
  }

  const verdict = row.$verdicts?.[clause.verdict];

  return typeof verdict === "boolean" ? verdict : UNKNOWN;
}

// Delegation asks the RELATED entity's policy for the operation the rule names, of the row its
// chain of relationships leads to, so it needs that row and its rules. A client holds neither for
// a type its build never syncs, and cannot ask the server mid-render - so the answer is no, the
// way it is for any rule the rows do not satisfy.
function viaHolds(rule, entityType, entity, actorUserId) {
  const [operation, relationshipNames] = rule.via;
  const end = chainRow(entityType, entity, relationshipNames);

  return (
    end !== null &&
    end !== UNKNOWN &&
    grants(end.type, end.row, operation, actorUserId)
  );
}

function grants(entityType, row, operation, actorUserId) {
  const entry = globalThis.Hologram.sync?.model?.[entityType];

  if (!entry) {
    return false;
  }

  const rules = entry.policy[operation] ?? [];
  const boxed = Model.box(entityType, row);

  return rules.some((related) =>
    ruleMatches(related, entityType, boxed, actorUserId),
  );
}

// The key an entity operation is baked under: an atom as its name, a per-role grant lifecycle
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
  "grant_role/3": (userOrId, role, entity) => {
    const userId = validateUserId(userOrId);
    const {entityType, entityId} = entityReference(entity, "granted");
    const roleName = validateDeclaredRole(entityType, role);
    const actorUserId = LocalDatabase.actorUserId;

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
  "revoke_role/3": (userOrId, role, entity) => {
    const userId = validateUserId(userOrId);
    const {entityType, entityId} = entityReference(entity, "revoked");
    const roleName = validateDeclaredRole(entityType, role);
    const actorUserId = LocalDatabase.actorUserId;

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
      claim: null,
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

    // The server's own refusal for an operation nothing on the type declares - a typo or a renamed
    // operation fails here, at the line that asks, rather than answering no as if the rules had
    // been consulted.
    Model.validateOperation(entityType, operation);

    const rules = entry.policy[operationName] ?? [];

    // An operation with no rules grants nothing, which is what makes the default deny.
    return Type.boolean(
      rules.some((rule) => ruleMatches(rule, entityType, entity, actorUserId)),
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
    claim: null,
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
  return `${scope} roles are ${verb} only by trusted code running without an acting user`;
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

  if (label !== null && expanded[label]) {
    return expanded[label];
  }

  const defined = Object.keys(expanded).sort();

  if (defined.length === 0) {
    Interpreter.raiseArgumentError(
      `unknown global role ${Interpreter.inspect(role)} - no module is defined with use Hologram.Role`,
    );
  }

  Interpreter.raiseArgumentError(
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
