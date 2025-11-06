"use strict";

import {
  assert,
  componentRegistryEntryFixture,
  defineGlobalErlangAndElixirModules,
  registerWebApis,
  sinon,
  waitForEventLoop,
} from "./support/helpers.mjs";

import Client from "../../assets/js/client.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Connection from "../../assets/js/connection.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import HttpTransport from "../../assets/js/http_transport.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineGlobalErlangAndElixirModules();
registerWebApis();

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

    it("handles params as keyword list", () => {
      const params = Type.keywordList([
        [Type.atom("active"), Type.boolean(true)],
        [Type.atom("visible"), Type.boolean(false)],
      ]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?active=true&visible=false");
    });

    it("encodes special characters in param keys", () => {
      const params = Type.map([
        [Type.atom("user name"), Type.bitstring("hello")],
      ]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?user%20name=hello");
    });

    it("encodes special characters in param values", () => {
      const params = Type.map([
        [Type.atom("name"), Type.bitstring("hello world")],
      ]);

      const result = Client.buildPageQueryString(params);

      assert.strictEqual(result, "?name=hello%20world");
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

  describe("connect()", () => {
    let connectionConnectStub, httpTransportRestartPingStub;

    beforeEach(() => {
      connectionConnectStub = sinon.stub(Connection, "connect");
      httpTransportRestartPingStub = sinon.stub(HttpTransport, "restartPing");
    });

    afterEach(() => {
      sinon.restore();
    });

    it("calls Connection.connect() and HttpTransport.restartPing() with sendImmediatePing=false", () => {
      Client.connect(false);

      sinon.assert.calledOnce(connectionConnectStub);
      sinon.assert.calledOnceWithExactly(httpTransportRestartPingStub, false);
    });

    it("calls Connection.connect() and HttpTransport.restartPing() with sendImmediatePing=true", () => {
      Client.connect(true);

      sinon.assert.calledOnce(connectionConnectStub);
      sinon.assert.calledOnceWithExactly(httpTransportRestartPingStub, true);
    });
  });

  describe("fetchPage()", () => {
    let fetchStub, onSuccessStub;

    const pageModule = Type.alias("MyPage");

    const params = Type.map([
      [Type.atom("user_id"), Type.integer(123)],
      [Type.atom("status"), Type.atom("active")],
    ]);

    beforeEach(() => {
      onSuccessStub = sinon.stub();
    });

    afterEach(() => {
      sinon.restore();
    });

    describe("fetch parameters", () => {
      it("constructs correct URL when toParam is a page module", async () => {
        const mockResponse = {
          ok: true,
          text: sinon.stub().resolves("<html>Response</html>"),
        };

        fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

        await Client.fetchPage(pageModule, onSuccessStub);

        sinon.assert.calledOnce(fetchStub);
        const [url] = fetchStub.firstCall.args;
        assert.equal(url, "/hologram/page/MyPage");
      });

      it("constructs correct URL when toParam is a tuple with page module and params", async () => {
        const mockResponse = {
          ok: true,
          text: sinon.stub().resolves("<html>Response</html>"),
        };

        fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

        const toParam = Type.tuple([pageModule, params]);

        await Client.fetchPage(toParam, onSuccessStub);

        sinon.assert.calledOnce(fetchStub);
        const [url] = fetchStub.firstCall.args;
        assert.equal(url, "/hologram/page/MyPage?user_id=123&status=active");
      });
    });

    describe("response handling", () => {
      it("calls onSuccess callback with response HTML when fetch succeeds", async () => {
        const expectedHtml = "<html><body>Success!</body></html>";

        const mockResponse = {
          ok: true,
          text: sinon.stub().resolves(expectedHtml),
        };

        fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

        await Client.fetchPage(pageModule, onSuccessStub);

        sinon.assert.calledOnceWithExactly(onSuccessStub, expectedHtml);
      });

      it("throws HologramRuntimeError when response status is not ok", async () => {
        const mockResponse = {
          ok: false,
          status: 404,
        };

        fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

        let errorThrown = false;

        try {
          await Client.fetchPage(pageModule, onSuccessStub);
        } catch (error) {
          errorThrown = true;
          assert.instanceOf(error, HologramRuntimeError);
          assert.equal(error.message, "page fetch failed: 404");
        }

        assert.isTrue(
          errorThrown,
          "Expected HologramRuntimeError to be thrown",
        );
        sinon.assert.notCalled(onSuccessStub);
      });

      it("throws HologramRuntimeError when fetch fails due to network problems", async () => {
        const networkError = new TypeError("Failed to fetch");

        fetchStub = sinon.stub(globalThis, "fetch").rejects(networkError);

        let errorThrown = false;

        try {
          await Client.fetchPage(pageModule, onSuccessStub);
        } catch (error) {
          errorThrown = true;
          assert.instanceOf(error, HologramRuntimeError);
          assert.equal(
            error.message,
            "page fetch failed: TypeError: Failed to fetch",
          );
        }

        assert.isTrue(
          errorThrown,
          "Expected HologramRuntimeError to be thrown",
        );
        sinon.assert.notCalled(onSuccessStub);
      });

      it("rethrows HologramRuntimeError when error occurs during URL construction", async () => {
        const invalidParams = Type.map([
          [Type.bitstring("status"), Type.atom("pending")], // key is not an atom
        ]);

        const toParam = Type.tuple([pageModule, invalidParams]);

        let errorThrown = false;

        try {
          await Client.fetchPage(toParam, onSuccessStub);
        } catch (error) {
          errorThrown = true;
          assert.instanceOf(error, HologramRuntimeError);
          assert.equal(
            error.message,
            'invalid param key type (only atom type is allowed), got: "status"',
          );
        }

        assert.isTrue(
          errorThrown,
          "Expected original HologramRuntimeError to be rethrown",
        );
        sinon.assert.notCalled(onSuccessStub);
      });
    });

    describe("edge cases", () => {
      it("handles response.text() rejection", async () => {
        const mockResponse = {
          ok: true,
          text: sinon.stub().rejects(new Error("Text parsing failed")),
        };

        fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

        let errorThrown = false;

        try {
          await Client.fetchPage(pageModule, onSuccessStub);
        } catch (error) {
          errorThrown = true;
          assert.instanceOf(error, HologramRuntimeError);
          assert.equal(
            error.message,
            "page fetch failed: Error: Text parsing failed",
          );
        }

        assert.isTrue(
          errorThrown,
          "Expected HologramRuntimeError to be thrown",
        );
        sinon.assert.notCalled(onSuccessStub);
      });
    });
  });

  describe("sendCommand()", () => {
    let fetchStub, hologramScheduleActionStub;

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

      hologramScheduleActionStub = sinon.stub(Hologram, "scheduleAction");

      globalThis.hologram = {csrfToken: "test-csrf-token-123"};
    });

    afterEach(() => {
      sinon.restore();
      delete globalThis.hologram;
    });

    it("calls fetch with correct URL, options, and payload including CSRF token", async () => {
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
        "X-Csrf-Token": "test-csrf-token-123",
      });

      assert.deepStrictEqual(
        options.body,
        Serializer.serialize(
          Type.map([
            [Type.atom("module"), module],
            [Type.atom("name"), name],
            [Type.atom("params"), params],
            [Type.atom("target"), target],
          ]),
          "server",
        ),
      );
    });

    it("command succeeds, next action is not nil", async () => {
      const mockResponse = {
        ok: true,
        json: sinon
          .stub()
          .resolves([
            1,
            'Type.actionStruct({name: Type.atom("dummy_action")})',
          ]),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      await waitForEventLoop();

      sinon.assert.calledOnceWithExactly(
        hologramScheduleActionStub,
        Type.actionStruct({name: Type.atom("dummy_action")}),
      );
    });

    it("command succeeds, next action is nil", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves([1, "Type.nil()"]),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      sinon.assert.notCalled(hologramScheduleActionStub);
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

      sinon.assert.notCalled(hologramScheduleActionStub);
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

      sinon.assert.notCalled(hologramScheduleActionStub);
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

      sinon.assert.notCalled(hologramScheduleActionStub);
    });
  });
});
