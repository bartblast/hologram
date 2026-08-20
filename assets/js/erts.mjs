"use strict";

import ApplicationEnv from "./erts/application_env.mjs";
import BinaryPatternRegistry from "./erts/binary_pattern_registry.mjs";
import CallStack from "./erts/call_stack.mjs";
import NativeObjectRegistry from "./erts/native_object_registry.mjs";
import NodeTable from "./erts/node_table.mjs";
import PromiseRegistry from "./erts/promise_registry.mjs";
import RegexEngine from "./erts/regex/regex_engine.mjs";
import RegexPatternRegistry from "./erts/regex_pattern_registry.mjs";
import Sequence from "./common/sequence.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";

export default class ERTS {
  // The PID of the init process (#PID<0.0.0>), which is the first process started
  // by the Erlang runtime.
  // Lazy getter to avoid circular dependency with Type.
  static #initPid = null;
  static get INIT_PID() {
    if (!$.#initPid) {
      $.#initPid = Type.pid(NodeTable.CLIENT_NODE, [0, 0, 0], "client");
    }
    return $.#initPid;
  }

  // Lazy for the same reason INIT_PID is - see above. These were module-scope constants, which
  // made erts unloadable whenever a bundle's import order reached it before type.
  static #refKeyValue = null;

  static get #REF_KEY() {
    if (!$.#refKeyValue) {
      $.#refKeyValue = Type.encodeMapKey(Type.atom("ref"));
    }

    return $.#refKeyValue;
  }

  static #taskMfaValue = null;

  static get #TASK_MFA() {
    if (!$.#taskMfaValue) {
      $.#taskMfaValue = Type.tuple([
        Type.alias("Hologram.JS"),
        Type.atom("call"),
        Type.integer(3),
      ]);
    }

    return $.#taskMfaValue;
  }

  // Version of each OTP application whose modules the bundle carries, keyed by
  // application name - what :application.get_key/2 answers :vsn from. Assigned
  // by the runtime bundle from compiler-emitted data, and empty when client
  // stacktraces are disabled, which also emits no per-module app metadata.
  static appVersions = {};

  static applicationEnv = ApplicationEnv;

  static binaryPatternRegistry = BinaryPatternRegistry;

  // Shadow call stack backing Elixir stacktraces. Ported Erlang functions reach it through this
  // facade, since their bodies are extracted per-MFA into the bundle and can't carry imports.
  static callStack = CallStack;

  static ets = {};

  // TODO: add scoped lifecycle / GC for native object registry.
  // Entries are never released because registered objects may be global (e.g. stored on window)
  // and must survive page navigation.
  static nativeObjectRegistry = NativeObjectRegistry;

  // Entries are released via takePromise() when Task.await/1 is called.
  static promiseRegistry = PromiseRegistry;

  // Lazy getter to avoid referencing the class binding while the module
  // cycle erts -> regex engine -> bitstring -> erts is still initializing.
  static get regex() {
    return RegexEngine;
  }

  static regexPatternRegistry = RegexPatternRegistry;

  // Sequence for anonymous function `uniq` field.
  // Used to derive fun_info/1 fields: index, new_index, uniq, new_uniq.
  // In Erlang, index/new_index are per-module indices, and uniq/new_uniq are
  // calculated from compiled code; here we use a global sequence for all.
  static funSequence = new Sequence();

  static graphemeSegmenter = new Intl.Segmenter(undefined, {
    granularity: "grapheme",
  });

  // Where each module's code lives, keyed by module name - the application that
  // owns it and its source file, which stacktrace frames render. Filled per
  // bundle, so the runtime and each page contribute their own modules, and left
  // empty when client stacktraces are disabled.
  static moduleMetadata = {};

  static nodeTable = NodeTable;
  static referenceSequence = new Sequence();
  static uniqueIntegerSequence = new Sequence();
  static utf8Decoder = new TextDecoder("utf-8", {fatal: true});
  static utf8Encoder = new TextEncoder();

  // Mirrors the format_error_map/3 that erl_erts_errors, erl_kernel_errors and erl_stdlib_errors
  // each define identically: fragments name argument positions in order starting at the given
  // number, an "" fragment leaves its position unnamed, and a {general: fragment} fragment names
  // the call as a whole instead of an argument. Fragments are expanded by the calling module's own
  // expand_error/1, which is the only part the three OTP copies differ in. The entries accumulate
  // into the given boxed map.
  static formatErrorMap(fragments, argumentNumber, map, expandError) {
    const result = Type.cloneMap(map);
    let currentArgumentNumber = argumentNumber;

    for (const fragment of fragments) {
      if (fragment === "") {
        ++currentArgumentNumber;
        continue;
      }

      if (typeof fragment === "object" && "general" in fragment) {
        const generalKey = Type.atom("general");

        result.data[Type.encodeMapKey(generalKey)] = [
          generalKey,
          expandError(fragment.general),
        ];

        continue;
      }

      const key = Type.integer(currentArgumentNumber);
      result.data[Type.encodeMapKey(key)] = [key, expandError(fragment)];

      ++currentArgumentNumber;
    }

    return result;
  }

  // Takes in the modules of one bundle. Each bundle registers its own, so the
  // runtime's modules and every page's modules end up in the same table.
  static registerModuleMetadata(entries) {
    Object.assign($.moduleMetadata, entries);
  }

  static registerNativeObject(object) {
    const ref = $.uniqueReference();
    $.nativeObjectRegistry.put(ref, object);

    return ref;
  }

  // Each call creates a new Task with a unique ref, even for the same Promise.
  // This is intentional: multiple Task handles can independently await the same Promise.
  static registerPromise(promise) {
    const ref = $.uniqueReference();
    $.promiseRegistry.put(ref, promise);

    return Type.taskStruct($.#TASK_MFA, $.INIT_PID, ref);
  }

  static takePromise(taskStruct) {
    const ref = taskStruct.data[$.#REF_KEY][1];
    const promise = $.promiseRegistry.get(ref);

    if (promise !== null) {
      $.promiseRegistry.delete(ref);
    }

    return promise;
  }

  static uniqueReference() {
    const node = $.nodeTable.CLIENT_NODE;
    const creation = 0;

    // TODO: implement ID words similarly to how it's done in Erlang
    const idWords = [
      Utils.randomUint32(),
      Utils.randomUint32(),
      $.referenceSequence.next(),
    ];

    return Type.reference(node, creation, idWords);
  }
}

const $ = ERTS;
