"use strict";

import {
  createEntity,
  raiseWriteError,
  structValues,
  writeRefusal,
} from "./db.mjs";
import Elixir_Hologram_Entity from "./entity.mjs";
import Elixir_Hologram_Query from "./query.mjs";
import Interpreter from "../../interpreter.mjs";
import Model from "../../model.mjs";
import Type from "../../type.mjs";

// Enqueuing a job, hand-written for the client the way the data verbs are.
//
// On the wire a job is an ORDINARY CREATE of one of its rows - there is no enqueue op and no
// job-shaped branch in the batch path - so this is Entity.new plus whatever authority the call
// claimed, written through the same create every other verb goes through. What makes it its own
// verb is that a job's create schedules work to run after the batch commits, which is why
// DB.create refuses a job type and points here.
//
// Not ported: validate_creatable!/2, the server's early refusal of a job type declaring no allow
// lines under an acting user. The client CANNOT tell that state apart - a build that checks no
// permissions bakes an empty policy for every type, exactly as a type declaring none does - so the
// check would refuse jobs that are perfectly creatable. The server's AccessDeniedError arrives as
// the batch's rejection instead, which is what 2.7 says about every policy question.
function applyClaim(job, claim) {
  if (claim === null) {
    return job;
  }

  // trust/1 raises on this tier: the server's authority is not a client's to claim. A job
  // enqueued from server code is where trust: true belongs.
  return claim === "trust"
    ? Elixir_Hologram_Query["trust/1"](job)
    : Elixir_Hologram_Query["authorize/2"](job, claim);
}

// The job the enqueue writes: constructed the way any entity is, then carrying whatever authority
// the call claimed. Built here rather than in each verb so the bang has the job in hand and can
// name the values a refusal objected to.
function build(jobType, values, opts) {
  validateJobType(jobType);

  return applyClaim(
    Elixir_Hologram_Entity["new/2"](jobType, values),
    parseClaim(opts),
  );
}

// null for no claim, "trust", or the operation atom a claim named.
function parseClaim(opts) {
  if (Type.isList(opts) && opts.data.length === 0) {
    return null;
  }

  if (Type.isList(opts) && Type.isKeywordList(opts) && opts.data.length === 1) {
    const [key, value] = opts.data[0].data;

    if (key.value === "authorize" && Type.isAtom(value)) {
      return value;
    }

    if (key.value === "trust" && Type.isTrue(value)) {
      return "trust";
    }
  }

  Interpreter.raiseArgumentError(
    `Job.create takes authorize: operation or trust: true, got: ${Interpreter.inspect(opts)}`,
  );
}

// A job type is one the build baked framework attributes for - the three only the worker sets.
// Nothing else carries them, which is the client's whole notion of Reflection.job?/1.
function validateJobType(jobType) {
  const type = Type.isAlias(jobType)
    ? jobType.value.replace(/^Elixir\./, "")
    : null;

  if (type === null || !Model.isEntityType(type)) {
    Interpreter.raiseArgumentError(
      `${Interpreter.inspect(jobType)} is not a job type - Job.create takes a module defined with use Hologram.Job`,
    );
  }

  if (Model.entry(type).frameworkAttributes.length === 0) {
    Interpreter.raiseArgumentError(
      `${type} is not a job type - Job.create takes a module defined with use Hologram.Job`,
    );
  }

  return type;
}

const Elixir_Hologram_Job = {
  "create!/1": (jobType) =>
    Elixir_Hologram_Job["create!/3"](jobType, Type.map([]), Type.list([])),

  "create!/2": (jobType, values) =>
    Elixir_Hologram_Job["create!/3"](jobType, values, Type.list([])),

  "create!/3": (jobType, values, opts) => {
    const type = validateJobType(jobType);
    const job = build(jobType, values, opts);
    const result = createEntity(job, type);

    if (Type.isAtom(result.data[0]) && result.data[0].value === "ok") {
      return result.data[1];
    }

    raiseWriteError(
      `cannot create ${type}:\n` +
        writeRefusal(type, result.data[1], structValues(job)),
      result.data[1],
    );
  },

  "create/1": (jobType) =>
    Elixir_Hologram_Job["create/3"](jobType, Type.map([]), Type.list([])),

  "create/2": (jobType, values) =>
    Elixir_Hologram_Job["create/3"](jobType, values, Type.list([])),

  "create/3": (jobType, values, opts) =>
    createEntity(build(jobType, values, opts), validateJobType(jobType)),

  // Sorted, the way every job type's are - the acting user at the enqueue, the failure record,
  // and the status.
  "framework_attribute_names/0": () =>
    Type.list([Type.atom("actor_id"), Type.atom("error"), Type.atom("status")]),
};

export default Elixir_Hologram_Job;
