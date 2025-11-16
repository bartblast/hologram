"use strict";

import Bitstring from "../bitstring.mjs";
import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

const Erlang_Re = {
  // Start compile/1
  "compile/1": (regexp) => {
    const options = Type.list([]);
    return Erlang_Re["compile/2"](regexp, options);
  },
  // End compile/1
  // Deps: [:re.compile/2]

  // Start compile/2
  "compile/2": (regexp, options) => {
    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a list"),
      );
    }

    // Convert regexp to string
    let pattern;
    if (Type.isBinary(regexp)) {
      Bitstring.maybeSetBytesFromText(regexp);
      pattern = new TextDecoder("utf-8").decode(regexp.bytes);
    } else if (Type.isList(regexp)) {
      // Convert char list to string
      const chars = regexp.data.map((elem) => {
        if (!Type.isInteger(elem)) {
          Interpreter.raiseArgumentError("argument error");
        }
        return String.fromCharCode(Number(elem.value));
      });
      pattern = chars.join("");
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or iolist"),
      );
    }

    // Parse options
    let flags = "";
    let unicode = false;
    let caseless = false;
    let multiline = false;
    let dotall = false;

    for (const option of options.data) {
      if (Type.isAtom(option)) {
        const value = option.value;
        switch (value) {
          case "unicode":
            unicode = true;
            flags += "u";
            break;
          case "caseless":
            caseless = true;
            flags += "i";
            break;
          case "multiline":
            multiline = true;
            flags += "m";
            break;
          case "dotall":
            dotall = true;
            flags += "s";
            break;
          case "global":
            flags += "g";
            break;
          case "extended":
            // Extended mode (ignore whitespace) - not directly supported in JS
            break;
          default:
            // Ignore unknown options
            break;
        }
      }
    }

    try {
      // Remove duplicate flags
      flags = [...new Set(flags)].join("");
      const regex = new RegExp(pattern, flags);

      // Return compiled regex in opaque format
      return Type.tuple([
        Type.atom("ok"),
        Type.tuple([
          Type.atom("re_compiled_pattern"),
          Type.bitstring(new TextEncoder().encode(pattern), 0),
          Type.bitstring(new TextEncoder().encode(flags), 0),
        ]),
      ]);
    } catch (error) {
      return Type.tuple([
        Type.atom("error"),
        Type.tuple([
          Type.bitstring(new TextEncoder().encode(error.message), 0),
          Type.integer(0),
        ]),
      ]);
    }
  },
  // End compile/2
  // Deps: []

  // Start inspect/2
  "inspect/2": (mp, item) => {
    if (!Type.isTuple(mp) || mp.data.length !== 3) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a compiled regular expression"),
      );
    }

    if (!Type.isAtom(item)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not an atom"),
      );
    }

    const marker = mp.data[0];
    if (!Type.isAtom(marker) || marker.value !== "re_compiled_pattern") {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a compiled regular expression"),
      );
    }

    const patternBinary = mp.data[1];
    const flagsBinary = mp.data[2];

    switch (item.value) {
      case "source":
        return Type.tuple([Type.atom("ok"), patternBinary]);
      case "options": {
        // Convert flags back to options list
        Bitstring.maybeSetBytesFromText(flagsBinary);
        const flagsStr = new TextDecoder("utf-8").decode(flagsBinary.bytes);
        const optionsList = [];

        if (flagsStr.includes("i")) optionsList.push(Type.atom("caseless"));
        if (flagsStr.includes("m")) optionsList.push(Type.atom("multiline"));
        if (flagsStr.includes("s")) optionsList.push(Type.atom("dotall"));
        if (flagsStr.includes("u")) optionsList.push(Type.atom("unicode"));
        if (flagsStr.includes("g")) optionsList.push(Type.atom("global"));

        return Type.tuple([Type.atom("ok"), Type.list(optionsList)]);
      }
      default:
        return Type.tuple([Type.atom("error"), Type.atom("invalid_item")]);
    }
  },
  // End inspect/2
  // Deps: []

  // Start run/3
  "run/3": (subject, regexp, options) => {
    if (!Type.isList(options)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(3, "not a list"),
      );
    }

    // Convert subject to string
    let subjectStr;
    if (Type.isBinary(subject)) {
      Bitstring.maybeSetBytesFromText(subject);
      subjectStr = new TextDecoder("utf-8").decode(subject.bytes);
    } else if (Type.isList(subject)) {
      const chars = subject.data.map((elem) => {
        if (!Type.isInteger(elem)) {
          Interpreter.raiseArgumentError("argument error");
        }
        return String.fromCharCode(Number(elem.value));
      });
      subjectStr = chars.join("");
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a binary or iolist"),
      );
    }

    // Get regex pattern
    let pattern;
    let flags = "";

    if (Type.isBinary(regexp) || Type.isList(regexp)) {
      // Compile the regexp first
      const compileResult = Erlang_Re["compile/2"](regexp, Type.list([]));
      if (Type.isTuple(compileResult) && compileResult.data[0].value === "ok") {
        const compiled = compileResult.data[1];
        const patternBinary = compiled.data[1];
        const flagsBinary = compiled.data[2];

        Bitstring.maybeSetBytesFromText(patternBinary);
        pattern = new TextDecoder("utf-8").decode(patternBinary.bytes);

        Bitstring.maybeSetBytesFromText(flagsBinary);
        flags = new TextDecoder("utf-8").decode(flagsBinary.bytes);
      } else {
        return compileResult; // Return error from compile
      }
    } else if (Type.isTuple(regexp)) {
      const marker = regexp.data[0];
      if (Type.isAtom(marker) && marker.value === "re_compiled_pattern") {
        const patternBinary = regexp.data[1];
        const flagsBinary = regexp.data[2];

        Bitstring.maybeSetBytesFromText(patternBinary);
        pattern = new TextDecoder("utf-8").decode(patternBinary.bytes);

        Bitstring.maybeSetBytesFromText(flagsBinary);
        flags = new TextDecoder("utf-8").decode(flagsBinary.bytes);
      } else {
        Interpreter.raiseArgumentError("argument error");
      }
    } else {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a valid regular expression"),
      );
    }

    // Parse run options
    let capture = "all"; // all, all_but_first, first, none, all_names
    let captureType = "index"; // index, list, binary
    let global = flags.includes("g");

    for (const option of options.data) {
      if (Type.isAtom(option)) {
        const value = option.value;
        switch (value) {
          case "global":
            global = true;
            break;
          default:
            break;
        }
      } else if (Type.isTuple(option) && option.data.length === 2) {
        const key = option.data[0];
        const value = option.data[1];

        if (Type.isAtom(key)) {
          switch (key.value) {
            case "capture":
              if (Type.isAtom(value)) {
                capture = value.value;
              }
              break;
            case "return":
              if (Type.isAtom(value)) {
                captureType = value.value;
              }
              break;
            default:
              break;
          }
        }
      }
    }

    try {
      // Ensure global flag is set if global option is specified
      if (global && !flags.includes("g")) {
        flags += "g";
      }

      const regex = new RegExp(pattern, flags);

      if (global) {
        // Find all matches
        const matches = [...subjectStr.matchAll(regex)];

        if (matches.length === 0) {
          return Type.atom("nomatch");
        }

        const results = matches.map((match) => {
          const captures = [];

          if (capture === "all") {
            for (let i = 0; i < match.length; i++) {
              if (match[i] !== undefined) {
                const start = match.index + (i > 0 ? subjectStr.substring(match.index).indexOf(match[i]) : 0);
                const length = match[i].length;

                if (captureType === "index") {
                  captures.push(Type.tuple([Type.integer(start), Type.integer(length)]));
                } else if (captureType === "binary") {
                  const bytes = new TextEncoder().encode(match[i]);
                  captures.push(Type.bitstring(bytes, 0));
                } else if (captureType === "list") {
                  const chars = [...match[i]].map((c) =>
                    Type.integer(c.charCodeAt(0)),
                  );
                  captures.push(Type.list(chars));
                }
              } else {
                if (captureType === "index") {
                  captures.push(Type.tuple([Type.integer(-1), Type.integer(0)]));
                } else {
                  captures.push(Type.list([]));
                }
              }
            }
          } else if (capture === "first" || capture === "all_but_first") {
            const startIdx = capture === "first" ? 0 : 1;
            const idx = startIdx < match.length ? startIdx : 0;

            if (match[idx] !== undefined) {
              const start = match.index;
              const length = match[idx].length;

              if (captureType === "index") {
                return Type.tuple([Type.integer(start), Type.integer(length)]);
              } else if (captureType === "binary") {
                const bytes = new TextEncoder().encode(match[idx]);
                return Type.bitstring(bytes, 0);
              } else if (captureType === "list") {
                const chars = [...match[idx]].map((c) =>
                  Type.integer(c.charCodeAt(0)),
                );
                return Type.list(chars);
              }
            }
          }

          return Type.list(captures);
        });

        return Type.tuple([Type.atom("match"), Type.list(results)]);
      } else {
        // Find first match
        const match = regex.exec(subjectStr);

        if (!match) {
          return Type.atom("nomatch");
        }

        const captures = [];

        if (capture === "all") {
          for (let i = 0; i < match.length; i++) {
            if (match[i] !== undefined) {
              const start = i === 0 ? match.index : match.index + subjectStr.substring(match.index).indexOf(match[i]);
              const length = match[i].length;

              if (captureType === "index") {
                captures.push(Type.tuple([Type.integer(start), Type.integer(length)]));
              } else if (captureType === "binary") {
                const bytes = new TextEncoder().encode(match[i]);
                captures.push(Type.bitstring(bytes, 0));
              } else if (captureType === "list") {
                const chars = [...match[i]].map((c) =>
                  Type.integer(c.charCodeAt(0)),
                );
                captures.push(Type.list(chars));
              }
            } else {
              if (captureType === "index") {
                captures.push(Type.tuple([Type.integer(-1), Type.integer(0)]));
              } else {
                captures.push(Type.list([]));
              }
            }
          }

          return Type.tuple([Type.atom("match"), Type.list(captures)]);
        } else if (capture === "first") {
          const start = match.index;
          const length = match[0].length;

          if (captureType === "index") {
            return Type.tuple([
              Type.atom("match"),
              Type.list([Type.tuple([Type.integer(start), Type.integer(length)])]),
            ]);
          } else if (captureType === "binary") {
            const bytes = new TextEncoder().encode(match[0]);
            return Type.tuple([Type.atom("match"), Type.list([Type.bitstring(bytes, 0)])]);
          } else if (captureType === "list") {
            const chars = [...match[0]].map((c) =>
              Type.integer(c.charCodeAt(0)),
            );
            return Type.tuple([Type.atom("match"), Type.list([Type.list(chars)])]);
          }
        } else if (capture === "all_but_first") {
          for (let i = 1; i < match.length; i++) {
            if (match[i] !== undefined) {
              const start = match.index + subjectStr.substring(match.index).indexOf(match[i]);
              const length = match[i].length;

              if (captureType === "index") {
                captures.push(Type.tuple([Type.integer(start), Type.integer(length)]));
              } else if (captureType === "binary") {
                const bytes = new TextEncoder().encode(match[i]);
                captures.push(Type.bitstring(bytes, 0));
              } else if (captureType === "list") {
                const chars = [...match[i]].map((c) =>
                  Type.integer(c.charCodeAt(0)),
                );
                captures.push(Type.list(chars));
              }
            } else {
              if (captureType === "index") {
                captures.push(Type.tuple([Type.integer(-1), Type.integer(0)]));
              } else {
                captures.push(Type.list([]));
              }
            }
          }

          return Type.tuple([Type.atom("match"), Type.list(captures)]);
        }
      }
    } catch (error) {
      return Type.tuple([
        Type.atom("error"),
        Type.bitstring(new TextEncoder().encode(error.message), 0),
      ]);
    }

    return Type.atom("nomatch");
  },
  // End run/3
  // Deps: [:re.compile/2]
};

export default Erlang_Re;
