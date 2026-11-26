"use strict";

import Batches from "../../batches.mjs";
import Bitstring from "../../bitstring.mjs";
import Clock from "../../clock.mjs";
import Elixir_Hologram_Entity, {typeValid} from "./entity.mjs";
import Erlang from "../../erlang/erlang.mjs";
import Elixir_Hologram_Query_Stage from "./query/stage.mjs";
// A cycle - auth.mjs takes currentBatch from here - and a safe one: neither module calls the
// other while it is being evaluated, so both bindings are in place by the time a verb runs.
import {grantEntry, grantId, refuseDeniedChange} from "./auth.mjs";
import Interpreter from "../../interpreter.mjs";
import LocalDatabase from "../../local_database.mjs";
import Model from "../../model.mjs";
import QueryCheck from "../../query_check.mjs";
import QueryKernel from "../../query_kernel.mjs";
import StringOrder from "../../string_order.mjs";
import Type from "../../type.mjs";
import Utils from "../../utils.mjs";

// The data verbs, hand-written for the client the way the query stages are.
//
// One spelling on both tiers is the point: a domain helper reading and writing through these
// moves between an action, a command and a job untouched. What differs underneath is only where
// the rows are - the server reaches Postgres, and this reaches the client's own database through
// the overlay, so a read sees the writes the action made on the line before.
//
// No policy branch, where the server has one. The server filters a read by the acting user's
// policies because its database holds every row; this database holds only rows the server already
// decided this client may see, so filtering again would be asking the same question twice with
// less information. The acting user is still carried, for the predicates that NAME them.
// Thrown by rollback/1 and caught by the transaction it names. Not a boxed error: nothing outside
// this module should ever see it, and an app rescuing exceptions must not catch it by accident.
class Rollback {
  constructor(reason) {
    this.reason = reason;
  }
}

// How many transactions are open on the batch this action is writing to - what lets rollback/1
// refuse outside one. It does NOT need to name a layer: a throw is caught by the innermost
// enclosing catch, so a nested rollback stops at its own transaction by construction, where the
// server has to carry a depth because its throw travels through Postgrex's own machinery.
let openTransactions = 0;

const ROLE_GRANT = "Hologram.Auth.RoleGrant";

// A module reaches a verb as an alias, not as a struct - so its name is read off the alias rather
// than through Model.structTypeName, which answers for a boxed struct.
function aliasName(value) {
  return value.value.replace(/^Elixir\./, "");
}

// The batch an action's writes go to, or a refusal naming why there is none. A write outside an
// action has nowhere to belong: no batch would ship it and nothing would ever answer for it.
function currentBatch(verb) {
  const batch = Batches.current();

  if (batch === null) {
    Interpreter.raiseMisuseError(
      `${verb} was called outside an action - a client write happens inside an action, whose writes ship together when it returns`,
    );
  }

  // The action was suspended across a change of user, so what it reads now is the new user's. A
  // write built from that would go into the previous user's batch, and be sent as theirs. Counted
  // rather than compared, since the previous user may be back by now, after the action read
  // somebody else's rows.
  if (batch.actorUserChanges !== LocalDatabase.actorUserChanges) {
    Interpreter.raiseMisuseError(
      `${verb} was called after the signed-in user changed while this action was suspended - writes made for the new user belong in a new action`,
    );
  }

  return batch;
}

// The entity type a verb was handed a struct of, in the server's words when it was handed
// something else. The server reaches for entity.__struct__ and lets Elixir complain; naming the
// expectation is the same divergence Entity.new already carries for a non-struct argument.
function entityTypeOf(entity, verb) {
  const type = Model.structTypeName(entity);

  if (type === null || !Model.isEntityType(type)) {
    Interpreter.raiseMisuseError(
      `${verb} takes an entity struct, got: ${Interpreter.inspect(entity)}`,
    );
  }

  return type;
}

// The revisions the client last saw for the fields this write sets - what the server compares
// against to decide whether the column moved under it. A moved counter is deliberately absent: a
// delta is never merged, so there is nothing for it to be based on.
function basedOn(held, changes) {
  const revisions = held["$revisions"] ?? {};

  return Object.fromEntries(
    Object.keys(changes)
      .filter((name) => Object.hasOwn(revisions, name))
      .map((name) => [name, revisions[name]]),
  );
}

// The edges an update records, each its own entry, in one order however the stages were called -
// two clients making the same two edges send the same two writes. The order is by code point,
// since a locale's order folds the letter case two ids differ in.
function edgeEntries(entity, entityType, relationshipOps) {
  return Object.values(relationshipOps.data)
    .map(([key, op]) => {
      validateId(key.data[1]);

      return {
        id: Bitstring.toText(structField(entity, "id")),
        op: `${op.value}_relationship`,
        relationship: key.data[0].value,
        target_id: Bitstring.toText(key.data[1]),
        type: entityType,
      };
    })
    .sort((left, right) =>
      StringOrder.compare(
        `${left.relationship} ${left.target_id}`,
        `${right.relationship} ${right.target_id}`,
      ),
    );
}

// One field off a boxed struct - an entity's, or its metadata's, which is a struct too.
function structField(struct, name) {
  return struct.data[Type.encodeMapKey(Type.atom(name))][1];
}

// A server-only attribute is refused by the WRITE rather than by validation: the value is
// perfectly valid and server code may set it, so what makes it wrong is only that a browser is
// the one asking. The wire drops the name, so sending it would be malformed rather than rejected -
// which is why this is caught here, by name, before anything is built.
function refuseServerOnlyValues(entity, entityType) {
  for (const name of Model.entry(entityType).serverOnly) {
    const value = entity.data[Type.encodeMapKey(Type.atom(name))]?.[1];

    if (
      value !== undefined &&
      !Type.isNil(value) &&
      !isServerOnlySentinel(value)
    ) {
      refuseServerOnly(entityType, name);
    }
  }
}

// A create is refused for holding a VALUE the client was never shown; an update for NAMING one,
// which a put does outright. Same reason and same words either way.
function refuseServerOnly(entityType, name) {
  Interpreter.raiseMisuseError(
    `:${name} of ${entityType} is server-only - a browser cannot write it, set it in a command or a job`,
  );
}

function refuseServerOnlyNames(entityType, names) {
  const serverOnly = Model.entry(entityType).serverOnly;

  for (const name of names) {
    if (serverOnly.has(name)) {
      refuseServerOnly(entityType, name);
    }
  }
}

// What a row the client HOLDS shows for a server-only attribute - it stands for a value this
// client was never given, so it is not a value being written.
function isServerOnlySentinel(value) {
  return Model.structTypeName(value) === "Hologram.Entity.ServerOnly";
}

// A put sets a column and a move shifts it, so the wire takes them apart the way the executor
// does - and a field named by both was already refused by the stages.
function splitAttributeOps(attributeOps) {
  const changes = {};
  const deltas = {};

  for (const [name, op] of Object.values(attributeOps.data)) {
    if (op.data[0].value === "put") {
      changes[name.value] = op.data[1];
    } else {
      deltas[name.value] = op.data[1];
    }
  }

  return {changes, deltas};
}

// The row a delete names, or a refusal, because a client answers only for the rows it holds.
//
// The server answers :ok for a row that is not there, and that answer does not carry: ITS absent
// means the row is gone, where THIS one means "I do not have it" - which on a partial replica is
// also what a row never synced looks like, and what a row this user may not see looks like.
// Answering :ok would silently drop a delete of a row that is alive on the server, so the verbs
// share one rule instead: a client writes the rows it holds, and says so where they are not.
function heldRow(entityType, id, verb) {
  const held = LocalDatabase.getRow(entityType, id);

  if (held === null) {
    Interpreter.raiseMisuseError(
      `cannot ${verb} ${entityType} - no entity with id "${id}"`,
    );
  }

  return held;
}

// One bulleted line per violated declaration, sorted the way the server's are - by field, then by
// reason, over the boxed pair, so the ordering follows Elixir's own term order rather than a rule
// written twice.
//
// The :unique and :not_found lines the server also formats, and the line of a taken key, are NOT
// here: none of those reasons can be produced on this tier, because they are questions about
// OTHER rows. They arrive as the batch's rejection instead.
function refusalLines(entityType, violations, values) {
  const pairs = Object.values(violations.data).flatMap(([name, reasons]) =>
    reasons.data.map((reason) => Type.tuple([name, reason])),
  );

  return pairs
    .sort(Interpreter.compareTerms)
    .map((pair) => violationLine(entityType, values, pair))
    .join("\n");
}

function violationLine(entityType, values, pair) {
  const [name, reason] = pair.data;
  const spelled = Interpreter.inspect(name);
  const isReference = referenceFieldNames(entityType).includes(name.value);

  if (Type.isAtom(reason) && reason.value === "required") {
    return `  * ${isReference ? "reference" : "attribute"} ${spelled} is required`;
  }

  if (Type.isAtom(reason) && reason.value === "unknown") {
    return `  * ${spelled} is not a declared attribute or to-one reference`;
  }

  if (isReference) {
    return `  * reference ${spelled} must be a valid entity id, got: ${Interpreter.inspect(values[name.value] ?? Type.nil())}`;
  }

  const requirement = requirementDescription(reason);

  // A field the values do not hold has no received value to show - a move's amount is not among
  // the values.
  return name.value in values
    ? `  * attribute ${spelled} ${requirement}, got: ${Interpreter.inspect(values[name.value])}`
    : `  * attribute ${spelled} ${requirement}`;
}

function requirementDescription(reason) {
  const [key, value] = reason.data;
  const spelled = Interpreter.inspect(value);

  switch (key.value) {
    case "format":
      return `must match ${spelled}`;

    case "in":
      return `must be in ${spelled}`;

    case "length":
      return `must be exactly ${value.value} characters`;

    case "max":
      return `must be at most ${spelled}`;

    case "max_bytes":
      return `must hold at most ${value.value} bytes (the most its unique index can carry)`;

    case "max_length":
      return `must be at most ${value.value} characters`;

    case "min":
      return `must be at least ${spelled}`;

    case "min_length":
      return `must be at least ${value.value} characters`;

    case "type":
      return `must be of type ${spelled}`;

    default:
      return `must be one of ${spelled}`;
  }
}

// A to-one relationship's reference field, which a violation describes as a reference rather than
// as an attribute.
function referenceFieldNames(entityType) {
  return Object.entries(Model.entry(entityType).relationships)
    .filter(([_name, relationship]) => !relationship.toMany)
    .map(([name]) => `${name}_id`);
}

// The values a message quotes back. A create shows the struct's own fields, an update shows only
// what it was ASKED to write - an increment has none, and its line names no received value.
function structValues(entity) {
  return Object.fromEntries(
    Object.values(entity.data)
      .filter(([key]) => Type.isAtom(key))
      .map(([key, value]) => [key.value, value]),
  );
}

function putValues(entity) {
  const ops = structField(structField(entity, "__meta__"), "attribute_ops");

  return Object.fromEntries(
    Object.values(ops.data)
      .filter(([_name, op]) => op.data[0].value === "put")
      .map(([name, op]) => [name.value, op.data[1]]),
  );
}

function changeValues(changes) {
  return Object.fromEntries(
    mapNewPairs(changes).map(([name, value]) => [name.value, value]),
  );
}

// The create every creating verb shares. Job.create reaches it directly, past DB.create/1's job
// refusal, exactly as the server's reaches Writer.create past DB.create/1's.
export function createEntity(entity, entityType) {
  if (entityType === ROLE_GRANT) {
    Interpreter.raiseMisuseError(
      "role grants are written only through grant_role/revoke_role",
    );
  }

  refuseServerOnlyValues(entity, entityType);

  const batch = currentBatch("create");
  const validation = Elixir_Hologram_Entity["validate/1"](entity);

  if (!Type.isAtom(validation)) {
    return validation;
  }

  // Validation doesn't judge the id, and the server can't store a row under one that isn't an id.
  validateId(structField(entity, "id"));

  const stamp = Clock.stamp();
  const entry = writeEntry(entity, entityType, stamp);

  batch.append(entry);
  appendCreatorGrants(batch, entityType, entry.id);

  return Type.tuple([Type.atom("ok"), storedEntity(entity, entityType, stamp)]);
}

// The grants a creator takes, written beside the create that earns them. The server writes the
// same rows inside the create's own transaction (entity_operations.ex), and both tiers derive a
// grant's id from the grant itself - so these and the server's are one row, which is what lets the
// browser hold its roles from the moment it makes the row rather than from when the write lands.
//
// Nothing is asked of the rules: granted_to: :creator is a declaration being copied, not a
// permission being judged, and the applier admits such a grant without a gate for the same reason.
//
// The two answers that write nothing mirror the server's own. Nobody signed in takes no roles, and
// neither does a user id no user entity can have: creator_grants/1's nil clause. A grant the client
// already holds is not written twice, which is grant_role/3's idempotency read off the same derived
// id.
function appendCreatorGrants(batch, entityType, entityId) {
  const actorUserId = LocalDatabase.actorEntityId;

  if (actorUserId === null) {
    return;
  }

  const roleNames =
    globalThis.Hologram.sync?.model?.[entityType]?.creatorRoles ?? [];

  for (const roleName of roleNames) {
    const id = grantId(actorUserId, entityType, entityId, roleName);

    if (LocalDatabase.getRow(ROLE_GRANT, id) === null) {
      batch.append(
        grantEntry(actorUserId, entityType, entityId, roleName, actorUserId),
      );
    }
  }
}

// The lines a refused write is described by, shared with Job.create!.
export function writeRefusal(entityType, violations, values) {
  return refusalLines(entityType, violations, values);
}

export {
  currentBatch,
  isServerOnlySentinel,
  raiseWriteError,
  structValues,
  validateChangeNames,
};

function raiseWriteError(message, reason) {
  Erlang["error/1"](
    Type.struct("Hologram.WriteError", [
      [Type.atom("__exception__"), Type.boolean(true)],
      [Type.atom("message"), Type.bitstring(message)],
      [Type.atom("reason"), reason],
    ]),
  );
}

// The pairs Map.new/1 makes of the given term, which is what the server reads an update's changes
// through: a list by :maps.from_list/1, refused as that refuses it and with the last of a repeated
// key winning, a struct or any other enumerable as the list it enumerates to, and a map as it is.
function mapNewPairs(term) {
  if (
    Type.isMap(term) &&
    !Object.hasOwn(term.data, Type.encodeMapKey(Type.atom("__struct__")))
  ) {
    return Object.values(term.data);
  }

  const list = Type.isList(term) ? term : Elixir_Enum["to_list/1"](term);

  const pairs =
    Type.isProperList(list) &&
    list.data.every((item) => Type.isTuple(item) && item.data.length === 2);

  if (!pairs) {
    Interpreter.raiseBifError("badarg", "maps", "from_list", [list]);
  }

  return [
    ...new Map(
      list.data.map(({data}) => [Type.encodeMapKey(data[0]), data]),
    ).values(),
  ];
}

// A key or an id as a refusal prints it, with maps sorted so the text doesn't depend on their order.
// A map key the runtime can't sort prints as it stands.
function printedKey(key) {
  const sortMaps = Type.keywordList([
    [
      Type.atom("custom_options"),
      Type.keywordList([[Type.atom("sort_maps"), Type.boolean(true)]]),
    ],
  ]);

  try {
    return Interpreter.inspect(key, sortMaps);
  } catch {
    return Interpreter.inspect(key);
  }
}

// The type-indexed form does its own name checking rather than leaning on put_attribute's,
// because the server's does too and says something different: it names EVERY offending key at
// once, in the order of their printed text, where a stage refuses the first one it meets. A system
// attribute is among them - it is not a settable column, so it is "not something that can be
// updated" rather than "managed automatically", which is what the struct form says about the same
// name.
//
// WARNING: must match validate_changes!/4 in Hologram.DB.EntityOperations.
function validateChangeNames(entityType, pairs) {
  if (pairs.length === 0) {
    Interpreter.raiseMisuseError(
      `invalid changes for ${entityType} - at least one declared attribute or to-one relationship must be changed`,
    );
  }

  const keys = pairs
    .map(([key]) => ({key, text: printedKey(key)}))
    .sort((left, right) => StringOrder.compare(left.text, right.text));

  const atomNames = keys
    .filter(({key}) => Type.isAtom(key))
    .map(({key}) => key.value);

  // A derived field has no column - it's computed from its definition - so it is refused in the
  // words the stages refuse it, before it would be called something that can't be updated.
  const derivedName = atomNames.find((name) =>
    Object.hasOwn(Model.derived(entityType), name),
  );

  if (derivedName !== undefined) {
    Interpreter.raiseMisuseError(
      `invalid changes for ${entityType} - ${Model.derivedReadOnlyMessage(entityType, derivedName)}`,
    );
  }

  const settable = atomNames.length === 0 ? [] : settableFieldNames(entityType);

  const unknown = keys.filter(
    ({key}) => !Type.isAtom(key) || !settable.includes(key.value),
  );

  if (unknown.length > 0) {
    const listed = unknown.map(({text}) => text).join(", ");

    Interpreter.raiseMisuseError(
      `invalid changes for ${entityType} - only declared attributes and to-one relationships can be updated: ${listed}`,
    );
  }
}

// What the mapping carries as a settable column: the declared attributes and every to-one
// relationship's reference field. Server-only is IN it, the way the server's mapping is - a
// browser writing one is refused later, by name, with a reason of its own.
function settableFieldNames(entityType) {
  const entry = Model.entry(entityType);

  const declared = Object.keys(entry.attributes).filter(
    (name) => !Model.systemAttributes.includes(name),
  );

  const references = Object.entries(entry.relationships)
    .filter(([_name, relationship]) => !relationship.toMany)
    .map(([name]) => `${name}_id`);

  return [...declared, ...references];
}

// The amounts no column can hold, each under its counter's name, to be judged beside the values a
// write puts - as the server judges them, before any move lands. It can't be handed one, and a
// batch carrying one would never leave the queue.
function refusedAmounts(deltas) {
  return Object.entries(deltas)
    .filter(([_name, amount]) => !typeValid(amount, "integer"))
    .map(([name, amount]) => [Type.atom(name), amount]);
}

// Judges where the moves would land from the value this client holds. That value can be out of
// date, so the answer is never grounds for refusing a write: only the server judges a move, on
// what its statement returns.
function validateMoves(entityType, held, deltas) {
  const moved = Object.entries(deltas).map(([name, amount]) => [
    Type.atom(name),
    Type.integer(BigInt(held[name]) + amount.value),
  ]);

  return moved.length === 0
    ? Type.atom("ok")
    : Elixir_Hologram_Entity["validate/2"](
        Type.alias(entityType),
        Type.map(moved),
      );
}

// The counters whose amount no column holds, or whose move lands on a value failing its declaration.
// One this client holds no value for has nowhere to land, so it says nothing here.
function unmovableCounters(entityType, held, deltas) {
  const refused = refusedAmounts(deltas).map(([name]) => name.value);

  const movable = Object.fromEntries(
    Object.entries(deltas).filter(
      ([name]) => !refused.includes(name) && (held[name] ?? null) !== null,
    ),
  );

  const validation = validateMoves(entityType, held, movable);

  return [
    ...refused,
    ...(Type.isAtom(validation)
      ? []
      : Object.values(validation.data[1].data).map(([name]) => name.value)),
  ];
}

function validateEntityType(query) {
  if (!Type.isAlias(query) || !Model.isEntityType(aliasName(query))) {
    Interpreter.raiseMisuseError(
      `${Interpreter.inspect(query)} is not an entity type module - a by-id read takes the entity type, a query term is read with read/1`,
    );
  }
}

// One entry for the columns an update sets and moves - the values it puts, the amounts it moves,
// and the revisions it saw for what it puts.
function updateEntry(entity, entityType, id, held, data, deltas) {
  const entry = {
    id,
    op: "update",
    stamp: Clock.stamp(),
    type: entityType,
  };

  if (Object.keys(data).length > 0) {
    entry.based_on = basedOn(held, data);
    entry.data = data;
  }

  if (Object.keys(deltas).length > 0) {
    entry.deltas = Object.fromEntries(
      Object.entries(deltas).map(([name, amount]) => [
        name,
        Model.unbox(amount, "integer"),
      ]),
    );
  }

  return entry;
}

// A delete says it was based on the row's WHOLE revision map, because it touches every column -
// the server keeps it only if none of them moved since this client last saw the row.
function deleteRow(entityType, id) {
  if (entityType === ROLE_GRANT) {
    Interpreter.raiseMisuseError(
      "role grants are written only through grant_role/revoke_role",
    );
  }

  const rowId = Bitstring.toText(id);
  const held = heldRow(entityType, rowId, "delete");
  const batch = currentBatch("delete");

  batch.append({
    based_on: {...(held["$revisions"] ?? {})},
    id: rowId,
    op: "delete",
    stamp: Clock.stamp(),
    type: entityType,
  });

  return Type.atom("ok");
}

// The row a create will store, as the wire spells it, beside the struct the verb answers with.
// Both timestamps come from the write's own stamp, so what the browser shows and what the server
// stores are the same instant derived from one number.
function writeEntry(entity, entityType, stamp) {
  return {
    data: Model.unboxRow(entityType, entity),
    id: Bitstring.toText(entity.data[Type.encodeMapKey(Type.atom("id"))][1]),
    op: "create",
    stamp,
    type: entityType,
  };
}

// What the verb answers: the struct as the row now stands, carrying the revisions this write set
// and nothing of what it was asked to do. The server's own create answers the same way - the
// metadata starts over, because what the struct was holding has been spent by the write. The
// server's pair is the one difference: nil until the row reaches the server, which stamps it.
function storedEntity(entity, entityType, stamp) {
  const timestamp = Model.boxValue(
    Model.wireDateTime(Clock.wallClockMs(stamp)),
    "datetime",
  );

  const revisions = Model.settableFields(entityType).map((name) => [
    Type.atom(name),
    Type.integer(stamp),
  ]);

  const metadata = Type.map([
    [Type.atom("__struct__"), Type.alias("Hologram.Entity.Metadata")],
    [Type.atom("attribute_ops"), Type.map([])],
    [Type.atom("claim"), Type.nil()],
    [Type.atom("relationship_ops"), Type.map([])],
    [Type.atom("revisions"), Type.map(revisions)],
    [Type.atom("stamp"), Type.nil()],
    [Type.atom("waiting"), Type.map([])],
  ]);

  const stored = Type.cloneMap(entity);

  for (const [key, value] of [
    [Type.atom("__meta__"), metadata],
    [Type.atom("created_at"), timestamp],
    [Type.atom("server_created_at"), Type.nil()],
    [Type.atom("server_created_seq"), Type.nil()],
    [Type.atom("server_updated_at"), Type.nil()],
    [Type.atom("server_updated_seq"), Type.nil()],
    [Type.atom("updated_at"), timestamp],
  ]) {
    stored.data[Type.encodeMapKey(key)] = [key, value];
  }

  return stored;
}

function validateId(id) {
  if (!Type.isBinary(id) || !Utils.isEntityId(Bitstring.toText(id))) {
    Interpreter.raiseMisuseError(
      `invalid id ${printedKey(id)} - entity ids are strings of 22 base62 characters`,
    );
  }
}

const Elixir_Hologram_DB = {
  "create!/1": (entity) => {
    const result = Elixir_Hologram_DB["create/1"](entity);

    if (Type.isAtom(result.data[0]) && result.data[0].value === "ok") {
      return result.data[1];
    }

    const entityType = Model.structTypeName(entity);

    raiseWriteError(
      `cannot create ${entityType}:\n` +
        refusalLines(entityType, result.data[1], structValues(entity)),
      result.data[1],
    );
  },

  "create/1": (entity) => {
    const entityType = entityTypeOf(entity, "create");

    // A job's create means more than storing a row - it schedules work to run after the batch
    // commits - so it has one spelling, the way a role grant has one.
    if (Model.entry(entityType).frameworkAttributes.length > 0) {
      Interpreter.raiseMisuseError(
        `${entityType} is a job type - create it through Job.create/2, which records who enqueued it so the worker can run it as them after the transaction commits`,
      );
    }

    return createEntity(entity, entityType);
  },

  "delete!/1": (entity) => Elixir_Hologram_DB["delete/1"](entity),

  "delete!/2": (entityType, id) =>
    Elixir_Hologram_DB["delete/2"](entityType, id),

  // Aborts the innermost enclosing transaction, making it answer {:error, reason}.

  "delete/1": (entity) => {
    const entityType = entityTypeOf(entity, "delete");

    return deleteRow(entityType, structField(entity, "id"));
  },

  "delete/2": (entityType, id) => deleteRow(aliasName(entityType), id),

  // A delete answers :ok or raises here, and never {:error, ...}: the server's refusal names the
  // row that still references this one, which is a question about rows this client does not have.
  // It arrives as the batch's rejection instead, so there is no error branch to write.

  "read/1": (query) => {
    const term = Elixir_Hologram_Query_Stage["normalize/1"](query);

    // Read from the rows sync keeps current: a server-only attribute is one the browser never
    // holds, so a filter or sort on it would answer as if every row held nil, and a type sync
    // never sends would answer from rows that never change. A query written in one piece in browser
    // code is checked at build time too, and any other, like one the server built, only here.
    const refusal =
      QueryCheck.refusal(term) ?? QueryCheck.unsyncedRefusal(term);

    if (refusal !== null) {
      Interpreter.raiseMisuseError(
        `DB.read can't answer the query: it ${refusal}`,
      );
    }

    const result = QueryKernel.run(term);

    return Model.boxResult(term, result);
  },

  "read/2": (entityType, id) => {
    validateId(id);
    validateEntityType(entityType);

    const query = Elixir_Hologram_Query_Stage["one/1"](
      Elixir_Hologram_Query_Stage["filter/2"](
        entityType,
        Type.list([Type.tuple([Type.atom("id"), id])]),
      ),
    );

    return Elixir_Hologram_DB["read/1"](query);
  },

  "rollback/1": (reason) => {
    if (openTransactions === 0) {
      Interpreter.raiseMisuseError(
        "cannot rollback - not inside a transaction",
      );
    }

    throw new Rollback(reason);
  },

  // The client has no database transaction to open - an action's writes already ship together -
  // so what this marks is a position in the batch. A rollback or a raise truncates back to it,
  // which IS the undo: the overlay folds the batch's writes, so a write removed from that list is
  // a write the database no longer shows.
  //
  // The opts are accepted and ignored. Their one intended use is read-set validation, which is
  // deferred past v1.

  "transaction/1": (fun) =>
    Elixir_Hologram_DB["transaction/2"](fun, Type.list([])),

  "transaction/2": (fun, _opts) => {
    const batch = currentBatch("transaction");
    const mark = batch.writes.length;
    openTransactions += 1;

    try {
      const value = Interpreter.callAnonymousFunction(fun, []);

      return Type.tuple([Type.atom("ok"), value]);
    } catch (error) {
      batch.writes.length = mark;

      if (error instanceof Rollback) {
        return Type.tuple([Type.atom("error"), error.reason]);
      }

      throw error;
    } finally {
      openTransactions -= 1;
    }
  },

  "update!/1": (entity) => {
    const result = Elixir_Hologram_DB["update/1"](entity);

    if (Type.isAtom(result)) {
      return result;
    }

    const entityType = Model.structTypeName(entity);
    const id = Interpreter.inspect(structField(entity, "id"));

    raiseWriteError(
      `cannot update ${entityType} ${id}:\n` +
        refusalLines(entityType, result.data[1], putValues(entity)),
      result.data[1],
    );
  },

  "update!/3": (entityType, id, changes) => {
    const result = Elixir_Hologram_DB["update/3"](entityType, id, changes);

    if (Type.isAtom(result)) {
      return result;
    }

    const type = aliasName(entityType);

    raiseWriteError(
      `cannot update ${type} ${Interpreter.inspect(id)}:\n` +
        refusalLines(type, result.data[1], changeValues(changes)),
      result.data[1],
    );
  },

  "update/1": (entity) => {
    const entityType = entityTypeOf(entity, "update");
    const metadata = structField(entity, "__meta__");
    const attributeOps = structField(metadata, "attribute_ops");
    const relationshipOps = structField(metadata, "relationship_ops");

    if (
      Object.keys(attributeOps.data).length === 0 &&
      Object.keys(relationshipOps.data).length === 0
    ) {
      Interpreter.raiseMisuseError(
        "update takes recorded changes - put values with put_attribute, move counters with " +
          "increment or decrement, and edges with add_relationship or delete_relationship. " +
          "A field set directly on the struct is not recorded: writing the whole struct " +
          "would overwrite concurrent changes to fields you didn't touch.",
      );
    }

    validateId(structField(entity, "id"));

    const id = Bitstring.toText(structField(entity, "id"));
    const held = LocalDatabase.getRow(entityType, id);

    // The server locks the row and refuses when there is none. This client can only answer for
    // the rows it holds - which is also what makes a move meaningful, since a delta needs a value
    // to preview against.
    if (held === null) {
      Interpreter.raiseMisuseError(
        `cannot update ${entityType} - no entity with id "${id}"`,
      );
    }

    const {changes, deltas} = splitAttributeOps(attributeOps);

    // Both halves: a move is as much a write of the column as a put, and a struct built with the
    // value on it rather than read back carries a real number past the stage's own refusal.
    refuseServerOnlyNames(entityType, [
      ...Object.keys(changes),
      ...Object.keys(deltas),
    ]);

    const batch = currentBatch("update");

    // Before the values are judged, as on the server: a rule reads an invalid value as the stored
    // one, and someone it refuses is told that rather than what's wrong with the value.
    refuseDeniedChange(
      entityType,
      id,
      changes,
      deltas,
      Object.values(relationshipOps.data).map(([key]) => key.data[0].value),
      () => unmovableCounters(entityType, held, deltas),
    );

    const boxedChanges = Object.entries(changes).map(([name, value]) => [
      Type.atom(name),
      value,
    ]);

    const validation = Elixir_Hologram_Entity["validate/2"](
      Type.alias(entityType),
      Type.map([...boxedChanges, ...refusedAmounts(deltas)]),
    );

    if (!Type.isAtom(validation)) {
      return validation;
    }

    const data = Model.unboxChanges(entityType, changes);
    const entries = edgeEntries(entity, entityType, relationshipOps);

    if (Object.keys(changes).length > 0 || Object.keys(deltas).length > 0) {
      entries.unshift(updateEntry(entity, entityType, id, held, data, deltas));
    }

    // One call, several entries: the ones after the first say they came with it, so the server
    // judges them all against the row the call started from, as its own update/1 does.
    entries.forEach((entry, index) =>
      batch.append(index === 0 ? entry : {...entry, same_call: true}),
    );

    return Type.atom("ok");
  },

  // The type-indexed twin of update/1: no struct, so no recorded changes - the changes are given
  // outright.

  "update/3": (entityType, id, changes) => {
    const type = aliasName(entityType);

    if (type === ROLE_GRANT) {
      Interpreter.raiseMisuseError(
        "role grants are written only through grant_role/revoke_role",
      );
    }

    // The changes are judged before the row is looked up, as the server judges them. A type the
    // build carries no entry for has no names to judge them by.
    const pairs = mapNewPairs(changes);

    if (Object.hasOwn(globalThis.Hologram.sync?.model ?? {}, type)) {
      validateChangeNames(type, pairs);
    }

    validateId(id);

    const rowId = Bitstring.toText(id);
    const held = LocalDatabase.getRow(type, rowId);

    // Whoever is signed in, a browser write is a client's, which the server locks the row for
    // before it judges a value - the answer Writer.update/3 gives under an acting user.
    if (held === null) {
      Interpreter.raiseMisuseError(
        `cannot update ${type} - no entity with id "${rowId}"`,
      );
    }

    const entity = Elixir_Hologram_Query_Stage["put_attribute/2"](
      Model.box(type, held),
      Type.map(pairs),
    );

    return Elixir_Hologram_DB["update/1"](entity);
  },
};

export default Elixir_Hologram_DB;
