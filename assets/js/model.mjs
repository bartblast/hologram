"use strict";

import Bitstring from "./bitstring.mjs";
import Calendar from "./calendar.mjs";
import Deserializer from "./deserializer.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Interpreter from "./interpreter.mjs";
import Serializer from "./serializer.mjs";
import SortKey from "./sort_key.mjs";
import Type from "./type.mjs";

// What the client knows about the shape of its own rows, and the boundary where a row becomes
// something transpiled Elixir can read.
//
// The database holds rows as the wire spells them - plain values, dates and datetimes and enums
// and uuids as strings - because that is the form the kernel matches and sorts on. A boxed entity
// struct is built only when a result leaves for a template, which is the only form that can be
// read there.
//
// A value's type is not recoverable from the value itself, since a date, an enum and a uuid all
// arrive as strings, so reading one back means knowing the attribute it belongs to. That is what
// the build bakes into the bundle constants, for every type this client can hold.
//
// An enum attribute's declared values ride in the entry for the same reason, in the order the
// declaration spells them: that order is the type's order, so sorting rows by an enum attribute
// is a comparison of positions in this list rather than of the labels themselves.
export default class Model {
  // The attributes every entity type carries without declaring them - Hologram.Entity's
  // @system_attributes. The model bakes them alongside the declared ones, because reading a row
  // back needs their types, so anything asking what a type DECLARES has to subtract them. Held
  // here rather than beside each reader: it is one list mirroring an Elixir one, and a second copy
  // is how the two drift.
  static systemAttributes = [
    "created_at",
    "id",
    "server_created_at",
    "server_updated_at",
    "updated_at",
  ];

  // IMPORTANT!
  // The twin of Hologram.Policy.framework_operations/0 - the seven operations the framework itself
  // asks about, always askable on every type. Pinned on both tiers ("framework_operations/0" in
  // test/elixir/hologram/policy_test.exs, "frameworkOperations" in test/javascript/model_test.mjs).
  // Always update both together. A baked entry's operations list carries these too; this copy
  // exists so a refusal can say which of a type's operations are the names its lines carry.
  static frameworkOperations = [
    "create",
    "delete",
    "grant_role",
    "read",
    "read_roles",
    "revoke_role",
    "update",
  ];

  static #entries = {};

  // Moves whenever the model's entries are read afresh, so what was worked out from them can tell
  // it is out of date.
  static #generation = 0;

  // What an integer column holds.
  static #INT8_MAX = 9223372036854775807n;
  static #INT8_MIN = -9223372036854775808n;

  // A year the way Date.to_iso8601/1 spells one, which is how every date and datetime arrives:
  // four digits, or more with no leading zero, and a minus before a year below 0 - never before 0
  // itself. So one year is one spelling, as one day is, and the year of every date the server
  // accepts reads back - the entity validator asks only that the calendar has the day.
  static #YEAR = "((?!-0000)-?(?:\\d{4}|[1-9]\\d{4,}))";

  // Signed either way and of any width, since toISOString - which wireDateTime builds on - writes a
  // year past 9999 as +010000 and one below 0 as -000001. Only the wall clock reaches it, so neither
  // arrives, but an order that read one wrongly would break the sort it is handed to.
  static #YEAR_PREFIX = /^[+-]?\d+/;

  static #DATE_PATTERN = new RegExp(`^${Model.#YEAR}-(\\d{2})-(\\d{2})$`);

  static #DATETIME_PATTERN = new RegExp(
    `^${Model.#YEAR}-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(?:\\.(\\d+))?Z$`,
  );

  // Every relationship of a row is absent from the row itself: a to-many lives in the
  // relationship facts and a to-one behind the reference field, so both are assembled by whoever
  // reads them and handed over here. What no reader asked for stays unasked-for rather than
  // becoming null, which is a different answer.
  static box(type, row, includes = {}) {
    const entry = Model.entry(type);

    const data = [
      [Type.atom("__struct__"), Type.alias(type)],
      [Type.atom("__meta__"), Model.#metadata(row)],
    ];

    for (const [name, attributeType] of Object.entries(entry.attributes)) {
      data.push([
        Type.atom(name),
        Model.#boxAttribute(entry, name, attributeType, row),
      ]);
    }

    for (const [name, relationship] of Object.entries(entry.relationships)) {
      if (!relationship.toMany) {
        const referenceField = `${name}_id`;

        data.push([
          Type.atom(referenceField),
          Model.boxValue(row[referenceField], "uuid"),
        ]);
      }

      data.push([Type.atom(name), includes[name] ?? Model.notIncluded(name)]);
    }

    // An inverse stores nothing on the row, so it has no reference field - only what was included
    // of it, or the sentinel. A derived field is computed rather than stored, so it is the same:
    // what was included of it, or the sentinel.
    for (const name of [
      ...Object.keys(entry.inverses),
      ...Object.keys(entry.derived),
    ]) {
      data.push([Type.atom(name), includes[name] ?? Model.notIncluded(name)]);
    }

    return Type.map(data);
  }

  // The framework's own state on an entity struct, as one that arrived from nowhere carries it:
  // nothing recorded toward a write, and no revisions, because it was read from no row.
  static emptyMetadata() {
    return Model.#metadataWithRevisions(Type.map([]));
  }

  // A label beginning with an uppercase letter names a module, which is stored without the
  // prefix every module atom carries - the same rule the database codec reads labels by.
  static boxEnumValue(label) {
    const first = label[0];

    return first >= "A" && first <= "Z" ? Type.alias(label) : Type.atom(label);
  }

  // Why this lives here rather than in the renderer, where it was written: a query result is boxed
  // for a template AND for a read inside an action, and the two must agree. A row read one way and
  // rendered the other would otherwise be two different structs of the same row.
  // What the kernel evaluated to, in the form a template reads: a count is a number, a
  // single-result query is one struct or nil, and everything else is a list.
  static boxResult(term, result) {
    if (term.cardinality === "count") {
      return Type.integer(result);
    }

    if (term.cardinality === "one") {
      return result === null ? Type.nil() : Model.#boxNode(term, result);
    }

    return Type.list(result.map((node) => Model.#boxNode(term, node)));
  }

  // Which attributes need a key is a fact about the TYPE - every string attribute is ordered and
  // compared by its key on both tiers - so it is read from the entry's attribute types rather than
  // listed, and the key itself is derived, so it is computed here rather than sent. A server-only
  // string's value never arrives, and its key is null like any unset value's.
  //
  // Writes into the object it is given and hands it back, because both callers - a row arriving
  // from the server and a row this client wrote - are filing that same object.
  static computeSortKeys(type, attributes) {
    for (const [name, attributeType] of Object.entries(
      Model.entry(type).attributes,
    )) {
      if (attributeType !== "string") {
        continue;
      }

      const value = attributes[name];

      attributes[Model.sortKeyField(name)] =
        value === null || value === undefined ? null : SortKey.compute(value);
    }

    return attributes;
  }

  // The entity type a boxed struct names, or nothing at all when the value is not a struct -
  // which is how a verb tells "wrong kind of value" from "wrong kind of struct" without raising
  // on the way to finding out.
  static structTypeName(value) {
    if (!Type.isMap(value)) {
      return null;
    }

    const entry = value.data[Type.encodeMapKey(Type.atom("__struct__"))];

    return entry === undefined || !Type.isAlias(entry[1])
      ? null
      : entry[1].value.replace(/^Elixir\./, "");
  }

  // The client's Hologram.Entity.describe_inverse/2: where the fact behind a declared inverse
  // lives, as a refusal names it - the reference column of the related type for an inverse of a
  // to-one, the related type's relationship for an inverse of a to-many.
  static describeInverse(type, name) {
    const inverse = Model.inverses(type)[name];

    return inverse.reference
      ? `the ${inverse.forward}_id reference of ${inverse.type}`
      : `the ${inverse.forward} relationship of ${inverse.type}`;
  }

  // The type's derived fields by name, each with what it holds - kind "scalar" with its declared
  // type and an enum's labels, or kind "one" or "set" with its row type - and its definition.
  static derived(type) {
    return Model.entry(type).derived;
  }

  // The value the given baked object holds under the given name, or undefined. Its own keys only:
  // the baked model is made of plain objects, so a name like constructor or toString would otherwise
  // read a property of Object.prototype.
  static own(object, name) {
    return Object.hasOwn(object, name) ? object[name] : undefined;
  }

  // The derived field of the given name, or null for a name the type declares no derived field by -
  // its own key only, so a name like constructor is no derived field.
  static derivedField(type, name) {
    const derived = Model.derived(type);

    return Object.hasOwn(derived, name) ? derived[name] : null;
  }

  // The client's Hologram.Entity.Derived.read_only_message/2: every write path refuses a derived
  // field in these words.
  static derivedReadOnlyMessage(type, name) {
    return `:${name} is a derived field of ${type} - it's computed from its definition, so it's read-only`;
  }

  static inverses(type) {
    return Model.entry(type).inverses;
  }

  // Whether this build carries the given entity type - the client's answer to the server's
  // Reflection.entity?/1. A type a page neither queries nor mentions is not baked, so what this
  // can say is "not an entity type THIS BUILD knows", which is the same divergence Entity.new
  // already carries.
  static isEntityType(type) {
    return Boolean(globalThis.Hologram.sync?.model?.[type]);
  }

  static entry(type) {
    let entry = Model.#entries[type];

    if (entry) {
      return entry;
    }

    const baked = globalThis.Hologram.sync?.model?.[type];

    if (!baked) {
      throw new HologramRuntimeError(
        `entity type ${type} is not part of this build's data model`,
      );
    }

    // The ones every struct is built and written through - the three the write path INDEXES into,
    // and the inverses and derived fields each boxed row walks - stand in for themselves when a
    // baked entry does not carry them, where the ones that are only carried can stay undefined: a
    // reader asking what an attribute declares has to be told "nothing" rather than meet a crash. A
    // build writes all of them for every type - what has fewer keys is a hand-built entry, which is
    // how most of this suite states the little it reads.
    entry = {
      attributes: baked.attributes,
      constraints: Model.#boxConstraints(baked.constraints ?? {}),
      defaults: baked.defaults ?? {},
      derived: baked.derived ?? {},
      enumValues: baked.enumValues,
      frameworkAttributes: baked.frameworkAttributes ?? [],
      inverses: baked.inverses ?? {},
      policy: baked.policy,
      relationships: baked.relationships,
      serverOnly: new Set(baked.serverOnly),
    };

    Model.#entries[type] = entry;

    return entry;
  }

  // What a relationship nobody asked for holds, naming itself - a read of one reports which
  // relationship was not included rather than answering nil, which is a different fact.
  static notIncluded(name) {
    return Type.map([
      [Type.atom("__struct__"), Type.alias("Hologram.Entity.NotIncluded")],
      [Type.atom("relationship"), Type.atom(name)],
    ]);
  }

  // The type a chain of relationships leads to from the given type - what a path's last name is an
  // attribute of. A relationship leads to the type its rows are, so the chain may pass through a
  // to-many or an inverse as well as a to-one.
  static pathTarget(type, relationshipNames) {
    return relationshipNames.reduce(
      (current, name) =>
        (
          Model.own(Model.relationships(current), name) ??
          Model.own(Model.inverses(current), name)
        ).type,
      type,
    );
  }

  static relationships(type) {
    return Model.entry(type).relationships;
  }

  // The client's Hologram.Entity.Derived.rows_term/3: the term the rows the given field holds are
  // read with, given the term the field is included with - a relationship's as included, a derived
  // field's embedding what its definition includes, every query it may choose included, beside the
  // nested includes the field is included with. Where both include one relationship, the
  // definition's include is kept and gains what the other includes.
  static rowsTerm(type, name, includedTerm) {
    const derived = Model.derivedField(type, name);

    if (derived === null) {
      return includedTerm;
    }

    const include = Model.#definitionQueries(derived.definition).reduce(
      (acc, query) => Model.#mergedInclude(query.include, acc),
      includedTerm.include,
    );

    return {...includedTerm, include};
  }

  // The fields a client may write, which is what a create's data carries and what the server's
  // Hologram.Mutation.Envelope.settable_fields/1 admits - the declared attributes plus a to-one's
  // reference field. Three kinds are left out and each for its own reason: the system attributes
  // are the framework's to fill, a server-only attribute is one this client was never shown, and a
  // job's framework attributes are what the worker records. A to-many is not a field at all - its
  // edges travel as their own writes.
  //
  // Sorted, so a batch built twice from one struct spells its data the same way both times.
  static settableFields(type) {
    const entry = Model.entry(type);

    const attributes = Object.keys(entry.attributes).filter(
      (name) =>
        !Model.systemAttributes.includes(name) &&
        !entry.serverOnly.has(name) &&
        !entry.frameworkAttributes.includes(name),
    );

    const references = Object.entries(entry.relationships)
      .filter(([_name, relationship]) => !relationship.toMany)
      .map(([name]) => `${name}_id`);

    return attributes.concat(references).sort();
  }

  // The row field a string attribute's sort key is filed under. A declared name can't contain $, so
  // the key never lands on a field the entity declares - an attribute named title_sort beside
  // title keeps its own value.
  static sortKeyField(name) {
    return `${name}$sort`;
  }

  // The client's Hologram.Policy.validate_operation!/2: refuses an operation the given entity type
  // cannot be asked about, with the server's own sentences (pinned as pairs in
  // test/elixir/hologram/policy_test.exs and test/javascript/model_test.mjs). A framework
  // operation always passes. An atom passes when the type's baked operations list names it. A
  // {:grant_role, role} / {:revoke_role, role} tuple - a two-tuple of atoms, which is the caller's
  // shape check to make - passes when the type's baked roles name the role, and an {:update, field}
  // or {:update, fields} tuple - a field atom or a proper list - when every field it names is one
  // of #updateFields, a list naming at least one.
  //
  // Read off the raw baked entry, as can?/3 and the role check read it: entry() normalizes the
  // keys the write path indexes into and carries neither of these. A hand-built entry without them
  // (which is how most of the suite states the little it reads) declares nothing of its own.
  static validateOperation(type, operation) {
    const baked = globalThis.Hologram.sync?.model?.[type];
    const operations = baked?.operations ?? [];

    if (Type.isAtom(operation)) {
      const name = operation.value;

      if (
        Model.frameworkOperations.includes(name) ||
        operations.includes(name)
      ) {
        return;
      }

      const names = operations.filter(
        (candidate) => !Model.frameworkOperations.includes(candidate),
      );

      let carried;

      if (names.length === 0) {
        carried = "carry no name";
      } else if (names.length === 1) {
        carried = `carry the name :${names[0]}`;
      } else {
        carried = `carry the names ${Model.#joinNames(names)}`;
      }

      Interpreter.raiseMisuseError(
        `unknown operation ${Interpreter.inspect(operation)} for ${type} - the framework's operations are ${Model.#joinNames(Model.frameworkOperations)}, and its allow lines ${carried}`,
      );
    }

    const [name, role] = operation.data;

    if (
      name.value === "update" &&
      (Type.isAtom(role) || Type.isProperList(role))
    ) {
      Model.#validateUpdateFields(type, baked, operation);
      return;
    }

    if (!["grant_role", "revoke_role"].includes(name.value)) {
      Interpreter.raiseMisuseError(
        `unknown operation ${Interpreter.inspect(operation)} for ${type} - the operation tuples are {:grant_role, role}, {:revoke_role, role}, {:update, field} and {:update, fields}`,
      );
    }

    const roles = baked?.roles ?? [];

    if (!roles.includes(role.value)) {
      const declared =
        roles.length === 0
          ? "it declares no role"
          : `declared roles are: ${roles.map((roleName) => `:${roleName}`).join(", ")}`;

      Interpreter.raiseMisuseError(
        `unknown role ${Interpreter.inspect(role)} in ${Interpreter.inspect(operation)} for ${type} - ${declared}`,
      );
    }
  }

  // The way back over the same boundary: a value written in a query becomes the way the wire
  // spells it, because that is what the rows it will be compared against hold. A date written as
  // a date compares with a date written as a string only if one of them stops being what it was,
  // and the rows cannot be the ones to change.
  static unbox(value, attributeType) {
    if (Type.isNil(value)) {
      return null;
    }

    switch (attributeType) {
      case "boolean":
        return Type.isTrue(value);

      case "date":
        return Model.#unboxDate(value);

      case "datetime":
        return Model.#unboxDateTime(value);

      case "enum":
        return Model.#unboxEnum(value);

      case "float":
      case "integer":
        return Number(value.value);

      case "time":
        return Model.#unboxTime(value);

      default:
        return Bitstring.toText(value);
    }
  }

  // A boxed entity struct as the wire spells its settable fields - the object a create's data
  // carries. A reference field has no attribute type of its own and is always a uuid, which is
  // what the server's own field_types/1 says about it.
  static unboxRow(type, struct) {
    const boxed = Object.fromEntries(
      Model.settableFields(type).map((field) => [
        field,
        Model.#field(struct, field),
      ]),
    );

    return Model.unboxChanges(type, boxed);
  }

  // The same boundary for SOME of a row's fields - what an update sets rather than what a create
  // carries. A reference field has no attribute type of its own and is always a uuid.
  static unboxChanges(type, changes) {
    const entry = Model.entry(type);

    return Object.fromEntries(
      Object.entries(changes).map(([name, value]) => [
        name,
        Model.unbox(value, entry.attributes[name] ?? "uuid"),
      ]),
    );
  }

  // Takes the model entries a server enforcing other rules than this bundle was built with hands
  // over (see Hologram.Compiler.render_rules/1): the entry of every type a build bakes whatever the
  // pages reach, so a type it leaves out declares no rule and no role.
  //
  // A type this client holds takes the entry's rules and verdict entries, and its operations,
  // derived fields and inverses join the ones the bundle baked - added or redefined, never taken
  // away, because the bundle's own code can still ask about an operation or read a field the new
  // build dropped. An operation left without rules is denied, which is what the new build answers
  // for it. A type the client holds that the entries leave out keeps everything but its rules and
  // verdict entries, which go, the server's default deny. A type the client does not hold is taken
  // whole: rules a deploy added can read a type the bundle never carried, and a derived field
  // redefined can lead to one, whose rows arrive with them. Its defaults and constraints arrive
  // serialized, since a frame carries JSON where the bundle spells their terms as JavaScript, and
  // are taken in as the bundle would have baked them. Every other part of a held entry stays the
  // bundle's - the model is the same, which is what the handshake checked before sending these.
  static replaceRules(entries) {
    const model = globalThis.Hologram.sync.model;

    for (const [type, held] of Object.entries(model)) {
      const entry = entries[type];

      model[type] = entry
        ? {
            ...held,
            derived: {...held.derived, ...entry.derived},
            inverses: {...held.inverses, ...entry.inverses},
            operations: [
              ...new Set([...(held.operations ?? []), ...entry.operations]),
            ].sort(),
            policy: entry.policy,
            verdicts: entry.verdicts,
          }
        : {...held, policy: {}, verdicts: {}};
    }

    for (const [type, entry] of Object.entries(entries)) {
      model[type] ??= Model.#deserializedTerms(entry);
    }

    Model.reset();
  }

  // How many times the model's entries have been read afresh: a value worked out from the model is
  // current while this stays what it was.
  static generation() {
    return Model.#generation;
  }

  static reset() {
    Model.#entries = {};
    Model.#generation += 1;
  }

  // The model entries this client holds, in the shape a server hands them over in (see
  // Hologram.Compiler.render_rules/1): the terms among the defaults and constraints serialized,
  // where the rest is the data it already is - so a tab of this browser built with other rules can
  // take them in through replaceRules().
  static serializedEntries() {
    return Object.fromEntries(
      Object.entries(globalThis.Hologram.sync.model).map(([type, entry]) => [
        type,
        Model.#serializedTerms(entry),
      ]),
    );
  }

  // Two dates, or two datetimes, as the wire spells them, in the order of the days or instants
  // they name: -1, 0 or 1. Within one year the rest of the spelling is fixed width - every datetime
  // on the wire is UTC at six fractional digits - so it orders as its characters do, but the year
  // does not: it is as wide as it needs and signed, so -2 would sort after -1 and 10000 before 9999.
  // So the years compare as numbers, BigInt for any width, and the rest as the string it is.
  //
  // Two values in years 0 to 9999 - nearly every one - both have their first dash at index 4, and
  // then their characters do order them, so they compare whole and skip the parse: this runs for
  // every pair a sort or an ordering filter compares.
  static compareTemporal(left, right) {
    if (left[4] === "-" && right[4] === "-") {
      if (left === right) {
        return 0;
      }

      return left < right ? -1 : 1;
    }

    const [leftYear] = left.match(Model.#YEAR_PREFIX);
    const [rightYear] = right.match(Model.#YEAR_PREFIX);

    const leftNumber = BigInt(leftYear);
    const rightNumber = BigInt(rightYear);

    if (leftNumber !== rightNumber) {
      return leftNumber < rightNumber ? -1 : 1;
    }

    const leftRest = left.slice(leftYear.length);
    const rightRest = right.slice(rightYear.length);

    if (leftRest === rightRest) {
      return 0;
    }

    return leftRest < rightRest ? -1 : 1;
  }

  // The given value as it compares with the other one. A BigInt beside a Number reads as a Number,
  // which is what the database does with an integer beside a float. Beside a safe integer the
  // rounding changes nothing, since a BigInt held here is always past what a Number holds exactly.
  // One no column can hold stays exact, as Hologram.Query.Ordering leaves it.
  static widened(value, other) {
    return Model.#isInt8BigInt(value) && typeof other === "number"
      ? Number(value)
      : value;
  }

  // The given value as a field of the given declared type reads it: an integer a float field reads
  // is a Number, the way the database casts it.
  static widenedTo(value, type) {
    return type === "float" &&
      typeof value === "bigint" &&
      Number.isFinite(Number(value))
      ? Number(value)
      : value;
  }

  static #isInt8BigInt(value) {
    return (
      typeof value === "bigint" &&
      value >= Model.#INT8_MIN &&
      value <= Model.#INT8_MAX
    );
  }

  // A datetime as the wire spells it, from a count of milliseconds - six fractional digits, the
  // same rule #unboxDateTime follows, so an instant this client derives is spelled the way one the
  // server sent is. toISOString writes exactly three, which is all a millisecond has.
  static wireDateTime(milliseconds) {
    return `${new Date(milliseconds).toISOString().slice(0, -1)}000Z`;
  }

  // A value the client may not have is not a value it is missing: the model says the attribute
  // exists and is not for this client, which is what the sentinel says in its place - and it
  // names the attribute, so a read of one reports which.
  static #boxAttribute(entry, name, attributeType, row) {
    if (entry.serverOnly.has(name)) {
      return Type.map([
        [Type.atom("__struct__"), Type.alias("Hologram.Entity.ServerOnly")],
        [Type.atom("attribute"), Type.atom(name)],
      ]);
    }

    return Model.boxValue(row[name], attributeType);
  }

  static #boxAttributeConstraints(options) {
    const entries = Object.entries(options).map(([option, value]) => [
      option,
      Model.#boxConstraintValue(option, value),
    ]);

    return Object.fromEntries(entries);
  }

  // The declared constraints, in the form the checks read them: a range as the struct a
  // membership test walks, a pattern as the struct a match runs, and everything else as the
  // build wrote it. Boxed once per type rather than at every check, because a type is read back
  // far more often than it is met for the first time.
  static #boxConstraints(constraints) {
    const entries = Object.entries(constraints).map(([name, options]) => [
      name,
      Model.#boxAttributeConstraints(options),
    ]);

    return Object.fromEntries(entries);
  }

  static #boxConstraintValue(option, value) {
    switch (option) {
      case "format":
        return Model.#compileFormat(value);

      case "in":
        return Type.range(value.first, value.last, value.step);

      default:
        return value;
    }
  }

  // Refused the way #boxTime and #boxDateTime refuse: the shape first, then the fields against the
  // calendar itself. Nothing healthy can put an impossible date here - the entity validator turns
  // one down on both tiers, and a date column cannot hold one - so this is the third reader of one
  // rule agreeing with the other two, rather than a gate anything is expected to reach.
  static #boxDate(value) {
    const match = value.match(Model.#DATE_PATTERN);

    if (!match) {
      throw new HologramRuntimeError(`invalid date on the wire: ${value}`);
    }

    const [_full, year, month, day] = match;

    if (!Calendar.validDate(Number(year), Number(month), Number(day))) {
      throw new HologramRuntimeError(`invalid date on the wire: ${value}`);
    }

    return Type.map([
      [Type.atom("__struct__"), Type.alias("Date")],
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("day"), Type.integer(day)],
      [Type.atom("month"), Type.integer(month)],
      [Type.atom("year"), Type.integer(year)],
    ]);
  }

  // Every datetime on the wire is UTC, which is what gives one instant one spelling - so the zone
  // is the same one every time rather than something to read.
  static #boxDateTime(value) {
    const match = value.match(Model.#DATETIME_PATTERN);

    if (!match) {
      throw new HologramRuntimeError(`invalid datetime on the wire: ${value}`);
    }

    const [_full, year, month, day, hour, minute, second, rawFraction = ""] =
      match;

    // A datetime holds microseconds and no more, so digits past the sixth are dropped rather
    // than read - which is what Elixir does with the same string, and being the same is the
    // whole point of this side. Keeping them would put a precision outside 0..6 in the struct
    // and make an amount that no longer means what its digits say.
    const fraction = rawFraction.slice(0, 6);

    const amount = fraction === "" ? 0 : parseInt(fraction.padEnd(6, "0"), 10);

    const microsecond = Type.tuple([
      Type.integer(amount),
      Type.integer(fraction.length),
    ]);

    // The regex above constrains digit COUNT only, so 2026-13-40T25:00:00Z gets this far - both
    // halves are asked of the calendar, as #boxDate asks the date half and the entity validator
    // asks both. The microsecond pair cannot fail here (the slice above caps the precision at 6,
    // which caps the amount at 999999), and is passed rather than assumed so this reads as the
    // same rule the other two readers apply.
    if (
      !Calendar.validDate(Number(year), Number(month), Number(day)) ||
      !Calendar.validTime(
        Number(hour),
        Number(minute),
        Number(second),
        amount,
        fraction.length,
      )
    ) {
      throw new HologramRuntimeError(`invalid datetime on the wire: ${value}`);
    }

    return Type.map([
      [Type.atom("__struct__"), Type.alias("DateTime")],
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("day"), Type.integer(day)],
      [Type.atom("hour"), Type.integer(hour)],
      [Type.atom("microsecond"), microsecond],
      [Type.atom("minute"), Type.integer(minute)],
      [Type.atom("month"), Type.integer(month)],
      [Type.atom("second"), Type.integer(second)],
      [Type.atom("std_offset"), Type.integer(0)],
      [Type.atom("time_zone"), Type.bitstring("Etc/UTC")],
      [Type.atom("utc_offset"), Type.integer(0)],
      [Type.atom("year"), Type.integer(year)],
      [Type.atom("zone_abbr"), Type.bitstring("UTC")],
    ]);
  }

  // A to-many include is a list of nodes, a to-one is one node or nothing at all - an absent
  // to-one is nil, which is what the relationship not being there means.
  static #boxIncluded(subTerm, included) {
    if (Array.isArray(included)) {
      return Type.list(
        included.map((subNode) => Model.#boxNode(subTerm, subNode)),
      );
    }

    return included === null ? Type.nil() : Model.#boxNode(subTerm, included);
  }

  // Deps: [:maps.from_list/1]
  // A result node becomes the entity struct a template can read, its includes boxed with it.
  // The node carries the row and what was included of it, and the TERM says what each of those
  // is - a node has no type of its own. A derived field holding a value carries it the way the wire
  // spells it, boxed by its declared type, and one holding rows carries them read with what its
  // definition embeds.
  static #boxNode(term, node) {
    const includes = {};

    for (const [name, subTerm] of Object.entries(term.include)) {
      const derived = Model.derivedField(term.entity, name);

      includes[name] =
        derived?.kind === "scalar"
          ? Model.boxValue(node.includes[name], derived.type)
          : Model.#boxIncluded(
              Model.rowsTerm(term.entity, name, subTerm),
              node.includes[name],
            );
    }

    return Model.box(term.entity, node.row, includes);
  }

  // A time of day carries no date and no zone, so there is nothing to read but the clock - and
  // the fraction, which is what the struct's own precision counts.
  static #boxTime(value) {
    const match = value.match(
      /^([01]\d|2[0-3]):([0-5]\d):([0-5]\d)(?:\.(\d+))?$/,
    );

    if (!match) {
      throw new HologramRuntimeError(`invalid time on the wire: ${value}`);
    }

    const [_full, hour, minute, second, rawFraction = ""] = match;

    // Digits past the sixth are dropped rather than read, for the reason #boxDateTime gives.
    const fraction = rawFraction.slice(0, 6);

    const microsecond = Type.tuple([
      Type.integer(fraction === "" ? 0 : parseInt(fraction.padEnd(6, "0"), 10)),
      Type.integer(fraction.length),
    ]);

    return Type.map([
      [Type.atom("__struct__"), Type.alias("Time")],
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("hour"), Type.integer(hour)],
      [Type.atom("microsecond"), microsecond],
      [Type.atom("minute"), Type.integer(minute)],
      [Type.atom("second"), Type.integer(second)],
    ]);
  }

  // A wire value as the term a template reads - the counterpart of the public unbox/2, and the
  // same boundary: values are stored the way the wire spells them and boxed only on the way out.
  static boxValue(value, attributeType) {
    if (value === null || value === undefined) {
      return Type.nil();
    }

    switch (attributeType) {
      case "boolean":
        return Type.boolean(value);

      case "date":
        return Model.#boxDate(value);

      case "datetime":
        return Model.#boxDateTime(value);

      case "enum":
        return Model.boxEnumValue(value);

      case "float":
        return Type.float(value);

      case "integer":
        return Type.integer(value);

      case "time":
        return Model.#boxTime(value);

      default:
        return Type.bitstring(value);
    }
  }

  // A compiled pattern exists only inside the runtime that compiled it, so the build bakes what
  // compiles into one - the source and the options it was written with - and this is the runtime
  // that compiles it. The struct is the one a violation carries, so it holds the same three
  // fields Elixir's does.
  static #compileFormat({opts, source}) {
    const boxedSource = Type.bitstring(source);

    // The options arrive boxed, as the term the declaration held: not every one of them is a
    // name, since ~r/x/s reads back as [:dotall, {:newline, :anycrlf}].
    const compiled = Interpreter.moduleProxy("re")["compile/2"](
      boxedSource,
      opts,
    );

    return Type.struct("Regex", [
      [Type.atom("opts"), opts],
      [Type.atom("re_pattern"), compiled.data[1]],
      [Type.atom("source"), boxedSource],
    ]);
  }

  static #definitionQueries(definition) {
    if ("query" in definition) {
      return [definition.query];
    }

    if ("if" in definition) {
      return [
        ...Model.#definitionQueries(definition.then),
        ...Model.#definitionQueries(definition.else),
      ];
    }

    return [];
  }

  // A constraint's term serialized the way a frame carries it, from the one the bundle baked.
  static #serializedConstraint(option, value) {
    switch (option) {
      case "format":
        return {...value, opts: Serializer.serialize(value.opts, "client")};

      case "max":
      case "min":
        return Serializer.serialize(value, "client");

      default:
        return value;
    }
  }

  // The given entry with the terms among its defaults and constraints serialized.
  static #serializedTerms(entry) {
    const defaults = Object.entries(entry.defaults ?? {}).map(
      ([name, value]) => [name, Serializer.serialize(value, "client")],
    );

    const constraints = Object.entries(entry.constraints ?? {}).map(
      ([name, options]) => [
        name,
        Object.fromEntries(
          Object.entries(options).map(([option, value]) => [
            option,
            Model.#serializedConstraint(option, value),
          ]),
        ),
      ],
    );

    return {
      ...entry,
      constraints: Object.fromEntries(constraints),
      defaults: Object.fromEntries(defaults),
    };
  }

  // A constraint's term as the bundle bakes it, from the serialized one a frame carries.
  static #deserializedConstraint(option, value) {
    switch (option) {
      case "format":
        return {...value, opts: Deserializer.deserialize(value.opts)};

      case "max":
      case "min":
        return Deserializer.deserialize(value);

      default:
        return value;
    }
  }

  // The given entry with the terms among its defaults and constraints as the bundle bakes them.
  static #deserializedTerms(entry) {
    const defaults = Object.entries(entry.defaults ?? {}).map(
      ([name, value]) => [name, Deserializer.deserialize(value)],
    );

    const constraints = Object.entries(entry.constraints ?? {}).map(
      ([name, options]) => [
        name,
        Object.fromEntries(
          Object.entries(options).map(([option, value]) => [
            option,
            Model.#deserializedConstraint(option, value),
          ]),
        ),
      ],
    );

    return {
      ...entry,
      constraints: Object.fromEntries(constraints),
      defaults: Object.fromEntries(defaults),
    };
  }

  static #field(struct, name) {
    return struct.data[Type.encodeMapKey(Type.atom(name))][1];
  }

  // The framework's state on the struct, as the server would fill it for a row that was READ:
  // the revisions the wire carried, and the write-side fields empty - those record what a struct
  // is carrying toward a write, and a row arriving from the server is carrying none.
  // ":a", ":a and :b", ":a, :b and :c" - the spoken form, for a message listing a few names
  static #joinNames(names) {
    const spelled = names.map((name) => `:${name}`);

    if (spelled.length === 1) {
      return spelled[0];
    }

    return `${spelled.slice(0, -1).join(", ")} and ${spelled.at(-1)}`;
  }

  static #mergedInclude(keptInclude, otherInclude) {
    const merged = {...otherInclude, ...keptInclude};

    for (const [name, otherTerm] of Object.entries(otherInclude)) {
      const keptTerm = keptInclude[name];

      if (keptTerm && otherTerm) {
        merged[name] = {
          ...keptTerm,
          include: Model.#mergedInclude(keptTerm.include, otherTerm.include),
        };
      }
    }

    return merged;
  }

  static #metadata(row) {
    const revisions = Object.entries(row["$revisions"] ?? {}).map(
      ([name, revision]) => [Type.atom(name), Type.integer(revision)],
    );

    return Model.#metadataWithRevisions(Type.map(revisions));
  }

  // Every field Hologram.Entity.Metadata declares is written here, at its own default, whether or
  // not this side has anything to put in it: a struct short of a field answers a read of that
  // field with a KeyError where the server's answers nil, and stops comparing equal to a struct
  // the server built. One list, so the two can only drift by someone editing this line.
  static #metadataWithRevisions(revisions) {
    return Type.map([
      [Type.atom("__struct__"), Type.alias("Hologram.Entity.Metadata")],
      [Type.atom("attribute_ops"), Type.map([])],
      [Type.atom("claim"), Type.nil()],
      [Type.atom("relationship_ops"), Type.map([])],
      [Type.atom("revisions"), revisions],
      [Type.atom("stamp"), Type.nil()],
    ]);
  }

  static #pad(value, width) {
    return String(value).padStart(width, "0");
  }

  // A time of day's clock as the wire spells it, the amount in microseconds always at six digits -
  // the reason is on #unboxTime.
  static #spellClock(hour, minute, second, microsecond) {
    return `${Model.#pad(hour, 2)}:${Model.#pad(minute, 2)}:${Model.#pad(second, 2)}.${Model.#pad(microsecond, 6)}`;
  }

  // A day as the wire spells it: the year the way Date.to_iso8601/1 spells it - at least four
  // digits, and a minus before a year below 0 rather than inside the padding - so one day is one
  // spelling on both tiers. The year may be a BigInt (a struct's field) or a Number (a Date's).
  static #spellDate(year, month, day) {
    const spelledYear =
      year < 0 ? `-${Model.#pad(-year, 4)}` : Model.#pad(year, 4);

    return `${spelledYear}-${Model.#pad(month, 2)}-${Model.#pad(day, 2)}`;
  }

  static #unboxDate(value) {
    return Model.#spellDate(
      Model.#field(value, "year").value,
      Model.#field(value, "month").value,
      Model.#field(value, "day").value,
    );
  }

  // The instant the struct stands for, in UTC: its wall clock moved back by the offsets it carries,
  // which is what the server's codec does before it spells one - so a datetime in any zone is the
  // instant it names, in a query and in a write alike. The move is a Date's, built through
  // setUTCFullYear rather than Date.UTC, which maps years 0 to 99 into the 1900s, and a Date
  // reaches past every year the server can hold a datetime in. Offsets are whole seconds, so the
  // microseconds never move.
  static #unboxDateTime(value) {
    const part = (name) => Number(Model.#field(value, name).value);
    const offset = part("utc_offset") + part("std_offset");

    const instant = new Date(0);
    instant.setUTCFullYear(part("year"), part("month") - 1, part("day"));
    instant.setUTCHours(part("hour"), part("minute"), part("second") - offset);

    const microsecond = Model.#field(value, "microsecond").data[0].value;

    const date = Model.#spellDate(
      instant.getUTCFullYear(),
      instant.getUTCMonth() + 1,
      instant.getUTCDate(),
    );

    const clock = Model.#spellClock(
      instant.getUTCHours(),
      instant.getUTCMinutes(),
      instant.getUTCSeconds(),
      microsecond,
    );

    return `${date}T${clock}Z`;
  }

  // A module travels as its name without the prefix every module atom carries, a plain atom as
  // it is spelled - the same two cases the label reader tells apart coming the other way.
  static #unboxEnum(value) {
    return Type.isAlias(value)
      ? value.value.replace(/^Elixir\./, "")
      : value.value;
  }

  // Always six fractional digits, whatever precision the value was written at: the wire carries
  // one spelling per time of day, which is what lets these compare as plain strings at all. A
  // value written with fewer digits and left that way would sort before a time it comes after,
  // and would not equal the same time read back from a column, which is always all six. The
  // amount is in microseconds whatever the precision, as Elixir keeps it - half a second is
  // {500000, 1} - so the precision only says how many of the digits were written.
  static #unboxTime(value) {
    return Model.#spellClock(
      Model.#field(value, "hour").value,
      Model.#field(value, "minute").value,
      Model.#field(value, "second").value,
      Model.#field(value, "microsecond").data[0].value,
    );
  }

  // The client's Hologram.Policy.update_fields/1, read off the raw baked entry: the declared
  // attributes but the system ones and a job's framework-owned ones, and every forward
  // relationship, a to-one by its relationship name - sorted, as the server sorts atoms.
  static #updateFields(baked) {
    const frameworkAttributes = baked?.frameworkAttributes ?? [];

    const attributes = Object.keys(baked?.attributes ?? {}).filter(
      (name) =>
        !Model.systemAttributes.includes(name) &&
        !frameworkAttributes.includes(name),
    );

    return attributes.concat(Object.keys(baked?.relationships ?? {})).sort();
  }

  static #validateUpdateFields(type, baked, operation) {
    const fields = operation.data[1];

    if (Type.isList(fields) && fields.data.length === 0) {
      Interpreter.raiseMisuseError(
        `unknown operation ${Interpreter.inspect(operation)} for ${type} - {:update, fields} names at least one field`,
      );
    }

    const updateFields = Model.#updateFields(baked);
    const asked = Type.isList(fields) ? fields.data : [fields];

    const unknown = asked.find(
      (field) => !Type.isAtom(field) || !updateFields.includes(field.value),
    );

    if (unknown !== undefined) {
      const described =
        updateFields.length === 0
          ? "it has no field an update sets"
          : `the fields an update sets are ${updateFields.map((name) => `:${name}`).join(", ")}`;

      Interpreter.raiseMisuseError(
        `unknown field ${Interpreter.inspect(unknown)} in ${Interpreter.inspect(operation)} for ${type} - ${described}`,
      );
    }
  }
}
