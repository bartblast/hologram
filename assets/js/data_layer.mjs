"use strict";

import Batches from "./batches.mjs";
import Client from "./client.mjs";
import Deltas from "./deltas.mjs";
import Durability from "./durability.mjs";
import IdentityTracker from "./identity_tracker.mjs";
import Interpreter from "./interpreter.mjs";
import LocalDatabase from "./local_database.mjs";
import ManuallyPortedElixirHologramAuth from "./elixir/hologram/auth.mjs";
import ManuallyPortedElixirHologramDB from "./elixir/hologram/db.mjs";
import ManuallyPortedElixirHologramEntity from "./elixir/hologram/entity.mjs";
import ManuallyPortedElixirHologramJob from "./elixir/hologram/job.mjs";
import ManuallyPortedElixirHologramQueryStage from "./elixir/hologram/query/stage.mjs";
import Model from "./model.mjs";
import QueryCheck from "./query_check.mjs";
import QueryKernel from "./query_kernel.mjs";
import QuerySpelling from "./query_spelling.mjs";
import ReloadNotice from "./reload_notice.mjs";
import Replica from "./replica.mjs";
import Sse from "./sse.mjs";
import SyncStream from "./sync_stream.mjs";
import Tabs from "./tabs.mjs";
import Type from "./type.mjs";

// How long a page about to be loaded afresh waits for this tab's writes to reach the store. A write
// takes milliseconds; this is the bound for one that never answers.
const SAVE_WAIT_MS = 3000;

// How many query refusals are kept before the cache starts over: a query holding values a user
// types has as many spellings as values, so the cache is bounded rather than grown forever.
const QUERY_REFUSALS_LIMIT = 5000;

// The longest spelling the cache keeps, so that its limit bounds the memory it holds too.
const QUERY_REFUSAL_KEY_LIMIT = 4096;

// The client half of the data layer behind one class: each public static is a place where the
// runtime hands control to the data layer. The data layer's own modules - the batches, the deltas,
// the durable store, the local database, the model, the query kernel, the replica, the tabs and
// the ported data verbs - are reached from here.
//
// The bodies assume the build carries a data model, so the sync constants are there.
export default class DataLayer {
  // The refusals queryRefusal() worked out, with the model generation and the synced types they
  // were worked out against.
  static #queryRefusals = {
    generation: null,
    refusals: new Map(),
    syncedTypes: null,
  };

  // The keys of the carried counts of the page on screen, which its snapshot saves. Those it arrived
  // with, so that a save before its first render keeps them, and those its renders answered with.
  static #shownCounts = new Set();

  // The counts of a restored page that came too early to be filed, which its next save keeps.
  static #unfiledCounts = [];

  // Made public to make tests easier
  //
  // Whether this document has taken up what the store holds, so whether it holds a place is known.
  static isStoreRestored = false;

  // Whether the mount under way moved this tab to another user, so the stream has to be replaced
  // once the mount is done (see #followMountedIdentity).
  static #reconnectsAfterMount = false;

  // Made public to make tests easier
  //
  // The tag the tab last opened a new stream to catch up with, until a handshake names a tag or the
  // tab follows one (see catchUpIdentity).
  static caughtUpTag = null;

  // Based on run_query!/4
  //
  // Answers the given normalized term a derived field of the given module is defined by, for the
  // given name. The arguments its function was called with are in the term, as the values it
  // reads. The result is boxed here and
  // nowhere else: rows live plain, and this is the boundary where one becomes something a
  // template can read.
  static answerDerivedQuery(module, name, args, term) {
    const carried = $.#carriedCount(module, name, term);

    if (carried !== null) {
      return Type.integer(carried);
    }

    const result = QueryKernel.run(term);

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

    // The identity this document was rendered for, which the stream's handshake is held to (see
    // takeHandshake).
    SyncStream.followedTag = IdentityTracker.tag;

    // Opened here and read below, once the group is joined.
    await Durability.open();

    // The group this browser's tabs share, joined before the mount and before the stream opens -
    // which is what lets the tab that leads greet the server with sync on its FIRST connect, and
    // stops a follower opening a sync session it would have to drop a moment later.
    //
    // And joined before the store is READ, which is what lets a tab starting while another syncs
    // miss nothing. The tab holding the stream stores each frame and then posts it to the group, so
    // a frame posted before this tab was listening was stored before this tab reads, and one posted
    // after reaches it as a message, held until it has taken up what it read (see Tabs.ready).
    // Read first and joined after, a frame stored after the read and posted before the join would
    // reach it neither way. (Between the leader's store and this tab's read, what orders them is
    // IndexedDB, which starts a read only after the writes created before it; between the leader's
    // post and this tab's join, it is the lock round trip the join waits out - not a guarantee
    // anything states, but a margin no post outruns.)
    //
    // Named for the database and for the user this page mounts under. Per database because tabs on
    // different models or sync protocols cannot share a store, and per user because the leader can
    // only send what the session it holds is allowed to send - a tab still mounted under somebody
    // else must not be sending, or reading, for this one.
    //
    // Nothing to join where there is no store: the tabs of such a browser share nothing, so each
    // is a replica of its own, exactly as every tab was before any of this.
    if (Durability.mode === "indexeddb") {
      await Tabs.join(Durability.groupName(readActorUserId() ?? null), {});
    }

    // Awaited HERE, before the mount, which is what lets the restore that follows the mount be
    // synchronous - everything from the mount onwards runs in one continuation, so the first local
    // write cannot land ahead of what a previous page load left.
    await Durability.load();

    // A store that opened and then could not be read, or that another tab took away while it was
    // being read, leaves nothing to share - so the tab leads itself, as it would had the open
    // failed. A store failure another tab reported has already ended the group (see Tabs.dissolve).
    //
    // And it lets go of every batch it holds, of which there should be none: before its mount a
    // tab has made none of its own, and it takes up none from the group before its restore - a
    // batch another tab filed is held until then, and a tab that leads sends nothing until then
    // (see Tabs.ready). Any it did hold would be numbered under the group's identity, which this
    // tab no longer sends under (see Batches.disown). The group's leader sends them, or the next
    // page load does.
    if (Durability.mode === "memory" && Tabs.name !== null) {
      Tabs.leave();
      Batches.disown();
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

  // Opens a new stream when a command's or a save's reply names an identity this tab doesn't
  // follow, and its handshake follows it (see takeHandshake). The server tells every stream of the
  // session of a change, but a stream whose request left with the previous cookie, and which
  // started listening just after the change was told, never hears of it and goes on serving the
  // previous user. When the stream told this tab first, the tags match and nothing is done.
  //
  // Once per tag, until a handshake names a tag or the tab follows one: replies that land while the
  // handshake is on its way would each open another stream and throw away the one about to open,
  // and a handshake that names no tag follows nothing. A tab already waiting to hear who it serves
  // has a new stream coming.
  static catchUpIdentity() {
    const tag = IdentityTracker.tag;

    if (
      !Sse.isStarted ||
      tag === null ||
      tag === SyncStream.followedTag ||
      tag === $.caughtUpTag ||
      SyncStream.awaitingIdentity
    ) {
      return;
    }

    $.caughtUpTag = tag;
    Sse.reconnect();
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
      "has_role?/2",
      "public",
      ManuallyPortedElixirHologramAuth["has_role?/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Auth",
      "has_role?/3",
      "public",
      ManuallyPortedElixirHologramAuth["has_role?/3"],
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
      ManuallyPortedElixirHologramQueryStage["add_relationship/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "count/1",
      "public",
      ManuallyPortedElixirHologramQueryStage["count/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "decrement/3",
      "public",
      ManuallyPortedElixirHologramQueryStage["decrement/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "delete_relationship/3",
      "public",
      ManuallyPortedElixirHologramQueryStage["delete_relationship/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "filter/2",
      "public",
      ManuallyPortedElixirHologramQueryStage["filter/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "filter/3",
      "public",
      ManuallyPortedElixirHologramQueryStage["filter/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "include/2",
      "public",
      ManuallyPortedElixirHologramQueryStage["include/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "include/3",
      "public",
      ManuallyPortedElixirHologramQueryStage["include/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "increment/3",
      "public",
      ManuallyPortedElixirHologramQueryStage["increment/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "normalize/1",
      "public",
      ManuallyPortedElixirHologramQueryStage["normalize/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "one/1",
      "public",
      ManuallyPortedElixirHologramQueryStage["one/1"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "put_attribute/2",
      "public",
      ManuallyPortedElixirHologramQueryStage["put_attribute/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "put_attribute/3",
      "public",
      ManuallyPortedElixirHologramQueryStage["put_attribute/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "skip/2",
      "public",
      ManuallyPortedElixirHologramQueryStage["skip/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "sort/2",
      "public",
      ManuallyPortedElixirHologramQueryStage["sort/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "sort/3",
      "public",
      ManuallyPortedElixirHologramQueryStage["sort/3"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "take/2",
      "public",
      ManuallyPortedElixirHologramQueryStage["take/2"],
    );

    Interpreter.defineManuallyPortedFunction(
      "Hologram.Query.Stage",
      "trust/1",
      "public",
      ManuallyPortedElixirHologramQueryStage["trust/1"],
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
    $.#shownCounts = new Set(Object.keys(mountData.syncCounts ?? {}));
    $.#unfiledCounts = [];

    if (mountData.syncRows) {
      // The period the page was rendered in rather than the one lasting now: the identity can
      // change between a page arriving and its mount.
      const period = mountData.identityPeriod ?? IdentityTracker.period;

      if ($.holdsOtherUser(mountData.actorUserId)) {
        $.#followMountedIdentity(mountData);
      }

      // A number counted for one identity must never answer for another. The period tells apart
      // what the ids can't, like one user signing out and back in. The ids cover a server that
      // tags no responses, where the period never moves.
      if (
        period !== LocalDatabase.syncCountsPeriod ||
        (mountData.actorUserId ?? null) !== (LocalDatabase.actorUserId ?? null)
      ) {
        LocalDatabase.dropCounts();
      }

      LocalDatabase.syncCountsPeriod = period;
      LocalDatabase.actorUserId = mountData.actorUserId;
      LocalDatabase.actorEntityId = mountData.actorEntityId ?? null;
      Deltas.apply(mountData.syncRows, {insertOnly: true});

      // A count has no rows behind it, so the rows cannot carry one - the numbers this render
      // answered with travel beside them. They join the ones earlier visits carried rather than
      // replace them: Back or Forward reads no mount data, so a page it returns to has only those.
      LocalDatabase.carryCounts(
        mountData.syncCounts ?? {},
        mountData.syncCountTypes ?? {},
      );
    }
  }

  // Whether a page for the given user is for somebody else than this tab holds. Only once this
  // document has read its store: its first mount is what says who it is for, and the store it read
  // is held to that (see Durability.restore).
  static holdsOtherUser(actorUserId) {
    return (
      $.isStoreRestored &&
      (actorUserId ?? null) !== (LocalDatabase.actorUserId ?? null)
    );
  }

  // Takes this tab to the user the server says is signed in now, in one turn, so that nothing reads
  // the previous user's rows under the new user's name. The rows, the place and the counts go, and
  // the previous user's batches leave the queue and the screen and wait in the store for them.
  //
  // The period moves first: what is filed for the new user from here on belongs to it. A server
  // that tags no responses has no new period to move to, so the one lasting now counts as ended
  // (see LocalDatabase.reset).
  //
  // The same user keeps everything. Another user's tab holds no pair until a handshake hands it
  // one, which mints a pair for that tab alone (see takeHandshake): the server's event names none,
  // since two groups of one user on builds that differ only in protocol version or storage layout
  // would each send under it from their own counter.
  //
  // `heldSync` is whether the stream the tab is leaving held a sync session, which a tab that ends
  // up following has to close (see #moveGroup).
  //
  // Answers whether the tab moved to another user.
  static followIdentity(
    {actorEntityId, actorUserId, identityTag, userRow},
    {heldSync = SyncStream.heldSync} = {},
  ) {
    // This stream's server side has moved to an identity this tab can't take for the latest, so
    // what it sends from here on may not be for the user the tab holds. A new stream is opened
    // under the session as it stands, once the server has said who that is.
    if (IdentityTracker.isBehind(identityTag)) {
      SyncStream.awaitingIdentity = true;
      Client.settleIdentity().then(() => Sse.reconnect());

      return false;
    }

    const owner = actorUserId ?? null;
    const isSameUser = owner === (LocalDatabase.actorUserId ?? null);

    IdentityTracker.observe(identityTag);
    SyncStream.followedTag = identityTag ?? null;

    // A cookie set back brings an earlier tag back, stamp and all, which a catch-up has to see.
    $.caughtUpTag = null;

    if (!isSameUser) {
      LocalDatabase.reset();

      if (identityTag !== null && identityTag !== undefined) {
        LocalDatabase.identityEndedPeriod = null;
      }

      LocalDatabase.actorUserId = owner;
      LocalDatabase.actorEntityId = actorEntityId ?? null;

      if (userRow) {
        Deltas.apply(userRow, {insertOnly: true});
      }

      SyncStream.syncCursor = null;
      SyncStream.rowsChangedSinceRender = true;

      Batches.releaseForeign(owner);
      SyncStream.scheduleRender();

      // The pair goes with the user. The previous user's would be written into the new user's
      // slot, or sent under the new user's session: the tab holds none until the store, its group
      // or a handshake gives it the new user's (see SyncStream.awaitingPair). The page's offer was
      // minted for the previous user too.
      Replica.owner = owner;
      $.#holdNoPair();
    }

    if (!isSameUser && Tabs.name !== null) {
      $.#moveGroup(owner, heldSync);
    }

    return !isSameUser;
  }

  // Takes in what a stream's handshake says of the session, before the stream is greeted, and
  // answers whether the stream may open.
  //
  // The cookie the handshake was made with can name another identity than this tab follows. Newer,
  // when this tab missed the change: a login made outside Hologram announces nothing, and a stream
  // opened after the announcement never hears it. So the tab follows it here. Older, when the
  // server announced the change before the response that set the cookie arrived. Then the stream
  // would serve the previous user, so none opens: the follow asks the server again who is signed in
  // and opens a new stream once it has answered (see followIdentity), and writes wait for it (see
  // SyncStream.holdsWrites). After about four seconds that answer is believed, so a cookie that
  // never catches up is followed rather than waited for.
  //
  // A server that names no identity in its handshake isn't held to one.
  //
  // The handshake also hands the tab a pair for the session as it stands, which the tab keeps as
  // the fresh one, so a refusal of the pair in use has a pair to switch to (see Batches.flush). A
  // tab holding none takes it up when it sends for itself: one leading its group, which writes it
  // down and hands it to the group, or one in no group. A tab following its group takes the group's
  // pair, and a lead taken up while it settles reads the store's, which is why it's left alone then
  // too: its next handshake comes once it has settled.
  static takeHandshake({actorEntityId, actorUserId, identityTag, replica}) {
    const named = identityTag !== null && identityTag !== undefined;

    // A handshake that names who the stream serves answers any catch-up, followed or not: an older
    // cookie set back while it was on its way names the tag already followed.
    if (named) {
      $.caughtUpTag = null;
    }

    if (named && identityTag !== SyncStream.followedTag) {
      // The stream about to open replaces the one the tab is leaving, which closes any sync session
      // that one held.
      $.followIdentity(
        {actorEntityId, actorUserId, identityTag},
        {heldSync: false},
      );
    }

    SyncStream.laggingCookie = named && identityTag !== SyncStream.followedTag;

    if (SyncStream.laggingCookie) {
      return false;
    }

    if (replica?.id) {
      Replica.fresh = {id: replica.id, token: replica.token};

      // A leader sends only under a pair it has written down, and a slot that belongs to another
      // user isn't its to write.
      const leadsForItself =
        Tabs.leader &&
        !Tabs.takingLead &&
        Replica.owner === (LocalDatabase.actorUserId ?? null);

      if (Replica.id === null && (Tabs.name === null || leadsForItself)) {
        Replica.adopt(Replica.fresh);

        if (Tabs.name !== null) {
          Durability.persistReplica(Replica.current());
          Tabs.postState();
        }
      }
    }

    return true;
  }

  // Holds no pair, and writes wait for the one the next handshake hands (see takeHandshake).
  static #holdNoPair() {
    Replica.id = null;
    Replica.token = null;
    Replica.fresh = null;
    SyncStream.awaitingPair = true;
  }

  // Takes a tab that followed the session to another user out of the previous user's group and
  // into the new one's, and takes up what the store holds for the new user, as a page load would:
  // joined first, read after (see boot). The store is judged by the tab that leads the new group,
  // and claimed by it when another user's: only the holder of a user's lock claims for that user,
  // so a tab leading that user's group never finds its claim out of date. One that follows reads
  // only whose the store is (see Durability.restore).
  //
  // What the tab held of its own is kept: the rows its page carried, and the batches of the new
  // user it still holds. The store adds the rest of that user's queue - a tab back with a user it
  // left takes up everything they left, the batches it released itself included, since its
  // counter has moved past them.
  //
  // Then a stream the server serves as the tab now stands. One that leads asks for sync from the
  // place the store gave it, or from nowhere: the stream it had may be serving the new user
  // already, but frames it sent while the tab joined were passed over (see
  // SyncStream.dropsFrame). One that follows closes the sync session its stream held, if it did.
  //
  // A newer follow, or the group ending, takes over from any point here.
  static async #moveGroup(owner, heldSync) {
    // A tab whose store already stopped has nothing to share with the new user's tabs, and joined,
    // it could lead them from memory. So it leaves the group it was in and goes on as a replica of
    // its own. It keeps its batches, as a tab that leads does when its store stops: the ones it
    // made since were never stored, and it is the only tab that can send them. The reconnect's
    // handshake hands it a pair of its own (see takeHandshake).
    if (Durability.mode !== "indexeddb") {
      Tabs.leave();

      if (Sse.isStarted) {
        Sse.reconnect();
      }

      return;
    }

    const visit = await Tabs.move(Durability.groupName(owner));

    if (visit === null) {
      return;
    }

    // A lead handed over from here on is taken at ready(), which opens its own stream (see
    // Tabs.#lead).
    const ledOnJoin = Tabs.leader;

    await Durability.load(() => Tabs.isVisit(visit));

    if (!Tabs.isVisit(visit)) {
      return;
    }

    // The store couldn't be read, or stopped while the tab moved: nothing left to share, so the tab
    // leads itself and lets go of the batches the store holds, as at boot. The tab leading the new
    // user's group sends those, or the next page load does. Kept, each would be sent twice: by this
    // tab, and from the store under another pair. The ones its actions sealed after the store
    // stopped are kept: nothing else holds them. Its filings settle first, since that is what tells
    // the two apart. The other tabs are told nothing, since the store failed only for this one.
    //
    // Its stream is a replica's of its own from here, served sync from no place, and it holds no
    // pair until that stream's handshake hands it one. Any fresh pair a handshake handed it while
    // it read goes too, so it switches to none: the reconnect below hands one for the stream it
    // goes on with.
    if (Durability.mode !== "indexeddb") {
      await Batches.recorded();

      if (!Tabs.isVisit(visit)) {
        return;
      }

      Tabs.leave();
      $.#holdNoPair();
      Batches.disownStored();

      if (Sse.isStarted) {
        Sse.reconnect();
      }

      return;
    }

    const resumed = Durability.restore(Tabs.leader);

    SyncStream.syncCursor = resumed.cursor;
    SyncStream.scheduleRender();

    $.#resume(resumed);

    if (Sse.isStarted && (ledOnJoin || (!Tabs.leader && heldSync))) {
      Sse.reconnect();
    }
  }

  // A page arrived for another user than this tab holds. The stream in front of it can still be
  // serving the previous user, so its frames wait for a new one, opened once the mount is done:
  // its handshake presents the receipts of the page now mounted, and a login made outside Hologram
  // announces nothing. The page's response carries no replica pair, so writes wait for one (see
  // followIdentity).
  static #followMountedIdentity(mountData) {
    $.followIdentity({
      actorEntityId: mountData.actorEntityId,
      actorUserId: mountData.actorUserId,
      identityTag: IdentityTracker.tag,
    });

    SyncStream.awaitingIdentity = true;

    $.#reconnectsAfterMount = Sse.isStarted;
  }

  // The four sync kinds the stream delivers (see SyncStream.listen).
  static listenToStream(eventSource) {
    SyncStream.listen(eventSource);
  }

  // Called by every render: the rows the derived fields read are now the ones it computed them
  // from (see rowsChangedSinceRender).
  static markRendered() {
    SyncStream.rowsChangedSinceRender = false;
  }

  // Based on Stage.normalize/1
  static normalizeQuery(query) {
    return ManuallyPortedElixirHologramQueryStage["normalize/1"](query);
  }

  // An action's writes are one batch: opened when it starts, sealed when it returns, discarded
  // when it raises. That is what makes "the writes of one action" need no bookkeeping from the app
  // - a DB verb writes to whichever batch is open, and there is one open only while an action
  // runs.
  static openBatch(target) {
    Batches.open(target);
  }

  // The carried counts the page on screen is showing, for its snapshot to keep (see restoreCounts).
  static pageCounts() {
    return [...LocalDatabase.countEntries($.#shownCounts), ...$.#unfiledCounts];
  }

  // Why the given normalized term can't be a derived field's query, or null (see QueryCheck): what it
  // asks for that the browser may not hold, then a type it reads that sync never sends - in the
  // order the server refuses them.
  //
  // Asked of every derived query on every render, so the answer is kept by the term's spelling,
  // which names one query whatever object holds it. It depends only on the term, the model and the
  // synced types, so it starts over when either of the last two changes.
  static queryRefusal(term) {
    const syncedTypes = globalThis.Hologram.sync?.syncedTypes;
    const generation = Model.generation();
    const cache = DataLayer.#queryRefusals;

    if (
      cache.syncedTypes !== syncedTypes ||
      cache.generation !== generation ||
      cache.refusals.size >= QUERY_REFUSALS_LIMIT
    ) {
      DataLayer.#queryRefusals = {generation, refusals: new Map(), syncedTypes};
    }

    const refusals = DataLayer.#queryRefusals.refusals;
    const key = QuerySpelling.spell(term);

    // A shape the spelling doesn't know is marked with a "!", and two of them can spell alike, so
    // a term holding one is answered afresh rather than from the cache. A value holding a "!" is
    // too, which only costs the walk. So is one too long to keep.
    if (key.length > QUERY_REFUSAL_KEY_LIMIT || key.includes("!")) {
      return QueryCheck.refusal(term) ?? QueryCheck.unsyncedRefusal(term);
    }

    if (!refusals.has(key)) {
      refusals.set(
        key,
        QueryCheck.refusal(term) ?? QueryCheck.unsyncedRefusal(term),
      );
    }

    return refusals.get(key);
  }

  // Settles once what this tab's actions wrote is in the store, for a page about to be loaded afresh
  // (see Batches.recorded) - or after SAVE_WAIT_MS, whichever comes first. A store write that never
  // answers would otherwise leave a click on a link doing nothing at all.
  static saved() {
    let timer;

    return Promise.race([
      Batches.recorded(),
      new Promise((resolve) => {
        timer = setTimeout(resolve, SAVE_WAIT_MS);
      }),
    ]).finally(() => clearTimeout(timer));
  }

  // Whether a navigation loads the next page afresh: the server stopped serving this tab, and
  // in-app the next page would run the same code the server can no longer serve - or it serves the
  // tab across models, and in-app the next page would run the new build's code over this tab's
  // runtime and store (see SyncStream.servedAcrossModels). Only the first shows the reload notice.
  static stopped() {
    return SyncStream.stopReason !== null || SyncStream.servedAcrossModels();
  }

  // Called by every render that finished: a tab the server stopped serving says so to the person
  // (see ReloadNotice).
  static rendered() {
    ReloadNotice.update(SyncStream.stopReason !== null);
  }

  // Replaces the stream when the mount that just ended moved this tab to another user (see
  // #followMountedIdentity). Called for a mount that raised too, which would otherwise leave the
  // tab on a stream whose frames it drops.
  static reconnectIfFollowed() {
    if ($.#reconnectsAfterMount) {
      $.#reconnectsAfterMount = false;

      Sse.reconnect();
    }
  }

  // Takes up what a previous page load left - the place to resume the stream from, the number to
  // count batches on from, and the batches it never managed to send - and answers nothing on every
  // visit after the first, since the runtime's page-script listener fires again on each
  // client-side navigation and this runs once per page visit.
  //
  // Only the first visit reads the store: a tab moving to another user's group takes up what it
  // reads itself (see #moveGroup), which a later visit landing between that read and its use
  // must not take instead.
  static restore() {
    const resumed = $.isStoreRestored ? null : Durability.restore(Tabs.leader);

    $.isStoreRestored = true;

    if (resumed !== null) {
      SyncStream.syncCursor = resumed.cursor;
    }

    // What a Back before the first mount brought with it, now that the place is known. Only then:
    // filing trims the counts to the cap, and a page's own counts may go past it.
    if ($.#unfiledCounts.length > 0) {
      $.#fileCounts($.#unfiledCounts);
      $.#unfiledCounts = [];
    }

    $.reconnectIfFollowed();

    if (resumed !== null) {
      $.#resume(resumed);
    }
  }

  // What a tab does with what its restore took up, at its first visit and after moving to another
  // user's group (see #moveGroup).
  static #resume(resumed) {
    Batches.resumeFrom(resumed.seq);
    Batches.adopt(resumed.batches);

    // Everything this tab starts with is in place, so what the group has said since may land on it
    // - and whatever arrived while it was starting up is applied now, in the order it arrived.
    Tabs.ready(resumed.readForeign);

    // And what the store could not tell it is asked for: what is complete, which nothing
    // writes down, and the place and the identity as they stand in the tab that has them.
    Tabs.post({kind: "joined"});

    // The third thing that wakes the sender, beside an action finishing and the stream opening.
    // It is needed rather than tidy: a tab that leads sends nothing before it is ready (see
    // Tabs.sends), so an action the mount ran flushed nothing, and the stream opens only after
    // this. Without it these batches would wait for the user to do something.
    Batches.flush();
  }

  // A page is back on screen from its snapshot, with the counts the snapshot saved. They are the
  // page's until its first render, so a save before then keeps them. Filing them brings back the
  // number of a page whose document has gone, and one this document let go of.
  //
  // Before this document has read its store, it can't tell whether it holds a place, so they wait
  // unfiled. A client holding a place finished a fill, so its own count beats a number from before
  // it, however old the snapshot is. And nothing comes back in a period the stream ended by saying
  // somebody else signed in. A count the client has counted for itself isn't filed either (see
  // LocalDatabase.restoreCountEntries).
  static restoreCounts(entries) {
    $.#shownCounts = new Set((entries ?? []).map(([key]) => key));
    $.#unfiledCounts = [];

    if (!entries) {
      return;
    }

    if (!$.isStoreRestored) {
      $.#unfiledCounts = entries;
      return;
    }

    $.#fileCounts(entries);
  }

  static #fileCounts(entries) {
    const isIdentityEnded =
      LocalDatabase.identityEndedPeriod !== null &&
      LocalDatabase.identityEndedPeriod === IdentityTracker.period;

    if (SyncStream.syncCursor === null && !isIdentityEnded) {
      LocalDatabase.restoreCountEntries(entries);
    }
  }

  // Whether rows changed since the last render, which computed the derived fields from the rows it
  // saw - so an action about to read them knows to compute them again first.
  static rowsChangedSinceRender() {
    return SyncStream.rowsChangedSinceRender;
  }

  // Based on read_session_user/2 (renderer.ex)
  //
  // The session user's row as this client holds it, boxed the way the server hands it over as the
  // {Hologram, :user} context: the row of the user entity type whose id is the acting user's, or
  // nil when nobody is signed in or no such row is held. The client holds only rows its user may
  // read, so a row the read rules deny is nil here as it is on the server.
  //
  // Answered on every render rather than read from the context the page arrived with, so a write
  // to the row - this client's own or one the stream delivers - reaches every prop reading it.
  //
  // Looked up by id rather than run as a query: every render of every page asks, and a query
  // would scan the whole user table, which holds every user the session user may read. The answer
  // is the one the query would give - the row as the pending writes leave it, boxed with nothing
  // included.
  //
  // WARNING: must match read_session_user/2 (renderer.ex).
  static sessionUser() {
    const userEntity = globalThis.Hologram.sync.userEntity;
    const actorEntityId = LocalDatabase.actorEntityId;

    const row =
      actorEntityId === null
        ? null
        : LocalDatabase.getRow(userEntity, actorEntityId);

    // Compared as the query compares, since a table is a plain object: an id spelled like one of
    // its inherited members would find that member rather than a row.
    return row && row.id === actorEntityId
      ? Model.box(userEntity, row)
      : Type.nil();
  }

  // The one signal that actually means the network is worth trying again. A batch whose send got
  // no answer is still pending, and this is what wakes the queue that stopped behind it.
  static streamOpened() {
    Batches.flush();
  }

  // What a render that handed a page over counted, for as long as this client's own database cannot
  // count for itself.
  //
  // A count has no rows behind it, so carrying rows cannot answer one: until the fill is complete
  // for the rows it counts, counting locally would count a pot that is still filling and report a
  // number climbing towards the truth. The markers say when that stops - one per entity type, once
  // the client holds every row of it it may see, and the whole pot's. A count reads the types the
  // server worked out for it when it counted (`syncCountTypes`, see Carry.collect_count/4), and the
  // client counts for itself once every one of them is marked, on whichever page and in whichever
  // tab. A count carried with no types waits for the whole pot.
  //
  // The key names the component, the derived field and the query it ran, spelled the way the
  // server spells it (see QuerySpelling). The query holds every value it reads, so a row argument
  // whose field the query reads changing is a query the server never counted, and misses, while
  // one whose other fields change still finds the number. Two instances of one component running
  // one query share a number, which is the same number.
  //
  // WARNING: must match count_key/3 on the server (carry.ex).
  static #carriedCount(module, name, term) {
    if (term.cardinality !== "count") {
      return null;
    }

    // Every count is local once the client holds every row, so no key needs spelling.
    if (LocalDatabase.isAllSynced()) {
      return null;
    }

    const key = `${module}/${name.value}/${QuerySpelling.spell(term)}`;

    if (LocalDatabase.countsLocally(key)) {
      return null;
    }

    const carried = LocalDatabase.syncCounts[key] ?? null;

    if (carried !== null) {
      $.#shownCounts.add(key);
    }

    return carried;
  }
}

const $ = DataLayer;
