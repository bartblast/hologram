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

  describe("putPageRefNames() / refNames()", () => {
    afterEach(() => {
      ElementRefRegistry.pageRefNames = new Map();
    });

    it("returns the names the current page's bundle put", () => {
      ElementRefRegistry.putPageRefNames("Elixir.MyPage", [
        ["item", 1],
        ["search", 0],
      ]);

      ElementRefRegistry.putPageRefNames("Elixir.MyOtherPage", [["menu", 0]]);

      ElementRefRegistry.replace(new Map(), pageModule);

      assert.deepStrictEqual(ElementRefRegistry.refNames(), [
        ["item", 1],
        ["search", 0],
      ]);
    });

    it("returns none for a page whose bundle put none", () => {
      ElementRefRegistry.replace(new Map(), pageModule);

      assert.deepStrictEqual(ElementRefRegistry.refNames(), []);
    });

    it("returns none when no page is shown", () => {
      ElementRefRegistry.putPageRefNames("Elixir.MyPage", [["search", 0]]);

      assert.deepStrictEqual(ElementRefRegistry.refNames(), []);
    });

    it("keeps the names of a page a navigation left", () => {
      ElementRefRegistry.putPageRefNames("Elixir.MyPage", [["search", 0]]);
      ElementRefRegistry.replace(new Map(), pageModule);

      ElementRefRegistry.clear();
      ElementRefRegistry.replace(new Map(), pageModule);

      assert.deepStrictEqual(ElementRefRegistry.refNames(), [["search", 0]]);
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
