"use strict";

export default class Config {
  static clientFetchTimeoutMs = 3000;
  static fetchPageTimeoutMs = 3000;

  // How long a mutation POST may go unanswered before the client gives up on it. Policy rather
  // than a measured bound: giving up early costs one resend, which (replica_id, seq) makes
  // idempotent, and giving up late costs a wait nobody sees, since the rows are on screen and the
  // next action's close tries again. So it is set where "the connection is gone" is the only
  // remaining reading, not where "this is slow" is.
  static mutationTimeoutMs = 30_000;
}
