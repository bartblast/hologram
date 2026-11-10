"use strict";

import {assert} from "./support/helpers.mjs";

import ElementRefRegistry from "../../assets/js/element_ref_registry.mjs";
import Type from "../../assets/js/type.mjs";

describe("ElementRefRegistry", () => {
  const element = document.createElement("div");
  const pageModule = Type.alias("MyPage");
  const search = Type.atom("search");

  afterEach(() => {
    ElementRefRegistry.clear();
  });

  describe("clear()", () => {
    it("forgets the elements and the page", () => {
      ElementRefRegistry.replace(
        new Map([[Type.encodeMapKey(search), element]]),
        pageModule,
      );

      ElementRefRegistry.clear();

      assert.deepStrictEqual(ElementRefRegistry.elements, new Map());
      assert.isNull(ElementRefRegistry.pageModule);
    });
  });

  describe("get()", () => {
    it("returns the element rendered under the ref", () => {
      ElementRefRegistry.replace(
        new Map([[Type.encodeMapKey(search), element]]),
        pageModule,
      );

      assert.strictEqual(ElementRefRegistry.get(search), element);
    });

    it("finds a tuple ref by its value", () => {
      ElementRefRegistry.replace(
        new Map([
          [
            Type.encodeMapKey(
              Type.tuple([Type.atom("message"), Type.integer(42)]),
            ),
            element,
          ],
        ]),
        pageModule,
      );

      assert.strictEqual(
        ElementRefRegistry.get(
          Type.tuple([Type.atom("message"), Type.integer(42)]),
        ),
        element,
      );
    });

    it("returns null when nothing is rendered under the ref", () => {
      ElementRefRegistry.replace(new Map(), pageModule);

      assert.isNull(ElementRefRegistry.get(search));
    });
  });

  describe("replace()", () => {
    it("takes the given elements and page in place of the ones it held", () => {
      ElementRefRegistry.replace(
        new Map([[Type.encodeMapKey(Type.atom("old")), element]]),
        Type.alias("MyOldPage"),
      );

      const elementsByRef = new Map([[Type.encodeMapKey(search), element]]);

      ElementRefRegistry.replace(elementsByRef, pageModule);

      assert.strictEqual(ElementRefRegistry.elements, elementsByRef);
      assert.strictEqual(ElementRefRegistry.pageModule, pageModule);
    });
  });
});
