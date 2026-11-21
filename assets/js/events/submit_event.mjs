"use strict";

import Type from "../type.mjs";

const textDecoder = new TextDecoder("utf-8", {ignoreBOM: true});
const textEncoder = new TextEncoder();

export default class SubmitEvent {
  static isDefaultAllowed = false;

  static buildEventParam(event) {
    const form = event.target;

    // Read before FormData is built: a formdata listener runs inside its constructor and can change
    // the checkboxes after their entries are in.
    const checkboxValues = $.#loneCheckboxEntryValues(form);

    const entries = [...new FormData(form).entries()];
    const checkboxNames = $.#checkboxEntryNames(checkboxValues, entries);

    const mapData = entries.map(([name, value]) => {
      if (checkboxNames.has(name)) {
        // Note: FormData only includes checked checkboxes
        // Since this name appears in FormData, its checkbox was checked when FormData was built
        return [Type.bitstring(name), Type.boolean(true)];
      }

      return [Type.bitstring(name), Type.bitstring(value)];
    });

    return Type.map(mapData);
  }

  static isEventIgnored(_event) {
    return false;
  }

  // The names whose entry comes from a checkbox. FormData doesn't say which control added an entry,
  // and holds names no control has, like an input's dirname entry, so a name counts only when it
  // has one entry, holding the value of the checkbox that has the name to itself. Controls sharing
  // a name, like a checkbox group or a hidden input paired with a checkbox, keep their values, and
  // so do entries a dirname, a form-associated custom element or a formdata listener adds under a
  // checkbox's name.
  static #checkboxEntryNames(checkboxValues, entries) {
    // FormData values are strings or files, never null
    const valuesByName = new Map();

    for (const [name, value] of entries) {
      valuesByName.set(name, valuesByName.has(name) ? null : value);
    }

    const names = new Set();

    for (const [name, value] of valuesByName) {
      if (checkboxValues.get(name) === value) {
        names.add(name);
      }
    }

    return names;
  }

  // The value of each checkbox that adds an entry and shares its name with no other control of the
  // form, by name. A checkbox adds an entry when it's named, checked, enabled (a disabled fieldset
  // disables it too) and outside a datalist. The controls are read through the prototype's getter,
  // since a control named "elements" shadows form.elements.
  static #loneCheckboxEntryValues(form) {
    const elements = Object.getOwnPropertyDescriptor(
      HTMLFormElement.prototype,
      "elements",
    ).get.call(form);

    const elementsByName = new Map();

    for (const element of elements) {
      const nameAttr = element.getAttribute("name");
      const name = nameAttr === null ? null : $.#toUSVString(nameAttr);

      elementsByName.set(name, elementsByName.has(name) ? null : element);
    }

    const values = new Map();

    for (const [name, element] of elementsByName) {
      if (
        name !== null &&
        name !== "" &&
        element?.localName === "input" &&
        element.type === "checkbox" &&
        element.checked &&
        !element.matches(":disabled") &&
        element.closest("datalist") === null
      ) {
        values.set(name, $.#toUSVString(element.value));
      }
    }

    return values;
  }

  // FormData holds names and values as USV strings, with each lone surrogate replaced by U+FFFD, so
  // the control's own strings are converted the same way before they're compared. The decoder
  // ignores BOMs, so a leading U+FEFF stays, as it does in FormData.
  static #toUSVString(string) {
    return textDecoder.decode(textEncoder.encode(string));
  }
}

const $ = SubmitEvent;
