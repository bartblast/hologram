"use strict";

import Clock from "./clock.mjs";
import LocalDatabase from "./local_database.mjs";
import Logger from "./logger.mjs";
import Replica from "./replica.mjs";
import Tabs from "./tabs.mjs";
import Utils from "./utils.mjs";

// What this browser keeps between page loads, and where it keeps it.
//
// Memory stays canonical: every read a query, a policy check or an action makes is answered by
// LocalDatabase and the overlay, exactly as before. This writes BEHIND memory and reads only at
// startup, so nothing on the hot path waits for a disk.
//
// What is written down is only what the STREAM delivered - a frame's rows, and the place in the
// log those rows are dated at, in one transaction so a crash cannot leave a place claiming rows
// that were never written. A row a page carried is not written: every page visit carries it again.
// A row a confirmed batch promoted is not written either: the server sends its own frame for that
// change, and a client cut off before it arrives is dated before the batch and replays it.
//
// Beside the rows it holds what this BROWSER did rather than what the server said - the replica
// identity, the batch counter and the clock. Those outlive a resync, a model change and somebody
// else signing in, because none of the three makes them untrue: a number reused is a batch the
// server answers from the record of a different batch, and a clock restarted low is a write the
// server reads as moved.
//
// And it holds the QUEUE: the batches this browser has written and not yet had an answer to,
// which is the one thing here that is nobody else's copy of anything. A row can always be
// downloaded again; a write nothing has taken delivery of exists only where it was made. So the
// queue outlives more than the rest - a resync and somebody else signing in leave it alone, and
// even a storage failure keeps what is already on disk, because those batches are still the
// user's unfinished work whatever has gone wrong since. Its record shape is FROZEN, spelled and
// argued in `batch.mjs`: a bundle drains what an older bundle wrote.
//
// A storage failure leaves all of them standing too. A number under an identity is spent only where
// the store records it, so a tab that lost its store spends none under the stored identity. It
// sends the batches the store already holds under that identity, which the server answers from
// its record if it has seen them, and anything newer goes out under an identity the server mints
// for it (see Replica.requestMint).
//
// The identity is kept PER USER, each under a key of its own in `meta`, because a replica's
// numbering is that user's. A user who comes back to a browser somebody else used in between has to
// send their queued batches under the pair they were numbered under, or a batch whose answer was
// lost is applied a second time. And a tab whose store another user took can go on writing its own
// pair without touching theirs.
//
// ONE DATABASE PER MODEL VERSION, named for the layout of the store itself and the model this
// bundle speaks. A deploy that changes the model lands in a new tab while an old tab is still open,
// and the two would otherwise share one store - a v1 tab must never read rows v2 rewrote, and no
// lens code ships to the browser to translate them. Named apart, they cannot meet: every tab is
// durable the whole time, in its own bundle's shape, and nothing has to decide which of them
// yields. The price is one refill per model change, which is what a model change costs anyway.
// (Draining an old model's database and deleting it once its tabs are gone is version skew's to
// build - what this step owes is only that the two never share.)
//
// Where the browser offers no durable storage - private browsing, an odd embedder, a failed
// transaction - the whole thing degrades to memory mode: fully functional, and honest about it
// through `mode`.
const ENTITIES = "entities";

// The shape of the store: which object stores exist, keyed how. Part of the database's NAME, so a
// bundle with a different layout opens a different database rather than upgrading this one - which
// is why VERSION below never moves.
//
// Still 1 with the queue added to it: the shape is edited in place while nothing anywhere holds
// data in the old one, and the number starts moving when there is something to move it for. A
// browser that a person opened by hand before the queue existed holds a two-store database and
// drops to memory mode on the missing store - clearing site data is the whole of the fix, and
// nothing automated is in that position, since every driven browser starts from an empty profile.
const LAYOUT = 1;

const META = "meta";
const QUEUE = "queue";

// What starts the key in META of each user's replica pair. One key per user rather than one map,
// so that a storage failure drops a pair with a delete: a write can be refused on a full disk, and
// refused inside the failure's transaction it would roll the whole cleanup back.
const REPLICA_PREFIX = "replica:";

const VERSION = 1;

export default class Durability {
  // Transactions started and not yet complete. A test waits on it, and a devtools panel reads it -
  // nothing in the framework does.
  static inFlight = 0;

  // "indexeddb" once a database is open, "memory" before that and after anything goes wrong.
  static mode = "memory";

  // Whether the browser has agreed to keep this origin's storage rather than evicting it under
  // pressure, and nothing until it has been asked or where it cannot be. A devtools read; nothing
  // in the framework reads it.
  static persisted = null;

  // How many batch records the load found, of every owner - not only the ones this page may take
  // up. Taken once and not kept current: a test and a devtools panel read it to tell "this page
  // is not sending them" apart from "there are none", and nothing in the framework reads it.
  static storedBatches = 0;

  // Whether this page ever had a store open. Once it has, a pair it isn't sure the store doesn't
  // hold can have numbers recorded under it (see Batches.#numbered).
  static hadStore = false;

  static #db = null;

  // What load() read, held until restore() consumes it. Read before the mount so that restore has
  // nothing to await: it runs after the page has mounted, and everything after the mount happens
  // in one continuation, before an action could dispatch and write.
  static #loaded = null;

  // What the restore's read saw of the queue: the highest number spent and the numbers still
  // queued (see wasAnswered). Nothing until a restore has taken something up.
  static #queueAtRestore = null;

  // Whether restore() has run, after which this tab holds what the store held or knows it held
  // nothing.
  static #restored = false;

  // The id of the identity the store holds, as far as this tab knows (see holdsIdentity).
  static #storedReplicaId = null;

  // Whether this page load has already put the question to the browser. Flipped BEFORE the asking
  // starts, which is what stops two batches stored in the same turn from both asking.
  static #persistenceAsked = false;

  // How this tab's latest filing ended, once it has (see fileBatch).
  static #lastFiling = null;

  // The last identity write started, for a send to wait on (see replicaWritten).
  static #replicaWrite = Promise.resolve();

  // The id of the last claim this tab knows of. Every change of owner writes a new one, so a tab
  // holding an older id knows the store was wiped since, even when it is back under this tab's user
  // and holds rows this tab never saw. A frame written over them would date them at a place they
  // are not at.
  //
  // Moved only inside a transaction (see #whileOwned), because transactions on one store run in the
  // order they were created, so a write started after a claim always sees that claim.
  static #claimId = null;

  // The batches this browser has filed, oldest first, or only those numbered below `below` - what
  // a tab reads before it sends, so that what it ships is the queue as the DATABASE holds it rather
  // than as messages happened to reach it.
  //
  // Why it is read at all: any tab of a group can file a batch, and it says so on the channel - but
  // a message can arrive late, can be missed by a tab that was starting up, and is never sent by a
  // tab that closed straight after filing. The store is the record either way, and reading it back
  // is reading it in number order, which is the order batches must go out in.
  //
  // Below a number because that's all a sender needs to know before sending the batch holding it,
  // and a queue drained one send at a time would otherwise read every record again for each one.
  //
  // A READ, so it is deliberately not `#write`: it starts no read-write transaction, and it is not
  // counted as work in flight, which is what a test waits on to know a WRITE has landed. A read
  // that fails answers nothing rather than tearing the storage down - nothing has been lost, and
  // the next send asks again.
  static async queuedBatches(below = null) {
    if (Durability.mode === "memory") {
      return [];
    }

    try {
      const transaction = Durability.#db.transaction([QUEUE], "readonly");
      const queue = transaction.objectStore(QUEUE);

      const records = await Durability.#request(
        below === null
          ? queue.getAll()
          : queue.getAll(globalThis.IDBKeyRange.upperBound(below, true)),
      );

      return records ?? [];
    } catch {
      return [];
    }
  }

  // Drops what the SERVER said and keeps what this browser did: the rows go, the place they were
  // dated at goes with them, and the identity, the counter and the clock stay. Called when a
  // resync replaces the whole pot, and when what is stored cannot be read by this page. Never over
  // another user's rows.
  static clear() {
    return Durability.#write([ENTITIES, META], (transaction) =>
      Durability.#whileOwned(transaction, () => Durability.#wipe(transaction), {
        settlesStore: true,
      }),
    );
  }

  // `hologram.<layout>.<protocol version>.<model hash>` - a bundle carrying another store layout,
  // speaking another sync protocol or built against another model opens a database of its own.
  //
  // The framework's half comes first and the app's second, broad before narrow: the layout is
  // Hologram's own and moves when the shape of the store does, the protocol is Hologram's too and
  // moves when what the stream sends does, and the model hash is the app's and moves on any deploy
  // that touches an entity. That also leaves the stable half as a prefix - `hologram.<layout>.`
  // names every database of one shape, which is a prefix test rather than a parse for anything
  // that ever has to gate on a shape it cannot read.
  //
  // The protocol is in the name for the group rather than for the store. The server stops serving
  // a tab speaking an older protocol, and a tab loaded after the upgrade would otherwise join that
  // tab's group and follow a leader that is never served. Two protocols are two groups, so a group
  // is one model and one protocol, and whatever stops one of its tabs stops all of them.
  //
  // Public because the group of tabs sharing this database is named from it, and so is the lock
  // that elects their leader - one database, one queue, one leader.
  static databaseName() {
    const sync = globalThis.Hologram.sync;

    return `hologram.${LAYOUT}.${sync.protocolVersion}.${sync.modelHash}`;
  }

  // The group of the given user's tabs over this database, so that two owners the store tells apart
  // are two groups.
  static groupName(owner) {
    return `${Durability.databaseName()}.${Durability.#ownerKey(owner)}`;
  }

  // Makes the store the given user's, with the given replica pair. The stored rows and place go
  // when they were somebody else's, and stay when the store is already this user's: a tab can have
  // read it before another tab of its group claimed it.
  //
  // ONE transaction, with the owner read inside it. Cleared in one and owned in another, a tab
  // reading between the two would find an empty store under the previous owner, and one reading
  // after a frame landed there would find the new user's rows under the old name. The pair goes
  // down with the owner, under that owner's name, and every other user's stays.
  //
  // The queue stays, as it does through every clear: the previous owner's batches wait there for a
  // page mounted under them.
  static claim(owner, replica) {
    const claimId = Utils.uuidv7();

    Durability.#replicaWrite = Durability.#write(
      [ENTITIES, META],
      (transaction) => {
        const meta = transaction.objectStore(META);
        const stored = meta.get("actorUserId");
        const storedClaim = meta.get("claim");

        storedClaim.onsuccess = () => {
          if ((stored.result ?? null) === owner) {
            Durability.#claimId = storedClaim.result ?? null;
          } else {
            Durability.#wipe(transaction);

            meta.put(owner, "actorUserId");
            meta.put(claimId, "claim");

            Durability.#claimId = claimId;
          }

          Durability.#writePair(transaction, owner, replica);
        };
      },
    ).then((stored) => {
      if (stored) {
        Durability.noteStoredReplica(replica);
      }

      return stored;
    });

    return Durability.#replicaWrite;
  }

  // Lets go of the database without touching what it holds. For a tab told that the tab leading its
  // group could not write: that tab wiped the rows and the place and closed, and this one has to
  // stop using the store too. And for a tab another one needs a new database version from.
  //
  // What load() read goes too, when this comes before the restore. The group ends with this (see
  // Tabs.dissolve): a follower asks for an identity of its own and lets go of the batches the store
  // holds, and taking up the stored identity and queue afterwards would make it a second sender
  // under the group's replica. The leader keeps what it already holds, and a queue it never took up
  // stays in the store for the next page load rather than going out twice.
  static detach() {
    Durability.#loaded = null;

    Durability.#letGo();
  }

  // A batch this browser has sealed, given the next number and written down - all three inside ONE
  // TRANSACTION, which is what makes the number safe to share between tabs.
  //
  // The number is READ where it is spent. Every tab of a browser writes into one queue keyed by
  // that number, so a counter moved in a tab's own memory is a counter two tabs can move to the
  // same value - and the second `put` would then overwrite the first tab's batch, losing a write
  // with nothing said.
  //
  // WHAT MAKES THE READ AND THE WRITE ONE STEP IS THE TRANSACTION, and it is worth saying outright
  // because it is easy to read this as unguarded. IndexedDB orders read-write transactions whose
  // scopes overlap, and it orders them per DATABASE rather than per connection - so a second tab
  // asking for `meta` and `queue` waits until the first tab's transaction has committed, and then
  // reads the number that transaction wrote. A Web Lock around this was written and removed: it
  // guarded nothing this does not already guarantee, and every mutation of it stayed green.
  //
  // What that costs is testability, which is the price of the guarantee living in the database
  // rather than in this file: a fake IndexedDB serializes everything anyway, so no unit test here
  // can tell a correct version from one that reads the counter outside the transaction. The two
  // tabs of `multi_tab_test.exs` are what bind it, in a browser where the case is real.
  //
  // The number taken is above the counter AND above every batch already in the queue. They're
  // normally the same, and part in a store an earlier build failed on, which dropped the counter and
  // kept the queue. 10b applied that rule when a page load resumed; applying it at every seal is
  // what makes it hold for a tab that never resumed anything.
  //
  // The batch and its number go down TOGETHER, in one transaction, because either without the
  // other is wrong in its own way. A number with no batch is one the next load counts on from for
  // work that no longer exists anywhere. A batch with no number is worse - the next load would
  // count from below it and hand the same number to something else, and whichever reached the
  // server second would be answered with the other's verdict.
  //
  // Nothing is read with `await` inside the transaction: an IndexedDB transaction commits the
  // moment it has no request outstanding, so the write has to be chained onto the read's own
  // callback rather than sequenced by the event loop.
  //
  // In memory mode the batch is left UNNUMBERED and the caller numbers it: there is nothing to file
  // and no transaction to order it against.
  //
  // Answers whether the batch is stored. One that isn't gives back the number it read here: that
  // was spent only in a transaction that didn't commit, so another tab can file under it.
  static async fileBatch(batch) {
    if (Durability.mode === "memory") {
      return false;
    }

    // The first batch stored is the first moment this browser holds something that exists nowhere
    // else - a row can always be downloaded again, an unsent write cannot - so it is the moment to
    // ask for the storage to be kept. Once per page load, and never awaited: the batch's own write
    // does not wait on a permission being read.
    if (!Durability.#persistenceAsked) {
      Durability.#persistenceAsked = true;

      Durability.#requestPersistence();
    }

    let taken = false;

    // Each filing's transaction starts in the turn its batch closed, so a tab letting go of the
    // store doesn't cut off the ones waiting in line. IndexedDB runs them in that order, so one
    // behind a filing that aborted aborts too. Stored, it would go out ahead of the earlier batch,
    // and the server would refuse it if it names a row that batch created.
    //
    // This transaction starts only once the earlier one has finished, but the event saying how can
    // still be on its way. Reading again keeps this one open until it arrives.
    const stored = await Durability.#write([META, QUEUE], (transaction) => {
      const earlier = Durability.#lastFiling;
      const filing = {aborted: false, done: false};

      Durability.#lastFiling = filing;

      transaction.addEventListener("abort", () => {
        filing.aborted = true;
        filing.done = true;
      });

      transaction.addEventListener("complete", () => {
        filing.done = true;
      });

      const meta = transaction.objectStore(META);
      const queue = transaction.objectStore(QUEUE);

      const readCounter = () => {
        const counter = meta.get("seq");

        counter.onsuccess = () => {
          if (earlier !== null && !earlier.done) {
            readCounter();

            return;
          }

          if (earlier?.aborted) {
            transaction.abort();

            return;
          }

          const highest = queue.openKeyCursor(null, "prev");

          highest.onsuccess = () => {
            const spent = Math.max(
              counter.result ?? 0,
              highest.result?.key ?? 0,
            );

            batch.seal(spent + 1);
            taken = true;

            queue.put(batch.record());
            meta.put(batch.seq, "seq");
            Durability.#putClock(meta);
          };
        };
      };

      readCounter();
    });

    // Only a number this filing put there: a store that failed on the spot never reached the read,
    // and the caller has numbered the batch for itself by now.
    if (!stored && taken) {
      batch.seq = null;
    }

    return stored;
  }

  // A batch the server has ruled on, gone from the queue. Confirmed or refused alike: either way
  // nothing is waiting on it any more, and a later page load has no reason to take it up.
  //
  // Fire and forget, unlike the write that put it there. What a crash between the verdict and this
  // delete costs is one batch sent a second time on the next load. A verdict on the server's record
  // is answered from it, so that costs a round trip. One that isn't is judged afresh (see
  // #forgetWithoutStore).
  //
  // Whose batch it is gets read here, before the wait: an answer to the next batch can move this
  // tab to another identity while the delete is running.
  static async forgetBatch(seq) {
    const owner = Durability.#pairOwner();
    const replicaId = Replica.id;
    const holdsIdentity = Durability.hadStore && Durability.holdsIdentity();

    if (Durability.mode !== "memory") {
      const deleted = await Durability.#write([QUEUE], (transaction) =>
        transaction.objectStore(QUEUE).delete(seq),
      );

      if (deleted) {
        return;
      }
    }

    if (holdsIdentity) {
      await Durability.#forgetWithoutStore(seq, owner, replicaId);
    }
  }

  // The same, for a tab that has let go of the store, or just did because this delete failed, and
  // is still sending the batches it holds. Not every verdict is on the server's record: a refusal
  // of a signed-out visitor's batch isn't, and neither is a `:clock` refusal. A batch left in the
  // queue would go out again on the next load and be judged afresh, so a write the person watched
  // fail could apply.
  //
  // Over a connection of its own, for this one delete, which usually works on a full disk too. If
  // it doesn't, the next load sends the batch again and that risk stands.
  //
  // Only while the store still names this identity. Under another one, the same number can be a
  // different batch. And a database deleted meanwhile stays deleted: opening it would otherwise
  // bring it back with no stores in it, and every later load would fall to memory mode.
  static async #forgetWithoutStore(seq, owner, replicaId) {
    let db = null;

    try {
      const request = globalThis.indexedDB.open(
        Durability.databaseName(),
        VERSION,
      );

      request.onupgradeneeded = () => request.transaction.abort();

      db = await Durability.#request(request);
      db.onversionchange = () => db.close();

      const transaction = db.transaction([META, QUEUE], "readwrite");
      const stored = transaction
        .objectStore(META)
        .get(Durability.#pairKey(owner));

      stored.onsuccess = () => {
        if (stored.result?.id === replicaId) {
          transaction.objectStore(QUEUE).delete(seq);
        }
      };

      await Durability.#complete(transaction);
    } catch {
      // There is nothing further to try, and the batch has had its answer either way.
    } finally {
      db?.close();
    }
  }

  // Everything the previous page load left, read in one go and held for restore() - apart from
  // open() because the tab joins its group between the two. A tab that read first and joined
  // after would miss a frame the leading tab stored after the read and posted before the join:
  // in neither the store it read nor any message it heard.
  //
  // Answers nothing, and never throws, the same as open(): a store that cannot be read is a page
  // that carries on from memory.
  //
  // Read again by a tab moving to another user's group, which can move on again while this reads
  // (see DataLayer.followIdentity). `isCurrent` says whether the move that asked still stands, and
  // a read it no longer wants is dropped, so the next restore can't take it up.
  static async load(isCurrent = () => true) {
    if (Durability.mode === "memory") {
      return;
    }

    let loaded;

    try {
      loaded = await Durability.#read();
    } catch (error) {
      // A move the tab has moved on from says nothing about the store the next move reads, which
      // fails on its own if it fails at all.
      if (!isCurrent()) {
        return;
      }

      return Durability.#memoryMode(`read failed (${error})`);
    }

    // Let go of while it was being read - another tab could not write, or needs a new version.
    // Closing a database lets a transaction already running finish, so the read still answers,
    // and taking up what it found would hand this tab, which now leads itself, the identity and the
    // queue the group's leader is still sending: two senders under one replica.
    if (Durability.mode !== "indexeddb" || !isCurrent()) {
      return;
    }

    Durability.#claimId = loaded.claim;
    Durability.#loaded = loaded;
    Durability.#storedReplicaId =
      loaded.replicas[Durability.#ownerKey(Durability.#pairOwner())]?.id ??
      null;
    Durability.storedBatches = loaded.queue.length;
  }

  // Opens the database and reads nothing from it - load() does that, once the tab has joined the
  // group sharing it (see DataLayer.boot).
  //
  // Answers nothing, and never throws: a browser that cannot store is a browser that carries on
  // from memory. Every way that can happen is named, because the reason is what a developer needs
  // when a page is unexpectedly re-downloading everything.
  static async open() {
    // Reaching the API AT ALL is inside the try, not only awaiting its answer. Where storage is
    // restricted - a sandboxed iframe, an opaque origin, a browser told to block site data - both
    // the property read and the open() call throw SYNCHRONOUSLY, and a throw escaping here would
    // not merely cost this page its durability: the runtime awaits this during boot, so the whole
    // page would fail to start in exactly the context this function exists to absorb.
    try {
      if (!globalThis.indexedDB) {
        return Durability.#memoryMode("IndexedDB unavailable");
      }

      // What is stored is shared by every tab of this browser, and sharing it needs one tab to
      // speak for the rest - which is what a Web Lock elects. Without one, every tab leads itself:
      // two streams downloading every frame twice, and two senders draining ONE queue under one
      // replica identity, where the watermark a frame carries - the number that stops this client
      // applying its own write a second time - describes a single sender. So a browser that cannot
      // elect keeps its tabs independent, each working from its own memory: it costs durability
      // there, and it cannot cost a write.
      //
      // (The COUNTER is not the reason, though it reads like one: the number is read and spent
      // inside the transaction that files the batch, and IndexedDB orders those across tabs on its
      // own - see `fileBatch`.)
      if (!globalThis.navigator?.locks) {
        return Durability.#memoryMode("no Web Locks");
      }

      const request = globalThis.indexedDB.open(
        Durability.databaseName(),
        VERSION,
      );

      request.onupgradeneeded = () => Durability.#upgrade(request.result);

      Durability.#db = await Durability.#request(request);
    } catch (error) {
      return Durability.#memoryMode(`open failed (${error})`);
    }

    // Another tab is moving the database to a version this bundle does not speak. Letting go AT
    // ONCE is the whole of what the event asks for: holding on blocks that upgrade for as long as
    // this page lives, and even starting a transaction here would block it for as long as the
    // transaction takes.
    //
    // Closed rather than failed, and the difference matters: nothing stored has become untrue. The
    // rows, the place and the counter are all still exactly what they were, and the bundle doing
    // the upgrading is the one that decides what to carry across. Wiping would block the upgrade
    // in order to throw away a store that the upgrading bundle wanted.
    //
    // The group ends with it, since a tab with no store can't lead one or follow it. Every tab of
    // the group gets this event for its own connection, so none has to be told.
    Durability.#db.onversionchange = () => {
      Logger.debug(
        "Hologram: another tab needs a new database version, the database lives in memory for this page",
      );

      Durability.detach();
      Tabs.dissolve();
    };

    Durability.hadStore = true;
    Durability.mode = "indexeddb";
  }

  // One frame, one transaction: the rows it wrote, the place those rows are dated at, and where
  // the clock now stands. Together, because a place is a claim about rows - stored apart, a crash
  // between them would leave a client naming a place it does not hold the rows for, and the server
  // would tell it only what changed since.
  //
  // Not awaited by anything on the write path. The rows are already in memory and already on
  // screen, and what this buys is only whether they are still there after a reload. What waits for
  // it is telling the other tabs (see Tabs.post).
  //
  // Only into a store this tab's user owns. The clock goes down either way, since it is what this
  // browser did rather than anything about the rows.
  //
  // `factRemovals` are pairs to take out of stored sets, leaving the rest of each record as stored
  // (see `LocalDatabase.takeStoredFactRemovals`). Read after the frame's own puts, which a
  // transaction runs in order, so a record this frame wrote is judged as written.
  static persistFrame(records, cursor, factRemovals = []) {
    return Durability.#write([ENTITIES, META], (transaction) => {
      const entities = transaction.objectStore(ENTITIES);
      const meta = transaction.objectStore(META);

      Durability.#whileOwned(transaction, () => {
        for (const record of records) {
          if (record.row === null) {
            entities.delete([record.type, record.id]);
          } else {
            entities.put(record);
          }
        }

        Durability.#removeStoredFacts(entities, factRemovals);

        // A frame sent mid-fill names no place, because a client holding part of a pot could not
        // honour the claim one makes. The place already stored still describes the rows that were
        // there before this fill started, so it is left standing rather than cleared - which is
        // what lets a client cut off mid-fill come back asking for what it can still honour.
        if (cursor !== null) {
          meta.put(cursor, "cursor");
        }
      });

      Durability.#putClock(meta);
    });
  }

  // A pending batch whose writes the base has caught up with, written down again for the marks.
  //
  // Why the marks are worth storing at all: a batch can be sent, committed, have its frame arrive
  // and be stored, and then lose its ANSWER to a dropped connection. The next page load takes the
  // batch up and sends it again, the server answers from its record, and the client promotes it -
  // and a moved counter promoted onto a base that already holds the move counts it twice, for
  // good. Nothing later corrects that, because the server has nothing new to say about a row
  // nobody has touched since. The marks are what makes the promotion pass over it.
  //
  // The counter is deliberately NOT rewritten here, which is what makes this different from the
  // write that first stored the batch. A frame can land the writes of a batch that is not the
  // newest one sealed, and putting this batch's number down would walk the counter backwards -
  // onto a number a later batch has already spent.
  //
  // Fire and forget: the marks are already in memory, and what storing them buys is only whether
  // they are still true after a reload.
  //
  // Only over a record the queue still holds. A tab other than the sender can hear the frame that
  // lands a batch after the sender was answered and let go of it - a follower whose frame arrives
  // behind the delete, or a starting tab replaying what it heard while starting - and writing it
  // back would put an answered batch in the queue for the next page load to send again. Read and
  // written in ONE transaction, the put chained onto the read's callback, so a delete cannot land
  // in between.
  //
  // And with the marks the record already holds kept: another tab can have stored more of them,
  // having heard frames this one has not yet, and a mark lost is a move promoted a second time,
  // by the next page load or by a later read of the store (see Tabs.#takeStore).
  //
  // The marks are taken as they stand now, not when the record answers: a frame that lands another
  // write meanwhile has its own write coming, behind its rows, and its mark written here would go
  // down ahead of those rows.
  static persistLanded(batch) {
    const record = batch.record();

    return Durability.#write([QUEUE], (transaction) => {
      const queue = transaction.objectStore(QUEUE);
      const stored = queue.get(batch.seq);

      stored.onsuccess = () => {
        if (stored.result === undefined) {
          return;
        }

        // A record can predate the marks (see Batch#record): none stored is none landed.
        const landed = new Set([
          ...(stored.result.landed ?? []),
          ...record.landed,
        ]);

        queue.put({
          ...record,
          landed: Array.from(landed).sort((left, right) => left - right),
        });
      };
    });
  }

  // The identity this browser presents, kept so that the next page load can ignore the fresh pair
  // it is offered and go on numbering where this one left off.
  //
  // Under this tab's own user, whoever owns the store's rows at the moment.
  static persistReplica(replica) {
    const owner = Durability.#pairOwner();

    Durability.#replicaWrite = Durability.#write([META], (transaction) => {
      Durability.#writePair(transaction, owner, replica);
    }).then((stored) => {
      if (stored) {
        Durability.noteStoredReplica(replica);
      }

      return stored;
    });

    return Durability.#replicaWrite;
  }

  // The identity the store holds, for a tab that learned it from its group rather than reading or
  // writing it itself. A tab's state names an identity only once it's written down (see
  // Tabs.postState).
  static noteStoredReplica(replica) {
    Durability.#storedReplicaId = replica.id;
  }

  // Whether the identity this tab presents is the one the store holds. A tab without a store that
  // does may send the stored batches under it, and nothing else: their numbers are recorded, and a
  // new one would be recorded nowhere, so the next load could spend it again.
  static holdsIdentity() {
    return Replica.id !== null && Replica.id === Durability.#storedReplicaId;
  }

  // The rows the store holds and the place they stand at, read again after the load - for a tab
  // that follows and hears the group name a place it does not hold. The tab that led can have
  // brought the store somewhere this tab never followed it to (see repair), and the store is the
  // one record of where that is, and of the rows that stand there.
  //
  // Given the place the tab holds, so the rows are read only when they can be other than the ones
  // it has. A place is only ever written with its rows, in one transaction, and the rows under a
  // place that stands change only through frames every tab of the group hears in order - so the
  // same place is taken for the same rows, which is the equality repair rests on too. A store
  // holding no place has no rows to take up: they are a fill that never finished, which is why a
  // restore refuses them. Answers the stored place, with every stored record, or with
  // `records: null` when the place is the given one or there is none - and the user the store
  // belongs to, since one store serves every user of the browser, each in a group of their own.
  //
  // With the rows comes what the queue records as landed, batch by batch: a stored frame can
  // have landed a batch this tab holds unlanded, and promoted again over rows that already hold
  // its writes, a moved counter would count twice.
  //
  // ONE read-only transaction, the rows read in the callback of the place's own request: a write
  // landing between two transactions could leave the rows of one place beside another.
  //
  // A READ, like queuedBatches: not counted as work in flight, and one that fails answers nothing
  // rather than tearing the storage down. So does memory mode, where there is nothing to read.
  // Whatever goes wrong, it answers: a tab waits on it before it hears its group again.
  static async readBase(cursor) {
    if (Durability.mode === "memory") {
      return null;
    }

    try {
      const transaction = Durability.#db.transaction(
        [ENTITIES, META, QUEUE],
        "readonly",
      );

      return await new Promise((resolve, reject) => {
        transaction.onabort = () => reject(transaction.error);

        const meta = transaction.objectStore(META);

        // Requests on one transaction answer in the order they were made, so the owner is in by the
        // time the place's callback runs.
        const owned = meta.get("actorUserId");
        const stored = meta.get("cursor");

        owned.onerror = () => reject(owned.error);
        stored.onerror = () => reject(stored.error);

        stored.onsuccess = () => {
          const owner = owned.result ?? null;
          const place = stored.result ?? null;

          if (place === cursor || place === null) {
            resolve({cursor: place, owner, records: null});

            return;
          }

          try {
            Promise.all([
              Durability.#request(transaction.objectStore(ENTITIES).getAll()),
              Durability.#request(transaction.objectStore(QUEUE).getAll()),
            ]).then(
              ([records, queued]) =>
                resolve({
                  cursor: place,
                  // A record can predate the marks (see Batch#record).
                  landed: (queued ?? []).map(({landed, seq}) => ({
                    landed: landed ?? [],
                    seq,
                  })),
                  owner,
                  records: records ?? [],
                }),
              reject,
            );
          } catch (error) {
            reject(error);
          }
        };
      });
    } catch {
      return null;
    }
  }

  // The store brought to what this tab holds in memory, where the two name different places - what
  // a tab does on taking the lead of its group.
  //
  // Why they can differ: the tab that led before wrote things down before telling the group of
  // them, so a tab closed between the two leaves the store ahead of what every other tab heard. A
  // frame ahead is harmless on its own - the rows are newer than the place this tab greets from,
  // and the server sends them again. The store can be behind too, for a tab that read it ahead and
  // leads after another tab's repair. Either way the rows memory holds are written whole, with the
  // place they stand at, in one transaction, and the server sends what follows that place again.
  //
  // Only where they differ. A place is a string, so equal places mean the store already holds
  // exactly what the memory does, and nothing is written - which is the usual case.
  //
  // And never over a store naming NO place, which this tab cannot tell from a clear ahead: a
  // start-over the tab that led wrote down and closed before telling anyone of (see Tabs.post).
  // Whatever emptied it, the rows this tab holds are not what the store vouches for. Rewritten, the
  // store would claim them while a tab that read it empty meanwhile takes this tab's place and
  // completeness over none. So nothing is written, and this answers true: the tab taking the lead
  // starts over, the way the start-over would have told it to.
  //
  // The read and the write are ONE read-write transaction, created before this returns, and the
  // write is chained onto the read's own callback the way fileBatch chains its counter: read in a
  // transaction of its own, a write after it could land on top of something stored in between and
  // put the store back behind what this tab holds. (The tab serves itself no frames while this
  // decides - see Tabs.takingLead - but this does not rest on that.)
  //
  // So a read that fails is a write that fails, and stops the storage the way any failed write
  // does (see #fail) - rather than skipping the repair, which would leave the store naming another
  // place than this tab with nothing to say so.
  //
  // Over a store another user owns it writes nothing and answers false. What that store holds or
  // lacks says nothing about this tab's rows, so the tab keeps its place and works from memory.
  // Over this user's store it takes up the current claim, since it leaves the store matching this
  // tab, or starts over from it.
  static async repair(records, cursor) {
    let placeless = false;

    await Durability.#write([ENTITIES, META], (transaction) => {
      const entities = transaction.objectStore(ENTITIES);
      const meta = transaction.objectStore(META);

      Durability.#whileOwned(
        transaction,
        () => {
          const stored = meta.get("cursor");

          stored.onsuccess = () => {
            const place = stored.result ?? null;

            if (place === null) {
              placeless = true;

              return;
            }

            if (place === cursor) {
              return;
            }

            entities.clear();

            for (const record of records) {
              entities.put(record);
            }

            meta.put(cursor, "cursor");
            Durability.#putClock(meta);
          };
        },
        {settlesStore: true},
      );
    });

    return placeless;
  }

  // Settles once every identity write started so far has - what a send waits on, so nothing goes
  // out under an identity still on its way to the store (see Batches.flush). Writes to the same
  // store commit in the order they were made, so the last one settling means every earlier one has.
  //
  // Not every write is awaited where it is made: the restore writes a fresh pair and goes on, and
  // the tab's first send can follow at once. A reload landing between the two would take up yet
  // another pair, and send the same batch again under it.
  static replicaWritten() {
    return Durability.#replicaWrite;
  }

  // Takes up what the previous page load left, and answers the three things the runtime resumes
  // from: the place to greet the stream with, the number to count batches on from, and the batches
  // this page may send.
  //
  // `leader` says whether this tab is the one that speaks to the store for the group of tabs
  // sharing it. A FOLLOWER ASKS ONE THING OF THE STORE: whose it is. One store serves every user of
  // the browser, so rows of another user are never taken up, by any tab, not even until the leader
  // has judged them: a query answered from them in that gap would show one person another's data.
  // The follower takes no rows and no place then, and what its own leader stores from here reaches
  // it as frames.
  //
  // Beyond that it refuses no rows, clears nothing, writes no identity and records no owner. The
  // leader makes those calls once for everyone, and tells the group to start over when it refuses
  // (the same frame a server resync sends). A follower that read a stale store refills on that and
  // takes the fill from the channel, and one that reads the store after the leader cleared it finds
  // it empty. What that buys is the one case where a follower's own judgement WOULD be wrong: rows
  // with no place because the leader is filling right now, which are half of a base the frames
  // are about to complete - refused, nothing would bring that half back.
  //
  // SYNCHRONOUS, and called after the page has mounted rather than before. After, because the rows
  // the page itself carried are the freshest thing this client has - the server rendered them for
  // this request - so they go in first and a stored row fills only what the page said nothing
  // about. Synchronous, because everything the mount leads to runs in one continuation, which is
  // what puts this ahead of the first local write without anything having to race.
  //
  // Answers NOTHING when there is nothing to take up - a browser with no durable storage, and
  // every call after the first. The second matters: the runtime's page-script listener runs again
  // on each client-side navigation, so this is reached once per page visit, and a later call that
  // answered a place of null would take away the one the stream had been keeping all along. A tab
  // moving to another user's group loads again and takes that up the same way, as the user it now
  // holds (see DataLayer.followIdentity).
  //
  // The rows are dropped rather than used in two cases, and each is a case where showing them
  // would be showing something untrue. (A model change is not among them any more: a bundle on
  // another model opens another database, and finds it empty.) What this browser DID - its identity, its counter, its
  // clock - survives all three: those are not the server's to take away, and reusing a number or
  // restarting a clock low is how a write gets answered by the wrong batch or read as moved.
  //
  // The batches are taken up whether or not the ROWS are, and the queue is not dropped in either
  // case. A pending write over a base that has started again is the same case as a resync with
  // writes pending: a create folds as a new row, an update of a row the base does not hold yet
  // folds nothing until the fill brings it, and the fill's rows carry the revisions the fold
  // weighs the write against.
  //
  // ONLY THIS PAGE'S OWN USER'S BATCHES. A batch is applied by the server under the user of the
  // session that SENDS it, so a batch taken up by a page somebody else has since signed in on
  // would be written in their name - or refused by their policies, and the work thrown away.
  // Somebody else's batches are left in the store untouched: not loaded, not folded, not sent, not
  // forgotten, and taken up by the next load that mounts under their own owner. (Nothing else can
  // deliver them - the server knows nothing of a batch it has never been sent - so waiting is the
  // whole of what is available, and it costs nothing.)
  //
  // The counter resumes above every STORED BATCH as well as above the number itself, which are
  // normally the same. They part in a store an earlier build failed on, which dropped the counter
  // and kept the queue. Counting from nothing would then hand a new batch a number a stored one
  // already holds, and its record would be overwritten by a batch that is not it.
  static restore(leader) {
    const loaded = Durability.#loaded;

    Durability.#loaded = null;
    Durability.#restored = true;

    if (loaded === null) {
      return null;
    }

    // Before anything else and whatever happens below: a stamp this browser issues has to be above
    // every stamp it issued or was told about on any earlier load.
    Clock.observe(loaded.clock);

    const ownerChanged =
      loaded.actorUserId !== (LocalDatabase.actorUserId ?? null);

    const refusal = leader ? Durability.#refusal(loaded, ownerChanged) : null;
    const takesRows = refusal === null && !ownerChanged;
    const owner = LocalDatabase.actorUserId ?? null;
    const storedPair = loaded.replicas[Durability.#ownerKey(owner)] ?? null;

    if (takesRows) {
      LocalDatabase.restore(loaded.records);
    }

    // A page load offers a fresh pair and a browser already holding one for this user ignores it -
    // re-minting per load would abandon the numbering its batches are identified by. Taken up
    // whoever's rows the store holds now, and before the claim below writes the pair in use.
    if (storedPair !== null) {
      Replica.adopt(storedPair);
    }

    Replica.owner = owner;

    if (refusal !== null) {
      Logger.debug(
        `Hologram: the stored rows were dropped (${refusal}), this page fills from nothing`,
      );

      // Somebody else's store becomes this user's. Once for the group, and the first send waits
      // for it (see replicaWritten).
      if (ownerChanged) {
        Durability.claim(owner, Replica.current());
      } else {
        Durability.clear();
      }

      // The other tabs of the group are told to start over the way a server resync tells everyone
      // - AFTER the transaction is created, so a tab that reads the store on hearing this reads it
      // as it now stands.
      //
      // Never as `identity`, even over another user's rows, since that word drops what a tab holds
      // at once. Every tab hearing this was mounted for this tab's user and took none of those
      // rows (see above), so what it holds is its own page's, which a refill keeps readable.
      Tabs.post({
        event: "sync_resync",
        frame: {reason: refusal},
        kind: "frame",
      });
    }

    // With none stored for this user, the leader writes the page's, once for the group, which its
    // first send waits for (see replicaWritten). A follower writes none: it presents no identity of
    // its own to the server, and the pair the leader settled on reaches it with the group's state.
    //
    // A store let go after this read can't record that pair, so the tab asks for one of its own.
    if (storedPair === null && Durability.mode === "memory") {
      Replica.requestMint();
    } else if (storedPair === null && leader && !ownerChanged) {
      Durability.persistReplica(Replica.current());
    }

    const queued = loaded.queue.map((record) => record.seq);
    const seq = Math.max(loaded.seq, ...queued);

    Durability.#queueAtRestore = {highest: seq, numbers: new Set(queued)};
    Durability.#storedReplicaId = storedPair?.id ?? null;

    return {
      batches: loaded.queue.filter((record) => record.actorUserId === owner),
      cursor: takesRows ? loaded.cursor : null,
      readForeign: !leader && ownerChanged,
      seq,
    };
  }

  // Drops the database entirely and puts this module back as it starts. For tests - nothing in the
  // framework throws away what a browser has kept.
  static async reset() {
    Durability.#close();

    try {
      await Durability.#request(
        globalThis.indexedDB.deleteDatabase(Durability.databaseName()),
      );
      // eslint-disable-next-line no-empty
    } catch {}

    Durability.hadStore = false;
    Durability.inFlight = 0;
    Durability.persisted = null;
    Durability.storedBatches = 0;

    Durability.#loaded = null;
    Durability.#lastFiling = null;
    Durability.#persistenceAsked = false;
    Durability.#queueAtRestore = null;
    Durability.#restored = false;
    Durability.#storedReplicaId = null;
    Durability.#replicaWrite = Promise.resolve();
    Durability.#claimId = null;
  }

  // Whether a batch was answered before this page read the store, which a tab that started later
  // has no message to tell it. A number leaves the queue only by being answered, so one at or below
  // the highest the read saw, and not in the queue it read, has been. The stored counter never
  // falls back, so no later batch is handed a number at or below that highest.
  static wasAnswered(seq) {
    const read = Durability.#queueAtRestore;

    return read !== null && seq <= read.highest && !read.numbers.has(seq);
  }

  static #close() {
    if (Durability.#db !== null) {
      Durability.#db.close();
      Durability.#db = null;
    }

    Durability.mode = "memory";
  }

  static #complete(transaction) {
    return new Promise((resolve, reject) => {
      transaction.onabort = () => reject(transaction.error);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
  }

  // Something the database was asked to do could not be done. What follows is always the same:
  // the rows and the place go, and this page carries on from memory.
  //
  // They go because a base missing one frame's is worse than no base at all - the next startup
  // cannot tell the two apart, and would resume from a place claiming rows that were never
  // written. Only this tab's user's rows: a store another user took holds nothing this failure made
  // untrue. What this browser DID is left alone, as everywhere else: a number reused and a clock
  // restarted low cost more than a re-download.
  //
  // That includes the identity and its counter, which stay true: nothing spends a number under the
  // stored identity without the store (see Batches.#numbered). And the stored queue needs them. A
  // batch answered after this point may stay in the queue if its delete fails too (see
  // forgetBatch). The next load then sends it again, and only under the same identity and number
  // does the server answer it from its record rather than apply it twice.
  //
  // The wipe deliberately does NOT go through the ordinary write path. A failure here must not
  // come back round to this function, and it cannot: nothing in this block reports one. That is
  // also why there is no "already failing" flag to keep in step - the shape rules the case out
  // rather than catching it.
  //
  // Only the tab that leads wipes the rows and the place. It's the only one that writes them, so
  // what it wipes lands behind its own frames. A tab that follows failed on the queue or the
  // counter, which leaves them true, and a wipe from it could land ahead of a frame the leader has
  // already started: the store would then name a place holding that frame's rows alone.
  static #fail(reason) {
    // A write still running when this tab let go of the store. The tab has left its group, and what
    // the store holds is no longer its to wipe.
    if (Durability.#db === null) {
      return;
    }

    Logger.debug(
      `Hologram: durable storage stopped (${reason}), the database lives in memory for this page`,
    );

    if (Tabs.leader) {
      try {
        const transaction = Durability.#db.transaction(
          [ENTITIES, META],
          "readwrite",
        );

        Durability.#whileOwned(transaction, () =>
          Durability.#wipe(transaction),
        );
      } catch {
        // There is nothing further to try - this page stops storing either way.
      }
    }

    Durability.#letGo();

    // This tab leaves its group, since it can't lead one or file into one with no store. If it led,
    // the other tabs are told, since the rows and the place have just gone from under them.
    Tabs.storeLost();
  }

  // Closes the store for the rest of this page. A tab that has taken up nothing from it, and now
  // never will, counts from 1 under whatever pair it presents, so it asks for one of its own. Every
  // way a boot can end without a store comes through here.
  static #letGo() {
    Durability.#close();

    if (Durability.#loaded === null && !Durability.#restored) {
      Replica.requestMint();
    }
  }

  static #memoryMode(reason) {
    Logger.debug(
      `Hologram: no durable storage (${reason}), the database lives in memory for this page`,
    );

    Durability.#letGo();
  }

  // Asks the browser to exempt this origin from eviction - and NEVER puts a dialog in front of
  // anyone to do it.
  //
  // Worth asking at all because of Safari: it clears a site's storage after about seven days
  // without a visit, and where that used to cost a re-download it now costs writes that were never
  // sent. Chrome and Firefox evict only under disk pressure, and Chrome grants this on its own to
  // a site somebody actually uses.
  //
  // The permission is READ before it is requested, which is the whole of how the dialog is avoided:
  // `prompt` means asking would raise one, so this does not ask. Not a browser check - there is no
  // honest way to write one, since every browser's user agent lies about what it is - but a
  // question put to the browser about its own behaviour.
  //
  // A browser that does not know the permission name throws, and that is the case to go AHEAD on:
  // it does not gate this behind a dialog, and Safari - which knows no such permission - is exactly
  // the browser the seven-day rule makes this worth doing for.
  //
  // The lever that beats all of this is INSTALLING the app, which is exempt from Safari's rule and
  // auto-granted by Chrome. Nothing here can ask for that, and it is where the mobile and desktop
  // story goes.
  static async #requestPersistence() {
    if (Durability.mode !== "indexeddb" || !navigator.storage?.persist) {
      return;
    }

    try {
      const {state} = await navigator.permissions.query({
        name: "persistent-storage",
      });

      if (state === "prompt") {
        Durability.persisted = false;

        Logger.debug(
          "Hologram: this browser would ask permission to keep the data, so it was not asked - storage here may be evicted",
        );

        return;
      }
      // eslint-disable-next-line no-empty
    } catch {}

    Durability.persisted = await navigator.storage.persist();

    if (!Durability.persisted) {
      Logger.debug(
        "Hologram: the browser did not agree to keep this site's data, storage here may be evicted",
      );
    }
  }

  // Everything the previous page load left, in one read - the six things `meta` holds and every
  // row record. Absences are normalized here rather than at every reader: a key nothing was ever
  // written under reads as undefined, and "nothing stored" is a state restore has to reason about.
  static async #read() {
    const transaction = Durability.#db.transaction(
      [ENTITIES, META, QUEUE],
      "readonly",
    );

    const entities = transaction.objectStore(ENTITIES);
    const meta = transaction.objectStore(META);
    const queue = transaction.objectStore(QUEUE);

    const pairKeys = globalThis.IDBKeyRange.bound(
      REPLICA_PREFIX,
      `${REPLICA_PREFIX}\uffff`,
    );

    const [
      actorUserId,
      claim,
      clock,
      cursor,
      queued,
      records,
      storedPairKeys,
      storedPairs,
      seq,
    ] = await Promise.all([
      Durability.#request(meta.get("actorUserId")),
      Durability.#request(meta.get("claim")),
      Durability.#request(meta.get("clock")),
      Durability.#request(meta.get("cursor")),
      Durability.#request(queue.getAll()),
      Durability.#request(entities.getAll()),
      Durability.#request(meta.getAllKeys(pairKeys)),
      Durability.#request(meta.getAll(pairKeys)),
      Durability.#request(meta.get("seq")),
    ]);

    return {
      actorUserId: actorUserId ?? null,
      claim: claim ?? null,
      clock: clock ?? 0,
      cursor: cursor ?? null,
      queue: queued ?? [],
      records: records ?? [],
      replicas: Object.fromEntries(
        storedPairKeys.map((key, index) => [
          key.slice(REPLICA_PREFIX.length),
          storedPairs[index],
        ]),
      ),
      seq: seq ?? 0,
    };
  }

  // Why the stored rows cannot be used, or nothing when they can.
  //
  // No place is the sharper of the two: rows were written by a fill that never finished, and a
  // base with no place is not resumable at all - the server would fill it from scratch and never
  // say which of the held rows it is no longer sending, so a row deleted while this browser was
  // away would stay on the screen for as long as the store lived.
  //
  // An owner changed makes them somebody else's - and that is not corrected by the stream either,
  // since a resuming client is told what MOVED, never what it should no longer be holding.
  static #refusal(loaded, ownerChanged) {
    if (loaded.cursor === null) {
      return "no place to resume from";
    }

    if (ownerChanged) {
      return "somebody else is signed in";
    }

    return null;
  }

  // The text naming an owner in a key or a group name. A user's is the server's exact text (see
  // Hologram.Auth.owner_key/1), which starts with i, s or u, so it is never the word for a visitor.
  static #ownerKey(owner) {
    return owner ?? "anonymous";
  }

  static #pairKey(owner) {
    return `${REPLICA_PREFIX}${Durability.#ownerKey(owner)}`;
  }

  // Whose the pair in use is. The actor can move on at a page visit while the pair stays the one
  // this document took up, and written under the new actor it would replace that user's own.
  static #pairOwner() {
    return Replica.owner === undefined
      ? (LocalDatabase.actorUserId ?? null)
      : Replica.owner;
  }

  // Nothing for a tab holding no pair: one that followed a page to another user is given none (see
  // DataLayer.followIdentity), and the slot it would write over is that user's own.
  static #writePair(transaction, owner, replica) {
    if (!replica?.id) {
      return;
    }

    transaction.objectStore(META).put(replica, Durability.#pairKey(owner));
  }

  // One read per record, applying all its removals at once: two reads of one record would both see
  // it as stored, and the second put would undo the first.
  static #removeStoredFacts(entities, factRemovals) {
    const byRecord = new Map();

    for (const removal of factRemovals) {
      const key = JSON.stringify([removal.type, removal.id]);

      byRecord.set(key, [...(byRecord.get(key) ?? []), removal]);
    }

    for (const removals of byRecord.values()) {
      const {id, type} = removals[0];
      const read = entities.get([type, id]);

      read.onsuccess = () => {
        const record = read.result;

        if (record === undefined) {
          return;
        }

        const facts = {...record.facts};

        for (const {relationship, targetIds} of removals) {
          if (facts[relationship] !== undefined) {
            const removed = new Set(targetIds);

            facts[relationship] = facts[relationship].filter(
              (targetId) => !removed.has(targetId),
            );
          }
        }

        entities.put({...record, facts});
      };
    }
  }

  static #request(request) {
    return new Promise((resolve, reject) => {
      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result);

      // Only an open can be blocked, and only by a tab still holding the database at a version
      // this one is trying to replace - which is not something to wait out. Set here rather than
      // beside the open, so that one wrapper covers every outcome a request has.
      request.onblocked = () => reject(new Error("blocked by another tab"));
    });
  }

  // The facts ride inside a row's record rather than in a store of their own: they are keyed by
  // their source row, a row leaving takes them with it, and an edge names the row whose
  // relationships changed - so one row is one record and one change is one write.
  //
  // A row record is keyed by its type and id together, which is how a frame's rows are named, and
  // how one type's rows are dropped without touching another's.
  //
  // A batch is keyed by its number, because that is the order batches were made in and therefore
  // the order they ship in - a later batch may name a row an earlier one created. Reading them
  // back in key order is reading them back in the order to send them, with nothing to sort.
  static #upgrade(db) {
    db.createObjectStore(ENTITIES, {keyPath: ["type", "id"]});
    db.createObjectStore(META);
    db.createObjectStore(QUEUE, {keyPath: "seq"});
  }

  // Where this tab's clock stands, unless the store's already stands further. Every user's tabs
  // write it, and a tab of another user can be behind the clock this user's rows were stamped
  // with: written over, the next load would start the clock below revisions it holds.
  static #putClock(meta) {
    const stored = meta.get("clock");

    stored.onsuccess = () => {
      meta.put(Math.max(stored.result ?? 0, Clock.last()), "clock");
    };
  }

  // Runs the given write only if the store is this tab's user's and has not been claimed since this
  // tab last knew it, both read inside the write's own transaction, so another tab's claim lands
  // wholly before it or wholly after it.
  //
  // A write that leaves the whole store matching this tab settles it, and takes up a newer claim of
  // the same user: a follower can have read the store before its leader claimed it.
  //
  // The tab's user has to be the one its document took the store up for too. A navigation can move
  // the actor to another user while the tab still holds the previous user's rows and place, and
  // those must not land under the new user's name.
  //
  // A tab refused here goes on from memory. Its queue and its pair stay writable, since both are
  // kept per user.
  static #whileOwned(transaction, write, {settlesStore = false} = {}) {
    const owner = LocalDatabase.actorUserId ?? null;
    const meta = transaction.objectStore(META);
    const storedOwner = meta.get("actorUserId");
    const storedClaim = meta.get("claim");

    storedClaim.onsuccess = () => {
      const claim = storedClaim.result ?? null;

      if (
        Durability.#pairOwner() !== owner ||
        (storedOwner.result ?? null) !== owner ||
        (claim !== Durability.#claimId && !settlesStore)
      ) {
        // What was refused is missing from the store, so no later frame may date the rows at a
        // place past it, even once the owner matches again. No stored id equals undefined, so only
        // a write that settles the whole store, or this tab's own claim, opens it again.
        Durability.#claimId = undefined;

        return;
      }

      Durability.#claimId = claim;

      write();
    };
  }

  // What is stored ON BEHALF OF THE SERVER, gone: the rows and the place they are dated at. Shared
  // by the resync path, which means it deliberately, and by the failure path, which has no choice.
  //
  // The queue is deliberately not touched by either. A batch waiting to go out is this browser's
  // own work rather than a copy of the server's, so neither the server replacing what it says nor
  // this page losing the ability to store anything further makes one untrue.
  static #wipe(transaction) {
    transaction.objectStore(ENTITIES).clear();
    transaction.objectStore(META).delete("cursor");
  }

  // Every write goes through here, so there is one place that counts what is in flight and one
  // place that decides what a failure means.
  //
  // `relaxed` durability lets the browser answer before the operating system has flushed, which is
  // the right trade for a cache of what the server already holds: throughput here is bound by
  // commits, and the worst a lost tail costs is rows downloaded again.
  //
  // In memory mode this answers an already-settled promise, so a caller that awaits one - the
  // batch counter does - waits for nothing rather than branching.
  //
  // Answers whether the write committed.
  static async #write(storeNames, fn) {
    if (Durability.mode === "memory") {
      return false;
    }

    Durability.inFlight += 1;

    try {
      const transaction = Durability.#db.transaction(storeNames, "readwrite", {
        durability: "relaxed",
      });

      fn(transaction);

      await Durability.#complete(transaction);

      return true;
    } catch (error) {
      Durability.#fail(`write failed (${error})`);

      return false;
    } finally {
      Durability.inFlight -= 1;
    }
  }
}
