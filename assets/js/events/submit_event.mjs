"use strict";

import Type from "../type.mjs";

const textDecoder = new TextDecoder("utf-8", {ignoreBOM: true});
const textEncoder = new TextEncoder();

export default class SubmitEvent {
  static isDefaultAllowed = false;

  static buildOperationParam(event) {
    const form = event.target;
    const entries = [...new FormData(form).entries()];
    const checkboxNames = $.#checkedCheckboxNames(form, entries);

    const mapData = entries.map(([name, value]) => {
      if (checkboxNames.has(name)) {
        // Note: FormData only includes checked checkboxes
        // Since this name appears in FormData, its checkbox is checked
        return [Type.bitstring(name), Type.boolean(true)];
      }

      return [Type.bitstring(name), Type.bitstring(value)];
    });

    return Type.map(mapData);
  }

  static isEventIgnored(_event) {
    return false;
  }

  // The names whose entry comes from a checked checkbox. FormData doesn't say which control added an
  // entry, and holds names no control has, like an input's dirname entry, so a name counts only
  // when one control of the form has it, a checked checkbox, and the name has one entry, holding
  // that checkbox's value. Controls sharing a name, like a checkbox group or a hidden input paired
  // with a checkbox, keep their values, and so do entries a dirname, a form-associated custom
  // element or a formdata listener adds under a checkbox's name. The controls are read through the
  // prototype's getter, since a control named "elements" shadows form.elements.
  static #checkedCheckboxNames(form, entries) {
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

    // FormData values are strings or files, never null
    const valuesByName = new Map();

    for (const [name, value] of entries) {
      valuesByName.set(name, valuesByName.has(name) ? null : value);
    }

    const names = new Set();

    for (const [name, value] of valuesByName) {
      const element = elementsByName.get(name);

      if (
        element?.localName === "input" &&
        element.type === "checkbox" &&
        element.checked &&
        $.#toUSVString(element.value) === value
      ) {
        names.add(name);
      }
    }

    return names;
  }

  // FormData holds names and values as USV strings, with each lone surrogate replaced by U+FFFD, so
  // the control's own strings are converted the same way before they're compared. The decoder
  // ignores BOMs, so a leading U+FEFF stays, as it does in FormData.
  static #toUSVString(string) {
    return textDecoder.decode(textEncoder.encode(string));
  }
}

const $ = SubmitEvent;
