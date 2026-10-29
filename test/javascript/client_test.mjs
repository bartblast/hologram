"use strict";

import {
  assert,
  componentRegistryEntryFixture,
  defineRuntimeGlobals,
  encodedSubscriptionReceiptKey,
  registerWebApis,
  sinon,
  waitForEventLoop,
} from "./support/helpers.mjs";

import App from "../../assets/js/app.mjs";
import Client from "../../assets/js/client.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Connection from "../../assets/js/connection.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import HttpTransport from "../../assets/js/http_transport.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Type from "../../assets/js/type.mjs";

defineRuntimeGlobals();
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

    let originalInstanceId;

    beforeEach(() => {
      ComponentRegistry.clear();
      App.subscriptionReceiptRegistry.entries.clear();

      originalInstanceId = App.instanceId;
      App.instanceId = "test-instance-id";
    });

    afterEach(() => {
      App.subscriptionReceiptRegistry.entries.clear();
      App.instanceId = originalInstanceId;
    });

    it("builds command payload when target component is registered", () => {
      const entry = componentRegistryEntryFixture({module: module});
      ComponentRegistry.putEntry(target, entry);

      const result = Client.buildCommandPayload(command);

      const expected = Type.map([
        [Type.atom("instance_id"), Type.bitstring("test-instance-id")],
        [Type.atom("module"), module],
        [Type.atom("name"), name],
        [Type.atom("params"), params],
        [Type.atom("sub_receipts"), Type.list([])],
        [Type.atom("target"), target],
      ]);

      assert.deepStrictEqual(result, expected);
    });

    it("includes the tokens held in the subscription receipt registry", () => {
      const entry = componentRegistryEntryFixture({module: module});
      ComponentRegistry.putEntry(target, entry);

      App.subscriptionReceiptRegistry.entries.set(
        encodedSubscriptionReceiptKey(Type.atom("room_a"), "page"),
        Type.tuple([
          Type.atom("room_a"),
          Type.bitstring("page"),
          Type.bitstring("token-a"),
        ]),
      );

      App.subscriptionReceiptRegistry.entries.set(
        encodedSubscriptionReceiptKey(Type.atom("room_b"), "comp_1"),
        Type.tuple([
          Type.atom("room_b"),
          Type.bitstring("comp_1"),
          Type.bitstring("token-b"),
        ]),
      );

      const result = Client.buildCommandPayload(command);

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("sub_receipts"), result),
        Type.list([Type.bitstring("token-a"), Type.bitstring("token-b")]),
      );
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
    let fetchStub, onNotPageStub, onSuccessStub, originalInstanceId;

    const pageModule = Type.alias("MyPage");

    const pageDataResponse = (payload) => ({
      headers: new Headers({"hologram-page-data": "true"}),
      ok: true,
      json: sinon.stub().resolves(payload),
    });

    beforeEach(() => {
      onNotPageStub = sinon.stub();
      onSuccessStub = sinon.stub();

      App.subscriptionReceiptRegistry.entries.clear();

      originalInstanceId = App.instanceId;
      App.instanceId = "test-instance-id";
    });

    afterEach(() => {
      sinon.restore();
      App.subscriptionReceiptRegistry.entries.clear();
      App.instanceId = originalInstanceId;
    });

    it("asks the page data route for the page", async () => {
      fetchStub = sinon
        .stub(globalThis, "fetch")
        .resolves(pageDataResponse({type: "page"}));

      await Client.fetchPage(pageModule, onSuccessStub, onNotPageStub);

      const [url, opts] = fetchStub.firstCall.args;

      assert.equal(url, "/hologram/page/MyPage");
      assert.equal(opts.method, "POST");

      // Redirects are for the browser to follow, not this fetch: one followed here would be
      // consumed out of sight.
      assert.equal(opts.redirect, "manual");
    });

    // A redirect answers by fetching the next page, so whatever the callback goes on to do is part
    // of this call. Without the await a failure there would reject a promise nobody holds.
    it("carries a failure from the success callback to the caller", async () => {
      sinon
        .stub(globalThis, "fetch")
        .resolves(pageDataResponse({type: "page"}));

      const failing = async () => {
        throw new HologramRuntimeError("callback failed");
      };

      let thrownError = null;

      try {
        await Client.fetchPage(pageModule, failing, onNotPageStub);
      } catch (error) {
        thrownError = error;
      }

      assert.equal(thrownError?.message, "callback failed");
    });

    it("carries a failure from the not-a-page callback to the caller", async () => {
      sinon.stub(globalThis, "fetch").resolves({
        headers: new Headers({}),
        ok: true,
      });

      const failing = async () => {
        throw new HologramRuntimeError("callback failed");
      };

      let thrownError = null;

      try {
        await Client.fetchPage(pageModule, onSuccessStub, failing);
      } catch (error) {
        thrownError = error;
      }

      assert.equal(thrownError?.message, "callback failed");
    });

    it("hands over a marked payload", async () => {
      const payload = {pageDigest: "abc", type: "page"};

      fetchStub = sinon
        .stub(globalThis, "fetch")
        .resolves(pageDataResponse(payload));

      await Client.fetchPage(pageModule, onSuccessStub, onNotPageStub);

      sinon.assert.calledOnceWithExactly(onSuccessStub, payload);
      sinon.assert.notCalled(onNotPageStub);
    });

    // A page's middleware can answer with any status it likes, a plain 200 included, so the marker
    // rather than the status is what says an answer describes a page.
    it("treats an unmarked success as something other than a page", async () => {
      fetchStub = sinon.stub(globalThis, "fetch").resolves({
        headers: new Headers(),
        ok: true,
        json: sinon.stub().resolves({}),
      });

      await Client.fetchPage(pageModule, onSuccessStub, onNotPageStub);

      sinon.assert.calledOnce(onNotPageStub);
      sinon.assert.notCalled(onSuccessStub);
    });

    it("treats a denied response as something other than a page", async () => {
      fetchStub = sinon.stub(globalThis, "fetch").resolves({
        headers: new Headers(),
        ok: false,
        status: 403,
      });

      await Client.fetchPage(pageModule, onSuccessStub, onNotPageStub);

      sinon.assert.calledOnce(onNotPageStub);
      sinon.assert.notCalled(onSuccessStub);
    });

    // An opaque redirect carries no headers at all, which is the shape a redirect takes when the
    // fetch is told not to follow it.
    it("treats an opaque redirect as something other than a page", async () => {
      fetchStub = sinon.stub(globalThis, "fetch").resolves({
        headers: new Headers(),
        ok: false,
        status: 0,
        type: "opaqueredirect",
      });

      await Client.fetchPage(pageModule, onSuccessStub, onNotPageStub);

      sinon.assert.calledOnce(onNotPageStub);
      sinon.assert.notCalled(onSuccessStub);
    });
  });

  describe("sendCommand()", () => {
    // A reply field holds a term the way the server sends it: serialized, and already parsed along
    // with the rest of the reply.
    const serialized = (term) =>
      JSON.parse(Serializer.serialize(term, "server"));

    let fetchStub,
      schedulePushedActionStub,
      originalHologram,
      originalInstanceId,
      originalRegistryEpoch;

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
      App.subscriptionReceiptRegistry.entries.clear();

      const entry = componentRegistryEntryFixture({module: module});
      ComponentRegistry.putEntry(Type.bitstring("my_target"), entry);

      schedulePushedActionStub = sinon.stub(Hologram, "schedulePushedAction");

      originalHologram = globalThis.Hologram;
      globalThis.Hologram = {csrfToken: "test-csrf-token-123"};

      originalInstanceId = App.instanceId;
      App.instanceId = "test-instance-id";

      // A value another test is unlikely to leave behind, so that the stamp the reply's actions
      // carry is visibly this describe's.
      originalRegistryEpoch = Hologram.registryEpoch;
      Hologram.registryEpoch = 3;
    });

    afterEach(() => {
      sinon.restore();
      App.subscriptionReceiptRegistry.entries.clear();
      globalThis.Hologram = originalHologram;
      App.instanceId = originalInstanceId;
      Hologram.registryEpoch = originalRegistryEpoch;
    });

    it("calls fetch with correct URL, options, and payload including CSRF token", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(Type.nil()),
          selfEchoes: serialized(Type.list()),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
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
            [Type.atom("instance_id"), Type.bitstring("test-instance-id")],
            [Type.atom("module"), module],
            [Type.atom("name"), name],
            [Type.atom("params"), params],
            [Type.atom("sub_receipts"), Type.list([])],
            [Type.atom("target"), target],
          ]),
          "server",
        ),
      );
    });

    it("command succeeds, next action is not nil", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(
            Type.actionStruct({name: Type.atom("dummy_action")}),
          ),
          selfEchoes: serialized(Type.list()),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      await waitForEventLoop();

      sinon.assert.calledOnceWithExactly(
        schedulePushedActionStub,
        Type.actionStruct({name: Type.atom("dummy_action")}),
        [],
        3,
      );
    });

    // The reply names the chunks the struct types in its actions need, and no action may run
    // before they are in.
    it("schedules the next action and the self-echoed actions with the reply's chunks", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(
            Type.actionStruct({name: Type.atom("next_action")}),
          ),
          chunks: ["AAAAAAAA", "BBBBBBBB"],
          selfEchoes: serialized(
            Type.list([
              Type.actionStruct({
                name: Type.atom("self_echo"),
                target: Type.bitstring("my_target"),
              }),
            ]),
          ),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);
      await waitForEventLoop();

      assert.deepStrictEqual(schedulePushedActionStub.args, [
        [
          Type.actionStruct({name: Type.atom("next_action")}),
          ["AAAAAAAA", "BBBBBBBB"],
          3,
        ],
        [
          Type.actionStruct({name: Type.atom("self_echo"), target: target}),
          ["AAAAAAAA", "BBBBBBBB"],
        ],
      ]);
    });

    it("command succeeds, next action is nil", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(Type.nil()),
          selfEchoes: serialized(Type.list()),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      sinon.assert.notCalled(schedulePushedActionStub);
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

      sinon.assert.notCalled(schedulePushedActionStub);
    });

    it("command fails due to result status code", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: "error message from server command handler",
          status: 0,
        }),
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

      sinon.assert.notCalled(schedulePushedActionStub);
    });

    it("dispatches each self-echoed action from the selfEchoes field", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(Type.nil()),
          selfEchoes: serialized(
            Type.list([
              Type.actionStruct({
                name: Type.atom("self_echo_a"),
                target: Type.bitstring("my_target"),
              }),
              Type.actionStruct({
                name: Type.atom("self_echo_b"),
                target: Type.bitstring("my_target"),
              }),
            ]),
          ),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);
      await waitForEventLoop();

      sinon.assert.calledTwice(schedulePushedActionStub);

      sinon.assert.calledWith(
        schedulePushedActionStub,
        Type.actionStruct({name: Type.atom("self_echo_a"), target: target}),
        [],
      );

      sinon.assert.calledWith(
        schedulePushedActionStub,
        Type.actionStruct({name: Type.atom("self_echo_b"), target: target}),
        [],
      );
    });

    // A self echo is a broadcast the sender's own tab receives, and the server picked its targets
    // from the subscriptions the command was sent with. One of them can be a component of a page
    // the user has left since, which is skipped the way SSE skips a pushed action for a cid the
    // page does not hold, rather than raising for a target the page never had.
    it("skips a self echo whose target is not on the page", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(Type.nil()),
          selfEchoes: serialized(
            Type.list([
              Type.actionStruct({
                name: Type.atom("self_echo_a"),
                target: Type.bitstring("left_page_component"),
              }),
              Type.actionStruct({
                name: Type.atom("self_echo_b"),
                target: Type.bitstring("my_target"),
              }),
            ]),
          ),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);
      await waitForEventLoop();

      sinon.assert.calledOnceWithExactly(
        schedulePushedActionStub,
        Type.actionStruct({name: Type.atom("self_echo_b"), target: target}),
        [],
      );
    });

    it("does not dispatch any self-echo when the selfEchoes field is an empty list", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(Type.nil()),
          selfEchoes: serialized(Type.list()),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      sinon.assert.notCalled(schedulePushedActionStub);
    });

    it("dispatches next_action before self-echoed actions", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(
            Type.actionStruct({name: Type.atom("next_action")}),
          ),
          selfEchoes: serialized(
            Type.list([
              Type.actionStruct({
                name: Type.atom("self_echo"),
                target: Type.bitstring("my_target"),
              }),
            ]),
          ),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);
      await waitForEventLoop();

      sinon.assert.calledTwice(schedulePushedActionStub);

      assert.deepStrictEqual(
        schedulePushedActionStub.firstCall.args[0],
        Type.actionStruct({name: Type.atom("next_action")}),
      );

      assert.deepStrictEqual(
        schedulePushedActionStub.secondCall.args[0],
        Type.actionStruct({name: Type.atom("self_echo"), target: target}),
      );
    });

    // The next action belongs to the page the command was sent from, which the caller names: the
    // displayed page for a command the user triggered, the parent action's page for one an action
    // put. A self echo is a broadcast, so it is passed on with no stamp and schedulePushedAction
    // stamps it with the page the registry answers for when it arrives, whichever page that is.
    it("stamps the next action with the epoch it is given, and leaves a self echo to be stamped on arrival", async () => {
      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(
            Type.actionStruct({name: Type.atom("next_action")}),
          ),
          selfEchoes: serialized(
            Type.list([
              Type.actionStruct({
                name: Type.atom("self_echo"),
                target: Type.bitstring("my_target"),
              }),
            ]),
          ),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command, 7);
      await waitForEventLoop();

      assert.deepStrictEqual(schedulePushedActionStub.args, [
        [Type.actionStruct({name: Type.atom("next_action")}), [], 7],
        [Type.actionStruct({name: Type.atom("self_echo"), target: target}), []],
      ]);
    });

    // The default's one job is to read the epoch before the request goes out. A navigation can
    // complete while the fetch is in flight, and a next action stamped on arrival would then pass
    // for the destination's and run there against a target that page never had. A self echo is the
    // other way round: the subscription it answers may have survived the navigation, so it is
    // passed on with no stamp, to be stamped on arrival and run on the destination if its target
    // is on that page.
    it("stamps the next action with the registry's epoch when the command is sent, and leaves a self echo to be stamped on arrival", async () => {
      let resolveFetch;

      const fetchPromise = new Promise((resolve) => {
        resolveFetch = resolve;
      });

      fetchStub = sinon.stub(globalThis, "fetch").returns(fetchPromise);

      const sendCommandPromise = Client.sendCommand(command);

      // A page transition completing mid-flight.
      Hologram.registryEpoch = 4;

      resolveFetch({
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(
            Type.actionStruct({name: Type.atom("next_action")}),
          ),
          selfEchoes: serialized(
            Type.list([
              Type.actionStruct({
                name: Type.atom("self_echo"),
                target: Type.bitstring("my_target"),
              }),
            ]),
          ),
          status: 1,
          subReceiptAdds: serialized(Type.list()),
          subReceiptDrops: serialized(Type.list()),
        }),
      });

      await sendCommandPromise;
      await waitForEventLoop();

      assert.deepStrictEqual(schedulePushedActionStub.args, [
        [Type.actionStruct({name: Type.atom("next_action")}), [], 3],
        [Type.actionStruct({name: Type.atom("self_echo"), target: target}), []],
      ]);
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

      sinon.assert.notCalled(schedulePushedActionStub);
    });

    it("merges adds and drops from the subReceiptAdds and subReceiptDrops fields into the registry", async () => {
      App.subscriptionReceiptRegistry.entries.clear();

      App.subscriptionReceiptRegistry.merge(
        Type.list([
          Type.tuple([
            Type.atom("room_a"),
            Type.bitstring("page"),
            Type.bitstring("token-a"),
          ]),
        ]),
        Type.list(),
      );

      const mockResponse = {
        ok: true,
        json: sinon.stub().resolves({
          action: serialized(Type.nil()),
          selfEchoes: serialized(Type.list()),
          status: 1,
          subReceiptAdds: serialized(
            Type.list([
              Type.tuple([
                Type.atom("room_b"),
                Type.bitstring("page"),
                Type.bitstring("token-b"),
              ]),
            ]),
          ),
          subReceiptDrops: serialized(
            Type.list([
              Type.tuple([Type.atom("room_a"), Type.bitstring("page")]),
            ]),
          ),
        }),
      };

      fetchStub = sinon.stub(globalThis, "fetch").resolves(mockResponse);

      await Client.sendCommand(command);

      assert.isFalse(
        App.subscriptionReceiptRegistry.entries.has(
          encodedSubscriptionReceiptKey(Type.atom("room_a"), "page"),
        ),
      );

      const stored = App.subscriptionReceiptRegistry.entries.get(
        encodedSubscriptionReceiptKey(Type.atom("room_b"), "page"),
      );

      assert.equal(stored.data[2].text, "token-b");
    });
  });
});
