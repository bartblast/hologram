"use strict";

import {assert, sinon, waitForEventLoop} from "./support/helpers.mjs";

import Tabs from "../../assets/js/tabs.mjs";

// Node's own BroadcastChannel, made to work under jsdom - it does not otherwise, and the reason is
// worth knowing before anyone treats this as decoration.
//
// Node builds the message event out of whatever `Event` is GLOBAL when its messaging internals
// first load, which under `jsdom-global` is jsdom's Event rather than its own - and its dispatch
// then refuses the very event it just built ("The 'event' argument must be an instance of Event.
// Received an instance of MessageEvent"). Taking the lock works, delivering a message does not.
//
// So Node's own Event is put back for exactly as long as it takes ONE MESSAGE to be delivered,
// which is the moment those internals build that class and keep it; afterwards jsdom's Event goes
// back and every later channel - in this file and in any other - delivers. A channel merely opened
// is not enough: the class is built when a message first arrives, so the warm-up has to complete a
// round trip. Node's Event is reached through an abort event, since nothing exports the class and
// jsdom has replaced the global.
//
// The alternative was a stand-in of our own, and this suite is about using the browser's real
// election and the browser's real channel correctly, so there is nothing a stand-in could say here.
const nodeEvent = await new Promise((resolve) => {
  const controller = new AbortController();

  controller.signal.addEventListener("abort", (event) =>
    resolve(event.constructor),
  );
  controller.abort();
});

const jsdomEvent = globalThis.Event;

globalThis.Event = nodeEvent;

await new Promise((resolve) => {
  const speaking = new BroadcastChannel("hologram.warmup");
  const listening = new BroadcastChannel("hologram.warmup");

  listening.onmessage = () => {
    speaking.close();
    listening.close();

    resolve();
  };

  speaking.postMessage(0);
});

globalThis.Event = jsdomEvent;

// The other tabs of the group are real: a Web Lock taken the way another tab would take it, and a
// BroadcastChannel of the same name. Nothing here stands in for the browser, because what this
// module claims is that it uses the browser's own election correctly.
describe("Tabs", () => {
  let groupCount = 0;
  let openChannels;
  let releases;

  // A group of its own per test. Locks and channels are named per process here exactly as they are
  // named per origin in a browser, so a lock one test leaves held would otherwise decide what the
  // next one sees.
  const nextGroup = () => `hologram.1.model-${++groupCount}.anonymous`;

  // Takes the group's lock the way another tab would, and answers what lets it go. Waits for the
  // grant, so a test that follows knows the lock is really taken rather than merely asked for.
  const holdLeaderLock = async (group) => {
    let granted;
    let release;

    const held = new Promise((resolve) => {
      release = resolve;
    });

    const isGranted = new Promise((resolve) => {
      granted = resolve;
    });

    navigator.locks.request(`${group}.leader`, () => {
      granted();

      return held;
    });

    await isGranted;
    releases.push(release);

    return release;
  };

  const isLockFree = (group) =>
    navigator.locks.request(
      `${group}.leader`,
      {ifAvailable: true},
      (lock) => lock !== null,
    );

  const sibling = (group) => {
    const channel = new BroadcastChannel(group);

    openChannels.push(channel);

    return channel;
  };

  const stubs = () => ({onLead: () => {}, onMessage: () => {}});

  beforeEach(() => {
    openChannels = [];
    releases = [];
  });

  afterEach(async () => {
    await Tabs.leave();

    releases.forEach((release) => release());
    openChannels.forEach((channel) => channel.close());
  });

  describe("join()", () => {
    it("leads when nobody holds the group's lock", async () => {
      assert.isTrue(await Tabs.join(nextGroup(), stubs()));
      assert.isTrue(Tabs.leader);
    });

    it("follows when another tab holds it", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);

      assert.isFalse(await Tabs.join(group, stubs()));
      assert.isFalse(Tabs.leader);
    });

    it("takes the lead when the holder lets go", async () => {
      const group = nextGroup();
      const release = await holdLeaderLock(group);

      let led;

      const hasLed = new Promise((resolve) => {
        led = resolve;
      });

      await Tabs.join(group, {onLead: led, onMessage: () => {}});

      release();
      await hasLed;

      assert.isTrue(Tabs.leader);
    });

    it("names the group it joined", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());

      assert.equal(Tabs.name, group);
    });

    it("hands a sibling's message to the handler it was given", async () => {
      const group = nextGroup();

      let received;

      const hasReceived = new Promise((resolve) => {
        received = resolve;
      });

      await Tabs.join(group, {onLead: () => {}, onMessage: received});

      sibling(group).postMessage({kind: "state"});

      assert.deepStrictEqual(await hasReceived, {kind: "state"});
    });
  });

  describe("leave()", () => {
    it("releases the lock so another tab can take it", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());
      await Tabs.leave();

      assert.isTrue(await isLockFree(group));
    });

    it("leads itself afterwards", async () => {
      const group = nextGroup();

      await holdLeaderLock(group);
      await Tabs.join(group, stubs());
      await Tabs.leave();

      assert.isTrue(Tabs.leader);
      assert.isNull(Tabs.name);
    });

    // A tab that leaves while waiting is granted the lock eventually anyway, and what it does with
    // that grant has to be nothing - it belongs to a group this tab is no longer in.
    it("does not take the lead of the group it joined next", async () => {
      const left = nextGroup();
      const joined = nextGroup();
      const release = await holdLeaderLock(left);

      await Tabs.join(left, stubs());
      await Tabs.leave();

      const led = sinon.spy();

      await holdLeaderLock(joined);
      await Tabs.join(joined, {onLead: led, onMessage: () => {}});

      release();
      await waitForEventLoop();

      assert.isFalse(led.called);
      assert.isFalse(Tabs.leader);
    });
  });

  describe("post()", () => {
    it("reaches a tab listening on the group's channel", async () => {
      const group = nextGroup();

      await Tabs.join(group, stubs());

      let received;

      const hasReceived = new Promise((resolve) => {
        received = resolve;
      });

      sibling(group).onmessage = (event) => received(event.data);

      Tabs.post({kind: "joined"});

      assert.deepStrictEqual(await hasReceived, {kind: "joined"});
    });

    it("says nothing outside a group", () => {
      assert.doesNotThrow(() => Tabs.post({kind: "joined"}));
    });
  });
});
