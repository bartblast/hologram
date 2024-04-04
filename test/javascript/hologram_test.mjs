"use strict";

import {
  assert,
  componentRegistryEntryFixture,
  linkModules,
  sinon,
  unlinkModules,
} from "./support/helpers.mjs";

import {defineModule1Fixture} from "./support/fixtures/hologram/module_1.mjs";

import ComponentRegistry from "../../assets/js/component_registry.mjs";
import Hologram from "../../assets/js/hologram.mjs";
import Type from "../../assets/js/type.mjs";

before(() => {
  linkModules();
  defineModule1Fixture();
});

after(() => unlinkModules());

describe("Hologram", () => {
  describe("handleEvent()", () => {
    const cid = Type.bitstring("my_component");
    const defaultTarget = cid;
    const eventType = "click";
    const module = Type.alias("Module1");

    describe("action", () => {
      const operationSpecDom = Type.keywordList([
        [
          Type.atom("expression"),
          Type.tuple([
            Type.atom("my_action"),
            Type.keywordList([
              [Type.atom("a"), Type.integer(1)],
              [Type.atom("b"), Type.integer(2)],
            ]),
          ]),
        ],
      ]);

      let stub;

      beforeEach(() => {
        ComponentRegistry.entries = Type.map([
          [cid, componentRegistryEntryFixture({module: module})],
        ]);

        stub = sinon.stub(Hologram, "render").callsFake(() => null);
      });

      afterEach(() => {
        Hologram.render.restore();
      });

      it("event is not ignored", () => {
        const event = {pageX: 1, pageY: 2, preventDefault: () => null};

        Hologram.handleEvent(event, eventType, operationSpecDom, defaultTarget);

        assert.deepStrictEqual(
          ComponentRegistry.getEntry(cid),
          componentRegistryEntryFixture({
            emittedContext: Type.map([
              [
                Type.atom("event"),
                Type.map([
                  [Type.atom("page_x"), Type.integer(1)],
                  [Type.atom("page_y"), Type.integer(2)],
                ]),
              ],
            ]),
            module: module,
            state: Type.map([[Type.atom("c"), Type.integer(3)]]),
          }),
        );

        sinon.assert.calledOnce(stub);
      });

      it("event is ignored", () => {
        const event = {
          ctrlKey: true,
          pageX: 1,
          pageY: 2,
          preventDefault: () => null,
        };

        Hologram.handleEvent(event, eventType, operationSpecDom, defaultTarget);

        assert.deepStrictEqual(
          ComponentRegistry.getEntry(cid),
          componentRegistryEntryFixture({module: module}),
        );

        sinon.assert.notCalled(stub);
      });
    });
  });
});
