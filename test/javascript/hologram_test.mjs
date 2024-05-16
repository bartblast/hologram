"use strict";

import {linkModules, sinon, unlinkModules} from "./support/helpers.mjs";

import Hologram from "../../assets/js/hologram.mjs";
import Type from "../../assets/js/type.mjs";

const cid1 = Type.bitstring("my_component_1");

describe("Hologram", () => {
  before(() => linkModules());
  after(() => unlinkModules());

  describe("handleEvent()", () => {
    let enqueueCommandStub, executeActionStub;

    const actionSpecDom = Type.keywordList([
      [Type.atom("text"), Type.bitstring("my_action")],
    ]);

    const defaultTarget = cid1;
    const eventType = "click";
    const notIgnoredEvent = {pageX: 1, pageY: 2, preventDefault: () => null};

    beforeEach(() => {
      enqueueCommandStub = sinon
        .stub(Hologram, "enqueueCommand")
        .callsFake(() => null);

      executeActionStub = sinon
        .stub(Hologram, "executeAction")
        .callsFake(() => null);
    });

    afterEach(() => {
      Hologram.enqueueCommand.restore();
      Hologram.executeAction.restore();
    });

    it("event is ignored", () => {
      const ignoredEvent = {
        ctrlKey: true,
        pageX: 1,
        pageY: 2,
        preventDefault: () => null,
      };

      Hologram.handleEvent(
        ignoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(enqueueCommandStub);
      sinon.assert.notCalled(executeActionStub);
    });

    it("action", () => {
      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        actionSpecDom,
        defaultTarget,
      );

      sinon.assert.notCalled(enqueueCommandStub);
      sinon.assert.calledOnce(executeActionStub);
    });

    it("command", () => {
      const commandSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.keywordList([
              [Type.atom("name"), Type.atom("my_command")],
              [Type.atom("type"), Type.atom("command")],
            ]),
          ]),
        ],
      ]);

      Hologram.handleEvent(
        notIgnoredEvent,
        eventType,
        commandSpecDom,
        defaultTarget,
      );

      sinon.assert.calledOnce(enqueueCommandStub);
      sinon.assert.notCalled(executeActionStub);
    });
  });
});
