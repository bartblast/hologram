"use strict";

import {
  JSDOM,
  assert,
  compileInScriptElement,
  compileInTestRealm,
  defineRuntimeGlobals,
} from "./support/helpers.mjs";

import {VirtualConsole} from "../../assets/node_modules/jsdom/lib/api.js";

import App from "../../assets/js/app.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import ScriptEvaluator from "../../assets/js/script_evaluator.mjs";
import TrustedTypes from "../../assets/js/trusted_types.mjs";

defineRuntimeGlobals();

// The real compile runs the code in a script element, which needs a document that runs scripts.
// Its results come from jsdom's own realm, so the cases here compare primitives only.
describe("ScriptEvaluator", () => {
  describe("compile()", () => {
    let originalDocument, originalNonce, originalWindow, scriptWindow;

    beforeEach(() => {
      originalDocument = globalThis.document;
      originalNonce = App.cspNonce;
      originalWindow = globalThis.window;

      scriptWindow = new JSDOM("", {
        url: "http://localhost",
        runScripts: "dangerously",
      }).window;

      globalThis.document = scriptWindow.document;
      globalThis.window = scriptWindow;

      ScriptEvaluator.compile = compileInScriptElement;
    });

    afterEach(() => {
      ScriptEvaluator.compile = compileInTestRealm;

      App.cspNonce = originalNonce;
      globalThis.document = originalDocument;
      globalThis.window = originalWindow;
    });

    it("returns a function running the code with its parameters in scope", () => {
      const fun = ScriptEvaluator.compile(
        "return context + Type + Interpreter;",
      );

      assert.equal(fun(1, 2, 3), 6);
    });

    it("gives the script element the document's nonce", () => {
      App.cspNonce = "R4nd0mN0nce";

      const head = scriptWindow.document.head;
      const appendChild = head.appendChild.bind(head);
      const appendedElements = [];

      head.appendChild = (element) => {
        appendedElements.push(element);
        return appendChild(element);
      };

      ScriptEvaluator.compile("return 1;");

      assert.equal(appendedElements.length, 1);
      assert.equal(appendedElements[0].nonce, "R4nd0mN0nce");
    });

    it("assigns the script element's code through the Trusted Types policy", () => {
      const assignedCode = [];

      TrustedTypes.cachedPolicy = undefined;

      globalThis.trustedTypes = {
        createPolicy: (_name, rules) => ({
          createScript: (code) => {
            assignedCode.push(code);
            return rules.createScript(code);
          },
        }),
      };

      let fun;

      try {
        fun = ScriptEvaluator.compile("return 21 + 21;");
      } finally {
        delete globalThis.trustedTypes;
        TrustedTypes.cachedPolicy = undefined;
      }

      assert.equal(fun(), 42);
      assert.equal(assignedCode.length, 1);
      assert.include(assignedCode[0], "return 21 + 21;");
    });

    it("gives the script element no nonce when the document has none", () => {
      App.cspNonce = null;

      const head = scriptWindow.document.head;
      const appendChild = head.appendChild.bind(head);
      const appendedElements = [];

      head.appendChild = (element) => {
        appendedElements.push(element);
        return appendChild(element);
      };

      assert.equal(ScriptEvaluator.compile("return 1;")(), 1);
      assert.equal(appendedElements.length, 1);
      assert.equal(appendedElements[0].nonce, "");
    });

    it("leaves no script element and no window property behind", () => {
      ScriptEvaluator.compile("return 1;");

      try {
        ScriptEvaluator.compile("return 1 +;");
      } catch {
        // Thrown to the caller, as a case below asserts.
      }

      assert.equal(scriptWindow.document.querySelectorAll("script").length, 0);
      assert.notProperty(scriptWindow, ScriptEvaluator.SLOT);
    });

    it("throws an error the code raises to the caller", () => {
      const fun = ScriptEvaluator.compile('throw new Error("raised in code");');

      assert.throws(() => fun(), "raised in code");
    });

    // The error comes from the document's realm, so it is checked by name rather than by class.
    it("throws a syntax error to the caller", () => {
      let thrown = null;

      try {
        ScriptEvaluator.compile("return 1 +;");
      } catch (error) {
        thrown = error;
      }

      assert.equal(thrown.name, "SyntaxError");
      assert.equal(thrown.message, "Unexpected token ';'");
    });

    // The runtime reports uncaught errors from a window listener, and an error thrown to the
    // caller is not uncaught.
    it("keeps a syntax error from reaching the window's other error listeners", () => {
      let reached = false;
      const listener = () => (reached = true);

      scriptWindow.addEventListener("error", listener);

      try {
        ScriptEvaluator.compile("return 1 +;");
      } catch {
        // Thrown to the caller, as the previous case asserts.
      }

      scriptWindow.removeEventListener("error", listener);

      assert.isFalse(reached);
    });

    // An error event nobody cancels is reported to the console as uncaught.
    it("keeps a syntax error out of the console", () => {
      const virtualConsole = new VirtualConsole();
      const reportedErrors = [];

      virtualConsole.on("jsdomError", (error) => reportedErrors.push(error));

      const consoleWindow = new JSDOM("", {
        runScripts: "dangerously",
        url: "http://localhost",
        virtualConsole,
      }).window;

      globalThis.document = consoleWindow.document;
      globalThis.window = consoleWindow;

      try {
        ScriptEvaluator.compile("return 1 +;");
      } catch {
        // Thrown to the caller, as a previous case asserts.
      }

      assert.deepStrictEqual(reportedErrors, []);
    });

    // A document that runs no scripts stands in for a policy refusing the element: either way the
    // script runs nothing and no error event is raised.
    it("throws when the script element runs nothing", () => {
      const refusingWindow = new JSDOM("", {url: "http://localhost"}).window;

      globalThis.document = refusingWindow.document;
      globalThis.window = refusingWindow;

      assert.throws(
        () => ScriptEvaluator.compile("return 1;"),
        HologramRuntimeError,
        "JavaScript code could not be run: the document's Content Security Policy refused the script element running it",
      );
    });
  });
});
