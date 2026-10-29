"use strict";

import App from "./app.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import TrustedTypes from "./trusted_types.mjs";

// Turns JavaScript code given as a string into a function, without eval() or new Function(), which a
// Content Security Policy without 'unsafe-eval' blocks. The code is placed in a script element the
// runtime creates, which such a policy allows: the element carries the document's nonce, and under
// 'strict-dynamic' a script created by a trusted one is trusted too.
//
// Only the parse happens in the script element. The function it defines is called by the caller,
// so what the code throws, or the promise an async body returns, reaches the caller as it would
// from a direct call.
export default class ScriptEvaluator {
  // The name of the window property the script element leaves its function under. A window
  // property rather than a property of a runtime object, since the script runs with the window as
  // its global and the slot has to be reachable from there.
  static SLOT = "__hologramEvaluatedFunction";

  // Returns the function whose body is the given code, taking context, Type and Interpreter as its
  // parameters.
  //
  // A classic inline script runs synchronously the moment it is inserted, so the function is there
  // on the next line. A script that fails to parse runs nothing and reports its error on the window
  // instead of throwing here, so the error is caught there and thrown to the caller. The listener
  // runs in the capture phase and stops the event, so the runtime's own uncaught error handler
  // never sees an error the caller is about to receive.
  //
  // A script the document's Content Security Policy refuses runs nothing and raises no error
  // event, the browser only reports the violation in the console, so a missing function with no
  // error is that refusal.
  static compile(code) {
    const script = document.createElement("script");

    if (App.cspNonce !== null) {
      script.nonce = App.cspNonce;
    }

    // Placed as text rather than as markup, so no HTML parsing happens and code holding "</script>"
    // cannot end the element.
    script.textContent = TrustedTypes.script(
      `window.${$.SLOT} = function (context, Type, Interpreter) {\n${code}\n};`,
    );

    let parseError = null;

    const onError = (event) => {
      parseError = event.error;
      event.preventDefault();
      event.stopImmediatePropagation();
    };

    window.addEventListener("error", onError, {capture: true});
    document.head.appendChild(script);
    window.removeEventListener("error", onError, {capture: true});

    script.remove();

    const fun = window[$.SLOT];
    delete window[$.SLOT];

    if (parseError !== null) {
      throw parseError;
    }

    if (fun === undefined) {
      throw new HologramRuntimeError(
        "JavaScript code could not be run: the document's Content Security Policy refused the script element running it",
      );
    }

    return fun;
  }
}

const $ = ScriptEvaluator;
