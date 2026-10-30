"use strict";

import {
  assert,
  assertBoxedError,
  defineRuntimeGlobals,
  registerWebApis,
  setDataLayer,
  sinon,
  UUID_REGEX,
  waitForEventLoop,
} from "./support/helpers.mjs";

import ActionQueue from "../../assets/js/action_queue.mjs";
import App from "../../assets/js/app.mjs";
import AssetPathRegistry from "../../assets/js/asset_path_registry.mjs";
import Batches from "../../assets/js/batches.mjs";
import CallStack from "../../assets/js/erts/call_stack.mjs";
import Client from "../../assets/js/client.mjs";
import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Config from "../../assets/js/config.mjs";
import Debouncer from "../../assets/js/debouncer.mjs";
import EventListenerRegistry from "../../assets/js/event_listener_registry.mjs";
import Elixir_Task from "../../assets/js/elixir/task.mjs";
import ERTS from "../../assets/js/erts.mjs";
import EventListeners from "../../assets/js/event_listeners.mjs";
import FocusEvent from "../../assets/js/events/focus_event.mjs";
import GlobalRegistry from "../../assets/js/global_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import HologramBoxedError from "../../assets/js/errors/boxed_error.mjs";
import HologramRuntimeError from "../../assets/js/errors/runtime_error.mjs";
import Interpreter from "../../assets/js/interpreter.mjs";
import LiveReload from "../../assets/js/live_reload.mjs";
import MountGate from "../../assets/js/mount_gate.mjs";
import Overlay from "../../assets/js/overlay.mjs";
import Renderer from "../../assets/js/renderer.mjs";
import ScriptRegistry from "../../assets/js/script_registry.mjs";
import Serializer from "../../assets/js/serializer.mjs";
import Sse from "../../assets/js/sse.mjs";
import Throttler from "../../assets/js/throttler.mjs";
import Type from "../../assets/js/type.mjs";
import UncaughtErrorOverlay from "../../assets/js/uncaught_error_overlay.mjs";
import Vdom from "../../assets/js/vdom.mjs";

import {defineModule7Fixture} from "./support/fixtures/hologram/module_7.mjs";

defineRuntimeGlobals();
registerWebApis();
defineModule7Fixture();

const cid1 = Type.bitstring("my_component_1");
const cid2 = Type.bitstring("my_component_2");
const module7 = Type.alias("Hologram.Test.Fixtures.Module7");

describe("Hologram", () => {
  // A navigation that fails records its epoch dead for the rest of the session, and every later
  // dispatch stamped with that epoch is dropped. Left in place, a test's failed navigation would
  // decide the outcome of whichever test reuses the epoch next.
  afterEach(() => Hologram.deadEpochs.clear());

  describe("dispatchAction()", () => {
    let clock, executeActionStub;

    beforeEach(() => {
      clock = sinon.useFakeTimers();

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);
    });

    afterEach(() => {
      clock.restore();
      executeActionStub.restore();
    });

    // The counterpart of the hold covered in loadNewPage(): with no page swap in flight the page
    // on screen is the page the registry answers for, so there is nothing to wait for.
    it("dispatches an action right away when no page swap is in flight", () => {
      Hologram.dispatchAction("my_action", "my_component_1", {a: 1});

      clock.tick(0);

      sinon.assert.calledOnce(executeActionStub);

      const action = executeActionStub.firstCall.args[0];

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("name"), action),
        Type.atom("my_action"),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("target"), action),
        Type.bitstring("my_component_1"),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("params"), action),
        Type.map([[Type.atom("a"), Type.integer(1)]]),
      );
    });
  });

  describe("enqueueAction()", () => {
    let clock, executeActionStub, pendingSettles, warnStub;

    const actionNamed = (name, target = cid1) =>
      Type.actionStruct({
        name: Type.atom(name),
        params: Type.map(),
        target: target,
      });

    const action1 = actionNamed("action_1");
    const action2 = actionNamed("action_2");
    const action3 = actionNamed("action_3");
    const otherComponentAction = actionNamed("other_component_action", cid2);

    // A promise a test settles when it chooses to - or the teardown does, so that a component left
    // awaiting in one test is not still awaiting in the next.
    const pendingPromise = () => {
      let settle;

      const promise = new Promise((resolve) => {
        settle = resolve;
      });

      pendingSettles.push(settle);

      return promise;
    };

    beforeEach(() => {
      clock = sinon.useFakeTimers({shouldClearNativeTimers: true});
      ActionQueue.entries = [];
      pendingSettles = [];

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake(() => undefined);

      warnStub = sinon.stub(console, "warn");
    });

    afterEach(async () => {
      pendingSettles.forEach((settle) => settle());
      await clock.tickAsync(0);

      ActionQueue.entries = [];
      Hologram.domEpoch = 0;
      Hologram.registryEpoch = 0;
      Hologram.isMounting = false;
      Hologram.isRendering = false;
      clock.restore();
      sinon.restore();
    });

    // The ordinary case: nothing is in flight, so the action runs on the enqueuer's own stack -
    // which is what keeps a DOM dispatch synchronous.
    it("runs the action at once when nothing is ahead of it", () => {
      Hologram.enqueueAction(action1, 0);

      sinon.assert.calledOnceWithExactly(executeActionStub, action1, 0);
      assert.deepStrictEqual(ActionQueue.entries, []);
    });

    // An action's own code can enqueue the next one before it returns, e.g. by firing an event on
    // the DOM. The walk already on the stack takes it once its parent is done, rather than a nested
    // walk running it in the middle of the parent.
    it("runs an action enqueued by a running action after it", () => {
      const calls = [];

      executeActionStub.callsFake((action) => {
        if (action === action1) {
          Hologram.enqueueAction(action2, 0);
          calls.push("action_1 done");
        } else {
          calls.push("action_2");
        }
      });

      Hologram.enqueueAction(action1, 0);

      assert.deepStrictEqual(calls, ["action_1 done", "action_2"]);
    });

    // The reason the queue exists: the component's next action reads its state, so it must not
    // start before the running one has written it.
    it("waits for a component's asynchronous action before running its next one", async () => {
      executeActionStub.onFirstCall().returns(pendingPromise());

      Hologram.enqueueAction(action1, 0);
      Hologram.enqueueAction(action2, 0);

      sinon.assert.calledOnce(executeActionStub);

      pendingSettles[0]();
      await clock.tickAsync(0);

      sinon.assert.calledTwice(executeActionStub);
      assert.deepStrictEqual(executeActionStub.secondCall.args, [action2, 0]);
    });

    // An action never writes another component's struct, so another component has nothing to wait
    // for - and a promise that never settles must not hold the rest of the page.
    it("runs another component's action while one is awaiting", () => {
      executeActionStub.onFirstCall().returns(pendingPromise());

      Hologram.enqueueAction(action1, 0);
      Hologram.enqueueAction(otherComponentAction, 0);

      sinon.assert.calledTwice(executeActionStub);

      assert.deepStrictEqual(executeActionStub.secondCall.args, [
        otherComponentAction,
        0,
      ]);
    });

    it("keeps a component's later actions behind its awaiting one", () => {
      executeActionStub.onFirstCall().returns(pendingPromise());

      Hologram.enqueueAction(action1, 0);
      Hologram.enqueueAction(action2, 0);
      Hologram.enqueueAction(otherComponentAction, 0);

      sinon.assert.calledTwice(executeActionStub);

      assert.deepStrictEqual(executeActionStub.secondCall.args, [
        otherComponentAction,
        0,
      ]);

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action2, epoch: 0},
      ]);
    });

    // A later entry never overtakes an earlier one for the same component, whatever held the
    // earlier one back.
    it("keeps a component's later actions behind one that was passed over", async () => {
      executeActionStub.onFirstCall().returns(pendingPromise());

      Hologram.enqueueAction(action1, 0);

      Hologram.isRendering = true;
      Hologram.enqueueAction(action2, 0);
      Hologram.enqueueAction(action3, 0);
      Hologram.isRendering = false;

      pendingSettles[0]();
      await clock.tickAsync(0);

      assert.deepStrictEqual(
        executeActionStub.getCalls().map((call) => call.args[0]),
        [action1, action2, action3],
      );
    });

    // The settle of an action awaited on a page that has been left finds the epochs moved on. It
    // still releases its own component, since the wait it ends is its own.
    it("releases the component when its action settles after a navigation", async () => {
      executeActionStub.onFirstCall().returns(pendingPromise());

      Hologram.enqueueAction(action1, 0);

      Hologram.domEpoch = 1;
      Hologram.registryEpoch = 1;

      pendingSettles[0]();
      await clock.tickAsync(0);

      Hologram.enqueueAction(action2, 1);

      sinon.assert.calledTwice(executeActionStub);
      assert.deepStrictEqual(executeActionStub.secondCall.args, [action2, 1]);
    });

    // The two sides disagree, so the client is mid-transition: the page the action belongs to is
    // the one being moved to, and it cannot answer until it mounts.
    it("holds the queue while the client is mid-transition", () => {
      Hologram.domEpoch = 1;

      Hologram.enqueueAction(action1, 1);

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(warnStub);
      assert.equal(ActionQueue.entries.length, 1);
    });

    it("holds the queue while the page is mounting", () => {
      Hologram.isMounting = true;

      Hologram.enqueueAction(action1, 0);

      sinon.assert.notCalled(executeActionStub);
      assert.equal(ActionQueue.entries.length, 1);
    });

    it("holds the queue while a render is on the stack", () => {
      Hologram.isRendering = true;

      Hologram.enqueueAction(action1, 0);

      sinon.assert.notCalled(executeActionStub);
      assert.equal(ActionQueue.entries.length, 1);
    });

    // The shape a history restoration leaves behind: the registry has moved on while the page the
    // action came from is still on screen, so the page it was aimed at is already gone.
    it("drops an action whose page has been left, with a warning", () => {
      Hologram.registryEpoch = 1;

      Hologram.enqueueAction(action1, 0);

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.calledOnce(warnStub);
      assert.deepStrictEqual(ActionQueue.entries, []);
    });

    // A single focusout flushes every pending slot on the element at once, so a run of several is
    // the ordinary case and they have nothing to do with one another - the same bargain the
    // debouncer makes with the callbacks it flushes.
    it("delivers every action when one raises, and raises the first error", () => {
      const executed = [];

      executeActionStub.callsFake((action) => {
        executed.push(action);

        if (action === action1) {
          throw new Error("action failed");
        }
      });

      Hologram.isRendering = true;
      Hologram.enqueueAction(action1, 0);
      Hologram.enqueueAction(action2, 0);
      Hologram.isRendering = false;

      assert.throws(
        () => Hologram.enqueueAction(action3, 0),
        Error,
        "action failed",
      );

      assert.deepStrictEqual(executed, [action1, action2, action3]);
    });
  });

  describe("enqueueActionAfterDelay()", () => {
    let scheduleActionStub;

    const action = Type.actionStruct({
      name: Type.atom("my_action"),
      params: Type.map(),
      target: cid1,
    });

    const delayedAction = Type.actionStruct({
      name: Type.atom("my_delayed_action"),
      params: Type.map(),
      target: cid1,
      delay: Type.integer(500),
    });

    beforeEach(() => {
      ActionQueue.entries = [];
      scheduleActionStub = sinon.stub(Hologram, "scheduleAction");
    });

    afterEach(() => {
      ActionQueue.entries = [];
      sinon.restore();
    });

    it("puts an action without a delay on the queue at once", () => {
      Hologram.enqueueActionAfterDelay(action, 3);

      assert.deepStrictEqual(ActionQueue.entries, [{action: action, epoch: 3}]);
      sinon.assert.notCalled(scheduleActionStub);
    });

    // The same timer every other delayed action serves: the queue runs an entry as soon as it can,
    // so a delayed action must not be an entry until its delay has elapsed.
    it("puts an action with a delay through the timer", () => {
      Hologram.enqueueActionAfterDelay(delayedAction, 3);

      sinon.assert.calledOnceWithExactly(scheduleActionStub, delayedAction, 3);
      assert.deepStrictEqual(ActionQueue.entries, []);
    });
  });

  describe("executeAction()", () => {
    let callNamedFunctionStub, flushStub, renderStub;

    const actionFor = (target) =>
      Type.actionStruct({
        name: Type.atom("test_action"),
        params: Type.map(),
        target: target,
      });

    beforeEach(() => {
      ComponentRegistry.clear();
      Batches.reset();

      callNamedFunctionStub = sinon
        .stub(Interpreter, "callNamedFunction")
        .callsFake((_module, _fun, _args, _context) =>
          Type.componentStruct({state: Type.map()}),
        );

      // Sending is the queue's own business, specified in batches_test.mjs. Left real, every batch
      // sealed here would go to a fetch that rejects, and the retry that arms would outlive the test.
      flushStub = sinon.stub(Batches, "flush");

      // The result of a dispatch is rendered, which needs a page these tests don't mount.
      renderStub = sinon.stub(Hologram, "render").callsFake(() => null);
    });

    afterEach(() => {
      ComponentRegistry.clear();
      Batches.reset();
      sinon.restore();
    });

    const registered = (cid) => {
      ComponentRegistry.putEntry(
        cid,
        Type.map([
          [Type.atom("module"), module7],
          [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
        ]),
      );

      return cid;
    };

    // Whatever the action wrote, as a DB verb would leave it on the open batch.
    const writing = (id) =>
      callNamedFunctionStub.callsFake((_module, _fun, _args, _context) => {
        Batches.current().append({
          id,
          op: "delete",
          stamp: 1,
          type: "MyApp.Task",
        });

        return Type.componentStruct({state: Type.map()});
      });

    // The registry answers with plain null for a cid it does not hold, and null reaching
    // callNamedFunction faults on reading a module name off it.
    it("raises for a target the registry does not hold", () => {
      assertBoxedError(
        () => Hologram.executeAction(actionFor(Type.bitstring("nonexistent"))),
        "ArgumentError",
        'invalid action target, there is no component with CID: "nonexistent"',
      );
    });

    it("doesn't dispatch to a target the registry does not hold", () => {
      try {
        Hologram.executeAction(actionFor(Type.bitstring("nonexistent")));
      } catch {
        // Asserted on in the case above - what matters here is what didn't run.
      }

      sinon.assert.notCalled(callNamedFunctionStub);
    });

    it("dispatches to a registered target", () => {
      ComponentRegistry.putEntry(
        cid1,
        Type.map([
          [Type.atom("module"), module7],
          [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
        ]),
      );

      Hologram.executeAction(actionFor(cid1));

      sinon.assert.calledOnce(callNamedFunctionStub);
      sinon.assert.calledOnce(renderStub);

      assert.deepStrictEqual(callNamedFunctionStub.firstCall.args[0], module7);

      assert.deepStrictEqual(
        callNamedFunctionStub.firstCall.args[1],
        Type.atom("action"),
      );
    });

    describe("the action's batch", () => {
      beforeEach(() => {
        setDataLayer();
      });

      afterEach(() => {
        Hologram.dataLayer = null;
      });

      it("seals what the action wrote, taking the first sequence number", () => {
        writing("t1");

        Hologram.executeAction(actionFor(registered(cid1)));

        assert.equal(Batches.pending.length, 1);
        assert.equal(Batches.pending[0].seq, 1);
        assert.equal(Batches.pending[0].target, cid1);
      });

      it("gives a second action a batch and a number of its own", () => {
        writing("t1");
        Hologram.executeAction(actionFor(registered(cid1)));

        writing("t2");
        Hologram.executeAction(actionFor(cid1));

        assert.deepStrictEqual(
          Batches.pending.map((batch) => batch.seq),
          [1, 2],
        );
      });

      it("leaves nothing pending for an action that wrote nothing", () => {
        Hologram.executeAction(actionFor(registered(cid1)));

        assert.deepStrictEqual(Batches.pending, []);
        assert.isNull(Batches.current());
      });

      it("closes the batch before the render, so one frame shows both", () => {
        writing("t1");

        renderStub.callsFake(() => {
          assert.equal(Batches.pending.length, 1);

          return null;
        });

        Hologram.executeAction(actionFor(registered(cid1)));

        sinon.assert.calledOnce(renderStub);
      });

      // What binds the ORDER is the call sequence: the screen must not wait on the network.
      it("ships the batch after the render, not before it", () => {
        writing("t1");

        Hologram.executeAction(actionFor(registered(cid1)));

        sinon.assert.callOrder(renderStub, flushStub);
      });

      it("takes back what an action wrote before it raised", () => {
        callNamedFunctionStub.callsFake(() => {
          Batches.current().append({
            id: "t1",
            op: "delete",
            stamp: 1,
            type: "MyApp.Task",
          });

          throw new Error("boom");
        });

        assert.throw(
          () => Hologram.executeAction(actionFor(registered(cid1))),
          "boom",
        );

        assert.deepStrictEqual(Batches.pending, []);
        assert.isNull(Batches.current());
        assert.isFalse(Overlay.names("MyApp.Task", "t1"));
      });

      it("seals an async action's batch when its promise resolves", async () => {
        callNamedFunctionStub.callsFake(() => {
          Batches.current().append({
            id: "t1",
            op: "delete",
            stamp: 1,
            type: "MyApp.Task",
          });

          return Promise.resolve(Type.componentStruct({state: Type.map()}));
        });

        Hologram.executeAction(actionFor(registered(cid1)));

        assert.deepStrictEqual(Batches.pending, []);

        await waitForEventLoop();

        assert.equal(Batches.pending.length, 1);
      });

      // The result is dropped with the page it belongs to, but the writes are not the page's.
      it("seals an async action's batch when its page has been left before it resolves", async () => {
        let settle;

        callNamedFunctionStub.callsFake(() => {
          Batches.current().append({
            id: "t1",
            op: "delete",
            stamp: 1,
            type: "MyApp.Task",
          });

          return new Promise((resolve) => (settle = resolve));
        });

        sinon.stub(console, "warn");

        const promise = Hologram.executeAction(actionFor(registered(cid1)), 0);

        Hologram.domEpoch = 1;
        Hologram.registryEpoch = 1;

        try {
          settle(Type.componentStruct({state: Type.map()}));
          await promise;

          assert.equal(Batches.pending.length, 1);
          assert.isNull(Batches.current());
          sinon.assert.notCalled(renderStub);
        } finally {
          Hologram.domEpoch = 0;
          Hologram.registryEpoch = 0;
        }
      });

      it("takes back what an async action wrote before it rejected", async () => {
        callNamedFunctionStub.callsFake(() => {
          Batches.current().append({
            id: "t1",
            op: "delete",
            stamp: 1,
            type: "MyApp.Task",
          });

          return Promise.reject(new Error("boom"));
        });

        Hologram.executeAction(actionFor(registered(cid1)));

        await waitForEventLoop();

        assert.deepStrictEqual(Batches.pending, []);
        assert.isFalse(Overlay.names("MyApp.Task", "t1"));
      });

      // The compiler emits an async function for any action that awaits a command, so two can be
      // open at once and the second REPLACES the first as the action running. What brings the
      // first back to its own batch is the round trip Task.await/1 makes - the real one is called
      // here rather than imitated, since it is the whole of what makes this work.
      it("keeps two overlapping async actions on their own batches", async () => {
        let resumeFirst, resumeSecond;

        const firstAwaited = new Promise((resolve) => (resumeFirst = resolve));
        const secondAwaited = new Promise(
          (resolve) => (resumeSecond = resolve),
        );

        const suspending = (id, awaited) => async () => {
          await Elixir_Task["await/1"](ERTS.registerPromise(awaited));

          Batches.current().append({
            id,
            op: "delete",
            stamp: 1,
            type: "MyApp.Task",
          });

          return Type.componentStruct({state: Type.map()});
        };

        callNamedFunctionStub
          .onFirstCall()
          .callsFake(suspending("t1", firstAwaited));

        callNamedFunctionStub
          .onSecondCall()
          .callsFake(suspending("t2", secondAwaited));

        Hologram.executeAction(actionFor(registered(cid1)));
        Hologram.executeAction(actionFor(registered(cid2)));

        // The first comes back while the second is still away, which is the order that crosses
        // them: what the slot holds when the first resumes is the second action's batch.
        resumeFirst();
        await waitForEventLoop();

        resumeSecond();
        await waitForEventLoop();

        assert.deepStrictEqual(
          Batches.pending.map((batch) => [batch.target, batch.writes[0].id]),
          [
            [cid1, "t1"],
            [cid2, "t2"],
          ],
        );
      });

      // An app without a data model has no batch to open: the action runs and writes nothing down.
      it("opens no batch without a data layer", () => {
        const opening = sinon.spy(Batches, "open");
        Hologram.dataLayer = null;

        Hologram.executeAction(actionFor(registered(cid1)));

        sinon.assert.calledOnce(callNamedFunctionStub);
        sinon.assert.notCalled(opening);
        assert.deepStrictEqual(Batches.pending, []);
      });
    });

    it("returns nothing for a synchronous action", () => {
      ComponentRegistry.putEntry(
        cid1,
        Type.map([
          [Type.atom("module"), module7],
          [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
        ]),
      );

      assert.isUndefined(Hologram.executeAction(actionFor(cid1)));
    });

    // What the promise settles on is the commit, not the action's own return: a caller waiting on
    // it reads the state the action wrote.
    it("returns a promise that settles once an asynchronous action's result is processed", async () => {
      ComponentRegistry.putEntry(
        cid1,
        Type.map([
          [Type.atom("module"), module7],
          [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
        ]),
      );

      callNamedFunctionStub.callsFake((_module, _fun, _args, _context) =>
        Promise.resolve(
          Type.componentStruct({nextAction: Type.nil(), state: Type.map()}),
        ),
      );

      const result = Hologram.executeAction(actionFor(cid1));

      assert.instanceOf(result, Promise);
      sinon.assert.notCalled(renderStub);

      await result;

      sinon.assert.calledOnce(renderStub);
    });

    // A next action is a continuation of the one that produced it, so it belongs to the same page
    // - which is not necessarily the page current by the time it is scheduled, since the parent
    // may have been asynchronous. One with no delay runs before the browser paints, so that two
    // components a chain changes are never painted disagreeing: the browser paints between tasks,
    // so these tests check that it runs with the fake clock never ticked.
    describe("next action", () => {
      let clock, scheduleActionStub;

      const delayedNextActionStruct = Type.actionStruct({
        name: Type.atom("the_delayed_next_action"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(5),
      });

      const nextActionStruct = Type.actionStruct({
        name: Type.atom("the_next_action"),
        params: Type.map(),
        target: cid1,
      });

      const resultWith = (nextAction) =>
        Type.componentStruct({nextAction: nextAction, state: Type.map()});

      const executedActionNames = () =>
        callNamedFunctionStub.getCalls().map((call) => call.args[2].data[0]);

      beforeEach(() => {
        // The fake clock would hold a microtask until it ticks, and a zero-delay next action runs
        // on one when its parent is asynchronous.
        clock = sinon.useFakeTimers({
          shouldClearNativeTimers: true,
          toNotFake: ["queueMicrotask"],
        });

        ActionQueue.entries = [];

        ComponentRegistry.putEntry(
          cid1,
          Type.map([
            [Type.atom("module"), module7],
            [
              Type.atom("struct"),
              Type.componentStruct({nextAction: Type.nil()}),
            ],
          ]),
        );

        // Only the parent puts a next action, so a next action that runs ends the chain.
        callNamedFunctionStub.callsFake((_module, _fun, _args, _context) =>
          resultWith(Type.nil()),
        );

        scheduleActionStub = sinon
          .stub(Hologram, "scheduleAction")
          .callsFake((_action, _epoch) => null);
      });

      afterEach(async () => {
        // Lets a walk the microtask started finish before the next test.
        await Promise.resolve();

        ActionQueue.entries = [];
        clock.restore();
      });

      // Reading the epoch afresh at this point would stamp the next action with whatever page the
      // client has reached by the time its timer fires, which is how a delayed continuation would
      // land on a page that never produced it.
      it("a delayed next action does not take the epoch current when it is scheduled", () => {
        callNamedFunctionStub
          .onFirstCall()
          .returns(resultWith(delayedNextActionStruct));

        Hologram.domEpoch = 3;
        Hologram.registryEpoch = 3;

        try {
          Hologram.executeAction(actionFor(cid1), 1);

          sinon.assert.calledOnceWithExactly(
            scheduleActionStub,
            delayedNextActionStruct,
            1,
          );
        } finally {
          Hologram.domEpoch = 0;
          Hologram.registryEpoch = 0;
        }
      });

      // A delay is a request to wait, so the browser may paint before the action runs.
      it("a delayed next action goes on a timer with its parent's epoch", () => {
        callNamedFunctionStub
          .onFirstCall()
          .returns(resultWith(delayedNextActionStruct));

        Hologram.executeAction(actionFor(cid1), 7);

        sinon.assert.calledOnceWithExactly(
          scheduleActionStub,
          delayedNextActionStruct,
          7,
        );

        assert.deepStrictEqual(ActionQueue.entries, []);
      });

      it("a zero-delay next action inherits its parent's epoch", () => {
        callNamedFunctionStub
          .onFirstCall()
          .returns(resultWith(nextActionStruct));

        Hologram.executeAction(actionFor(cid1), 7);

        assert.deepStrictEqual(ActionQueue.entries, [
          {action: nextActionStruct, epoch: 7},
        ]);
      });

      // The parent's promise resolves when no walk is running, so the next action needs a walk of
      // its own, started before the browser can paint.
      it("a zero-delay next action of an asynchronous parent runs before any timer", async () => {
        callNamedFunctionStub
          .onFirstCall()
          .returns(Promise.resolve(resultWith(nextActionStruct)));

        await Hologram.executeAction(actionFor(cid1));

        assert.deepStrictEqual(executedActionNames(), [
          Type.atom("test_action"),
          Type.atom("the_next_action"),
        ]);

        sinon.assert.calledTwice(renderStub);
        sinon.assert.notCalled(scheduleActionStub);
      });

      // Run through the queue, the parent holds its component until its promise settles, and the
      // next action targets that same component, so the walk the parent's result starts passes
      // it over. The walk resumed once the parent settles takes it, still before any timer.
      it("a zero-delay next action of an asynchronous parent the queue awaits runs on the parent's own component before any timer", async () => {
        let nextActionRan;

        const nextActionRun = new Promise((resolve) => {
          nextActionRan = resolve;
        });

        callNamedFunctionStub
          .onFirstCall()
          .returns(Promise.resolve(resultWith(nextActionStruct)));

        callNamedFunctionStub.onSecondCall().callsFake(() => {
          nextActionRan();
          return resultWith(Type.nil());
        });

        Hologram.enqueueAction(actionFor(cid1), 0);
        await nextActionRun;

        assert.deepStrictEqual(executedActionNames(), [
          Type.atom("test_action"),
          Type.atom("the_next_action"),
        ]);

        sinon.assert.notCalled(scheduleActionStub);
      });

      it("a zero-delay next action runs before any timer", async () => {
        callNamedFunctionStub
          .onFirstCall()
          .returns(resultWith(nextActionStruct));

        Hologram.executeAction(actionFor(cid1));
        await Promise.resolve();

        assert.deepStrictEqual(executedActionNames(), [
          Type.atom("test_action"),
          Type.atom("the_next_action"),
        ]);

        sinon.assert.notCalled(scheduleActionStub);
      });

      // The ordinary case, a parent dispatched from the DOM: its own walk takes the next action
      // once the parent is done, on the dispatch's stack.
      it("a zero-delay next action runs on the walk that ran its parent", () => {
        callNamedFunctionStub
          .onFirstCall()
          .returns(resultWith(nextActionStruct));

        Hologram.enqueueAction(actionFor(cid1), 0);

        assert.deepStrictEqual(executedActionNames(), [
          Type.atom("test_action"),
          Type.atom("the_next_action"),
        ]);

        sinon.assert.calledTwice(renderStub);
      });

      // The parent's render is what shows its result, a spinner say, while the next action awaits:
      // the next action renders nothing until its promise resolves.
      it("an asynchronous zero-delay next action leaves its parent's render on screen while it awaits", async () => {
        let settle;

        callNamedFunctionStub
          .onFirstCall()
          .returns(resultWith(nextActionStruct));

        callNamedFunctionStub.onSecondCall().returns(
          new Promise((resolve) => {
            settle = resolve;
          }),
        );

        Hologram.executeAction(actionFor(cid1));
        await Promise.resolve();

        sinon.assert.calledTwice(callNamedFunctionStub);
        sinon.assert.calledOnce(renderStub);

        settle(resultWith(Type.nil()));
        await clock.tickAsync(0);

        sinon.assert.calledTwice(renderStub);
      });
    });

    // A next command belongs to the page its action belonged to, like a next action, so its reply
    // is stamped with the parent's epoch and dropped if that page has been left when it lands.
    describe("next command", () => {
      let sendCommandStub;

      const commandFor = (target) =>
        Type.commandStruct({
          name: Type.atom("the_next_command"),
          params: Type.map(),
          target: target,
        });

      const resultWith = (nextCommand) =>
        Type.componentStruct({nextCommand: nextCommand, state: Type.map()});

      beforeEach(() => {
        ComponentRegistry.putEntry(
          cid1,
          Type.map([
            [Type.atom("module"), module7],
            [
              Type.atom("struct"),
              Type.componentStruct({nextCommand: Type.nil()}),
            ],
          ]),
        );

        sendCommandStub = sinon
          .stub(Client, "sendCommand")
          .callsFake((_command, _epoch) => null);
      });

      it("sends a next command with its parent's epoch", () => {
        callNamedFunctionStub.returns(resultWith(commandFor(cid1)));

        Hologram.executeAction(actionFor(cid1), 7);

        sinon.assert.calledOnceWithExactly(
          sendCommandStub,
          commandFor(cid1),
          7,
        );
      });

      it("sends a next command with no target to its parent's target", () => {
        callNamedFunctionStub.returns(resultWith(commandFor(Type.nil())));

        Hologram.executeAction(actionFor(cid1), 7);

        sinon.assert.calledOnceWithExactly(
          sendCommandStub,
          commandFor(cid1),
          7,
        );
      });
    });

    // The await of an asynchronous action can span a navigation. Its result belongs to the page it
    // ran on, so once that page has been left the whole result is dropped: the struct, the next
    // command, the next action, the render and the next page. Each drop test runs the action on
    // page 0, moves the client on while the action awaits, and settles it then. The last three tests
    // are their controls: a result whose page has not been left is processed.
    describe("result after a navigation", () => {
      let enqueueSpy,
        fetchPageStub,
        originalStruct,
        sendCommandStub,
        settle,
        warnStub;

      const writtenState = Type.map([
        [Type.atom("written"), Type.boolean(true)],
      ]);

      const fullResult = Type.componentStruct({
        nextAction: Type.actionStruct({
          name: Type.atom("the_next_action"),
          params: Type.map(),
          target: cid1,
        }),
        nextCommand: Type.commandStruct({
          name: Type.atom("the_next_command"),
          params: Type.map(),
          target: cid1,
        }),
        nextPage: module7,
        state: writtenState,
      });

      // Runs the action on page 0, moves the client on while it awaits, and settles it. Both sides
      // move by default, a navigation that has mounted; moving one side alone is a navigation still
      // in flight. Awaiting the promise is part of every check: the queue's finally waits on it to
      // release the component and go on, so a dropped result must still settle it.
      const settleAfterNavigation = async ({
        domEpoch = 1,
        registryEpoch = 1,
      } = {}) => {
        const promise = Hologram.executeAction(actionFor(cid1), 0);

        Hologram.domEpoch = domEpoch;
        Hologram.registryEpoch = registryEpoch;

        settle(fullResult);
        await promise;
      };

      // Runs the action on page 3 and settles it with the client still there.
      const settleOnScreen = async () => {
        Hologram.domEpoch = 3;
        Hologram.registryEpoch = 3;

        const promise = Hologram.executeAction(actionFor(cid1), 3);

        settle(Type.componentStruct({state: writtenState}));
        await promise;
      };

      beforeEach(() => {
        ActionQueue.entries = [];

        originalStruct = Type.componentStruct({nextAction: Type.nil()});

        ComponentRegistry.putEntry(
          cid1,
          Type.map([
            [Type.atom("module"), module7],
            [Type.atom("struct"), originalStruct],
          ]),
        );

        // Only the action awaits. Everything else goes through, the router helper a next page's
        // path is built with among them.
        callNamedFunctionStub.callsFake((module, fun, args, context) =>
          fun.value === "action"
            ? new Promise((resolve) => {
                settle = resolve;
              })
            : callNamedFunctionStub.wrappedMethod(module, fun, args, context),
        );

        enqueueSpy = sinon.spy(ActionQueue, "enqueue");
        fetchPageStub = sinon.stub(Client, "fetchPage");
        sendCommandStub = sinon.stub(Client, "sendCommand");
        warnStub = sinon.stub(console, "warn");
      });

      afterEach(() => {
        ActionQueue.entries = [];
        Hologram.domEpoch = 0;
        Hologram.registryEpoch = 0;
      });

      it("writes no struct from a dropped result", async () => {
        await settleAfterNavigation();

        assert.strictEqual(
          ComponentRegistry.getComponentStruct(cid1),
          originalStruct,
        );
      });

      it("renders nothing from a dropped result", async () => {
        await settleAfterNavigation();

        sinon.assert.notCalled(renderStub);
      });

      it("warns when it drops a result", async () => {
        await settleAfterNavigation();

        sinon.assert.calledOnceWithExactly(
          warnStub,
          "Hologram: dropped the result of an action whose page has been left:",
          ":test_action",
        );
      });

      it("sends no next command from a dropped result", async () => {
        await settleAfterNavigation();

        sinon.assert.notCalled(sendCommandStub);
      });

      // Not put at all, rather than put with the parent's stamp and then dropped by the queue.
      it("puts no next action from a dropped result", async () => {
        await settleAfterNavigation();

        sinon.assert.notCalled(enqueueSpy);
      });

      it("navigates to no next page from a dropped result", async () => {
        await settleAfterNavigation();

        sinon.assert.notCalled(fetchPageStub);
      });

      // The two in-flight cases check the struct alone. It stands for the whole drop, which is one
      // early return in executeAction: the tests above cover what that return skips.
      //
      // The issue's own shape: the destination's markup is on screen and its bundle is still
      // loading when the await resolves, so only the displayed side has moved on.
      it("drops the result while a navigation away from its page is still in flight", async () => {
        await settleAfterNavigation({registryEpoch: 0});

        assert.strictEqual(
          ComponentRegistry.getComponentStruct(cid1),
          originalStruct,
        );
      });

      // The mirror of the case above: a history restore moves the registry's side on while the
      // left page's markup is still on screen.
      it("drops the result while a history restore away from its page is still in flight", async () => {
        await settleAfterNavigation({domEpoch: 0});

        assert.strictEqual(
          ComponentRegistry.getComponentStruct(cid1),
          originalStruct,
        );
      });

      // The controls: equality means the page has not been left, so the result is processed.
      it("writes the result of an asynchronous action whose page is still on screen", async () => {
        await settleOnScreen();

        assert.deepStrictEqual(
          ComponentRegistry.getComponentStruct(cid1),
          Type.componentStruct({state: writtenState}),
        );
      });

      it("renders the result of an asynchronous action whose page is still on screen", async () => {
        await settleOnScreen();

        sinon.assert.calledOnce(renderStub);
      });

      it("doesn't warn about the result of an asynchronous action whose page is still on screen", async () => {
        await settleOnScreen();

        sinon.assert.notCalled(warnStub);
      });
    });
  });

  describe("executeLoadPrefetchedPageAction()", () => {
    let eventTargetNode, loadNewPageStub;

    const payload = {type: "page"};

    const loadPrefetchedPageAction = Type.actionStruct({
      name: Type.atom("__load_prefetched_page__"),
      params: Type.map([[Type.atom("to"), module7]]),
      target: cid1,
    });

    const pagePath = "/hologram-test-fixtures-module7";

    beforeEach(() => {
      loadNewPageStub = sinon
        .stub(Hologram, "loadNewPage")
        .callsFake((_pagePath, _payload) => null);

      eventTargetNode = {id: "dummy_event_target_node"};
    });

    afterEach(() => Hologram.loadNewPage.restore());

    it("adds a Hologram ID to an event target DOM node that doesn't have one", () => {
      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      assert.match(eventTargetNode.__hologramId__, UUID_REGEX);
    });

    it("doesn't add a Hologram ID to an event target DOM node that already has one", () => {
      eventTargetNode.__hologramId__ = "dummy_hologram_id";

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      assert.equal(eventTargetNode.__hologramId__, "dummy_hologram_id");
    });

    it("confirms navigate if page HTML hasn't been fetched yet", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            payload: null,
            isNavigateConfirmed: false,
            pagePath: pagePath,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(mapValue, {
        payload: null,
        isNavigateConfirmed: true,
        pagePath: pagePath,
        timestamp: mapValue.timestamp,
      });

      sinon.assert.notCalled(loadNewPageStub);
    });

    it("loads page if page HTML has been already fetched", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            payload: payload,
            isNavigateConfirmed: false,
            pagePath: pagePath,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(loadNewPageStub, pagePath, payload);
    });

    // Dropping the entry instead would leave the link dead: the click looks the target up here,
    // and an entry that is not there does nothing at all.
    it("hands the target to the browser when the prefetch found no page", () => {
      const navigateBrowserToStub = sinon.stub(Hologram, "navigateBrowserTo");

      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            isNavigateConfirmed: false,
            isPage: false,
            pagePath: pagePath,
            payload: null,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(navigateBrowserToStub, pagePath);
      sinon.assert.notCalled(loadNewPageStub);

      navigateBrowserToStub.restore();
    });

    it("is a no-op if there is no prefeteched pages map entry for the given map key", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.executeLoadPrefetchedPageAction(
        loadPrefetchedPageAction,
        eventTargetNode,
      );

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.notCalled(loadNewPageStub);
    });
  });

  describe("executePrefetchPageAction()", () => {
    let clientFetchPageDataStub,
      eventTargetNode,
      handlePrefetchPageSuccessStub,
      successCallbacks;

    const pagePath = "/hologram-test-fixtures-module7";

    const prefetchPageAction = Type.actionStruct({
      name: Type.atom("__prefetch_page__"),
      params: Type.map([[Type.atom("to"), module7]]),
      target: cid1,
    });

    const resp = "dummy_resp";

    beforeEach(() => {
      successCallbacks = [];

      clientFetchPageDataStub = sinon
        .stub(Client, "fetchPage")
        .callsFake((_toParam, successCallback) => {
          successCallbacks.push(successCallback);
        });

      handlePrefetchPageSuccessStub = sinon
        .stub(Hologram, "handlePrefetchPageSuccess")
        .callsFake((_mapKey, _resp) => null);

      eventTargetNode = {id: "dummy_event_target_node"};
    });

    afterEach(() => {
      Client.fetchPage.restore();
      Hologram.handlePrefetchPageSuccess.restore();
    });

    it("adds a Hologram ID to an event target DOM node that doesn't have one", () => {
      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);
      assert.match(eventTargetNode.__hologramId__, UUID_REGEX);
    });

    it("doesn't add a Hologram ID to an event target DOM node that already has one", () => {
      eventTargetNode.__hologramId__ = "dummy_hologram_id";

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      assert.equal(eventTargetNode.__hologramId__, "dummy_hologram_id");
    });

    it("prefetches the page if there is no previous prefetch in progress", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      const mapKey = `${eventTargetNode.__hologramId__}:/hologram-test-fixtures-module7`;

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(mapValue, {
        isNavigateConfirmed: false,
        isPage: true,
        pagePath: pagePath,
        payload: null,
        timestamp: mapValue.timestamp,
      });

      assert.isAtMost(Math.abs(Date.now() - mapValue.timestamp), 100);

      sinon.assert.calledOnceWithExactly(
        clientFetchPageDataStub,
        module7,
        successCallbacks[0],
        sinon.match.func,
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageSuccessStub,
        mapKey,
        resp,
      );
    });

    it("prefetches the page if the previous prefetch has timed out", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            dummyKey: "dummy_value",
            timestamp: Date.now() - Config.fetchPageTimeoutMs - 1,
          },
        ],
      ]);

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(Hologram.prefetchedPages.get(mapKey), {
        isNavigateConfirmed: false,
        isPage: true,
        pagePath: pagePath,
        payload: null,
        timestamp: mapValue.timestamp,
      });

      assert.isAtMost(Math.abs(Date.now() - mapValue.timestamp), 100);

      sinon.assert.calledOnceWithExactly(
        clientFetchPageDataStub,
        module7,
        successCallbacks[0],
        sinon.match.func,
      );

      assert.equal(successCallbacks.length, 1);

      successCallbacks[0](resp);

      sinon.assert.calledOnceWithExactly(
        handlePrefetchPageSuccessStub,
        mapKey,
        resp,
      );
    });

    it("doesn't prefetch the page if the previous prefetch is in progress and hasn't timed out", () => {
      eventTargetNode = {__hologramId__: "dummy_hologram_id"};
      const mapKey = "dummy_hologram_id:/hologram-test-fixtures-module7";

      const mapValue = {
        dummyKey: "dummy_value",
        timestamp: Date.now(),
      };

      Hologram.prefetchedPages = new Map([[mapKey, mapValue]]);

      Hologram.executePrefetchPageAction(prefetchPageAction, eventTargetNode);

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));
      assert.equal(Hologram.prefetchedPages.get(mapKey), mapValue);

      sinon.assert.notCalled(clientFetchPageDataStub);
      sinon.assert.notCalled(handlePrefetchPageSuccessStub);
    });
  });

  describe("handleUiEvent()", () => {
    let executeActionStub,
      clientSendCommandStub,
      executeLoadPrefetchedPageActionStub,
      executePrefetchPageActionStub,
      scheduleActionStub;

    const actionSpecDom = Type.keywordList([
      [Type.atom("text"), Type.bitstring("my_action")],
    ]);

    // Example: $click={nil}
    const disabledSpecDom = Type.keywordList([
      [Type.atom("expression"), Type.tuple([Type.nil()])],
    ]);

    // Example: $click={command: :my_command}
    // Spec DOM: [expression: {[command: :my_command]}],
    // which is equivalent to [{:expression, {[{:command, :my_command}]}}]
    const commandSpecDom = Type.keywordList([
      [
        Type.atom("expression"),
        Type.tuple([
          Type.keywordList([[Type.atom("command"), Type.atom("my_command")]]),
        ]),
      ],
    ]);

    const defaultTarget = cid1;
    const eventType = "click";

    // What commandSpecDom dispatches for notIgnoredEvent below.
    const expectedCommand = Type.commandStruct({
      name: Type.atom("my_command"),
      params: Type.map([
        [
          Type.atom("event"),
          Type.map([
            [Type.atom("client_x"), Type.float(10)],
            [Type.atom("client_y"), Type.float(20)],
            [Type.atom("movement_x"), Type.float(5)],
            [Type.atom("movement_y"), Type.float(15)],
            [Type.atom("offset_x"), Type.float(30)],
            [Type.atom("offset_y"), Type.float(40)],
            [Type.atom("page_x"), Type.float(1)],
            [Type.atom("page_y"), Type.float(2)],
            [Type.atom("pointer_type"), Type.atom("mouse")],
            [Type.atom("screen_x"), Type.float(100)],
            [Type.atom("screen_y"), Type.float(200)],
          ]),
        ],
      ]),
      target: defaultTarget,
    });

    const notIgnoredEvent = {
      clientX: 10,
      clientY: 20,
      movementX: 5,
      movementY: 15,
      offsetX: 30,
      offsetY: 40,
      pageX: 1,
      pageY: 2,
      pointerType: "mouse",
      screenX: 100,
      screenY: 200,
      preventDefault: () => null,
      target: {id: "dummy_node"},
    };

    beforeEach(() => {
      clientSendCommandStub = sinon
        .stub(Client, "sendCommand")
        .callsFake((_command) => null);

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);

      executeLoadPrefetchedPageActionStub = sinon
        .stub(Hologram, "executeLoadPrefetchedPageAction")
        .callsFake((_action, _eventTargetNode) => null);

      executePrefetchPageActionStub = sinon
        .stub(Hologram, "executePrefetchPageAction")
        .callsFake((_action, _eventTargetNode) => null);

      scheduleActionStub = sinon
        .stub(Hologram, "scheduleAction")
        .callsFake((_action) => null);
    });

    afterEach(() => {
      Client.sendCommand.restore();
      Hologram.executeAction.restore();
      Hologram.executeLoadPrefetchedPageAction.restore();
      Hologram.executePrefetchPageAction.restore();
      Hologram.scheduleAction.restore();

      // A dispatch made mid-transition waits in the queue, and would be ahead of the next test's.
      ActionQueue.entries = [];
    });

    it("event is ignored", () => {
      const ignoredEvent = {
        clientX: 10,
        clientY: 20,
        movementX: 5,
        movementY: 15,
        offsetX: 30,
        offsetY: 40,
        pageX: 1,
        pageY: 2,
        pointerType: "mouse",
        screenX: 100,
        screenY: 200,
        ctrlKey: true,
        preventDefault: () => null,
      };

      Hologram.handleUiEvent(
        ignoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);
    });

    // A focus or blur the runtime causes while applying $focused or autofocus reports nothing
    // back: the state already says where focus is.
    describe("while the runtime moves focus", () => {
      beforeEach(() => {
        FocusEvent.isRuntimeFocusChange = true;
      });

      afterEach(() => {
        FocusEvent.isRuntimeFocusChange = false;
      });

      it("ignores a blur event", () => {
        assert.isNull(
          Hologram.handleUiEvent(
            notIgnoredEvent,
            "blur",
            actionSpecDom,
            defaultTarget,
          ),
        );
      });

      it("ignores a focus event", () => {
        assert.isNull(
          Hologram.handleUiEvent(
            notIgnoredEvent,
            "focus",
            actionSpecDom,
            defaultTarget,
          ),
        );
      });

      // A field that loses focus can fire change for what the user typed into it, which is the
      // user's doing and has to reach its binding.
      it("still dispatches an event of another kind", () => {
        const input = {tagName: "INPUT", type: "text", value: "abc"};
        const changeEvent = {currentTarget: input, target: input};

        const dispatch = Hologram.handleUiEvent(
          changeEvent,
          "change",
          actionSpecDom,
          defaultTarget,
        );

        assert.isFunction(dispatch);
      });
    });

    describe("binding that evaluates to a boolean", () => {
      // Example: $click={true}
      const trueSpecDom = Type.keywordList([
        [Type.atom("expression"), Type.tuple([Type.boolean(true)])],
      ]);

      // Example: $click={false}
      const falseSpecDom = Type.keywordList([
        [Type.atom("expression"), Type.tuple([Type.boolean(false)])],
      ]);

      it("raises for true", () => {
        assert.throw(
          () =>
            Hologram.handleUiEvent(
              notIgnoredEvent,
              eventType,
              trueSpecDom,
              defaultTarget,
            ),
          HologramRuntimeError,
          "an event binding evaluated to true, which is not an action or command name",
        );

        sinon.assert.notCalled(executeActionStub);
      });

      it("adds the $focused hint for a focus binding", () => {
        assert.throw(
          () =>
            Hologram.handleUiEvent(
              notIgnoredEvent,
              "focus",
              trueSpecDom,
              defaultTarget,
            ),
          HologramRuntimeError,
          "an event binding evaluated to true, which is not an action or command name - to control focus, use $focused",
        );
      });

      // Whether false should disable the binding the way nil does is a separate question, so it
      // dispatches as it always did: as an action named false.
      it("leaves false to dispatch as it did", () => {
        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          falseSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.calledOnce(executeActionStub);

        const action = executeActionStub.firstCall.args[0];

        assert.deepStrictEqual(
          action.data["atom(name)"][1],
          Type.atom("false"),
        );
      });
    });

    it("regular action without delay", () => {
      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        params: Type.map([
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(executeActionStub, expectedAction, 0);
      sinon.assert.notCalled(scheduleActionStub);
    });

    // The window a forward navigation opens: the destination's markup is on screen and clickable
    // while the registry still answers for the page being left, so the click waits for the mount
    // rather than resolving against a page that never carried the button.
    it("holds a click that lands while the destination is still mounting", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.domEpoch = 1;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          actionSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.notCalled(executeActionStub);
        sinon.assert.notCalled(scheduleActionStub);

        // A held click and a dropped one both leave executeAction uncalled. The absence of the
        // warning is what says this one is waiting for its page.
        sinon.assert.notCalled(warnStub);
      } finally {
        Hologram.domEpoch = 0;
        warnStub.restore();
      }
    });

    // The mirror window, opened by a history restoration: the registry has moved on to the page
    // being restored while the page the user clicked is still on screen, so the click is aimed at
    // a page that has been left and nothing can answer for it.
    it("drops a click from a page a restore has moved past", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.registryEpoch = 1;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          actionSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.notCalled(executeActionStub);
        sinon.assert.notCalled(scheduleActionStub);
        sinon.assert.calledOnce(warnStub);
      } finally {
        Hologram.registryEpoch = 0;
        warnStub.restore();
      }
    });

    // The whole reason the stamp is read when the event fires rather than when the dispatch runs:
    // a debounce or a throttle can hold a dispatch across a navigation, and it still belongs to
    // the page the user was looking at. Reading the epoch late would silently re-home it to
    // whatever page is on screen by then.
    it("stamps a deferred dispatch with the page the event happened on", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          actionSpecDom,
          defaultTarget,
        );

        // A navigation between the event and the dispatch it was held back from.
        Hologram.domEpoch = 1;

        dispatch();

        // Dropped, because it belongs to the page that has been left. Read late, the stamp would
        // have matched the destination and this would have been held for its mount instead.
        sinon.assert.notCalled(executeActionStub);
        sinon.assert.notCalled(scheduleActionStub);
        sinon.assert.calledOnce(warnStub);
      } finally {
        Hologram.domEpoch = 0;
        warnStub.restore();
      }
    });

    it("regular action with delay", () => {
      const delayedActionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("my_delayed_action")],
              [Type.atom("delay"), Type.integer(500)],
            ]),
          ]),
        ],
      ]);

      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        delayedActionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("my_delayed_action"),
        params: Type.map([
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
        delay: Type.integer(500),
      });

      // The epoch is the page the user acted on, recorded when the event fired rather than when
      // the delay elapses.
      sinon.assert.calledOnceWithExactly(
        scheduleActionStub,
        expectedAction,
        Hologram.domEpoch,
      );

      sinon.assert.notCalled(executeActionStub);
    });

    it("navigate to prefetched page action", () => {
      // Spec DOM: [expression: {[action: :__load_prefetched_page__, params: %{to: MyPage}]}],
      // which is equivalent to [{:expression, {[{:action, :__load_prefetched_page__}, {:params, %{to: MyPage}}]}}]
      const actionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("__load_prefetched_page__")],
              [
                Type.atom("params"),
                Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
              ],
            ]),
          ]),
        ],
      ]);

      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("__load_prefetched_page__"),
        params: Type.map([
          [Type.atom("to"), Type.alias("MyPage")],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(
        executeLoadPrefetchedPageActionStub,
        expectedAction,
        notIgnoredEvent.target,
      );
    });

    it("prefetch page action", () => {
      // Spec DOM: [expression: {[action: :__prefetch_page__, params: %{to: MyPage}]}],
      // which is equivalent to [{:expression, {[{:action, :__prefetch_page__}, {:params, %{to: MyPage}}]}}]
      const actionSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("action"), Type.atom("__prefetch_page__")],
              [
                Type.atom("params"),
                Type.map([[Type.atom("to"), Type.alias("MyPage")]]),
              ],
            ]),
          ]),
        ],
      ]);

      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);

      const expectedAction = Type.actionStruct({
        name: Type.atom("__prefetch_page__"),
        params: Type.map([
          [Type.atom("to"), Type.alias("MyPage")],
          [
            Type.atom("event"),
            Type.map([
              [Type.atom("client_x"), Type.float(10)],
              [Type.atom("client_y"), Type.float(20)],
              [Type.atom("movement_x"), Type.float(5)],
              [Type.atom("movement_y"), Type.float(15)],
              [Type.atom("offset_x"), Type.float(30)],
              [Type.atom("offset_y"), Type.float(40)],
              [Type.atom("page_x"), Type.float(1)],
              [Type.atom("page_y"), Type.float(2)],
              [Type.atom("pointer_type"), Type.atom("mouse")],
              [Type.atom("screen_x"), Type.float(100)],
              [Type.atom("screen_y"), Type.float(200)],
            ]),
          ],
        ]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(
        executePrefetchPageActionStub,
        expectedAction,
        notIgnoredEvent.target,
      );
    });

    it("command", () => {
      const dispatch = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        commandSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);

      sinon.assert.calledOnceWithExactly(
        clientSendCommandStub,
        expectedCommand,
        0,
      );
    });

    // The reply's actions carry this stamp, so they are dropped if the page the user clicked on
    // has been left by the time they land.
    it("sends a command stamped with the page the event happened on", () => {
      try {
        Hologram.domEpoch = 2;
        Hologram.registryEpoch = 2;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          commandSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.calledOnceWithExactly(
          clientSendCommandStub,
          expectedCommand,
          2,
        );
      } finally {
        Hologram.domEpoch = 0;
        Hologram.registryEpoch = 0;
      }
    });

    // A statement about the registries, not a scenario the browser reaches: the markup a forward
    // navigation patches in carries no bindings until the mount wires them. What it pins is that
    // a command is never built from a registry that answers for another page than the one on
    // screen.
    it("drops a command dispatched while the destination is still mounting", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.domEpoch = 1;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          commandSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.notCalled(clientSendCommandStub);

        sinon.assert.calledOnceWithExactly(
          warnStub,
          "Hologram: dropped a command dispatched on a page that has been left:",
          ":my_command",
        );
      } finally {
        Hologram.domEpoch = 0;
        warnStub.restore();
      }
    });

    // The mount that follows a history restore counts the restored page as the mounted one from
    // its start, but the left page's markup, with its bindings, stays on screen until the mount's
    // first render replaces it a frame later. A click on it in that frame carries the restored
    // page's epoch.
    it("drops a command dispatched before the mount's first render", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.isMounting = true;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          commandSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.notCalled(clientSendCommandStub);

        sinon.assert.calledOnceWithExactly(
          warnStub,
          "Hologram: dropped a command dispatched on a page that has been left:",
          ":my_command",
        );
      } finally {
        Hologram.isMounting = false;
        warnStub.restore();
      }
    });

    // The mirror window, opened by a history restoration: the registry has moved on to the page
    // being restored while the page the user clicked is still on screen, so the command comes from
    // a page that has been left and is not sent at all.
    it("drops a command from a page a restore has moved past", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.registryEpoch = 1;

        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          commandSpecDom,
          defaultTarget,
        );

        dispatch();

        sinon.assert.notCalled(clientSendCommandStub);

        sinon.assert.calledOnceWithExactly(
          warnStub,
          "Hologram: dropped a command dispatched on a page that has been left:",
          ":my_command",
        );
      } finally {
        Hologram.registryEpoch = 0;
        warnStub.restore();
      }
    });

    // A debounce or a throttle can hold the dispatch across a navigation. The command still
    // belongs to the page the user was looking at, which has been left by the time it fires.
    it("drops a deferred command whose page was left before it fired", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        const dispatch = Hologram.handleUiEvent(
          notIgnoredEvent,
          eventType,
          commandSpecDom,
          defaultTarget,
        );

        // A navigation between the event and the dispatch it was held back from.
        Hologram.domEpoch = 1;

        dispatch();

        sinon.assert.notCalled(clientSendCommandStub);

        sinon.assert.calledOnceWithExactly(
          warnStub,
          "Hologram: dropped a command dispatched on a page that has been left:",
          ":my_command",
        );
      } finally {
        Hologram.domEpoch = 0;
        warnStub.restore();
      }
    });

    it("does not prevent default when isDefaultAllowed is true", () => {
      // KeyboardEvent.isDefaultAllowed is true
      const preventDefault = sinon.spy();

      const keyboardEvent = {
        altKey: false,
        code: "Enter",
        ctrlKey: false,
        key: "Enter",
        metaKey: false,
        repeat: false,
        shiftKey: false,
        preventDefault,
        target: {id: "dummy_node"},
      };

      const dispatch = Hologram.handleUiEvent(
        keyboardEvent,
        "keydown",
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(preventDefault);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("prevents default when isDefaultAllowed is false", () => {
      // SubmitEvent.isDefaultAllowed is false, so a native form submit is prevented by default

      const preventDefault = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault,
      };

      Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.calledOnce(preventDefault);
    });

    it("allows the default when allowDefault is set", () => {
      // The binding's allow_default modifier opts out of the framework preventDefault, even for
      // an isDefaultAllowed: false event like submit.

      const preventDefault = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault,
      };

      const dispatch = Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
        true,
      );

      dispatch();

      sinon.assert.notCalled(preventDefault);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("prevents the default when forcePreventDefault is set", () => {
      // The binding's prevent_default modifier forces the framework preventDefault, even for an
      // isDefaultAllowed: true event like keydown.

      const preventDefault = sinon.spy();

      const keyboardEvent = {
        altKey: false,
        code: "Enter",
        ctrlKey: false,
        key: "Enter",
        metaKey: false,
        repeat: false,
        shiftKey: false,
        preventDefault,
        target: {id: "dummy_node"},
      };

      const dispatch = Hologram.handleUiEvent(
        keyboardEvent,
        "keydown",
        actionSpecDom,
        defaultTarget,
        false,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(preventDefault);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("does not stop propagation by default", () => {
      const stopPropagation = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault: () => null,
        stopPropagation,
      };

      const dispatch = Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      sinon.assert.notCalled(stopPropagation);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("stops propagation when stopPropagation is set", () => {
      // The binding's stop_propagation modifier stops the event from bubbling past the bound
      // element while the action still dispatches.

      const stopPropagation = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault: () => null,
        stopPropagation,
      };

      const dispatch = Hologram.handleUiEvent(
        submitEvent,
        "submit",
        actionSpecDom,
        defaultTarget,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(stopPropagation);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("does not stop propagation when the event is ignored", () => {
      // ClickEvent ignores a Ctrl+click, so the event edge work doesn't run for it.

      const stopPropagation = sinon.spy();

      const ignoredEvent = {
        clientX: 10,
        clientY: 20,
        movementX: 5,
        movementY: 15,
        offsetX: 30,
        offsetY: 40,
        pageX: 1,
        pageY: 2,
        pointerType: "mouse",
        screenX: 100,
        screenY: 200,
        ctrlKey: true,
        preventDefault: () => null,
        stopPropagation,
      };

      Hologram.handleUiEvent(
        ignoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
        false,
        true,
      );

      sinon.assert.notCalled(stopPropagation);
    });

    it("tolerates an event payload without a stopPropagation method", () => {
      // A resize binding's ResizeObserverEntry is not a DOM event and has no stopPropagation
      // method, so the call is skipped instead of crashing.

      const resizeObserverEntry = {
        target: {},
        borderBoxSize: [{blockSize: 10, inlineSize: 20}],
        contentBoxSize: [{blockSize: 8, inlineSize: 18}],
        devicePixelContentBoxSize: [{blockSize: 20, inlineSize: 40}],
      };

      const dispatch = Hologram.handleUiEvent(
        resizeObserverEntry,
        "resize",
        actionSpecDom,
        defaultTarget,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(executeActionStub);
    });

    it("tolerates an event payload without a preventDefault method", () => {
      // A resize binding's ResizeObserverEntry is not a DOM event and has no preventDefault
      // method, so a forced preventDefault is skipped instead of crashing.

      const resizeObserverEntry = {
        target: {},
        borderBoxSize: [{blockSize: 10, inlineSize: 20}],
        contentBoxSize: [{blockSize: 8, inlineSize: 18}],
        devicePixelContentBoxSize: [{blockSize: 20, inlineSize: 40}],
      };

      const dispatch = Hologram.handleUiEvent(
        resizeObserverEntry,
        "resize",
        actionSpecDom,
        defaultTarget,
        false,
        false,
        true,
      );

      dispatch();

      sinon.assert.calledOnce(executeActionStub);
    });

    it("returns null for a disabled binding", () => {
      const result = Hologram.handleUiEvent(
        notIgnoredEvent,
        eventType,
        disabledSpecDom,
        defaultTarget,
      );

      assert.isNull(result);

      sinon.assert.notCalled(clientSendCommandStub);
      sinon.assert.notCalled(executeActionStub);
      sinon.assert.notCalled(executeLoadPrefetchedPageActionStub);
      sinon.assert.notCalled(executePrefetchPageActionStub);
      sinon.assert.notCalled(scheduleActionStub);
    });

    it("does not prevent default for a disabled binding", () => {
      // SubmitEvent.isDefaultAllowed is false, so an enabled binding would prevent the default.

      const preventDefault = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault,
      };

      Hologram.handleUiEvent(
        submitEvent,
        "submit",
        disabledSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(preventDefault);
    });

    it("does not stop propagation for a disabled binding when stopPropagation is set", () => {
      const stopPropagation = sinon.spy();

      const submitEvent = {
        target: document.createElement("form"),
        preventDefault: () => null,
        stopPropagation,
      };

      Hologram.handleUiEvent(
        submitEvent,
        "submit",
        disabledSpecDom,
        defaultTarget,
        false,
        true,
      );

      sinon.assert.notCalled(stopPropagation);
    });

    it("dispatches a reach event with an empty payload", () => {
      const dispatch = Hologram.handleUiEvent(
        {target: {id: "dummy_node"}},
        "reach_bottom",
        actionSpecDom,
        defaultTarget,
      );

      dispatch();

      const expectedAction = Type.actionStruct({
        name: Type.atom("my_action"),
        params: Type.map([[Type.atom("event"), Type.map()]]),
        target: defaultTarget,
      });

      sinon.assert.calledOnceWithExactly(executeActionStub, expectedAction, 0);
    });
  });

  describe("loadNewPage()", () => {
    let assignedUrls, assignStub, fetchPageStub;

    // A payload field holds a term the way the server sends it: serialized, and already parsed
    // along with the rest of the response.
    const serialized = (term) =>
      JSON.parse(Serializer.serialize(term, "server"));

    const module7 = Type.atom("Elixir.Hologram.Test.Fixtures.Module7");
    const serializedModule7 = serialized(module7);
    const serializedNoParams = serialized(Type.map());

    // Built once: some tests stub the serializer to watch what the page snapshot saves.
    const serializedEmptyList = serialized(Type.list());

    const redirectTo = (to, serializedPageModule = serializedModule7) => ({
      pageModule: serializedPageModule,
      pageParams: serializedNoParams,
      to: to,
      type: "redirect",
    });

    // The wire form: an element is [tagName, attributes, children], attributes are a flat
    // name/value run, and text is a bare string.
    const wireElement = (tagName, attributes = [], children = []) => [
      tagName,
      attributes,
      children,
    ];

    const bundlePath = (pageDigest) =>
      `/hologram/page-Hologram.Test.Fixtures.Module7-${pageDigest}.js`;

    const wireBundleScript = (pageDigest) =>
      wireElement("script", ["src", bundlePath(pageDigest)]);

    // What the server sends: the whole document, the page's own bundle script included.
    const treeFor = (pageDigest, bodyText) => [
      wireElement(
        "html",
        [],
        [
          wireElement("head", [], [wireBundleScript(pageDigest)]),
          wireElement("body", [], [bodyText]),
        ],
      ),
    ];

    // The mount data the server used to write into an inline script, carried as payload fields.
    const serializedComponentRegistry = serialized(
      Type.map([
        [
          Type.bitstring("page"),
          Type.map([
            [Type.atom("module"), module7],
            [
              Type.atom("struct"),
              Type.componentStruct({
                state: Type.map([[Type.atom("count"), Type.integer(7)]]),
              }),
            ],
          ]),
        ],
      ]),
    );

    const payloadFor = (pageDigest, bodyText = "page content") => ({
      componentRegistry: serializedComponentRegistry,
      pageDigest: pageDigest,
      pageModule: serializedModule7,
      pageParams: serializedNoParams,
      selfEchoes: serializedEmptyList,
      subReceiptAdds: serializedEmptyList,
      subReceiptDrops: serializedEmptyList,
      tree: treeFor(pageDigest, bodyText),
      type: "page",
    });

    const bundleScript = (pageDigest) =>
      document.head.querySelector(`script[src="${bundlePath(pageDigest)}"]`);

    const chunkScript = (chunkDigest) =>
      document.head.querySelector(
        `script[src="/hologram/chunk-${chunkDigest}.js"]`,
      );

    // The page a navigation patches against, which on a document load is the render mirrored
    // onto what the server sent.
    const seedCurrentPage = () => {
      Hologram.virtualDocument = Vdom.mirror(
        Renderer.renderTree(
          Renderer.decodeTree(treeFor("current", "current page content")),
        ),
        document.documentElement,
      );
    };

    // Takes the fetched bundles out of the document and forgets them, with what waited for them.
    const removeBundleScripts = () => {
      document.head
        .querySelectorAll("script[src^='/hologram/']")
        .forEach((script) => script.remove());

      ScriptRegistry.statuses.clear();
      MountGate.require([]);
      MountGate.cancel();
    };

    beforeEach(() => {
      assignedUrls = [];

      assignStub = sinon
        .stub(Hologram, "navigateBrowserTo")
        .callsFake((url) => assignedUrls.push(url));

      fetchPageStub = sinon.stub(Client, "fetchPage");
    });

    afterEach(() => {
      Client.fetchPage.restore();
      assignStub.restore();

      // A navigation opens a transition window and only a mount closes it, which these tests
      // never reach - so it is closed here rather than left open for whatever runs next. The
      // same goes for the queue a held action waits in and the gate a reached mount sets.
      Hologram.domEpoch = 0;
      Hologram.registryEpoch = 0;
      Hologram.isMounting = false;
      ActionQueue.entries = [];
    });

    // A page the client cannot ask for is one only the browser can reach.
    it("hands a redirect target that names no page to the browser", async () => {
      await Hologram.loadNewPage("/clicked", {
        to: "https://example.com/x",
        type: "redirect",
      });

      assert.deepStrictEqual(assignedUrls, ["https://example.com/x"]);
      sinon.assert.notCalled(fetchPageStub);
    });

    it("follows a redirect by asking for the page it names", async () => {
      fetchPageStub.callsFake((toParam, _onSuccess, _onNotPage) => {
        assert.equal(
          toParam.data[0].value,
          "Elixir.Hologram.Test.Fixtures.Module7",
        );
        return null;
      });

      await Hologram.loadNewPage("/clicked", redirectTo("/target"));

      sinon.assert.calledOnce(fetchPageStub);
    });

    // A redirect can point at a page that redirects again, and a cycle would otherwise fetch
    // forever without anything to show for it.
    it("gives up after too many redirect hops", async () => {
      fetchPageStub.callsFake((_toParam, onSuccess, _onNotPage) =>
        onSuccess(redirectTo("/loop")),
      );

      let thrownError = null;

      try {
        await Hologram.loadNewPage("/clicked", redirectTo("/loop"));
      } catch (error) {
        thrownError = error;
      }

      assert.match(thrownError?.message ?? "", /Too many redirects/);
      assert.isAtMost(fetchPageStub.callCount, 10);
    });

    describe("the snapshot of the page being left", () => {
      let originalAssetManifest, serializeStub;

      beforeEach(() => {
        originalAssetManifest = globalThis.Hologram.assetManifest;

        globalThis.Hologram.assetManifest = {
          "hologram/runtime.js": "/hologram/runtime-abc.js",
        };

        window.requestAnimationFrame = () => {};
        serializeStub = sinon
          .stub(Serializer, "serialize")
          .returns("serialized");
      });

      afterEach(() => {
        globalThis.Hologram.assetManifest = originalAssetManifest;
        delete window.requestAnimationFrame;
        serializeStub.restore();
        removeBundleScripts();
      });

      it("is stamped with the code it was taken with", async () => {
        await Hologram.loadNewPage("/target", payloadFor("new"));

        const snapshot = serializeStub.firstCall.args[0];

        // No page is mounted in these tests, so the tab holds no bundle for one.
        assert.isNull(snapshot.pageDigest);
        assert.equal(snapshot.runtimeDigest, "abc");
      });

      it("is stamped with no runtime digest when the asset manifest names no runtime bundle", async () => {
        globalThis.Hologram.assetManifest = {};

        await Hologram.loadNewPage("/target", payloadFor("new"));

        const snapshot = serializeStub.firstCall.args[0];

        assert.isNull(snapshot.runtimeDigest);
      });

      // The state a snapshot holds can carry values of struct types whose protocol implementations
      // only chunks have, so the snapshot names the chunks to load before it is restored.
      it("names the chunks the tab has loaded", async () => {
        Hologram.requestChunks(["SNAPSHOT1", "SNAPSHOT2", "SNAPSHOT3"]);

        ScriptRegistry.statuses.set("SNAPSHOT1", "loaded");
        ScriptRegistry.statuses.set("SNAPSHOT2", "failed");

        await Hologram.loadNewPage("/target", payloadFor("new"));

        const snapshot = serializeStub.firstCall.args[0];

        assert.deepStrictEqual(snapshot.chunkDigests, ["SNAPSHOT1"]);
      });
    });

    describe("a page whose code the tab holds from an earlier visit", () => {
      const module7 = Type.atom("Elixir.Hologram.Test.Fixtures.Module7");

      let requestAnimationFrameSpy;

      beforeEach(() => {
        globalThis.Hologram.config.liveReload = true;

        // The frame's work is the in-app navigation. Not running it keeps these tests about
        // whether it was scheduled at all.
        requestAnimationFrameSpy = sinon.spy();
        window.requestAnimationFrame = requestAnimationFrameSpy;
      });

      afterEach(() => {
        globalThis.Hologram.config.liveReload = false;
        LiveReload.pageBundleDigests = new Map();
        delete window.requestAnimationFrame;
      });

      it("is handed to the browser when the server has rebuilt it since", async () => {
        LiveReload.recordPageBundle(module7, "old");

        await Hologram.loadNewPage("/target", payloadFor("new"));

        assert.deepStrictEqual(assignedUrls, ["/target"]);
        sinon.assert.notCalled(requestAnimationFrameSpy);
      });

      it("is shown in the app when its code is current", async () => {
        LiveReload.recordPageBundle(module7, "same");

        await Hologram.loadNewPage("/target", payloadFor("same"));

        assert.deepStrictEqual(assignedUrls, []);
        sinon.assert.calledOnce(requestAnimationFrameSpy);
      });

      it("is shown in the app where live reload does not run", async () => {
        globalThis.Hologram.config.liveReload = false;
        LiveReload.recordPageBundle(module7, "old");

        await Hologram.loadNewPage("/target", payloadFor("new"));

        assert.deepStrictEqual(assignedUrls, []);
        sinon.assert.calledOnce(requestAnimationFrameSpy);
      });
    });

    // The page the server described is patched in as soon as it arrives, so it is on screen a
    // round trip after it was asked for rather than a round trip plus a bundle plus a render.
    describe("showing the page the server described", () => {
      let patchStub;

      beforeEach(() => {
        // jsdom has no rAF, and the patch runs inside one. Running it now keeps the test reading
        // top to bottom.
        window.requestAnimationFrame = (callback) => callback();
        seedCurrentPage();
      });

      afterEach(() => {
        delete window.requestAnimationFrame;
        Hologram.isPageShown = false;
        Hologram.virtualDocument = null;

        patchStub?.restore();
        patchStub = null;

        removeBundleScripts();
      });

      // The point of carrying the state beside the render: it is readable without any element the
      // patch inserts. No boot data block exists in this tree at all.
      it("makes the page's mount data readable before the patch", async () => {
        await Hologram.loadNewPage("/target", payloadFor("mount-data"));

        // Nothing carried a block, so the mount can only read the payload.
        assert.isNull(document.querySelector("#hologram-boot-data"));
      });

      // That the mount then consumes it is a feature test's job - the mount is not reachable from
      // here, since it needs either the destination's code already registered or its bundle to
      // announce itself. What is provable here is that the payload's fields are decoded during
      // the swap: a field that cannot be read fails it, here a map whose entry is no pair.
      it("decodes the payload's mount data during the swap", async () => {
        const payload = {
          ...payloadFor("bad-registry"),
          componentRegistry: [4, {t: "m", d: ["i1"]}],
        };

        let thrown = null;

        try {
          await Hologram.loadNewPage("/target", payload);
        } catch (error) {
          thrown = error;
        }

        assert.isNotNull(thrown);
      });

      // The property the whole feature rests on: what the server described is on screen while the
      // page's own code is still in flight.
      it("puts the page on screen before its bundle has run", async () => {
        await Hologram.loadNewPage("/target", payloadFor("aaa", "new content"));

        assert.include(document.body.textContent, "new content");
        assert.equal(ScriptRegistry.statuses.get("aaa"), "requested");
      });

      // The swap advances the epoch of what is displayed while the registry's epoch stays put -
      // the gap between the two is what marks the transition window until the mount closes it.
      it("advances the epoch of what is on screen ahead of the registry", async () => {
        assert.equal(Hologram.domEpoch, 0);
        assert.equal(Hologram.registryEpoch, 0);

        await Hologram.loadNewPage("/target", payloadFor("epoch1"));

        assert.equal(Hologram.domEpoch, 1);
        assert.equal(Hologram.registryEpoch, 0);
      });

      // The destination is on screen from the patch onward, but its mount waits on the bundle -
      // so a dispatch that fires in between would run against a registry that is still the
      // previous page's, and render that page over the destination.
      it("drops a pending action before the destination is patched in", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        try {
          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("stale"),
              params: Type.map(),
              target: cid1,
              delay: Type.integer(100),
            }),
          );

          await Hologram.loadNewPage("/target", payloadFor("ddd"));

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
        }
      });

      // Everything the destination arms carries the destination's epoch, and the registry cannot
      // answer for that page until it mounts - so it waits rather than running against the page
      // being left, and rather than being swept.
      it("holds what the destination arms until the mount", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target", payloadFor("fff"));

          const action = Type.actionStruct({
            name: Type.atom("armed_by_destination"),
            params: Type.map(),
            target: cid1,
          });

          Hologram.scheduleAction(action, Hologram.domEpoch);
          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);

          // A held action and a dropped one both leave executeAction uncalled. The absence of the
          // warning is what says this one is waiting rather than gone.
          sinon.assert.notCalled(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // An action that reasoned about the registry - a server push, a command's reply - was right
      // about the page it saw, but that page is being left, so it goes no further.
      it("drops what reasoned about the page being left", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target", payloadFor("iii"));

          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("armed_by_the_registry"),
              params: Type.map(),
              target: cid1,
            }),
          );

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledOnce(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // The widest window a dispatch can outlive its page in is the one its own delay gives it -
      // the timer survives the navigation and only meets the settle rule once the delay is up.
      it("drops an action whose delay outlives the page that armed it", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("armed_before_the_swap"),
              params: Type.map(),
              target: cid1,
              delay: Type.integer(3000),
            }),
          );

          clock.tick(1000);
          sinon.assert.notCalled(executeActionStub);

          await Hologram.loadNewPage("/target", payloadFor("jjj"));

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledOnce(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // Nothing about the rule is per-action: everything the page being left had in flight goes,
      // whatever delay each was given.
      it("drops every action the page being left had pending", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        const pending = (name, delay) =>
          Type.actionStruct({
            name: Type.atom(name),
            params: Type.map(),
            target: cid1,
            delay: Type.integer(delay),
          });

        try {
          Hologram.scheduleAction(pending("pending_immediate", 0));
          Hologram.scheduleAction(pending("pending_100ms", 100));
          Hologram.scheduleAction(pending("pending_300ms", 300));

          await Hologram.loadNewPage("/target", payloadFor("kkk"));

          clock.tick(1000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledThrice(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // The destination's script runs during the patch, which for a page whose bundle is still
      // being fetched is a whole fetch before the mount - so dispatching then would resolve the
      // target against the page being left rather than against the page that carries the script.
      it("holds an action the destination's script dispatches before the mount", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target", payloadFor("ggg"));

          Hologram.dispatchAction("dispatched_by_script", "page", {value: 99});

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);

          // A held action and a dropped one both leave executeAction uncalled. The absence of the
          // warning is what says the script's dispatch is waiting for its page rather than having
          // been resolved against the page being left.
          sinon.assert.notCalled(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // A debounce holds its dispatch in a timer, and a timer outlives the page that armed it.
      // The destination is on screen from the patch onward and, when its bundle has still to
      // arrive, stays that way for a whole round trip before the mount - long enough for a window
      // opened on the page being left to elapse against the page that replaced it.
      it("drops a debounced dispatch the page being left had pending", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});
        const element = document.createElement("div");

        let dispatched = false;

        try {
          Debouncer.run(element, "my_slot", 2000, () => (dispatched = true));

          await Hologram.loadNewPage("/target", payloadFor("debounce-pending"));

          clock.tick(5000);

          assert.isFalse(dispatched);
        } finally {
          clock.restore();
        }
      });

      // The trailing edge is the throttle's equivalent of a pending debounce: a call held for the
      // end of a window that has not closed yet.
      it("drops a throttled dispatch the page being left was holding", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});
        const element = document.createElement("div");

        let leadingEdgeCount = 0;
        let trailingEdgeCount = 0;

        try {
          Throttler.run(element, "my_slot", 2000, () => leadingEdgeCount++);
          Throttler.run(element, "my_slot", 2000, () => trailingEdgeCount++);

          assert.equal(leadingEdgeCount, 1);
          assert.equal(trailingEdgeCount, 0);

          await Hologram.loadNewPage("/target", payloadFor("throttle-held"));

          clock.tick(5000);

          assert.equal(leadingEdgeCount, 1);
          assert.equal(trailingEdgeCount, 0);
        } finally {
          clock.restore();
        }
      });

      // A statement about the registries, not a scenario the browser reaches: a destination's
      // bindings are wired by the mount's render, not by the navigation's patch, so nothing it
      // owns can arm a window before it mounts. What this pins is that starting a navigation
      // schedules no later sweep.
      it("keeps a debounced dispatch armed after the navigation began", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});
        const element = document.createElement("div");

        let dispatched = false;

        try {
          await Hologram.loadNewPage("/target", payloadFor("debounce-armed"));

          Debouncer.run(element, "my_slot", 2000, () => (dispatched = true));

          clock.tick(5000);

          assert.isTrue(dispatched);
        } finally {
          clock.restore();
        }
      });

      // A registry listener - a <window>/<document> binding, a click_outside, a reach or resize
      // observer - is attached to a target the patch does not own, so it is the one kind of
      // listener that outlives the markup it was rendered for. One left alive would observe the
      // patch itself and dispatch with the destination's epoch.
      it("detaches the listeners of the page being left", async () => {
        const handler = sinon.spy();

        try {
          EventListenerRegistry.reconcile([
            {
              target: window,
              ...EventListeners.domEvent(window, "keydown"),
              handler,
            },
          ]);

          await Hologram.loadNewPage("/target", payloadFor("listeners-left"));

          window.dispatchEvent(new KeyboardEvent("keydown"));

          sinon.assert.notCalled(handler);
        } finally {
          EventListenerRegistry.detachAll();
        }
      });

      // The order is the design: a synchronous event the patch itself causes (Chrome fires blur
      // on a focused element being removed) must already find no listener.
      it("detaches them before the patch", async () => {
        const handler = sinon.spy();

        patchStub = sinon.stub(Vdom, "patchVirtualDocument").callsFake(() => {
          window.dispatchEvent(new KeyboardEvent("keydown"));
          return Hologram.virtualDocument;
        });

        try {
          EventListenerRegistry.reconcile([
            {
              target: window,
              ...EventListeners.domEvent(window, "keydown"),
              handler,
            },
          ]);

          await Hologram.loadNewPage("/target", payloadFor("listeners-patch"));

          sinon.assert.calledOnce(patchStub);
          sinon.assert.notCalled(handler);
        } finally {
          EventListenerRegistry.detachAll();
        }
      });

      it("fetches the bundle of a page this client has not run before", async () => {
        await Hologram.loadNewPage("/target", payloadFor("bbb"));

        assert.isNotNull(bundleScript("bbb"));
        assert.equal(ScriptRegistry.statuses.get("bbb"), "requested");
      });

      // The mount is what registers the page's code and converges the two epochs, and it cannot
      // run before the code it mounts is defined.
      it("holds the mount until the page's bundle has announced itself", async () => {
        await Hologram.loadNewPage("/target", payloadFor("held"));

        assert.deepStrictEqual(Array.from(MountGate.requiredDigests), ["held"]);
        assert.isNotNull(MountGate.pendingMount);
        assert.equal(Hologram.domEpoch, 1);
        assert.equal(Hologram.registryEpoch, 0);
      });

      // A script is keyed by the source it loads, so a bundle already in the document would be
      // adopted rather than run, and one only in memory would run a second time. Neither can
      // announce the mount, so the patch never carries the bundle.
      it("keeps the page's bundle out of the patch", async () => {
        patchStub = sinon
          .stub(Vdom, "patchVirtualDocument")
          .returns(Hologram.virtualDocument);

        await Hologram.loadNewPage("/target", payloadFor("ccc"));

        const patchedHead = patchStub.firstCall.args[1].children.find(
          (child) => child?.sel === "head",
        );

        assert.deepStrictEqual(patchedHead.children, []);
      });

      // The patch is where the page appears, so it is where its autofocus lands: in the same frame
      // as the markup, before the bundle has even been asked for.
      it("focuses the destination's autofocus element as its markup appears", async () => {
        const payload = {
          ...payloadFor("focus"),
          tree: [
            wireElement(
              "html",
              [],
              [
                wireElement("head", [], [wireBundleScript("focus")]),
                wireElement(
                  "body",
                  [],
                  [wireElement("input", ["id", "search", "autofocus", null])],
                ),
              ],
            ),
          ],
        };

        await Hologram.loadNewPage("/target", payload);

        const search = document.getElementById("search");

        assert.strictEqual(document.activeElement, search);

        search.blur();
        search.remove();
      });

      // The left page's focused element may survive the patch - the diff keeps a node whose
      // place matches - and a document load starts with nothing focused.
      it("starts the destination with nothing focused when it declares no focus", async () => {
        const field = document.createElement("input");
        field.id = "left_page_field";
        document.body.appendChild(field);
        field.focus();

        try {
          await Hologram.loadNewPage("/target", payloadFor("blank"));

          assert.strictEqual(document.activeElement, document.body);
        } finally {
          field.remove();
        }
      });

      it("patches as a page arrival and records that the page is shown", async () => {
        let isPageArrivalDuringPatch = null;

        patchStub = sinon.stub(Vdom, "patchVirtualDocument").callsFake(() => {
          isPageArrivalDuringPatch = Renderer.isPageArrival;
          return Hologram.virtualDocument;
        });

        await Hologram.loadNewPage("/target", payloadFor("arrival"));

        assert.isTrue(isPageArrivalDuringPatch);
        assert.isFalse(Renderer.isPageArrival);
        assert.isTrue(Hologram.isPageShown);
      });
    });

    // The browser went back or forward to an entry whose snapshot cannot be restored, so the
    // entry's page comes from the server instead. The entry exists already: the page is shown in
    // its place, and whatever is handed to the browser replaces it rather than adding one.
    describe("a page loaded into the history entry the browser went to", () => {
      const module7 = Type.atom("Elixir.Hologram.Test.Fixtures.Module7");

      let pushStateStub, replaceLocationStub, replaceStateStub;

      beforeEach(() => {
        window.requestAnimationFrame = (callback) => callback();
        seedCurrentPage();

        pushStateStub = sinon.stub(history, "pushState");
        replaceStateStub = sinon.stub(history, "replaceState");
        replaceLocationStub = sinon.stub(Hologram, "replaceBrowserLocation");
      });

      afterEach(() => {
        replaceLocationStub.restore();
        replaceStateStub.restore();
        pushStateStub.restore();

        globalThis.Hologram.config.liveReload = false;
        LiveReload.pageBundleDigests = new Map();

        delete window.requestAnimationFrame;
        Hologram.virtualDocument = null;
        removeBundleScripts();
      });

      it("follows a redirect into the same entry", async () => {
        let showRedirectTarget;

        fetchPageStub.callsFake((_toParam, onSuccess, _onNotPage) => {
          showRedirectTarget = onSuccess;
          return null;
        });

        await Hologram.loadNewPage(
          "/entry",
          redirectTo("/target"),
          0,
          "history-entry-1",
        );

        const loadNewPageStub = sinon.stub(Hologram, "loadNewPage");
        const nextPayload = payloadFor("entry-1");

        try {
          showRedirectTarget(nextPayload);

          sinon.assert.calledOnceWithExactly(
            loadNewPageStub,
            "/target",
            nextPayload,
            1,
            "history-entry-1",
          );
        } finally {
          loadNewPageStub.restore();
        }
      });

      it("is handed to the browser in place of the entry when the tab holds its code in an older version", async () => {
        globalThis.Hologram.config.liveReload = true;
        LiveReload.recordPageBundle(module7, "old");

        await Hologram.loadNewPage(
          "/entry",
          payloadFor("new"),
          0,
          "history-entry-2",
        );

        sinon.assert.calledOnceWithExactly(replaceLocationStub, "/entry");
        assert.deepStrictEqual(assignedUrls, []);
        sinon.assert.notCalled(replaceStateStub);
      });

      it("is handed to the browser in place of the entry when it redirects to a target that names no page", async () => {
        await Hologram.loadNewPage(
          "/entry",
          {to: "https://example.com/x", type: "redirect"},
          0,
          "history-entry-3",
        );

        sinon.assert.calledOnceWithExactly(
          replaceLocationStub,
          "https://example.com/x",
        );

        assert.deepStrictEqual(assignedUrls, []);
        sinon.assert.notCalled(fetchPageStub);
      });

      it("is shown in the entry, and no entry is added", async () => {
        await Hologram.loadNewPage(
          "/entry",
          payloadFor("entry-4"),
          0,
          "history-entry-4",
        );

        sinon.assert.calledOnceWithExactly(
          replaceStateStub,
          "history-entry-4",
          null,
          "/entry",
        );

        sinon.assert.notCalled(pushStateStub);
        assert.isNotNull(bundleScript("entry-4"));
      });
    });

    // A value of a struct type whose protocol implementations no bundle carries needs the chunks
    // that hold them, and so does the page's own code for the types it names. The server says
    // which, by digest.
    describe("chunks the page needs", () => {
      const payloadWithChunks = (pageDigest, chunkDigests) => ({
        ...payloadFor(pageDigest),
        chunks: chunkDigests,
      });

      beforeEach(() => {
        window.requestAnimationFrame = (callback) => callback();
        seedCurrentPage();
      });

      afterEach(() => {
        delete window.requestAnimationFrame;
        Hologram.virtualDocument = null;
        removeBundleScripts();
      });

      it("are fetched", async () => {
        await Hologram.loadNewPage(
          "/target",
          payloadWithChunks("chunks-1", ["AAAAAAAA", "BBBBBBBB"]),
        );

        assert.isNotNull(chunkScript("AAAAAAAA"));
        assert.isNotNull(chunkScript("BBBBBBBB"));
        assert.equal(ScriptRegistry.statuses.get("AAAAAAAA"), "requested");
        assert.equal(ScriptRegistry.statuses.get("BBBBBBBB"), "requested");
      });

      it("are not fetched again when the tab has them", async () => {
        ScriptRegistry.statuses.set("AAAAAAAA", "loaded");

        await Hologram.loadNewPage(
          "/target",
          payloadWithChunks("chunks-2", ["AAAAAAAA", "BBBBBBBB"]),
        );

        assert.isNull(chunkScript("AAAAAAAA"));
        assert.isNotNull(chunkScript("BBBBBBBB"));
      });

      it("hold the mount with the page's bundle until all have announced themselves", async () => {
        ScriptRegistry.statuses.set("AAAAAAAA", "loaded");

        await Hologram.loadNewPage(
          "/target",
          payloadWithChunks("chunks-3", ["AAAAAAAA", "BBBBBBBB"]),
        );

        assert.deepStrictEqual(Array.from(MountGate.requiredDigests), [
          "chunks-3",
          "AAAAAAAA",
          "BBBBBBBB",
        ]);

        assert.isNotNull(MountGate.pendingMount);
      });

      it("are none for a payload that names none", async () => {
        await Hologram.loadNewPage("/target", payloadFor("chunks-4"));

        assert.deepStrictEqual(Array.from(MountGate.requiredDigests), [
          "chunks-4",
        ]);
      });

      // The mount is never going to run without the chunk, like without the page's bundle.
      it("end the navigation when one fails to load", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage(
            "/target",
            payloadWithChunks("chunks-5", ["AAAAAAAA"]),
          );

          assert.throws(
            () => chunkScript("AAAAAAAA").onerror(),
            HologramRuntimeError,
            "Failed to load script: /hologram/chunk-AAAAAAAA.js",
          );

          assert.isNull(MountGate.pendingMount);

          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("after_chunk_failure"),
              params: Type.map(),
              target: cid1,
            }),
            Hologram.domEpoch,
          );

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledOnce(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });

      // A navigation from the server takes over from a restore still waiting for its chunks. The
      // chunk is the navigation's now, so its failure ends the navigation like any other chunk's,
      // and the restore, superseded, does nothing about it.
      it("end the navigation when one a superseded restore waited for too fails to load", async () => {
        const instanceId = App.instanceId;

        const pageSnapshot = {
          chunkDigests: ["AAAAAAAA"],
          componentRegistryEntries: Type.map(),
          instanceId: "superseded-restore-instance",
          pageModule: Type.atom(
            "Elixir.Hologram.Test.Fixtures.SupersededRestore",
          ),
          pageParams: Type.map(),
          scrollPosition: [0, 0],
          subscriptionReceipts: [],
        };

        sessionStorage.setItem(
          "hologram_page_snapshot_history-superseded",
          Serializer.serialize(pageSnapshot, "client"),
        );

        const consoleErrorStub = sinon.stub(console, "error");

        const fetchStub = sinon
          .stub(Client, "fetchPageDigest")
          .callsFake((_pageModule, onSuccess) => {
            if (onSuccess) {
              onSuccess("superseded-1");
            }

            return Promise.resolve("superseded-1");
          });

        try {
          await Hologram.handlePopstateEvent({state: "history-superseded"});

          await Hologram.loadNewPage(
            "/target",
            payloadWithChunks("chunks-8", ["AAAAAAAA"]),
          );

          assert.throws(
            () => chunkScript("AAAAAAAA").onerror(),
            HologramRuntimeError,
            "Failed to load script: /hologram/chunk-AAAAAAAA.js",
          );

          await new Promise((resolve) => setTimeout(resolve, 0));

          assert.isNull(MountGate.pendingMount);
          assert.strictEqual(App.instanceId, instanceId);

          // The entry's page is not asked for either: the navigation is somewhere else by now.
          sinon.assert.notCalled(fetchPageStub);
        } finally {
          fetchStub.restore();
          consoleErrorStub.restore();
          LiveReload.pageBundleDigests.delete(pageSnapshot.pageModule.value);
          sessionStorage.clear();
          ComponentRegistry.clear();
          App.instanceId = instanceId;
        }
      });

      // While a restore waits for its chunks the tab still holds the page being left, so a snapshot
      // saved then is that page's, and the entry the browser went to keeps its own.
      it("leave the snapshot of an entry whose restore still waits for them as it was", async () => {
        const instanceId = App.instanceId;

        const pageSnapshot = {
          chunkDigests: ["AAAAAAAA"],
          componentRegistryEntries: Type.map(),
          instanceId: "waiting-restore-instance",
          pageModule: Type.atom("Elixir.Hologram.Test.Fixtures.WaitingRestore"),
          pageParams: Type.map(),
          scrollPosition: [0, 0],
          subscriptionReceipts: [],
        };

        const snapshotKey = "hologram_page_snapshot_history-waiting";
        const storedSnapshot = Serializer.serialize(pageSnapshot, "client");

        sessionStorage.setItem(snapshotKey, storedSnapshot);

        const consoleErrorStub = sinon.stub(console, "error");
        const fetchStub = sinon.stub(Client, "fetchPageDigest");

        try {
          await Hologram.handlePopstateEvent({state: "history-waiting"});

          // A navigation saves the page it leaves.
          await Hologram.loadNewPage("/target", payloadFor("chunks-9"));

          assert.strictEqual(
            sessionStorage.getItem(snapshotKey),
            storedSnapshot,
          );
        } finally {
          // The restore is settled, so that it does not stay in flight for the tests that follow.
          globalThis.Hologram.pendingScripts = [
            {define: () => null, digest: "AAAAAAAA"},
          ];

          ScriptRegistry.defineLoaded({});
          await new Promise((resolve) => setTimeout(resolve, 0));

          fetchStub.restore();
          consoleErrorStub.restore();
          sessionStorage.clear();
          ComponentRegistry.clear();
          App.instanceId = instanceId;
        }
      });

      // The chunk of a page left behind by a later navigation is no longer what the mount waits
      // for, so its failure says nothing about the navigation now in flight.
      it("leave a later navigation's mount waiting when one of an earlier navigation fails", async () => {
        await Hologram.loadNewPage(
          "/target-1",
          payloadWithChunks("chunks-6", ["AAAAAAAA"]),
        );

        const supersededScript = chunkScript("AAAAAAAA");

        await Hologram.loadNewPage(
          "/target-2",
          payloadWithChunks("chunks-7", ["BBBBBBBB"]),
        );

        assert.throws(() => supersededScript.onerror(), HologramRuntimeError);

        assert.deepStrictEqual(Array.from(MountGate.requiredDigests), [
          "chunks-7",
          "BBBBBBBB",
        ]);

        assert.isNotNull(MountGate.pendingMount);
      });
    });

    // A bundle that never loads would otherwise end the navigation in silence: it never announces
    // itself, so the mount never runs and the page on screen stays put.
    describe("page bundle that fails to load", () => {
      beforeEach(() => {
        window.requestAnimationFrame = (callback) => callback();
        seedCurrentPage();
      });

      afterEach(() => {
        delete window.requestAnimationFrame;
        Hologram.virtualDocument = null;
        removeBundleScripts();
      });

      it("raises rather than leaving the navigation unfinished", async () => {
        await Hologram.loadNewPage("/target-eee", payloadFor("eee"));

        const script = bundleScript("eee");

        assert.isNotNull(script);

        assert.throws(
          () => script.onerror(),
          HologramRuntimeError,
          `Failed to load script: ${bundlePath("eee")}`,
        );
      });

      it("forgets the mount that waited for the bundle", async () => {
        await Hologram.loadNewPage("/target-fff", payloadFor("fff"));

        assert.isNotNull(MountGate.pendingMount);

        assert.throws(
          () => bundleScript("fff").onerror(),
          HologramRuntimeError,
        );

        assert.isNull(MountGate.pendingMount);
      });

      // The bundle of a page left behind by a later navigation is no longer what the mount waits
      // for, so its failure says nothing about the navigation now in flight.
      it("leaves a later navigation's mount waiting", async () => {
        await Hologram.loadNewPage("/target-iii", payloadFor("iii"));
        const supersededScript = bundleScript("iii");

        await Hologram.loadNewPage("/target-jjj", payloadFor("jjj"));

        assert.throws(() => supersededScript.onerror(), HologramRuntimeError);

        assert.deepStrictEqual(Array.from(MountGate.requiredDigests), ["jjj"]);
        assert.isNotNull(MountGate.pendingMount);
      });

      // A new need for the bundle is a new attempt at it.
      it("fetches the bundle again on the next navigation to the page", async () => {
        await Hologram.loadNewPage("/target-kkk", payloadFor("kkk"));

        const failedScript = bundleScript("kkk");
        assert.throws(() => failedScript.onerror(), HologramRuntimeError);
        failedScript.remove();

        await Hologram.loadNewPage("/target-kkk", payloadFor("kkk"));

        assert.isNotNull(bundleScript("kkk"));
        assert.equal(ScriptRegistry.statuses.get("kkk"), "requested");
        assert.isNotNull(MountGate.pendingMount);
      });

      // The mount that would have answered for this page is never going to run, so nothing it
      // carries can be resolved. Holding would swallow every later dispatch for the rest of the
      // session, so the epoch is recorded dead and what belongs to it is dropped - and said.
      it("drops a dispatch once the mount can no longer happen", async () => {
        const clock = sinon.useFakeTimers({shouldClearNativeTimers: true});

        const executeActionStub = sinon
          .stub(Hologram, "executeAction")
          .callsFake((_action) => null);

        const warnStub = sinon.stub(console, "warn");

        try {
          await Hologram.loadNewPage("/target-hhh", payloadFor("hhh"));

          assert.throws(
            () => bundleScript("hhh").onerror(),
            HologramRuntimeError,
            `Failed to load script: ${bundlePath("hhh")}`,
          );

          Hologram.scheduleAction(
            Type.actionStruct({
              name: Type.atom("after_bundle_failure"),
              params: Type.map(),
              target: cid1,
            }),
            Hologram.domEpoch,
          );

          clock.tick(5000);

          sinon.assert.notCalled(executeActionStub);
          sinon.assert.calledOnce(warnStub);
        } finally {
          clock.restore();
          executeActionStub.restore();
          warnStub.restore();
        }
      });
    });
  });

  describe("handlePrefetchPageNotPage()", () => {
    let navigateBrowserToStub;

    beforeEach(() => {
      navigateBrowserToStub = sinon.stub(Hologram, "navigateBrowserTo");
    });

    afterEach(() => navigateBrowserToStub.restore());

    it("leaves the app when navigate has already been confirmed", () => {
      Hologram.prefetchedPages = new Map([
        [
          "dummy_map_key",
          {
            isNavigateConfirmed: true,
            isPage: true,
            pagePath: "/my-page-path",
            payload: null,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.handlePrefetchPageNotPage("dummy_map_key");

      assert.equal(Hologram.prefetchedPages.size, 0);
      sinon.assert.calledOnceWithExactly(
        navigateBrowserToStub,
        "/my-page-path",
      );
    });

    // Before the click, the answer is only remembered: leaving the app on hover would take the
    // user somewhere they have not asked to go.
    it("marks the entry when navigate hasn't been confirmed", () => {
      const mapKey = "dummy_map_key";

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            isNavigateConfirmed: false,
            isPage: true,
            pagePath: "/my-page-path",
            payload: null,
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.handlePrefetchPageNotPage(mapKey);

      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isFalse(Hologram.prefetchedPages.get(mapKey).isPage);
      sinon.assert.notCalled(navigateBrowserToStub);
    });

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.handlePrefetchPageNotPage("dummy_map_key");

      assert.equal(Hologram.prefetchedPages.size, 0);
      sinon.assert.notCalled(navigateBrowserToStub);
    });
  });

  describe("handlePrefetchPageSuccess()", () => {
    let loadNewPageStub;

    beforeEach(() => {
      loadNewPageStub = sinon
        .stub(Hologram, "loadNewPage")
        .callsFake((_pagePath, _payload) => null);
    });

    afterEach(() => Hologram.loadNewPage.restore());

    it("no prefetchedPages map entry", () => {
      Hologram.prefetchedPages = new Map();

      Hologram.handlePrefetchPageSuccess("dummy_map_key", {type: "page"});

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.notCalled(loadNewPageStub);
    });

    it("navigate has been confirmed", () => {
      Hologram.prefetchedPages = new Map([
        [
          "dummy_map_key",
          {
            payload: null,
            isNavigateConfirmed: true,
            pagePath: "/my-page-path",
            timestamp: Date.now(),
          },
        ],
      ]);

      Hologram.handlePrefetchPageSuccess("dummy_map_key", {type: "page"});

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 0);

      sinon.assert.calledOnceWithExactly(loadNewPageStub, "/my-page-path", {
        type: "page",
      });
    });

    it("navigate hasn't been confirmed", () => {
      const mapKey = "dummy_map_key";
      const timestamp = Date.now();

      Hologram.prefetchedPages = new Map([
        [
          mapKey,
          {
            payload: null,
            isNavigateConfirmed: false,
            pagePath: "/my-page-path",
            timestamp: timestamp,
          },
        ],
      ]);

      Hologram.handlePrefetchPageSuccess(mapKey, {type: "page"});

      // Can't use assert.deepStrictEqual for Maps
      assert.instanceOf(Hologram.prefetchedPages, Map);
      assert.equal(Hologram.prefetchedPages.size, 1);
      assert.isTrue(Hologram.prefetchedPages.has(mapKey));

      const mapValue = Hologram.prefetchedPages.get(mapKey);

      assert.deepStrictEqual(mapValue, {
        payload: {type: "page"},
        isNavigateConfirmed: false,
        pagePath: "/my-page-path",
        timestamp: timestamp,
      });

      sinon.assert.notCalled(loadNewPageStub);
    });
  });

  describe("handlePopstateEvent()", () => {
    // The history's side of the navigation boundary. The handler needs a page to restore, and
    // the only way in from outside is the storage it reads: a snapshot is seeded under the key
    // the handler derives from the history id, and in jsdom the OPFS read throws into the
    // session storage fallback.
    it("detaches the listeners of the page being left", async () => {
      const handler = sinon.spy();
      const instanceId = App.instanceId;

      const pageSnapshot = {
        componentRegistryEntries: Type.map(),
        instanceId: "popstate-instance",
        pageModule: Type.atom("Elixir.Hologram.Test.Fixtures.Module7"),
        pageParams: Type.map(),
        scrollPosition: [0, 0],
        subscriptionReceipts: [],
      };

      sessionStorage.setItem(
        "hologram_page_snapshot_history-1",
        Serializer.serialize(pageSnapshot, "client"),
      );

      const consoleErrorStub = sinon.stub(console, "error");
      const fetchStub = sinon.stub(Client, "fetchPageDigest");

      try {
        EventListenerRegistry.reconcile([
          {
            target: window,
            ...EventListeners.domEvent(window, "keydown"),
            handler,
          },
        ]);

        await Hologram.handlePopstateEvent({state: "history-1"});

        window.dispatchEvent(new KeyboardEvent("keydown"));

        sinon.assert.notCalled(handler);
      } finally {
        EventListenerRegistry.detachAll();
        fetchStub.restore();
        consoleErrorStub.restore();
        sessionStorage.clear();
        ComponentRegistry.clear();
        App.instanceId = instanceId;
        Hologram.domEpoch = 0;
        Hologram.registryEpoch = 0;
      }
    });

    // A navigation the browser's history closes may have shown its destination and never
    // mounted it. The restore that follows has no interim patch, so its mount's render is where
    // the restored page appears, and the flag the shown page left must not say otherwise.
    it("forgets a page shown by the navigation it closes", async () => {
      const instanceId = App.instanceId;

      const pageSnapshot = {
        componentRegistryEntries: Type.map(),
        instanceId: "popstate-instance",
        pageModule: Type.atom("Elixir.Hologram.Test.Fixtures.Module7"),
        pageParams: Type.map(),
        scrollPosition: [0, 0],
        subscriptionReceipts: [],
      };

      sessionStorage.setItem(
        "hologram_page_snapshot_history-2",
        Serializer.serialize(pageSnapshot, "client"),
      );

      const consoleErrorStub = sinon.stub(console, "error");
      const fetchStub = sinon.stub(Client, "fetchPageDigest");

      Hologram.isPageShown = true;

      try {
        await Hologram.handlePopstateEvent({state: "history-2"});

        assert.isFalse(Hologram.isPageShown);
      } finally {
        fetchStub.restore();
        consoleErrorStub.restore();
        sessionStorage.clear();
        ComponentRegistry.clear();
        App.instanceId = instanceId;
        Hologram.domEpoch = 0;
        Hologram.registryEpoch = 0;
      }
    });

    // The state a snapshot holds can carry values of struct types whose protocol implementations
    // only the chunks it was taken with have, so it is restored once they are in. A snapshot can be
    // older than the build that serves the app now, and its chunks are named by digest, so the
    // files it names can be gone: the snapshot is then passed over, with the tab left as it was.
    describe("snapshot that names chunks", () => {
      const pageModule = Type.atom(
        "Elixir.Hologram.Test.Fixtures.RestoredFromSnapshot",
      );

      const announce = (digest) => {
        globalThis.Hologram.pendingScripts = [
          {define: () => null, digest: digest},
        ];

        ScriptRegistry.defineLoaded({});
      };

      const flushPromises = () =>
        new Promise((resolve) => setTimeout(resolve, 0));

      const snapshotChunkScripts = () =>
        Array.from(
          document.head.querySelectorAll(
            'script[src="/hologram/chunk-SNAPSHOT.js"]',
          ),
        );

      // Filed under a history id of its own each time: the handler first saves the page being
      // left under the id it holds, which is the one the last restore went to.
      const seedSnapshot = (historyId, snapshotPageModule = pageModule) => {
        const pageSnapshot = {
          chunkDigests: ["SNAPSHOT"],
          componentRegistryEntries: Type.map(),
          instanceId: "restored-instance",
          pageModule: snapshotPageModule,
          pageParams: Type.map(),
          scrollPosition: [0, 0],
          subscriptionReceipts: [],
        };

        sessionStorage.setItem(
          `hologram_page_snapshot_${historyId}`,
          Serializer.serialize(pageSnapshot, "client"),
        );
      };

      let consoleErrorStub, fetchPageStub, fetchStub, instanceId;

      beforeEach(() => {
        instanceId = App.instanceId;
        consoleErrorStub = sinon.stub(console, "error");
        fetchPageStub = sinon.stub(Client, "fetchPage");

        // The tab does not hold the page's code, so the server is asked which bundle serves it,
        // and the mount then waits for that bundle.
        fetchStub = sinon
          .stub(Client, "fetchPageDigest")
          .callsFake((_pageModule, onSuccess) => {
            if (onSuccess) {
              onSuccess("restored-1");
            }

            return Promise.resolve("restored-1");
          });
      });

      afterEach(() => {
        fetchStub.restore();
        fetchPageStub.restore();
        consoleErrorStub.restore();
        globalThis.Hologram.config.liveReload = false;

        document.head
          .querySelectorAll("script[src^='/hologram/']")
          .forEach((script) => script.remove());

        ScriptRegistry.statuses.clear();
        MountGate.require([]);
        MountGate.cancel();
        LiveReload.pageBundleDigests.delete(pageModule.value);

        sessionStorage.clear();
        ComponentRegistry.clear();
        App.instanceId = instanceId;
        Hologram.domEpoch = 0;
        Hologram.registryEpoch = 0;
      });

      // The entry's page is asked for the way a navigation asks for one, and goes into the entry
      // that exists already. Nothing of the tab is given up for it.
      it("is passed over, and the entry's page asked for, when one of its chunks fails to load", async () => {
        seedSnapshot("history-chunks-1");

        await Hologram.handlePopstateEvent({state: "history-chunks-1"});

        const [script] = snapshotChunkScripts();

        // The restore is prepared for it, so it is no error.
        assert.doesNotThrow(() => script.onerror());

        await flushPromises();

        assert.strictEqual(App.instanceId, instanceId);
        assert.isNull(MountGate.pendingMount);

        sinon.assert.calledOnce(fetchPageStub);

        const [toParam, showPage] = fetchPageStub.firstCall.args;

        assert.deepStrictEqual(toParam, Type.tuple([pageModule, Type.map()]));

        const loadNewPageStub = sinon.stub(Hologram, "loadNewPage");
        const payload = {type: "page"};

        try {
          showPage(payload);

          const {hash, pathname, search} = window.location;

          sinon.assert.calledOnceWithExactly(
            loadNewPageStub,
            `${pathname}${search}${hash}`,
            payload,
            0,
            "history-chunks-1",
          );
        } finally {
          loadNewPageStub.restore();
        }
      });

      // Taken with code other than the page's current one, which is only asked about where live
      // reload runs.
      it("is passed over, and the entry's page asked for, when it is outdated", async () => {
        globalThis.Hologram.config.liveReload = true;

        sessionStorage.setItem(
          "hologram_page_snapshot_history-chunks-4",
          Serializer.serialize(
            {
              chunkDigests: ["SNAPSHOT"],
              componentRegistryEntries: Type.map(),
              instanceId: "restored-instance",
              pageDigest: "outdated-1",
              pageModule: pageModule,
              pageParams: Type.map(),
              runtimeDigest: null,
              scrollPosition: [0, 0],
              subscriptionReceipts: [],
            },
            "client",
          ),
        );

        await Hologram.handlePopstateEvent({state: "history-chunks-4"});
        await flushPromises();

        assert.deepStrictEqual(snapshotChunkScripts(), []);
        assert.strictEqual(App.instanceId, instanceId);
        assert.isNull(MountGate.pendingMount);

        sinon.assert.calledOnce(fetchPageStub);

        assert.deepStrictEqual(
          fetchPageStub.firstCall.args[0],
          Type.tuple([pageModule, Type.map()]),
        );
      });

      it("is restored at once when the tab has its chunks", async () => {
        ScriptRegistry.statuses.set("SNAPSHOT", "loaded");
        seedSnapshot("history-chunks-2");

        await Hologram.handlePopstateEvent({state: "history-chunks-2"});
        await flushPromises();

        assert.deepStrictEqual(snapshotChunkScripts(), []);
        assert.strictEqual(App.instanceId, "restored-instance");
        assert.isNotNull(MountGate.pendingMount);
        sinon.assert.notCalled(fetchPageStub);
      });

      it("is restored once its chunks have loaded", async () => {
        seedSnapshot("history-chunks-3");

        await Hologram.handlePopstateEvent({state: "history-chunks-3"});
        await flushPromises();

        assert.strictEqual(snapshotChunkScripts().length, 1);
        assert.strictEqual(App.instanceId, instanceId);
        assert.isNull(MountGate.pendingMount);

        announce("SNAPSHOT");
        await flushPromises();

        assert.strictEqual(App.instanceId, "restored-instance");

        assert.deepStrictEqual(Array.from(MountGate.requiredDigests), [
          "restored-1",
        ]);

        assert.isNotNull(MountGate.pendingMount);
        sinon.assert.notCalled(fetchPageStub);
      });

      // The mount counts the restored page as the one the registry answers for from its start,
      // but the left page's markup, with its bindings, stays on screen until the mount's first
      // render replaces it a frame later. A click on it before that frame must carry the left
      // page's epoch, so that what it dispatches is dropped rather than run against the restored
      // page. The render itself runs with the restored page's epoch, since the inline scripts its
      // patch inserts are the restored page's.
      it("keeps what is on screen on the left page's epoch until the frame of the mount's first render", async () => {
        // A page module of its own, and a history id no other test files a snapshot under (the
        // handler caches the snapshots it reads): the mount registers the module, and the
        // neighbouring tests rely on theirs not being registered.
        const mountedModule = Type.atom(
          "Elixir.Hologram.Test.Fixtures.MountedFromSnapshot",
        );

        const assetPathEntries = AssetPathRegistry.entries;
        let domEpochDuringRender = null;

        const renderStub = sinon
          .stub(Hologram, "render")
          .callsFake(() => (domEpochDuringRender = Hologram.domEpoch));

        const scrollToStub = sinon.stub(window, "scrollTo");
        const sseConnectStub = sinon.stub(Sse, "connect");

        let frame = null;
        window.requestAnimationFrame = (callback) => (frame = callback);
        globalThis.Hologram.assetManifest = {};

        try {
          ScriptRegistry.statuses.set("SNAPSHOT", "loaded");
          seedSnapshot("history-mounted-from-snapshot", mountedModule);

          await Hologram.handlePopstateEvent({
            state: "history-mounted-from-snapshot",
          });

          await flushPromises();

          // What the runtime does once a script announces itself (#defineLoadedScripts).
          announce("restored-1");
          MountGate.settle();

          assert.isNotNull(frame);
          assert.equal(Hologram.registryEpoch, 1);
          assert.equal(Hologram.domEpoch, 0);

          // Whatever a navigation left behind, the mount's render is the last thing that reads it.
          Hologram.isPageShown = true;

          frame();

          assert.equal(domEpochDuringRender, 1);
          assert.equal(Hologram.domEpoch, 1);
          assert.isFalse(Hologram.isMounting);
          assert.isFalse(Hologram.isPageShown);
        } finally {
          delete window.requestAnimationFrame;
          delete globalThis.Hologram.assetManifest;
          AssetPathRegistry.entries = assetPathEntries;
          LiveReload.pageBundleDigests.delete(mountedModule.value);
          Hologram.isMounting = false;
          Hologram.isPageShown = false;
          renderStub.restore();
          scrollToStub.restore();
          sseConnectStub.restore();
        }
      });
    });
  });

  describe("handleUncaughtError()", () => {
    let overlayShowStub;

    const boxedError = () =>
      new HologramBoxedError(Type.errorStruct("MyError", "my message"));

    beforeEach(() => {
      CallStack.reset();
      overlayShowStub = sinon.stub(UncaughtErrorOverlay, "show");
      globalThis.Hologram.config.errorOverlay = false;
    });

    afterEach(() => {
      overlayShowStub.restore();
      globalThis.Hologram.config.errorOverlay = false;
    });

    // The overlay reads the frames and the message off the error itself, so
    // it is handed the error rather than the report rendered from it.
    it("renders the error in the page when the overlay is enabled", () => {
      globalThis.Hologram.config.errorOverlay = true;

      const error = boxedError();

      Hologram.handleUncaughtError(error);

      sinon.assert.calledOnceWithExactly(overlayShowStub, error);
    });

    it("keeps the error out of the page when the overlay is disabled", () => {
      Hologram.handleUncaughtError(boxedError());

      sinon.assert.notCalled(overlayShowStub);
    });

    it("records the error for the feature test helpers", () => {
      Hologram.handleUncaughtError(boxedError());

      assert.deepStrictEqual(GlobalRegistry.get("lastBoxedError"), {
        module: "MyError",
        message: "my message",
      });
    });

    // Deriving here a second time would fault the same way the first one did,
    // leaving the error unreported - the very thing the reader needs to see.
    it("records an error that failed to derive its message, naming the fault", () => {
      const normalizeErrorStub = sinon
        .stub(Interpreter, "normalizeError")
        .callsFake(() => {
          throw new TypeError("my fault");
        });

      const error = new HologramBoxedError(Type.atom("badarg"));

      normalizeErrorStub.restore();

      Hologram.handleUncaughtError(error);

      assert.deepStrictEqual(GlobalRegistry.get("lastBoxedError"), {
        module: "error",
        message: ":badarg (message derivation failed: my fault)",
      });
    });

    it("ignores an error raised outside the runtime", () => {
      globalThis.Hologram.config.errorOverlay = true;

      const error = new Error("my message");

      Hologram.handleUncaughtError(error);

      assert.equal(error.message, "my message");
      sinon.assert.notCalled(overlayShowStub);
    });
  });

  describe("queueActionsFromServerInits()", () => {
    const cid1 = Type.bitstring("component_1");
    const cid2 = Type.bitstring("component_2");
    const cid3 = Type.bitstring("component_3");
    const cid4 = Type.bitstring("component_4");
    const cid5 = Type.bitstring("component_5");
    const cid6 = Type.bitstring("component_6");

    const action1 = Type.actionStruct({
      name: Type.atom("action_1"),
      params: Type.map(),
      target: Type.bitstring("my_target_1"),
    });

    const action2 = Type.actionStruct({
      name: Type.atom("action_2"),
      params: Type.map([[Type.atom("my_param"), Type.integer(42)]]),
      target: Type.bitstring("my_target_2"),
    });

    const action3 = Type.actionStruct({
      name: Type.atom("action_3"),
      params: Type.map(),
      target: Type.nil(),
    });

    const action6 = Type.actionStruct({
      name: Type.atom("action_6"),
      params: Type.map(),
      target: Type.bitstring("my_target_6"),
    });

    const delayedAction = Type.actionStruct({
      name: Type.atom("delayed_action"),
      params: Type.map(),
      target: Type.nil(),
      delay: Type.integer(3000),
    });

    let entry1, entry2, entry3, entry4, entry5, entry6, delayedEntry;

    beforeEach(() => {
      ComponentRegistry.clear();
      ActionQueue.entries = [];

      entry1 = Type.map([
        [Type.atom("module"), Type.alias("Module1")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action1})],
      ]);

      entry2 = Type.map([
        [Type.atom("module"), Type.alias("Module2")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action2})],
      ]);

      entry3 = Type.map([
        [Type.atom("module"), Type.alias("Module3")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action3})],
      ]);

      entry4 = Type.map([
        [Type.atom("module"), Type.alias("Module4")],
        [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
      ]);

      entry5 = Type.map([
        [Type.atom("module"), Type.alias("Module5")],
        [Type.atom("struct"), Type.componentStruct({nextAction: Type.nil()})],
      ]);

      entry6 = Type.map([
        [Type.atom("module"), Type.alias("Module6")],
        [Type.atom("struct"), Type.componentStruct({nextAction: action6})],
      ]);

      delayedEntry = Type.map([
        [Type.atom("module"), Type.alias("DelayedModule")],
        [
          Type.atom("struct"),
          Type.componentStruct({nextAction: delayedAction}),
        ],
      ]);
    });

    // Nothing runs the queue in these tests, so what they enqueue would be ahead of the next
    // test's dispatch.
    afterEach(() => {
      ActionQueue.entries = [];
    });

    it("queues actions from all components that have next_action set", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, entry1],
        [cid2, entry2],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = ActionQueue.entries.map((entry) => entry.action);
      assert.equal(queuedActions.length, 2);

      assert.deepStrictEqual(queuedActions[0], action1);
      assert.deepStrictEqual(queuedActions[1], action2);
    });

    it("skips components that don't have next_action set", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, entry1],
        [cid4, entry4],
        [cid2, entry2],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = ActionQueue.entries.map((entry) => entry.action);
      assert.equal(queuedActions.length, 2);

      assert.deepStrictEqual(queuedActions[0], action1);
      assert.deepStrictEqual(queuedActions[1], action2);
    });

    it("handles empty component registry", () => {
      Hologram.queueActionsFromServerInits();

      const queuedActions = ActionQueue.entries.map((entry) => entry.action);
      assert.equal(queuedActions.length, 0);
    });

    it("handles component registry with only components without next_action", () => {
      ComponentRegistry.entries = Type.map([
        [cid4, entry4],
        [cid5, entry5],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = ActionQueue.entries.map((entry) => entry.action);
      assert.equal(queuedActions.length, 0);
    });

    it("preserves existing target when action already has one", () => {
      ComponentRegistry.entries = Type.map([[cid1, entry1]]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = ActionQueue.entries.map((entry) => entry.action);

      // Should not modify the action
      assert.deepStrictEqual(queuedActions[0], action1);

      assert.equal(ActionQueue.entries[0].epoch, Hologram.registryEpoch);
    });

    it("adds component ID as target when action has nil target", () => {
      ComponentRegistry.entries = Type.map([[cid3, entry3]]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = ActionQueue.entries.map((entry) => entry.action);

      const expectedAction = Erlang_Maps["put/3"](
        Type.atom("target"),
        cid3,
        action3,
      );

      assert.deepStrictEqual(queuedActions[0], expectedAction);
    });

    it("processes components in the order they appear in the registry", () => {
      ComponentRegistry.entries = Type.map([
        [cid2, entry2],
        [cid6, entry6],
        [cid1, entry1],
      ]);

      Hologram.queueActionsFromServerInits();

      const queuedActions = ActionQueue.entries.map((entry) => entry.action);
      assert.equal(queuedActions.length, 3);

      assert.deepStrictEqual(queuedActions[0], action2);
      assert.deepStrictEqual(queuedActions[1], action6);
      assert.deepStrictEqual(queuedActions[2], action1);
    });

    it("clears next_action from the component struct in the registry after queueing", () => {
      ComponentRegistry.entries = Type.map([
        [cid1, entry1],
        [cid3, entry3],
      ]);

      Hologram.queueActionsFromServerInits();

      const struct1 = ComponentRegistry.getComponentStruct(cid1);
      const struct3 = ComponentRegistry.getComponentStruct(cid3);

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("next_action"), struct1),
        Type.nil(),
      );

      assert.deepStrictEqual(
        Erlang_Maps["get/2"](Type.atom("next_action"), struct3),
        Type.nil(),
      );
    });

    // A delay in init/3 means "this long after the mount", and an entry runs as soon as it can.
    it("schedules a delayed action instead of queueing it", () => {
      const scheduleActionStub = sinon.stub(Hologram, "scheduleAction");

      try {
        ComponentRegistry.entries = Type.map([[cid1, delayedEntry]]);

        Hologram.queueActionsFromServerInits();

        const expectedAction = Erlang_Maps["put/3"](
          Type.atom("target"),
          cid1,
          delayedAction,
        );

        sinon.assert.calledOnceWithExactly(
          scheduleActionStub,
          expectedAction,
          Hologram.registryEpoch,
        );

        assert.deepStrictEqual(ActionQueue.entries, []);
      } finally {
        scheduleActionStub.restore();
      }
    });
  });

  describe("queueSelfEchoes()", () => {
    const action1 = Type.actionStruct({
      name: Type.atom("self_echo_a"),
      params: Type.map(),
      target: Type.bitstring("page"),
    });

    const action2 = Type.actionStruct({
      name: Type.atom("self_echo_b"),
      params: Type.map([[Type.atom("text"), Type.bitstring("hi")]]),
      target: Type.bitstring("page"),
    });

    beforeEach(() => {
      ActionQueue.entries = [];
    });

    // Nothing runs the queue in these tests, so what they enqueue would be ahead of the next
    // test's dispatch.
    afterEach(() => {
      ActionQueue.entries = [];
    });

    it("does not enqueue anything when the list is empty", () => {
      Hologram.queueSelfEchoes(Type.list([]));

      assert.deepStrictEqual(ActionQueue.entries, []);
    });

    it("enqueues each action in order, stamped with the page the registry answers for", () => {
      Hologram.queueSelfEchoes(Type.list([action1, action2]));

      assert.deepStrictEqual(ActionQueue.entries, [
        {action: action1, epoch: Hologram.registryEpoch},
        {action: action2, epoch: Hologram.registryEpoch},
      ]);
    });

    it("schedules a delayed self echo instead of queueing it", () => {
      const scheduleActionStub = sinon.stub(Hologram, "scheduleAction");

      const delayedAction = Type.actionStruct({
        name: Type.atom("delayed_self_echo"),
        params: Type.map(),
        target: Type.bitstring("page"),
        delay: Type.integer(3000),
      });

      try {
        Hologram.queueSelfEchoes(Type.list([action1, delayedAction]));

        sinon.assert.calledOnceWithExactly(
          scheduleActionStub,
          delayedAction,
          Hologram.registryEpoch,
        );

        assert.deepStrictEqual(ActionQueue.entries, [
          {action: action1, epoch: Hologram.registryEpoch},
        ]);
      } finally {
        scheduleActionStub.restore();
      }
    });
  });

  describe("readBootData()", () => {
    const fieldNames = [
      "assetManifest",
      "csrfToken",
      "initialChunkDigests",
      "initialPageDigest",
      "instanceId",
    ];

    let originalFields;

    const bootDataJson = (instanceId) =>
      JSON.stringify({
        assetManifest: {"hologram/runtime.js": "/hologram/runtime-AAAA.js"},
        chunks: ["CCCCCCCC"],
        csrfToken: "my_csrf_token",
        instanceId: instanceId,
        pageDigest: "my_page_digest",
      });

    const appendBlock = (instanceId, nonce = null, extraAttrs = {}) => {
      const block = document.createElement("script");
      block.type = "application/json";
      block.id = "hologram-boot-data";

      if (nonce !== null) {
        block.nonce = nonce;
      }

      for (const [name, value] of Object.entries(extraAttrs)) {
        block.setAttribute(name, value);
      }

      block.textContent = bootDataJson(instanceId);
      document.body.appendChild(block);
    };

    beforeEach(() => {
      originalFields = Object.fromEntries(
        fieldNames.map((name) => [name, globalThis.Hologram[name]]),
      );
    });

    afterEach(() => {
      document
        .querySelectorAll("#hologram-boot-data")
        .forEach((block) => block.remove());

      // With no block left, a read holds no boot data, so none leaks into a later test.
      Hologram.readBootData();

      for (const name of fieldNames) {
        globalThis.Hologram[name] = originalFields[name];
      }

      App.cspNonce = null;
    });

    it("puts the block's plain fields where the runtime reads them", () => {
      App.cspNonce = "my_nonce";
      appendBlock("my_instance_id", "my_nonce");

      Hologram.readBootData();

      assert.deepStrictEqual(globalThis.Hologram.assetManifest, {
        "hologram/runtime.js": "/hologram/runtime-AAAA.js",
      });

      assert.equal(globalThis.Hologram.csrfToken, "my_csrf_token");

      assert.deepStrictEqual(globalThis.Hologram.initialChunkDigests, [
        "CCCCCCCC",
      ]);

      assert.equal(globalThis.Hologram.initialPageDigest, "my_page_digest");
      assert.equal(globalThis.Hologram.instanceId, "my_instance_id");
    });

    it("passes over a block without the document's nonce in favor of the one with it", () => {
      App.cspNonce = "my_nonce";
      appendBlock("forged_instance_id", "other_nonce");
      appendBlock("my_instance_id", "my_nonce");

      Hologram.readBootData();

      assert.equal(globalThis.Hologram.instanceId, "my_instance_id");
    });

    it("passes over a block whose attributes hold an absorbed script tag", () => {
      App.cspNonce = "my_nonce";
      appendBlock("forged_instance_id", "my_nonce", {
        "data-x": '<script id="a"',
      });
      appendBlock("my_instance_id", "my_nonce");

      Hologram.readBootData();

      assert.equal(globalThis.Hologram.instanceId, "my_instance_id");
    });

    it("passes over a block whose attributes hold an absorbed style tag, whatever its case", () => {
      App.cspNonce = "my_nonce";
      appendBlock("forged_instance_id", "my_nonce", {"data-x": "<STYLE>"});
      appendBlock("my_instance_id", "my_nonce");

      Hologram.readBootData();

      assert.equal(globalThis.Hologram.instanceId, "my_instance_id");
    });

    it("throws when no block carries the document's nonce", () => {
      App.cspNonce = "my_nonce";
      appendBlock("forged_instance_id", "other_nonce");

      assert.throws(
        () => Hologram.readBootData(),
        HologramRuntimeError,
        "The page's boot data could not be read: no boot data block carries the document's nonce",
      );
    });

    it("takes the one block there is in a document without a nonce", () => {
      appendBlock("my_instance_id");

      Hologram.readBootData();

      assert.equal(globalThis.Hologram.instanceId, "my_instance_id");
    });

    it("sets nothing in a document with no block", () => {
      globalThis.Hologram.instanceId = "untouched";

      Hologram.readBootData();

      assert.equal(globalThis.Hologram.instanceId, "untouched");
    });
  });

  describe("render()", () => {
    let clock = null;

    const deferredAction1 = Type.actionStruct({
      name: Type.atom("deferred_action_1"),
      params: Type.map(),
      target: cid1,
    });

    const deferredAction2 = Type.actionStruct({
      name: Type.atom("deferred_action_2"),
      params: Type.map(),
      target: cid1,
    });

    afterEach(() => {
      clock?.restore();
      clock = null;
      ActionQueue.entries = [];
      Hologram.isMounting = false;
      Hologram.isPageShown = false;
      Hologram.isRendering = false;
      Hologram.virtualDocument = null;
      Renderer.isPageArrival = false;
      Renderer.listenerBindings = [];
      Renderer.resetFocusCandidates();
      sinon.restore();
    });

    // The seam for a dispatch that arrives from inside the patch: a scheduled action whose timer
    // is fired by hand while the patch stub is on the stack, which is where a focusout flush
    // reaches the queue in a real page.
    const stubRender = (patchFake) => {
      clock = sinon.useFakeTimers();

      sinon.stub(Renderer, "renderPage").returns({
        sel: "html",
        data: {},
        children: [],
      });

      sinon.stub(EventListenerRegistry, "reconcile");
      sinon.stub(EventListeners, "recheckScrollEdges");
      sinon.stub(Vdom, "patchVirtualDocument").callsFake(patchFake);

      Hologram.virtualDocument = {sel: "html", data: {}, children: []};
    };

    it("reconciles the global and resolved observer bindings collected during the render", () => {
      const listenerBindings = [
        {target: window, eventName: "keydown", handler: () => {}},
      ];

      const reachBinding = {
        target: {},
        key: "scroll-edge:bottom",
        attach: () => {},
        handler: () => {},
      };

      // renderPage() collects the page's <window>/<document> bindings into Renderer.listenerBindings.
      sinon.stub(Renderer, "renderPage").callsFake(() => {
        Renderer.listenerBindings = listenerBindings;
        return {sel: "html", data: {}, children: []};
      });

      // Observer bindings are resolved from their patched elements right before reconciliation.
      sinon.stub(Renderer, "resolveReachBindings").returns([reachBinding]);

      sinon.stub(Vdom, "patchVirtualDocument");
      const reconcileStub = sinon.stub(EventListenerRegistry, "reconcile");
      const recheckStub = sinon.stub(EventListeners, "recheckScrollEdges");

      Hologram.render();

      sinon.assert.calledOnceWithExactly(reconcileStub, [
        ...listenerBindings,
        reachBinding,
      ]);

      // Reach listeners persist, so each is rechecked after reconcile to re-sync and auto-fill.
      sinon.assert.calledOnce(recheckStub);
      sinon.assert.callOrder(reconcileStub, recheckStub);
    });

    // A full document load has no previous render to diff against, only the page the server sent,
    // so the old side is this render mirrored onto it. Reading the page into a vdom of its own
    // instead would describe it in terms the render never uses, and every node would be rebuilt.
    it("seeds the first render by mirroring it onto the page the server sent", () => {
      const renderedVirtualDocument = {sel: "html", data: {}, children: []};
      const mirroredVirtualDocument = {sel: "html", data: {}, children: []};

      sinon.stub(Renderer, "renderPage").returns(renderedVirtualDocument);
      const mirrorStub = sinon
        .stub(Vdom, "mirror")
        .returns(mirroredVirtualDocument);
      const patchStub = sinon.stub(Vdom, "patchVirtualDocument");

      Hologram.virtualDocument = null;

      Hologram.render();

      sinon.assert.calledOnceWithExactly(
        mirrorStub,
        renderedVirtualDocument,
        document.documentElement,
      );

      sinon.assert.calledOnceWithExactly(
        patchStub,
        mirroredVirtualDocument,
        renderedVirtualDocument,
      );
    });

    it("leaves a render that has a previous one to diff against alone", () => {
      const previousVirtualDocument = {sel: "html", data: {}, children: []};
      const renderedVirtualDocument = {sel: "html", data: {}, children: []};

      sinon.stub(Renderer, "renderPage").returns(renderedVirtualDocument);
      const mirrorStub = sinon.stub(Vdom, "mirror");
      const patchStub = sinon.stub(Vdom, "patchVirtualDocument");

      Hologram.virtualDocument = previousVirtualDocument;

      Hologram.render();

      sinon.assert.notCalled(mirrorStub);

      sinon.assert.calledOnceWithExactly(
        patchStub,
        previousVirtualDocument,
        renderedVirtualDocument,
      );
    });

    describe("focus", () => {
      const renderedVirtualDocument = {sel: "html", data: {}, children: []};

      let patchStub, resetStub, settleStub;

      beforeEach(() => {
        sinon.stub(Renderer, "renderPage").returns(renderedVirtualDocument);
        sinon.stub(EventListenerRegistry, "reconcile");
        sinon.stub(EventListeners, "recheckScrollEdges");

        patchStub = sinon.stub(Vdom, "patchVirtualDocument");
        resetStub = sinon.stub(Renderer, "resetFocusCandidates");
        settleStub = sinon.stub(Renderer, "settleFocus");

        Hologram.virtualDocument = {sel: "html", data: {}, children: []};
      });

      it("resets the candidates before the patch and settles them after it", () => {
        Hologram.render();

        sinon.assert.callOrder(resetStub, patchStub, settleStub);
        sinon.assert.calledOnceWithExactly(settleStub, false);
      });

      it("settles nothing on the boot render", () => {
        sinon
          .stub(Vdom, "mirror")
          .returns({sel: "html", data: {}, children: []});
        Hologram.virtualDocument = null;

        Hologram.render();

        sinon.assert.calledOnceWithExactly(settleStub, true);
      });

      // The focus and blur events a settled focus fires dispatch into the queue, which has to
      // hold them until the render is done, the way it holds a focusout the patch causes.
      it("settles focus while the render flag is still set", () => {
        let isRenderingDuringSettle = null;

        settleStub.callsFake(() => {
          isRenderingDuringSettle = Hologram.isRendering;
        });

        Hologram.render();

        assert.isTrue(isRenderingDuringSettle);
      });

      // A history restore has no interim patch: the left page stays up until this render, so
      // this render is where the page appears.
      it("patches a mount with no page shown before it as a page arrival", () => {
        let isPageArrivalDuringPatch = null;

        patchStub.callsFake(() => {
          isPageArrivalDuringPatch = Renderer.isPageArrival;
          return Hologram.virtualDocument;
        });

        Hologram.isMounting = true;

        Hologram.render();

        assert.isTrue(isPageArrivalDuringPatch);
      });

      // The interim patch of the navigation put the page on screen and settled its focus.
      it("patches a mount after a shown page as an ordinary render", () => {
        let isPageArrivalDuringPatch = null;

        patchStub.callsFake(() => {
          isPageArrivalDuringPatch = Renderer.isPageArrival;
          return Hologram.virtualDocument;
        });

        Hologram.isMounting = true;
        Hologram.isPageShown = true;

        Hologram.render();

        assert.isFalse(isPageArrivalDuringPatch);
      });

      it("patches the boot render as an ordinary render", () => {
        let isPageArrivalDuringPatch = null;

        sinon
          .stub(Vdom, "mirror")
          .returns({sel: "html", data: {}, children: []});
        Hologram.virtualDocument = null;

        patchStub.callsFake(() => {
          isPageArrivalDuringPatch = Renderer.isPageArrival;
          return {sel: "html", data: {}, children: []};
        });

        Hologram.isMounting = true;

        Hologram.render();

        assert.isFalse(isPageArrivalDuringPatch);
      });

      it("patches a render that is no mount as an ordinary render", () => {
        let isPageArrivalDuringPatch = null;

        patchStub.callsFake(() => {
          isPageArrivalDuringPatch = Renderer.isPageArrival;
          return Hologram.virtualDocument;
        });

        Hologram.render();

        assert.isFalse(isPageArrivalDuringPatch);
      });
    });

    // A dispatch arriving while the flag is set has to wait for the render to finish, so the flag
    // has to be set for the whole of the render and cleared by the time it returns.
    it("marks itself as running while it patches", () => {
      const renderedVirtualDocument = {sel: "html", data: {}, children: []};

      sinon.stub(Renderer, "renderPage").returns(renderedVirtualDocument);
      sinon.stub(EventListenerRegistry, "reconcile");
      sinon.stub(EventListeners, "recheckScrollEdges");

      let isRenderingDuringPatch = null;

      sinon.stub(Vdom, "patchVirtualDocument").callsFake(() => {
        isRenderingDuringPatch = Hologram.isRendering;
      });

      Hologram.virtualDocument = {sel: "html", data: {}, children: []};

      Hologram.render();

      assert.isTrue(isRenderingDuringPatch);
      assert.isFalse(Hologram.isRendering);
    });

    // A page's template expressions are app code and can raise. A render that died with the flag
    // still set would leave every dispatch after it waiting for a render that had already ended.
    it("stops marking itself as running when the render raises", () => {
      sinon.stub(Renderer, "renderPage").throws(new Error("render failed"));

      assert.throws(() => Hologram.render(), Error, "render failed");

      assert.isFalse(Hologram.isRendering);
    });

    // An undelayed dispatch settles synchronously, so one arriving from inside the patch would
    // otherwise run there and render into the tree the patch is walking.
    it("holds a dispatch that arrives while it is running, and runs it once it is done", () => {
      const calls = [];

      sinon
        .stub(Hologram, "executeAction")
        .callsFake(() => calls.push("execute action"));

      stubRender(() => {
        Hologram.scheduleAction(deferredAction1);
        clock.tick(0);
        calls.push("finish patch");
      });

      Hologram.render();

      assert.deepStrictEqual(calls, ["finish patch", "execute action"]);
    });

    it("runs waiting dispatches in the order they arrived", () => {
      const executeActionStub = sinon.stub(Hologram, "executeAction");

      stubRender(() => {
        Hologram.scheduleAction(deferredAction1);
        Hologram.scheduleAction(deferredAction2);
        clock.tick(0);
      });

      Hologram.render();

      sinon.assert.calledTwice(executeActionStub);

      assert.deepStrictEqual(executeActionStub.getCall(0).args, [
        deferredAction1,
        0,
      ]);

      assert.deepStrictEqual(executeActionStub.getCall(1).args, [
        deferredAction2,
        0,
      ]);
    });

    // A single focusout flushes every pending slot on the element at once, so a queue of several
    // is the ordinary case and they have nothing to do with one another - the same bargain the
    // debouncer makes with the callbacks it flushes.
    it("delivers every waiting dispatch when one of them raises, and raises the first error", () => {
      const executed = [];

      sinon.stub(Hologram, "executeAction").callsFake((action) => {
        executed.push(action);

        if (action === deferredAction1) {
          throw new Error("action failed");
        }
      });

      stubRender(() => {
        Hologram.scheduleAction(deferredAction1);
        Hologram.scheduleAction(deferredAction2);
        clock.tick(0);
      });

      assert.throws(() => Hologram.render(), Error, "action failed");

      assert.deepStrictEqual(executed, [deferredAction1, deferredAction2]);
    });

    // A render that raised left the DOM and the virtual document describing different pages, so
    // running the queue against that repairs nothing. It waits for a render that finishes.
    it("keeps a waiting dispatch when the render raises, and runs it on the next render", () => {
      const executeActionStub = sinon.stub(Hologram, "executeAction");

      let patchCount = 0;

      stubRender(() => {
        patchCount += 1;

        if (patchCount === 1) {
          Hologram.scheduleAction(deferredAction1);
          clock.tick(0);
        }
      });

      let reconcileCount = 0;

      // The reconcile runs after the patch, so the dispatch is already held when this raises.
      EventListenerRegistry.reconcile.callsFake(() => {
        reconcileCount += 1;

        if (reconcileCount === 1) {
          throw new Error("reconcile failed");
        }
      });

      assert.throws(() => Hologram.render(), Error, "reconcile failed");

      sinon.assert.notCalled(executeActionStub);

      Hologram.render();

      sinon.assert.calledOnceWithExactly(executeActionStub, deferredAction1, 0);
    });
  });

  describe("requestChunks()", () => {
    const chunkScripts = () =>
      Array.from(
        document.head.querySelectorAll("script[src^='/hologram/chunk-']"),
      );

    afterEach(() => {
      chunkScripts().forEach((script) => script.remove());
      ScriptRegistry.statuses.clear();
    });

    it("fetches each chunk from the path its digest names", () => {
      Hologram.requestChunks(["AAAAAAAA", "BBBBBBBB"]);

      assert.deepStrictEqual(
        chunkScripts().map((script) => script.getAttribute("src")),
        ["/hologram/chunk-AAAAAAAA.js", "/hologram/chunk-BBBBBBBB.js"],
      );

      assert.deepStrictEqual(Array.from(ScriptRegistry.statuses), [
        ["AAAAAAAA", "requested"],
        ["BBBBBBBB", "requested"],
      ]);
    });

    it("passes over a chunk the tab has", () => {
      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");

      Hologram.requestChunks(["AAAAAAAA"]);

      assert.deepStrictEqual(chunkScripts(), []);
    });

    it("raises when a chunk fails to load", () => {
      Hologram.requestChunks(["AAAAAAAA"]);

      const [script] = chunkScripts();

      assert.throws(
        () => script.onerror(),
        HologramRuntimeError,
        "Failed to load script: /hologram/chunk-AAAAAAAA.js",
      );

      assert.equal(ScriptRegistry.statuses.get("AAAAAAAA"), "failed");
    });
  });

  describe("scheduleAction()", () => {
    let clock, executeActionStub;

    const action1 = Type.actionStruct({
      name: Type.atom("test_action"),
      params: Type.map(),
      target: cid1,
    });

    beforeEach(() => {
      clock = sinon.useFakeTimers();

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake((_action) => null);
    });

    afterEach(() => {
      clock.restore();
      sinon.restore();
    });

    it("schedules action execution with setTimeout and 0 delay", () => {
      // Before scheduling, executeAction should not have been called
      sinon.assert.notCalled(executeActionStub);

      Hologram.scheduleAction(action1);

      // Action should not execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Advance time by 0ms to trigger setTimeout callback
      clock.tick(0);

      // Now the action should have been executed
      sinon.assert.calledOnceWithExactly(executeActionStub, action1, 0);
    });

    // The ordinary case: nothing is in flight, so the page on screen is the page the registry
    // answers for and the action it carries resolves against it.
    it("executes an action stamped with the current stable epoch", () => {
      Hologram.scheduleAction(action1);
      clock.tick(0);

      sinon.assert.calledOnceWithExactly(executeActionStub, action1, 0);
    });

    // The shape a history restoration leaves behind: the registry has moved on while the page the
    // action came from is still on screen, so the page it was aimed at is already gone.
    it("drops an action stamped below the current epoch", () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.registryEpoch = 1;

        Hologram.scheduleAction(action1, 0);
        clock.tick(0);

        sinon.assert.notCalled(executeActionStub);
        sinon.assert.calledOnce(warnStub);
      } finally {
        Hologram.registryEpoch = 0;
        warnStub.restore();
      }
    });

    it("schedules multiple actions independently", () => {
      const action2 = Type.actionStruct({
        name: Type.atom("test_action_2"),
        params: Type.map(),
        target: Type.bitstring("component_2"),
      });

      Hologram.scheduleAction(action1);
      Hologram.scheduleAction(action2);

      // Neither should execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Both should execute after time advancement
      clock.tick(0);

      sinon.assert.calledTwice(executeActionStub);
      sinon.assert.calledWith(executeActionStub.getCall(0), action1, 0);
      sinon.assert.calledWith(executeActionStub.getCall(1), action2, 0);
    });

    it("schedules action execution with custom delay", () => {
      const actionWithDelay = Type.actionStruct({
        name: Type.atom("test_action_with_delay"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(500),
      });

      sinon.assert.notCalled(executeActionStub);

      Hologram.scheduleAction(actionWithDelay);

      // Action should not execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Action should not execute after short delay
      clock.tick(100);
      sinon.assert.notCalled(executeActionStub);

      // Action should execute after specified delay
      clock.tick(400);
      sinon.assert.calledOnceWithExactly(executeActionStub, actionWithDelay, 0);
    });

    it("schedules multiple actions with different delays in correct order", () => {
      const actionDelayed100 = Type.actionStruct({
        name: Type.atom("action_100ms"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(100),
      });

      const actionDelayed300 = Type.actionStruct({
        name: Type.atom("action_300ms"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(300),
      });

      Hologram.scheduleAction(actionDelayed300);
      Hologram.scheduleAction(actionDelayed100);

      // Neither should execute immediately
      sinon.assert.notCalled(executeActionStub);

      // After 100ms, only the first action should execute
      clock.tick(100);
      sinon.assert.calledOnceWithExactly(
        executeActionStub,
        actionDelayed100,
        0,
      );

      // After another 200ms (total 300ms), the second action should execute
      clock.tick(200);
      sinon.assert.calledTwice(executeActionStub);
      sinon.assert.calledWith(
        executeActionStub.getCall(1),
        actionDelayed300,
        0,
      );
    });

    it("handles action with zero delay same as no delay specified", () => {
      const actionZeroDelay = Type.actionStruct({
        name: Type.atom("test_action_zero_delay"),
        params: Type.map(),
        target: cid1,
        delay: Type.integer(0),
      });

      Hologram.scheduleAction(actionZeroDelay);

      // Action should not execute immediately
      sinon.assert.notCalled(executeActionStub);

      // Action should execute after 0ms timeout
      clock.tick(0);
      sinon.assert.calledOnceWithExactly(executeActionStub, actionZeroDelay, 0);
    });
  });

  describe("schedulePushedAction()", () => {
    let originalRegistryEpoch, scheduleActionStub;

    const action = Type.actionStruct({
      name: Type.atom("pushed_action"),
      params: Type.map(),
      target: cid1,
    });

    const chunkScripts = () =>
      Array.from(
        document.head.querySelectorAll("script[src^='/hologram/chunk-']"),
      );

    // Lets the continuations of the promises settled so far run.
    const flushPromises = () =>
      new Promise((resolve) => setTimeout(resolve, 0));

    const announce = (digest) => {
      globalThis.Hologram.pendingScripts = [
        {define: () => null, digest: digest},
      ];
      ScriptRegistry.defineLoaded({});
    };

    beforeEach(() => {
      originalRegistryEpoch = Hologram.registryEpoch;
      Hologram.registryEpoch = 3;

      scheduleActionStub = sinon.stub(Hologram, "scheduleAction");
    });

    afterEach(() => {
      Hologram.registryEpoch = originalRegistryEpoch;
      scheduleActionStub.restore();

      chunkScripts().forEach((script) => script.remove());
      ScriptRegistry.statuses.clear();
      ScriptRegistry.waiters = [];
      delete globalThis.Hologram.pendingScripts;
    });

    it("fetches the chunks the tab lacks", () => {
      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");

      Hologram.schedulePushedAction(action, ["AAAAAAAA", "BBBBBBBB"]);

      assert.deepStrictEqual(
        chunkScripts().map((script) => script.getAttribute("src")),
        ["/hologram/chunk-BBBBBBBB.js"],
      );
    });

    it("schedules the action at once when it needs no chunk", () => {
      Hologram.schedulePushedAction(action, []);

      sinon.assert.calledOnceWithExactly(scheduleActionStub, action, 3);
    });

    it("schedules the action at once when the tab has its chunks", () => {
      ScriptRegistry.statuses.set("AAAAAAAA", "loaded");

      Hologram.schedulePushedAction(action, ["AAAAAAAA"]);

      sinon.assert.calledOnceWithExactly(scheduleActionStub, action, 3);
      assert.deepStrictEqual(chunkScripts(), []);
    });

    // A navigation while the chunk is fetched must leave the action stamped with the page it was
    // sent to, so that the queue drops it as stale.
    it("schedules the action once its chunks have loaded, stamped with the epoch it arrived in", async () => {
      Hologram.schedulePushedAction(action, ["AAAAAAAA", "BBBBBBBB"]);
      Hologram.registryEpoch = 4;

      announce("AAAAAAAA");
      await flushPromises();

      sinon.assert.notCalled(scheduleActionStub);

      announce("BBBBBBBB");
      await flushPromises();

      sinon.assert.calledOnceWithExactly(scheduleActionStub, action, 3);
    });

    // A command reply names the page the command was sent from, which the registry may have
    // moved past by the time the reply arrives.
    it("schedules the action with the epoch it is given", () => {
      Hologram.schedulePushedAction(action, [], 7);

      sinon.assert.calledOnceWithExactly(scheduleActionStub, action, 7);
    });

    it("schedules the action once its chunks have loaded, stamped with the epoch it is given", async () => {
      Hologram.schedulePushedAction(action, ["AAAAAAAA"], 7);
      Hologram.registryEpoch = 4;

      announce("AAAAAAAA");
      await flushPromises();

      sinon.assert.calledOnceWithExactly(scheduleActionStub, action, 7);
    });

    it("drops the action, and says so, when one of its chunks fails to load", async () => {
      const warnStub = sinon.stub(console, "warn");

      try {
        Hologram.schedulePushedAction(action, ["AAAAAAAA"]);

        const [script] = chunkScripts();

        assert.throws(() => script.onerror(), HologramRuntimeError);
        await flushPromises();

        sinon.assert.notCalled(scheduleActionStub);

        sinon.assert.calledOnceWithExactly(
          warnStub,
          "Hologram: dropped a pushed action whose chunk failed to load:",
          ":pushed_action",
          "AAAAAAAA",
        );
      } finally {
        warnStub.restore();
      }
    });
  });
});
