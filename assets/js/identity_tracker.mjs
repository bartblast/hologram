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
// identity in between put in it, and a response that left the server before a change can arrive
// after it, carrying the old tag.
export default class IdentityTracker {
  static HEADER = "hologram-identity-tag";

  // The period the document was loaded in, which its own page data was produced in.
  static documentPeriod = null;

  static period = null;

  // The tag of the identity the latest response was made for. Null while none is known.
  static tag = null;

  // Starts the document's first period, for the identity the server rendered the document for. A
  // document that names none starts with no tag, and its first tagged response starts another
  // period, which can only refuse restores, never allow one.
  static init(documentTag) {
    $.tag = documentTag ?? null;
    $.period = Utils.randomUUID();
    $.documentPeriod = $.period;
  }

  // Whether the given period is the one that lasts now.
  static isCurrent(period) {
    return period !== null && period !== undefined && period === $.period;
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
      $.period = Utils.randomUUID();
    }

    return $.period;
  }

  static observeResponse(response) {
    return $.observe(response.headers.get($.HEADER));
  }

  // The tag to stamp state with that was produced in the given period: the identity's while the
  // period lasts, and none once it has ended, since the state can then hold what two identities
  // put in it. State stamped with no tag is never restored into another document.
  static tagFor(period) {
    return $.isCurrent(period) ? $.tag : null;
  }
}

const $ = IdentityTracker;
