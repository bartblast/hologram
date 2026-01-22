"use strict";

import {
  assert,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "../support/helpers.mjs";

import Erlang_Os from "../../../assets/js/erlang/os.mjs";
import Type from "../../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

// IMPORTANT!
// Each JavaScript test has a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/erlang/os_test.exs
// Always update both together.

describe("Erlang_Os", () => {
  describe("client-side only behavior", () => {
    describe("type/0", () => {
      const type = Erlang_Os["type/0"];

      it("detects macOS via userAgentData", () => {
        sinon
          .stub(globalThis, "navigator")
          .value({userAgentData: {platform: "macOS"}});
        const result = type();

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("unix"), Type.atom("darwin")]),
        );
      });

      it("detects Windows via userAgentData", () => {
        sinon
          .stub(globalThis, "navigator")
          .value({userAgentData: {platform: "Windows"}});
        const result = type();

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("win32"), Type.atom("nt")]),
        );
      });

      it("detects Linux via userAgentData", () => {
        sinon
          .stub(globalThis, "navigator")
          .value({userAgentData: {platform: "Linux"}});
        const result = type();

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("unix"), Type.atom("linux")]),
        );
      });

      it("falls back to platform when userAgentData unavailable", () => {
        sinon
          .stub(globalThis, "navigator")
          .value({userAgentData: undefined, platform: "MacIntel"});
        const result = type();

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("unix"), Type.atom("darwin")]),
        );
      });

      it("falls back to userAgent when platform unavailable", () => {
        sinon.stub(globalThis, "navigator").value({
          userAgentData: undefined,
          platform: "",
          userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)...",
        });
        const result = type();

        assert.deepStrictEqual(
          result,
          Type.tuple([Type.atom("win32"), Type.atom("nt")]),
        );
      });
    });
  });
});
