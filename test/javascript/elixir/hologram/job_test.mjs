"use strict";

import {assert, defineRuntimeGlobals, sinon} from "../../support/helpers.mjs";

import Batches from "../../../../assets/js/batches.mjs";
import Bitstring from "../../../../assets/js/bitstring.mjs";
import Elixir_Hologram_Job from "../../../../assets/js/elixir/hologram/job.mjs";
import HologramBoxedError from "../../../../assets/js/errors/boxed_error.mjs";
import LocalDatabase from "../../../../assets/js/local_database.mjs";
import Model from "../../../../assets/js/model.mjs";
import Type from "../../../../assets/js/type.mjs";

defineRuntimeGlobals();

// Mirrors the create describes of test/elixir/hologram/job_test.exs, as far as this tier goes:
// there is no worker here, so what a job DOES is not among them - only that enqueuing one is an
// ordinary create of its row, carrying whatever authority the call claimed.
describe("Elixir_Hologram_Job", () => {
  const NOTIFY = "MyApp.Jobs.Notify";
  const TASK = "MyApp.Task";

  const notify = Type.alias(NOTIFY);
  const task = Type.alias(TASK);

  const create = Elixir_Hologram_Job["create/2"];
  const createBang = Elixir_Hologram_Job["create!/2"];
  const createWithOpts = Elixir_Hologram_Job["create/3"];

  const NOW_MS = 1_756_100_000_123;
  const STAMP = NOW_MS * 1024;

  let timers;

  const field = (struct, name) =>
    struct.data[Type.encodeMapKey(Type.atom(name))][1];

  const values = (pairs) =>
    Type.map(pairs.map(([name, value]) => [Type.atom(name), value]));

  const opts = (pairs) =>
    Type.list(
      pairs.map(([name, value]) => Type.tuple([Type.atom(name), value])),
    );

  beforeEach(() => {
    globalThis.Hologram.sync = {
      model: {
        [NOTIFY]: {
          attributes: {
            actor_id: "uuid",
            created_at: "datetime",
            error: "string",
            id: "uuid",
            reason: "string",
            status: "enum",
            updated_at: "datetime",
          },
          // The three the framework fills, declared the way use Hologram.Job declares them: the
          // actor and the failure record optional, the status defaulted to :queued.
          constraints: {actor_id: {optional: true}, error: {optional: true}},
          defaults: {status: Type.atom("queued")},
          enumValues: {status: ["queued", "running", "done", "failed"]},
          frameworkAttributes: ["actor_id", "error", "status"],
          relationships: {},
          serverOnly: ["error"],
        },
        [TASK]: {
          attributes: {done: "boolean", id: "uuid", title: "string"},
          constraints: {},
          defaults: {},
          enumValues: {},
          frameworkAttributes: [],
          relationships: {},
          serverOnly: [],
        },
      },
    };

    Batches.reset();
    LocalDatabase.reset();
    Model.reset();

    timers = sinon.useFakeTimers(NOW_MS);
    Batches.open("jobs");
  });

  afterEach(() => {
    timers.restore();
    Batches.reset();
  });

  describe("create/2 and create/3", () => {
    it("appends an ordinary create of the job's row", () => {
      const result = create(notify, values([["reason", Type.bitstring("x")]]));

      assert.deepStrictEqual(result.data[0], Type.atom("ok"));

      const [write] = Batches.current().writes;

      assert.equal(write.op, "create");
      assert.equal(write.type, NOTIFY);
      assert.equal(write.stamp, STAMP);
      assert.deepStrictEqual(write.data, {reason: "x"});
    });

    it("leaves the framework's own attributes out of the write", () => {
      create(notify, values([["reason", Type.bitstring("x")]]));

      const [write] = Batches.current().writes;

      assert.notProperty(write.data, "actor_id");
      assert.notProperty(write.data, "error");
      assert.notProperty(write.data, "status");
    });

    it("carries no claim when the call names none", () => {
      create(notify, values([["reason", Type.bitstring("x")]]));

      assert.isNull(Batches.current().writes[0].claim);
    });

    it("carries the operation an authorize option named", () => {
      createWithOpts(
        notify,
        values([["reason", Type.bitstring("x")]]),
        opts([["authorize", Type.atom("notify")]]),
      );

      assert.deepStrictEqual(Batches.current().writes[0].claim, [
        "authorize",
        "notify",
      ]);
    });

    it("answers the job as it now stands", () => {
      const job = create(notify, values([["reason", Type.bitstring("x")]]))
        .data[1];

      assert.deepStrictEqual(field(job, "reason"), Type.bitstring("x"));
      assert.match(Bitstring.toText(field(job, "id")), /^[0-9a-f-]{36}$/);
    });

    // The arity-one form is the arity-two one with no values, which is all it claims - this job
    // type declares a required attribute, so both answer the same refusal.
    it("takes the arity-one spelling, which is the arity-two one with no values", () => {
      const fromOne = Elixir_Hologram_Job["create/1"](notify);

      Batches.reset();
      Batches.open("jobs");

      assert.deepStrictEqual(fromOne, create(notify, Type.map([])));
    });

    it("answers a refusal from the declarations and appends nothing", () => {
      const result = create(notify, values([["reason", Type.nil()]]));

      assert.deepStrictEqual(result.data[0], Type.atom("error"));
      assert.deepStrictEqual(Batches.current().writes, []);
    });

    // The server refuses one more thing here that this tier cannot see: a job type declaring no
    // allow lines, under an acting user. A build that checks no permissions bakes an empty policy
    // for every type, so the client cannot tell that state from a type declaring none - the
    // server's denial arrives as the batch's rejection instead.
    it("raises for a module that is not a job type", () => {
      assert.throw(
        () => create(task, values([["title", Type.bitstring("x")]])),
        HologramBoxedError,
        "MyApp.Task is not a job type - Job.create takes a module defined with use Hologram.Job",
      );
    });

    it("raises for a value that is not a module at all", () => {
      assert.throw(
        () => create(Type.bitstring("x"), Type.map([])),
        HologramBoxedError,
        '"x" is not a job type - Job.create takes a module defined with use Hologram.Job',
      );
    });

    it("raises for an unknown option", () => {
      assert.throw(
        () =>
          createWithOpts(
            notify,
            Type.map([]),
            opts([["nope", Type.boolean(true)]]),
          ),
        HologramBoxedError,
        "Job.create takes authorize: operation or trust: true, got: [nope: true]",
      );
    });

    it("raises for both options at once", () => {
      assert.throw(
        () =>
          createWithOpts(
            notify,
            Type.map([]),
            opts([
              ["authorize", Type.atom("notify")],
              ["trust", Type.boolean(true)],
            ]),
          ),
        HologramBoxedError,
        "Job.create takes authorize: operation or trust: true, got: [authorize: :notify, trust: true]",
      );
    });

    // trust is the server's authority on either half, so a job claiming it belongs in server code.
    it("raises for a trust claim, which is not a client's to make", () => {
      assert.throw(
        () =>
          createWithOpts(
            notify,
            Type.map([]),
            opts([["trust", Type.boolean(true)]]),
          ),
        HologramBoxedError,
        "trust is the server's authority - a client cannot claim it",
      );
    });

    it("raises for a value of an attribute the framework sets", () => {
      assert.throw(
        () => create(notify, values([["status", Type.bitstring("done")]])),
        HologramBoxedError,
        ":status of MyApp.Jobs.Notify is set by the framework - a job is enqueued as queued, and the worker records the rest",
      );
    });
  });

  describe("create!/2 and create!/3", () => {
    it("answers the job directly when the write passes", () => {
      const job = createBang(notify, values([["reason", Type.bitstring("x")]]));

      assert.deepStrictEqual(field(job, "reason"), Type.bitstring("x"));
    });

    it("raises naming the job type and each violated declaration", () => {
      assert.throw(
        () => createBang(notify, values([["reason", Type.nil()]])),
        HologramBoxedError,
        "cannot create MyApp.Jobs.Notify:\n  * attribute :reason is required",
      );
    });
  });

  describe("framework_attribute_names/0", () => {
    it("answers the three the worker fills, sorted", () => {
      assert.deepStrictEqual(
        Elixir_Hologram_Job["framework_attribute_names/0"](),
        Type.list([
          Type.atom("actor_id"),
          Type.atom("error"),
          Type.atom("status"),
        ]),
      );
    });
  });
});
