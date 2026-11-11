"use strict";

import Interpreter from "./interpreter.mjs";
import Type from "./type.mjs";

// What a message about a declared ref nothing renders advises for a lookup inside an action.
const ACTION_LOOKUP_ADVICE =
  "An element the action's own state change renders is on the page only once the action " +
  "returns, so look it up in an action chained with put_action/2";

// How close a ref name has to be to one the page declares to be suggested, as Elixir's own
// did-you-mean suggestions take it.
const SUGGESTION_THRESHOLD = 0.77;

// The elements the last finished render put on the page under each ref, by the ref's encoded map
// key, and the page they belong to. They are replaced once a render's patch has given every
// rendered element its live node, so a render that raised leaves the last finished render's
// elements in place. A navigation clears them before anything of the destination exists, so a
// lookup in between finds nothing rather than an element of the page being left.
export default class ElementRefRegistry {
  // Made public to make tests easier
  static elements = new Map();

  // Made public to make tests easier
  static pageModule = null;

  // Made public to make tests easier
  // The literal refs each page renders, as [name, part count] pairs, by the page module's name. Each
  // page's bundle puts its own when it is defined, so the registry holds the names of every page
  // the tab has loaded.
  static pageRefNames = new Map();

  static clear() {
    $.elements = new Map();
    $.pageModule = null;
  }

  // The element rendered under the given ref, or null when nothing is.
  static get(ref) {
    return $.elements.get(Type.encodeMapKey(ref)) ?? null;
  }

  // What a message about a ref nothing is rendered under adds, from the literal refs the current
  // page renders: that a template declares the ref, how many parts refs of its name take, or the
  // closest declared name. A ref only an expression names, like $ref={@input_ref}, is declared by
  // no template, so a miss for one adds nothing. For a declared ref it gives the advice for a
  // lookup inside an action, or the advice passed instead, or none when that is null.
  static missingElementHint(ref, declaredRefAdvice = ACTION_LOOKUP_ADVICE) {
    const name = Type.isAtom(ref) ? ref.value : ref.data[0].value;
    const partCount = Type.isAtom(ref) ? 0 : ref.data.length - 1;
    const names = $.refNames();

    if (
      names.some(
        ([declaredName, count]) => declaredName === name && count === partCount,
      )
    ) {
      const advice = declaredRefAdvice === null ? "" : `. ${declaredRefAdvice}`;

      return (
        " - a template declares the ref, but nothing renders it right now" +
        advice
      );
    }

    const sameName = names.find(([declaredName]) => declaredName === name);

    if (sameName !== undefined) {
      return ` - refs named ${Interpreter.inspect(Type.atom(name))} take ${$.#partsText(sameName[1])} after the name`;
    }

    const closest = names.reduce(
      (best, entry) => {
        const distance = $.#jaroDistance(name, entry[0]);

        return distance >= SUGGESTION_THRESHOLD && distance > best.distance
          ? {distance, entry}
          : best;
      },
      {distance: 0, entry: null},
    );

    return closest.entry === null
      ? ""
      : ` - did you mean ${$.#refPattern(closest.entry)}?`;
  }

  // Puts the literal refs the given page renders, as [name, part count] pairs, by the page module's
  // name.
  static putPageRefNames(pageModuleName, names) {
    $.pageRefNames.set(pageModuleName, names);
  }

  // The literal refs the current page renders, as [name, part count] pairs, or none when no page is
  // shown or its bundle carries none.
  static refNames() {
    return $.pageModule === null
      ? []
      : ($.pageRefNames.get($.pageModule.value) ?? []);
  }

  static replace(elementsByRef, pageModule) {
    $.elements = elementsByRef;
    $.pageModule = pageModule;
  }

  // Based on String.jaro_distance/2, but over code points rather than graphemes, which give the
  // same result for ref names.
  static #jaroDistance(left, right) {
    const leftChars = Array.from(left);
    const rightChars = Array.from(right);

    if (leftChars.length === 0 || rightChars.length === 0) {
      return 0;
    }

    const window = Math.max(
      0,
      Math.floor(Math.max(leftChars.length, rightChars.length) / 2) - 1,
    );

    const leftMatched = leftChars.map(() => false);
    const rightMatched = rightChars.map(() => false);
    let matches = 0;

    leftChars.forEach((char, leftIndex) => {
      const from = Math.max(0, leftIndex - window);
      const to = Math.min(rightChars.length - 1, leftIndex + window);

      for (let rightIndex = from; rightIndex <= to; rightIndex += 1) {
        if (!rightMatched[rightIndex] && rightChars[rightIndex] === char) {
          leftMatched[leftIndex] = true;
          rightMatched[rightIndex] = true;
          matches += 1;
          break;
        }
      }
    });

    if (matches === 0) {
      return 0;
    }

    const leftMatches = leftChars.filter((_char, index) => leftMatched[index]);
    const rightMatches = rightChars.filter(
      (_char, index) => rightMatched[index],
    );

    const transpositions =
      leftMatches.filter((char, index) => char !== rightMatches[index]).length /
      2;

    return (
      (matches / leftChars.length +
        matches / rightChars.length +
        (matches - transpositions) / matches) /
      3
    );
  }

  static #partsText(partCount) {
    switch (partCount) {
      case 0:
        return "no parts";

      case 1:
        return "1 part";

      default:
        return `${partCount} parts`;
    }
  }

  // A declared ref as a template writes it, with its parts left out.
  static #refPattern([name, partCount]) {
    const nameText = Interpreter.inspect(Type.atom(name));

    return partCount === 0
      ? nameText
      : `{${[nameText, ...Array(partCount).fill("...")].join(", ")}}`;
  }
}

const $ = ElementRefRegistry;
