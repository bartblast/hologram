"use strict";

import {assert, sinon} from "./support/helpers.mjs";

import EventListeners from "../../assets/js/event_listeners.mjs";

describe("EventListeners", () => {
  describe("domEvent()", () => {
    it("attaches and detaches a DOM event listener on the target", () => {
      const target = {
        addEventListener: sinon.spy(),
        removeEventListener: sinon.spy(),
      };

      const dispatcher = sinon.spy();
      const detach = EventListeners.domEvent(target, "click", true).attach(
        dispatcher,
      );

      sinon.assert.calledOnceWithExactly(
        target.addEventListener,
        "click",
        dispatcher,
        true,
      );

      detach();

      sinon.assert.calledOnceWithExactly(
        target.removeEventListener,
        "click",
        dispatcher,
        true,
      );
    });

    it("defaults to the bubble phase", () => {
      const target = {
        addEventListener: sinon.spy(),
        removeEventListener: sinon.spy(),
      };

      EventListeners.domEvent(target, "click").attach(sinon.spy());

      sinon.assert.calledOnceWithExactly(
        target.addEventListener,
        "click",
        sinon.match.func,
        false,
      );
    });

    it("keys a bubble-phase listener distinctly from a capture-phase one", () => {
      assert.notEqual(
        EventListeners.domEvent(window, "click").key,
        EventListeners.domEvent(window, "click", true).key,
      );
    });
  });
});
