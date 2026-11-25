"use strict";

import App from "./app.mjs";
import Bitstring from "./bitstring.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Config from "./config.mjs";
import Connection from "./connection.mjs";
import Deserializer from "./deserializer.mjs";
import Hologram from "./hologram.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import HttpTransport from "./http_transport.mjs";
import IdentityTracker from "./identity_tracker.mjs";
import Interpreter from "./interpreter.mjs";
import Serializer from "./serializer.mjs";
import Type from "./type.mjs";

export default class Client {
  // How long to wait before each question in settleIdentity. They add up to about four seconds,
  // which a login's response can take to arrive after the stream has announced it.
  static IDENTITY_ASK_DELAYS_MS = [0, 100, 250, 500, 1000, 2000];

  static #identitySettling = null;

  // Deps: [:maps.get/2]
  static buildCommandPayload(command) {
    const target = Erlang_Maps["get/2"](Type.atom("target"), command);

    if (!ComponentRegistry.isCidRegistered(target)) {
      const message = `invalid command target, there is no component with CID: ${Interpreter.inspect(target)}`;
      throw new HologramRuntimeError(message);
    }

    const module = ComponentRegistry.getComponentModule(target);

    // Sent so the server can read this tab's subscriptions from signed receipts rather
    // than from its own node's registry, which holds nothing when the command lands on
    // a node that does not hold the connection.
    const subReceipts = Array.from(
      App.subscriptionReceiptRegistry.entries.values(),
    ).map((triple) => triple.data[2]);

    return Type.map([
      [Type.atom("instance_id"), Type.bitstring(App.instanceId)],
      [Type.atom("module"), module],
      [Type.atom("name"), Erlang_Maps["get/2"](Type.atom("name"), command)],
      [Type.atom("params"), Erlang_Maps["get/2"](Type.atom("params"), command)],
      [Type.atom("sub_receipts"), Type.list(subReceipts)],
      [Type.atom("target"), target],
    ]);
  }

  static buildPageQueryString(params) {
    if (Type.isList(params)) {
      params = Type.map(
        params.data.map((param) => [param.data[0], param.data[1]]),
      );
    }

    let queryParts = [];

    Object.values(params.data).forEach((param) => {
      const key = param[0];

      if (key.type !== "atom") {
        throw new HologramRuntimeError(
          `invalid param key type (only atom type is allowed), got: ${Interpreter.inspect(key)}`,
        );
      }

      const value = param[1];

      if (
        value.type !== "atom" &&
        value.type !== "float" &&
        value.type !== "integer" &&
        !Type.isBinary(value)
      ) {
        throw new HologramRuntimeError(
          `invalid param value type (only atom, float, integer and string types are allowed), got: ${Interpreter.inspect(value)}`,
        );
      }

      const encodedKey = encodeURIComponent(key.value);

      const rawValue = Type.isBitstring(value)
        ? Bitstring.toText(value)
        : value.value.toString();

      const encodedValue = encodeURIComponent(rawValue);

      queryParts.push(`${encodedKey}=${encodedValue}`);
    });

    return queryParts.length > 0 ? `?${queryParts.join("&")}` : "";
  }

  static buildPageRequestPayload() {
    const clientClaimedSubKeys = Array.from(
      App.subscriptionReceiptRegistry.entries.values(),
    ).map((triple) => Type.tuple([triple.data[0], triple.data[1]]));

    return Type.map([
      [Type.atom("client_claimed_sub_keys"), Type.list(clientClaimedSubKeys)],
      [Type.atom("instance_id"), Type.bitstring(App.instanceId)],
    ]);
  }

  // Checks the tab's stream against the identity a command's or a save's reply left the client
  // with, for a stream that missed the change (see DataLayer.catchUpIdentity). Every reply is
  // checked, not just one that moved the tracker: one turned away because the stream serves the
  // previous user names the tag the tracker already holds. Not for a page: a page for another user
  // follows it at mount and then opens a stream that presents the new page's receipts, and a
  // prefetched one isn't on screen.
  //
  // Takes what observeIdentity answered.
  static catchUpIdentity({settling}) {
    if (settling) {
      // The server's answer can move the identity the client knows.
      settling.then(() => Hologram.dataLayer?.catchUpIdentity());
    } else {
      Hologram.dataLayer?.catchUpIdentity();
    }
  }

  static connect(sendImmediatePing) {
    Connection.connect();
    HttpTransport.restartPing(sendImmediatePing);
  }

  // Asks the server for the tag of the identity the browser's session holds now (see
  // Hologram.checkIdentity). Answers null when no answer comes - offline, say - which says nothing
  // about the identity, and so does a server that doesn't answer in time: navigations and the sync
  // stream wait on this (see settleIdentity).
  static async fetchIdentityTag() {
    const controller = new AbortController();

    const deadline = setTimeout(
      () => controller.abort(),
      Config.clientFetchTimeoutMs,
    );

    try {
      const response = await fetch("/hologram/identity-tag", {
        cache: "no-store",
        signal: controller.signal,
      });

      return response.headers.get(IdentityTracker.HEADER);
    } catch {
      return null;
    } finally {
      clearTimeout(deadline);
    }
  }

  // Finds out who is signed in, after hearing about an identity that can't be told to be the latest.
  //
  // This asks the identity route rather than repeating the request, which could run app code
  // twice. An answer older than what the client knows can be a cookie that hasn't caught up with a
  // login yet, so it's asked again after a while. Once the delays run out the answer is believed:
  // the cookie this browser holds is what the next request will be served under.
  static settleIdentity() {
    $.#identitySettling ??= $.#askForIdentity().finally(() => {
      $.#identitySettling = null;
    });

    return $.#identitySettling;
  }

  // Asks the server to describe a page rather than render it, for a client that renders it itself.
  //
  // The answer is a page only when it says so: a page's middleware can answer the request instead,
  // with any status it likes including a plain 200, so the marker header rather than the status is
  // what tells the two apart. Anything that is not a page goes to onNotPage, for the caller to hand
  // to the browser - which is also where an opaque redirect lands, redirects being left to the
  // browser rather than followed here.
  static async fetchPage(toParam, onSuccess, onNotPage) {
    let pageModule, queryString;

    if (Type.isAlias(toParam)) {
      pageModule = toParam;
      queryString = "";
    } else {
      pageModule = toParam.data[0];
      queryString = $.buildPageQueryString(toParam.data[1]);
    }

    try {
      const pageModuleName = Interpreter.moduleExName(pageModule);
      const url = `/hologram/page/${pageModuleName}${queryString}`;

      const response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: Serializer.serialize($.buildPageRequestPayload(), "server"),
        redirect: "manual",
      });

      // Read whatever the answer is: a page's middleware can log the user in or out and answer
      // with something other than a page.
      const {period: identityPeriod} = $.observeIdentity(response);

      // Awaited so that whatever the callback goes on to do is part of this promise. A redirect
      // answers by fetching the next page, and without the await a failure there - the hop limit
      // being one - would reject a promise nobody holds instead of reaching the caller.
      if (response.headers.get("hologram-page-data") === "true") {
        const payload = await response.json();

        // The period the page's state was rendered in, which the page keeps once it is mounted. A
        // prefetched page can wait a while before it is shown, and the identity can change
        // meanwhile.
        payload.identityPeriod = identityPeriod;

        // A redirect doesn't name the page it answers for, and a stale one is asked for again.
        payload.requestedPage = toParam;

        await onSuccess(payload);
      } else {
        await onNotPage();
      }
    } catch (error) {
      if (error instanceof HologramRuntimeError) {
        throw error;
      }

      $.#handleFetchPageError(error);
    }
  }

  // Covered in feature tests
  static fetchPageDigest(pageModule, onSuccess, onFail) {
    const opts = {
      onSuccess,
      onError: onFail,
      onTimeout: onFail,
      timeout: Config.clientFetchTimeoutMs,
    };

    return Connection.sendRequest("page_digest", pageModule, opts);
  }

  // Covered in feature tests
  static isConnected() {
    return Connection.isConnected();
  }

  // Takes in the identity a response names, and asks the server when that can't be told to be the
  // latest word on it. Answers with the period and, when the server was asked, the promise of its
  // answer.
  static observeIdentity(response) {
    const period = IdentityTracker.observeResponse(response);

    // Not awaited: what the reply carries doesn't wait for the server's answer.
    const settling =
      period === IdentityTracker.SUPERSEDED ? $.settleIdentity() : null;

    return {period, settling};
  }

  // The epoch stamps the next action the reply carries: it is the page the command was sent from,
  // so that a reply landing after a navigation is dropped as stale instead of running against the
  // destination. A command the user triggered passes the displayed page's epoch, a command an
  // action put passes that action's. The default reads the registry when the command is sent,
  // never when the reply arrives. The reply's self echoes are not stamped with it: see below.
  // Deps: [:maps.get/2]
  static async sendCommand(command, epoch = Hologram.registryEpoch) {
    const opts = {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Csrf-Token": globalThis.Hologram.csrfToken,
      },
      body: Serializer.serialize($.buildCommandPayload(command), "server"),
    };

    // Checked once the reply is taken in, whatever came of it: the new stream's handshake presents
    // the receipts the reply added.
    let identity = null;

    try {
      const response = await fetch("/hologram/command", opts);

      // Read before the status: a command turned away can still have come with another identity
      // than the one the client knew, and this reply is where the client learns of it.
      identity = $.observeIdentity(response);

      if (!response.ok) {
        $.#failCommand(response.status);
      }

      // The chunks are the ones the struct types in the next action and in the self echoes need
      // (see Hologram.schedulePushedAction). A reply from a server that names none has none.
      const {
        action,
        chunks = [],
        selfEchoes: serializedSelfEchoes,
        status,
        subReceiptAdds: serializedSubReceiptAdds,
        subReceiptDrops: serializedSubReceiptDrops,
      } = await response.json();

      if (status === 0) {
        $.#failCommand(action);
      }

      const subReceiptAdds = Deserializer.deserialize(serializedSubReceiptAdds);

      const subReceiptDrops = Deserializer.deserialize(
        serializedSubReceiptDrops,
      );

      App.subscriptionReceiptRegistry.merge(subReceiptAdds, subReceiptDrops);

      const nextAction = Deserializer.deserialize(action);

      if (!Type.isNil(nextAction)) {
        Hologram.schedulePushedAction(nextAction, chunks, epoch);
      }

      const selfEchoes = Deserializer.deserialize(serializedSelfEchoes);

      // A self echo is the sender's own copy of a broadcast, so it goes where a broadcast from
      // another tab goes: to the page on screen when it arrives, since the subscription it answers
      // may have survived a navigation (a layout's, say), and nowhere when its target is not on
      // that page, the way SSE skips a pushed action for a cid the page does not hold. The server
      // picked the targets from the subscriptions the command was sent with, so one of them can
      // be a component only the page since left had.
      for (const action of selfEchoes.data) {
        const target = Erlang_Maps["get/2"](Type.atom("target"), action);

        if (ComponentRegistry.isCidRegistered(target)) {
          Hologram.schedulePushedAction(action, chunks);
        }
      }
    } catch (error) {
      if (error instanceof HologramRuntimeError) {
        throw error;
      }

      $.#failCommand(error);
    } finally {
      if (identity !== null) {
        $.catchUpIdentity(identity);
      }
    }
  }

  static async #askForIdentity() {
    let answer = null;

    for (const delayMs of $.IDENTITY_ASK_DELAYS_MS) {
      if (delayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }

      answer = await $.fetchIdentityTag();

      if (answer !== null && !IdentityTracker.isOlder(answer)) {
        break;
      }
    }

    if (answer !== null) {
      IdentityTracker.observe(answer);
    }
  }

  static #failCommand(message) {
    throw new HologramRuntimeError(`command failed: ${message}`);
  }

  static #handleFetchPageError(message) {
    throw new HologramRuntimeError(`page fetch failed: ${message}`);
  }
}

const $ = Client;
