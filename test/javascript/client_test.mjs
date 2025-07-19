"use strict";

import {
  assert,
  componentRegistryEntryFixture,
  defineGlobalErlangAndElixirModules,
  sinon,
} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();

describe("Client", () => {
  describe("buildCommandPayload()", () => {
    const module = Type.alias("MyComponent");

    const name = Type.atom("my_command");

    const params = Type.map([
      [Type.atom("param_1"), Type.integer(1)],
      [Type.atom("param2"), Type.integer(2)],
    ]);

    const target = Type.bitstring("my_target");

    const command = Type.commandStruct({name, params, target});

    beforeEach(() => {
      ComponentRegistry.clear();
    });

    it("builds command payload when target component is registered", () => {
      const entry = componentRegistryEntryFixture({module: module});
      ComponentRegistry.putEntry(target, entry);

      const result = Client.buildCommandPayload(command);

      const expected = Type.map([
        [Type.atom("module"), module],
        [Type.atom("name"), name],
        [Type.atom("params"), params],
        [Type.atom("target"), target],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("throws error when target component is not registered", () => {
      // Don't register the component, so it will not be found

      assert.throws(
        () => Client.buildCommandPayload(command),
        HologramRuntimeError,
        'invalid command target, there is no component with CID: "my_target"',
      );
    });
  });

  describe("buildPageQueryString()", () => {
    it("returns empty string when params map is empty", () => {
      const params = Type.map();
      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "");
    });

    it("returns query string with single atom param", () => {
      const params = Type.map([[Type.atom("status"), Type.atom("pending")]]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?status=pending");
    });

    it("returns query string with single integer param", () => {
      const params = Type.map([[Type.atom("user_id"), Type.integer(123)]]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?user_id=123");
    });

    it("returns query string with single float param", () => {
      const params = Type.map([[Type.atom("rating"), Type.float(4.5)]]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?rating=4.5");
    });

    it("returns query string with single binary string param", () => {
      const params = Type.map([
        [Type.atom("username"), Type.bitstring("bartblast")],
      ]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?username=bartblast");
    });

    it("returns query string with multiple params separated by ampersands", () => {
      const params = Type.map([
        [Type.atom("status"), Type.atom("pending")],
        [Type.atom("user_id"), Type.integer(123)],
        [Type.atom("rating"), Type.float(4.5)],
        [Type.atom("username"), Type.bitstring("bartblast")],
      ]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(
        result,
        "?status=pending&user_id=123&rating=4.5&username=bartblast",
      );
    });

    it("handles zero integer value", () => {
      const params = Type.map([[Type.atom("count"), Type.integer(0)]]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?count=0");
    });

    it("handles zero float value", () => {
      const params = Type.map([[Type.atom("amount"), Type.float(0.0)]]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?amount=0");
    });

    it("handles empty string value", () => {
      const params = Type.map([[Type.atom("search"), Type.bitstring("")]]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?search=");
    });

    it("handles boolean values (converted to atoms)", () => {
      const params = Type.map([
        [Type.atom("active"), Type.boolean(true)],
        [Type.atom("visible"), Type.boolean(false)],
      ]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?active=true&visible=false");
    });

    it("throws error when param key is not atom", () => {
      const params = Type.map([
        [Type.bitstring("status"), Type.atom("pending")],
      ]);

      assert.throws(
        () => Client.buildPageQueryString(params),
        HologramRuntimeError,
        'invalid param key type (only atom type is allowed), got: "status"',
      );
    });

    it("throws error when param value is tuple", () => {
      const params = Type.map([
        [
          Type.atom("coordinates"),
          Type.tuple([Type.integer(10), Type.integer(20)]),
        ],
      ]);

      assert.throws(
        () => Client.buildPageQueryString(params),
        HologramRuntimeError,
        "invalid param value type (only atom, float, integer and string types are allowed), got: {10, 20}",
      );
    });

    it("throws error when param value is list", () => {
      const params = Type.map([
        [Type.atom("tags"), Type.list([Type.atom("tag1"), Type.atom("tag2")])],
      ]);

      assert.throws(
        () => Client.buildPageQueryString(params),
        HologramRuntimeError,
        "invalid param value type (only atom, float, integer and string types are allowed), got: [:tag1, :tag2]",
      );
    });

    it("throws error when param value is map", () => {
      const params = Type.map([
        [
          Type.atom("metadata"),
          Type.map([[Type.atom("key"), Type.atom("value")]]),
        ],
      ]);

      assert.throws(
        () => Client.buildPageQueryString(params),
        HologramRuntimeError,
        "invalid param value type (only atom, float, integer and string types are allowed), got: %{key: :value}",
      );
    });

    it("throws error when param value is bitstring but not binary", () => {
      const params = Type.map([
        [Type.atom("data"), Type.bitstring([1, 0, 1, 0])],
      ]);

      assert.throws(
        () => Client.buildPageQueryString(params),
        HologramRuntimeError,
        "invalid param value type (only atom, float, integer and string types are allowed), got: <<10::size(4)>>",
      );
    });
  });

  describe("sendCommand()", () => {
    let fetchStub;
    let hologramExecuteActionStub;

    const module = Type.alias("MyComponent");
    const name = Type.atom("my_command");
    const target = Type.bitstring("my_target");

    const params = Type.map([
      [Type.atom("a"), Type.integer(1)],
      [Type.atom("b"), Type.integer(2)],
    ]);

    const command = Type.commandStruct({
      name: name,
      params: params,
      target: target,
    });

    beforeEach(() => {
      ComponentRegistry.clear();

      const entry = componentRegistryEntryFixture({module: module});
      ComponentRegistry.putEntry(Type.bitstring("my_target"), entry);

      hologramExecuteActionStub = sinon.stub(Hologram, "executeAction");
    });

    afterEach(() => {
      sinon.restore();
    });

    it("calls fetch with correct URL, options, and payload", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves([1, "Type.nil()"]),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      sinon.assert.calledOnce(fetchStub);
      const [url, options] = fetchStub.firstCall.args;

      assert.equal(url, "/hologram/command");
      assert.equal(options.method, "POST");

      assert.deepStrictEqual(options.headers, {
        "Content-Type": "application/json",
      });

      assert.deepStrictEqual(
        options.body,
        Type.map([
          [Type.atom("module"), module],
          [Type.atom("name"), name],
          [Type.atom("params"), params],
          [Type.atom("target"), target],
        ]),
      );
    });

    it("command succeeds, next action is not nil", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves([1, '(() => "dummy_" + "action")()']),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      sinon.assert.calledOnceWithExactly(
        hologramExecuteActionStub,
        "dummy_action",
      );
    });

    it("command succeeds, next action is nil", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves([1, "Type.nil()"]),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      sinon.assert.notCalled(hologramExecuteActionStub);
    });

    it("command fails due to response status code", async () => {
      const mockResponse = {
        ok: false,
        status: 500,
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      let errorThrown = false;

      try {
        await Client.sendCommand(command);
      } catch (error) {
        errorThrown = true;
        assert.instanceOf(error, HologramRuntimeError);
        assert.equal(error.message, "command failed: 500");
      }

      assert.isTrue(errorThrown, "Expected HologramRuntimeError to be thrown");

      sinon.assert.notCalled(hologramExecuteActionStub);
    });

    it("command fails due to result status code", async () => {
      const mockResponse = {
        ok: true,
        json: sinon
          .stub()
          .resolves([0, "error message from server command handler"]),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      let errorThrown = false;

      try {
        await Client.sendCommand(command);
      } catch (error) {
        errorThrown = true;
        assert.instanceOf(error, HologramRuntimeError);
        assert.equal(
          error.message,
          "command failed: error message from server command handler",
        );
      }

      assert.isTrue(errorThrown, "Expected HologramRuntimeError to be thrown");

      sinon.assert.notCalled(hologramExecuteActionStub);
    });

    it("command fails due to network error", async () => {
      const networkError = new TypeError("Failed to fetch");

      fetchStub = sinon.stub(globalThis, "fetch").rejects(networkError);

      let errorThrown = false;

      try {
        await Client.sendCommand(command);
      } catch (error) {
        errorThrown = true;
        assert.instanceOf(error, HologramRuntimeError);
        assert.equal(
          error.message,
          "command failed: TypeError: Failed to fetch",
        );
      }

      assert.isTrue(errorThrown, "Expected HologramRuntimeError to be thrown");

      sinon.assert.notCalled(hologramExecuteActionStub);
    });
  });
});
