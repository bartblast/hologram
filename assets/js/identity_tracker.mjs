"use strict";

import Utils from "./utils.mjs";

// Who the server's responses were made for, as far as this document has seen: which session, and
// which user in it. The server tags each response with the identity it leaves behind (see
// Hologram.Runtime.Session.identity_tag/1), and a period lasts as long as that tag stays the
// same: every change starts a new one. What the client keeps for Back and Forward is stamped with
// the period it was produced in, and restored only while that period lasts, so that it never
// outlives a login or a logout.
//
// A period is an id of its own rather than the tag, so that an identity that changes and then
// changes back still ends what came before the first change. That state can hold what the
// identity in between put in it.
//
// Responses and the stream can arrive in any order, and a response can name an identity the
// session has left. A tag starts with a stamp that goes up with every change, which tells them
// apart: a response no newer than what the tab knows doesn't move the tab, and the client asks
// the server who is signed in (see Client.settleIdentity).
export default class IdentityTracker {
  static HEADER = "hologram-identity-tag";

  // The period of a response naming an identity that isn't known to be the current one. No period
  // this document started, so what the response describes reads as stale.
  static SUPERSEDED = "superseded";

  static #NO_SESSION_PREFIX = "none.";

  // The period the document was loaded in, which its own page data was produced in.
  static documentPeriod = null;

  static period = null;

  // Every period this document started, the one that lasts now included. A period is a
  // document's own, so this is what tells a period of this document's from another document's.
  static periods = new Set();

  // The tag of the identity the latest response was made for. Null while none is known.
  static tag = null;

  // Starts the document's first period, for the identity the server rendered the document for. A
  // document that names none starts with no tag, and its first tagged response starts another
  // period, which can only refuse restores, never allow one.
  static init(documentTag) {
    $.tag = documentTag ?? null;
    $.period = Utils.uuidv7();
    $.documentPeriod = $.period;
    $.periods = new Set([$.period]);
  }

  // Whether the tag names another identity than the current one, and isn't newer than it. Two tags
  // with one stamp come from changes made at the same moment, so neither can be taken for the
  // later one.
  static isBehind(tag) {
    return (
      tag !== null &&
      tag !== undefined &&
      $.tag !== null &&
      tag !== $.tag &&
      $.#stampOf(tag) <= $.#stampOf($.tag)
    );
  }

  // Whether the given period is the one that lasts now.
  static isCurrent(period) {
    return period !== null && period !== undefined && period === $.period;
  }

  // Whether the given period is one this document started, lasting or ended.
  static isOwnPeriod(period) {
    return $.periods.has(period);
  }

  // Whether the tag names another identity than the current one, from before it. The tag of a
  // request with no session has no stamp and is from no time: its cookie was cleared.
  static isOlder(tag) {
    return (
      $.isBehind(tag) &&
      !tag.startsWith($.#NO_SESSION_PREFIX) &&
      $.#stampOf(tag) < $.#stampOf($.tag)
    );
  }

  // Whether the given tag names the identity the latest response was made for.
  static isCurrentTag(tag) {
    return tag !== null && tag !== undefined && tag === $.tag;
  }

  // Takes in the tag a response carried, and answers the period the response belongs to. A
  // response with no tag says nothing about the identity - one from a server that does not tag
  // its responses, or one no Hologram handler wrote - and leaves the period as it was.
  static observe(tag) {
    if (tag !== null && tag !== undefined && tag !== $.tag) {
      $.tag = tag;
      $.period = Utils.uuidv7();
      $.periods.add($.period);
    }

    return $.period;
  }

  // Takes in the tag a response carried, unless it can't be told to be the latest word on the
  // identity, and answers the period the response belongs to.
  static observeResponse(response) {
    const tag = response.headers.get($.HEADER);

    return $.isBehind(tag) ? $.SUPERSEDED : $.observe(tag);
  }

  // The tag to stamp state with that was produced in the given period: the identity's while the
  // period lasts, and none once it has ended, since the state can then hold what two identities
  // put in it. State stamped with no tag is never restored into another document.
  static tagFor(period) {
    return $.isCurrent(period) ? $.tag : null;
  }

  static #stampOf(tag) {
    return Number.parseInt(tag, 10) || 0;
  }
}

const $ = IdentityTracker;
