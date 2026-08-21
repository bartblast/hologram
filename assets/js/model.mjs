"use strict";

import Bitstring from "./bitstring.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
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
  static #entries = {};

  // Every relationship of a row is absent from the row itself: a to-many lives in the
  // relationship facts and a to-one behind the reference field, so both are assembled by whoever
  // reads them and handed over here. What no reader asked for stays unasked-for rather than
  // becoming null, which is a different answer.
  static box(type, row, includes = {}) {
    const entry = Model.entry(type);
    const data = [[Type.atom("__struct__"), Type.alias(type)]];

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
          Model.#boxValue(row[referenceField], "uuid"),
        ]);
      }

      data.push([Type.atom(name), includes[name] ?? Model.#notIncluded(name)]);
    }

    return Type.map(data);
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

    entry = {
      attributes: baked.attributes,
      enumValues: baked.enumValues,
      policy: baked.policy,
      relationships: baked.relationships,
      resourceType: baked.resourceType,
      serverOnly: new Set(baked.serverOnly),
    };

    Model.#entries[type] = entry;

    return entry;
  }

  static relationships(type) {
    return Model.entry(type).relationships;
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

      default:
        return Bitstring.toText(value);
    }
  }

  static reset() {
    Model.#entries = {};
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

    return Model.#boxValue(row[name], attributeType);
  }

  static #boxDate(value) {
    const [year, month, day] = value.split("-");

    return Type.map([
      [Type.atom("__struct__"), Type.alias("Date")],
      [Type.atom("calendar"), Type.alias("Calendar.ISO")],
      [Type.atom("day"), Type.integer(day)],
      [Type.atom("month"), Type.integer(month)],
      [Type.atom("year"), Type.integer(year)],
    ]);
  }

  // Every datetime on the wire is UTC, which is what makes them comparable as plain strings in
  // the first place - so the zone is the same one every time rather than something to read.
  static #boxDateTime(value) {
    const match = value.match(
      /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?Z$/,
    );

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

    const microsecond = Type.tuple([
      Type.integer(fraction === "" ? 0 : parseInt(fraction.padEnd(6, "0"), 10)),
      Type.integer(fraction.length),
    ]);

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

  // A label beginning with an uppercase letter names a module, which is stored without the
  // prefix every module atom carries - the same rule the database codec reads labels by.
  static #boxEnum(value) {
    const first = value[0];

    return first >= "A" && first <= "Z" ? Type.alias(value) : Type.atom(value);
  }

  static #boxValue(value, attributeType) {
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
        return Model.#boxEnum(value);

      case "float":
        return Type.float(value);

      case "integer":
        return Type.integer(value);

      default:
        return Type.bitstring(value);
    }
  }

  static #field(struct, name) {
    return struct.data[Type.encodeMapKey(Type.atom(name))][1];
  }

  static #pad(value, width) {
    return String(value).padStart(width, "0");
  }

  static #unboxDate(value) {
    const year = Model.#field(value, "year").value;
    const month = Model.#field(value, "month").value;
    const day = Model.#field(value, "day").value;

    return `${Model.#pad(year, 4)}-${Model.#pad(month, 2)}-${Model.#pad(day, 2)}`;
  }

  // Always six fractional digits, whatever precision the value was written at: the wire carries
  // one spelling per instant, which is what lets these compare as plain strings at all. A value
  // written with fewer digits and left that way would sort before an instant it comes after.
  static #unboxDateTime(value) {
    const microsecond = Model.#field(value, "microsecond");
    const [amount, precision] = microsecond.data.map((part) =>
      Number(part.value),
    );
    const fraction = amount * 10 ** (6 - precision);

    const date = Model.#unboxDate(value);

    const hour = Model.#pad(Model.#field(value, "hour").value, 2);
    const minute = Model.#pad(Model.#field(value, "minute").value, 2);
    const second = Model.#pad(Model.#field(value, "second").value, 2);

    return `${date}T${hour}:${minute}:${second}.${Model.#pad(fraction, 6)}Z`;
  }

  // A module travels as its name without the prefix every module atom carries, a plain atom as
  // it is spelled - the same two cases the label reader tells apart coming the other way.
  static #unboxEnum(value) {
    return Type.isAlias(value)
      ? value.value.replace(/^Elixir\./, "")
      : value.value;
  }

  static #notIncluded(name) {
    return Type.map([
      [Type.atom("__struct__"), Type.alias("Hologram.Entity.NotIncluded")],
      [Type.atom("relationship"), Type.atom(name)],
    ]);
  }
}
