"use strict";

// Under caseless matching PCRE2 widens each of these categories to all cased
// letters, by category rather than by case folding.
const CASED_LETTER_CATEGORIES = new Set(["Ll", "Lt", "Lu"]);

// PCRE2 special property names whose sets need more than one JS class atom,
// so a negated one can't be written as a single \P escape.
const COMPOUND_PROPERTY_NAMES = new Set(["Xan", "Xps", "Xsp", "Xuc", "Xwd"]);

const SCRIPT_KEYS = new Set(["Script", "Script_Extensions", "sc", "scx"]);

// Scripts PCRE2 matches by Script even when written as a script extension,
// where JS Script_Extensions gives a smaller set.
const SCRIPT_ONLY_NAMES = new Set([
  "Common",
  "Inherited",
  "Qaai",
  "Zinh",
  "Zyyy",
]);

export function isCompoundUnicodeProperty(name) {
  return COMPOUND_PROPERTY_NAMES.has(name);
}

// Returns the JS u-mode class atoms for a PCRE2 Unicode property name, as
// strings that join into class content with the same set. A bare name that
// JS doesn't know as a property of its own, like a category or a binary
// property, is matched as a script extension, following PCRE2, except the
// Common and Inherited scripts, which PCRE2 always matches by script.
export function unicodePropertyAtoms(name, caseless) {
  switch (name) {
    case "Any":
      return ["\\p{Any}"];

    // Xan matches alphanumeric chars
    case "Xan":
      return ["\\p{L}", "\\p{N}"];

    // Xps and Xsp both match Perl space chars: white space plus the
    // Mongolian vowel separator, which PCRE2 keeps as horizontal space
    case "Xps":
    case "Xsp":
      return ["\\p{White_Space}", "\\u180e"];

    // Xuc matches chars expressible as universal character names
    case "Xuc":
      return ["$", "@", "`", "\\u{a0}-\\u{d7ff}", "\\u{e000}-\\u{10ffff}"];

    // Xwd matches word chars: alphanumerics, nonspacing marks and connector
    // punctuation, the underscore among them
    case "Xwd":
      return ["\\p{L}", "\\p{N}", "\\p{Mn}", "\\p{Pc}"];

    default:
      if (caseless && CASED_LETTER_CATEGORIES.has(name)) return ["\\p{LC}"];

      return [`\\p{${resolveJsPropertyName(name)}}`];
  }
}

function resolveJsPropertyName(name) {
  // PCRE2 takes a colon as well as an equals sign between key and value
  const separatorIndex = name.search(/[:=]/);

  const [key, value] =
    separatorIndex === -1
      ? [null, name]
      : [name.slice(0, separatorIndex), name.slice(separatorIndex + 1)];

  if ((key === null || SCRIPT_KEYS.has(key)) && SCRIPT_ONLY_NAMES.has(value)) {
    return `Script=${value}`;
  }

  // TODO: resolve names with PCRE2 rules instead of JS ones (loose matching,
  // L&, Bidi_Class, rejecting JS-only names like Letter or gc=Lu)
  const candidates =
    key !== null ? [`${key}=${value}`] : [name, `Script_Extensions=${name}`];

  for (const candidate of candidates) {
    try {
      new RegExp(`\\p{${candidate}}`, "u");

      return candidate;
    } catch {
      // Try the next property name form
    }
  }

  throw new Error(`unsupported Unicode property: ${name}`);
}
