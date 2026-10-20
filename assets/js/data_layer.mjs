"use strict";

import Batches from "./batches.mjs";
import Deltas from "./deltas.mjs";
import Durability from "./durability.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
import ManuallyPortedElixirHologramAuth from "./elixir/hologram/auth.mjs";
import ManuallyPortedElixirHologramDB from "./elixir/hologram/db.mjs";
import ManuallyPortedElixirHologramEntity from "./elixir/hologram/entity.mjs";
import ManuallyPortedElixirHologramJob from "./elixir/hologram/job.mjs";
import ManuallyPortedElixirHologramQuery from "./elixir/hologram/query.mjs";
import Model from "./model.mjs";
import QueryKernel from "./query_kernel.mjs";
import Replica from "./replica.mjs";
import SyncStream from "./sync_stream.mjs";
import Tabs from "./tabs.mjs";
import Type from "./type.mjs";

// The client half of the data layer behind one class: each public static is a place where the
// runtime hands control to the data layer. The data layer's own modules - the batches, the deltas,
// the durable store, the local database, the model, the query kernel, the replica, the tabs and
// the ported data verbs - are reached from here.
//
// The bodies assume the build carries a data model, so the sync constants are there.
export default class DataLayer {
  // Based on run_prop_query!/4
  //
  // The builder is ordinary transpiled code piping the ported query stages, so calling it yields
  // the plain term the kernel evaluates - normalized first, exactly as the server normalizes
  // before running, so the client answers the same query the same way.
  //
  // The result is boxed here and nowhere else: rows live plain, and this is the boundary where
  // one becomes something a template can read.
  static answerPropQuery(module, propName, args, capture) {
    const term = ManuallyPortedElixirHologramQuery["normalize/1"](
      Interpreter.callAnonymousFunction(capture, args),
    );

    const carried = $.#carriedCount(module, propName, args, term);

    if (carried !== null) {
      return Type.integer(carried);
    }

    const result = QueryKernel.run(term, {
      actorUserId: LocalDatabase.actorUserId,
    });

    return Model.boxResult(term, result);
  }

  // What the data layer needs before the page mounts: the replica identity, the durable store and
  // the group of tabs sharing it, and the two read-only windows onto what it holds.
  //
  // The identity is {replica: {id, token}, readActorUserId}, the second a function: the actor is
  // read from the page's mount data only when the group has to be named by it.
  static async boot({replica, readActorUserId}) {
    // The pair this page was minted, handed over before the store is read: what is found there
    // wins, and this is what the client falls back to when the server refuses it.
    Replica.offer(replica);

    // Awaited HERE, before the mount, which is what lets the restore that follows the mount be
    // synchronous - everything from the mount onwards runs in one continuation, so the first local
    // write cannot land ahead of what a previous page load left.
    await Durability.open();

    // The group this browser's tabs share, joined before the mount and before the stream opens -
    // which is what lets the tab that leads greet the server with sync on its FIRST connect, and
    // stops a follower opening a sync session it would have to drop a moment later.
    //
    // Named for the database and for the user this page mounts under. Per database because tabs on
    // different models cannot share a store, and per user because the leader can only send what
    // the session it holds is allowed to send - a tab still mounted under somebody else must not
    // be sending, or reading, for this one.
    //
    // Nothing to join where there is no store: the tabs of such a browser share nothing, so each
    // is a replica of its own, exactly as every tab was before any of this.
    if (Durability.mode === "indexeddb") {
      const group = `${Durability.databaseName()}.${readActorUserId() ?? "anonymous"}`;

      await Tabs.join(group, {});
    }

    // A read-only window onto the write queue. Nothing in the framework reads it - it is for a
    // devtools panel, a browser-driven test, and whatever step 10's queue surface is built on.
    // Reads only: opening and closing batches is the action lifecycle's, and nothing outside it
    // should reach in.
    globalThis.Hologram.writes = {
      oldestPendingSeq: Batches.oldestPendingSeq,
      pendingCount: Batches.pendingCount,
      rejected: Batches.rejectedSummaries,
    };

    // The same kind of window onto what this browser keeps between page loads: whether it is
    // keeping anything at all, the place it would greet a stream with, the identity it is
    // presenting, and how many writes are still on their way down. Reads only, and nothing in the
    // framework reads them.
    globalThis.Hologram.durability = {
      cursor: () => SyncStream.syncCursor,
      group: () => Tabs.name,
      leader: () => Tabs.leader,
      mode: () => Durability.mode,
      pendingWrites: () => Durability.inFlight,
      persisted: () => Durability.persisted,
      replicaId: () => Replica.id,
      storedBatches: () => Durability.storedBatches,
    };
  }

  // What the client greets the stream with (see SyncStream.buildGreeting).
  static buildStreamGreeting(pageModule) {
    return SyncStream.buildGreeting(pageModule);
  }

  // Awaiting is where an action stops running and another may run in full before this one comes
  // back, so the batch it is writing to has to make the round trip with it - otherwise it would
  // resume into whichever action started meanwhile, and write, close or discard that one's batch.
  static carryAcrossSuspension(promise) {
    return Batches.carryAcrossSuspension(promise);
  }

  // Sealed BEFORE the render that follows an action, so the one frame that follows shows the
  // action's state change and its data change together - which is the whole point of the batch
  // boundary being the action.
  static closeBatch() {
    Batches.close();
  }

  // Defines the hand-written client versions of the Hologram.Auth, Hologram.DB, Hologram.Entity,
  // Hologram.Job and Hologram.Query.Stage functions as the functions of their modules. No bundle
  // carries their Elixir originals.
  static defineManuallyPortedFunctions() {
    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "can?/3",
      "public",
      ManuallyPortedElixirHologramAuth["can?/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "grant_role/2",
      "public",
      ManuallyPortedElixirHologramAuth["grant_role/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "grant_role/3",
      "public",
      ManuallyPortedElixirHologramAuth["grant_role/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "revoke_role/2",
      "public",
      ManuallyPortedElixirHologramAuth["revoke_role/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "revoke_role/3",
      "public",
      ManuallyPortedElixirHologramAuth["revoke_role/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "create!/1",
      "public",
      ManuallyPortedElixirHologramDB["create!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "create/1",
      "public",
      ManuallyPortedElixirHologramDB["create/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete!/1",
      "public",
      ManuallyPortedElixirHologramDB["delete!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete!/2",
      "public",
      ManuallyPortedElixirHologramDB["delete!/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete/1",
      "public",
      ManuallyPortedElixirHologramDB["delete/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "delete/2",
      "public",
      ManuallyPortedElixirHologramDB["delete/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "read/1",
      "public",
      ManuallyPortedElixirHologramDB["read/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "read/2",
      "public",
      ManuallyPortedElixirHologramDB["read/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "rollback/1",
      "public",
      ManuallyPortedElixirHologramDB["rollback/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "transaction/1",
      "public",
      ManuallyPortedElixirHologramDB["transaction/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "transaction/2",
      "public",
      ManuallyPortedElixirHologramDB["transaction/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update!/1",
      "public",
      ManuallyPortedElixirHologramDB["update!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update!/3",
      "public",
      ManuallyPortedElixirHologramDB["update!/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update/1",
      "public",
      ManuallyPortedElixirHologramDB["update/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.DB",
      "update/3",
      "public",
      ManuallyPortedElixirHologramDB["update/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "generate_id/0",
      "public",
      ManuallyPortedElixirHologramEntity["generate_id/0"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "new/1",
      "public",
      ManuallyPortedElixirHologramEntity["new/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "new/2",
      "public",
      ManuallyPortedElixirHologramEntity["new/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "validate/1",
      "public",
      ManuallyPortedElixirHologramEntity["validate/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Entity",
      "validate/2",
      "public",
      ManuallyPortedElixirHologramEntity["validate/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "add_relationship/3",
      "public",
      ManuallyPortedElixirHologramQuery["add_relationship/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "authorize/2",
      "public",
      ManuallyPortedElixirHologramQuery["authorize/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "count/1",
      "public",
      ManuallyPortedElixirHologramQuery["count/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "decrement/3",
      "public",
      ManuallyPortedElixirHologramQuery["decrement/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "delete_relationship/3",
      "public",
      ManuallyPortedElixirHologramQuery["delete_relationship/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "filter/2",
      "public",
      ManuallyPortedElixirHologramQuery["filter/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "include/2",
      "public",
      ManuallyPortedElixirHologramQuery["include/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "include/3",
      "public",
      ManuallyPortedElixirHologramQuery["include/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "increment/3",
      "public",
      ManuallyPortedElixirHologramQuery["increment/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "limit/2",
      "public",
      ManuallyPortedElixirHologramQuery["limit/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "normalize/1",
      "public",
      ManuallyPortedElixirHologramQuery["normalize/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "offset/2",
      "public",
      ManuallyPortedElixirHologramQuery["offset/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "one/1",
      "public",
      ManuallyPortedElixirHologramQuery["one/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "order_by/2",
      "public",
      ManuallyPortedElixirHologramQuery["order_by/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "put_attribute/2",
      "public",
      ManuallyPortedElixirHologramQuery["put_attribute/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "put_attribute/3",
      "public",
      ManuallyPortedElixirHologramQuery["put_attribute/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "trust/1",
      "public",
      ManuallyPortedElixirHologramQuery["trust/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create!/1",
      "public",
      ManuallyPortedElixirHologramJob["create!/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create!/2",
      "public",
      ManuallyPortedElixirHologramJob["create!/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create!/3",
      "public",
      ManuallyPortedElixirHologramJob["create!/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create/1",
      "public",
      ManuallyPortedElixirHologramJob["create/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create/2",
      "public",
      ManuallyPortedElixirHologramJob["create/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "create/3",
      "public",
      ManuallyPortedElixirHologramJob["create/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Job",
      "framework_attribute_names/0",
      "public",
      ManuallyPortedElixirHologramJob["framework_attribute_names/0"],
    );
  }

  // Nothing half-done: an action that raises leaves no rows behind, and dropping the batch is the
  // whole of putting them back.
  static discardBatch() {
    Batches.discard();
  }

  // After the render rather than before it: what the user sees does not wait on the network.
  static flush() {
    Batches.flush();
  }

  // Before the first render, so that a prop reading a query answers from the database rather than
  // from nothing - the rows the server read to render this page are the rows those queries need,
  // and they go in through the same ingest the stream uses. Every page visit carries again, which
  // is how navigation needs no server for what it already has.
  //
  // A bundle built before any of this existed carries neither field - it leaves the database as it
  // was.
  static ingestMountData(mountData) {
    if (mountData.syncRows) {
      LocalDatabase.actorUserId = mountData.actorUserId;
      Deltas.apply(mountData.syncRows, {insertOnly: true});

      // A count has no rows behind it, so the rows cannot carry one - the numbers this render
      // answered with travel beside them, and each page visit replaces them the way it replaces
      // what its own props read.
      LocalDatabase.syncCounts = mountData.syncCounts ?? {};
    }
  }

  // The four sync kinds the stream delivers (see SyncStream.listen).
  static listenToStream(eventSource) {
    SyncStream.listen(eventSource);
  }

  // An action's writes are one batch: opened when it starts, sealed when it returns, discarded
  // when it raises. That is what makes "the writes of one action" need no bookkeeping from the app
  // - a DB verb writes to whichever batch is open, and there is one open only while an action
  // runs.
  static openBatch(target) {
    Batches.open(target);
  }

  // Takes up what a previous page load left - the place to resume the stream from, the number to
  // count batches on from, and the batches it never managed to send - and answers nothing on every
  // visit after the first, since the runtime's page-script listener fires again on each
  // client-side navigation and this runs once per page visit.
  static restore() {
    const resumed = Durability.restore(Tabs.leader);

    if (resumed === null) {
      return;
    }

    SyncStream.syncCursor = resumed.cursor;
    Batches.resumeFrom(resumed.seq);
    Batches.adopt(resumed.batches);

    // Everything this tab starts with is in place, so what the group has said since may land on it
    // - and whatever arrived while it was starting up is applied now, in the order it arrived.
    Tabs.ready();

    // And what the store could not tell it is asked for: the completeness scopes, which nothing
    // writes down, and the place and the identity as they stand in the tab that has them.
    Tabs.post({kind: "joined"});

    // The third thing that wakes the sender, beside an action finishing and the stream opening.
    // It is needed rather than tidy: the stream is connected before the mount, so it can have
    // opened - and flushed an empty queue - before these batches were taken up. Without this they
    // would wait for the user to do something.
    Batches.flush();
  }

  // The one signal that actually means the network is worth trying again. A batch whose send got
  // no answer is still pending, and this is what wakes the queue that stopped behind it.
  static streamOpened() {
    Batches.flush();
  }

  // What the render that handed this page over counted, for as long as this client's own database
  // cannot count for itself.
  //
  // A count has no rows behind it, so carrying rows cannot answer one: until the fill is complete
  // for the rows it counts, counting locally would count a pot that is still filling and report a
  // number climbing towards the truth. The marker says when that stops - the page's own scope for
  // the page this client connected on, whose rows the server declares complete first, and the
  // whole pot's for any page reached since, whose rows are only promised at "all".
  //
  // The key names the component, the prop and the arguments the builder was called with - which
  // is what tells two instances of one component apart, and what both tiers can spell alike.
  static #carriedCount(module, propName, args, term) {
    if (term.cardinality !== "count") {
      return null;
    }

    const scope =
      module === GlobalRegistry.get("connectPageModule") ? "page" : "all";

    if (LocalDatabase.isSynced(scope)) {
      return null;
    }

    const key = `${module}/${propName.value}/${args
      .map((arg) => Interpreter.inspect(arg))
      .join(",")}`;

    return LocalDatabase.syncCounts[key] ?? null;
  }
}

const $ = DataLayer;
