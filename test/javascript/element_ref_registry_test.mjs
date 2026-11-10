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

  describe("missingElementHint()", () => {
    const chainedActionHint =
      " - a template declares the ref, but nothing renders it right now. An element the action's " +
      "own state change renders is on the page only once the action returns, so look it up in " +
      "an action chained with put_action/2";

    const showPage = (names) => {
      ElementRefRegistry.putPageRefNames("Elixir.MyPage", names);
      ElementRefRegistry.replace(new Map(), pageModule);
    };

    const tuple = (name, ...keys) =>
      Type.tuple([Type.atom(name), ...keys.map((key) => Type.integer(key))]);

    afterEach(() => {
      ElementRefRegistry.pageRefNames = new Map();
    });

    it("says a template declares an atom ref nothing renders", () => {
      showPage([["search", 0]]);

      assert.equal(
        ElementRefRegistry.missingElementHint(Type.atom("search")),
        chainedActionHint,
      );
    });

    it("says a template declares a tuple ref nothing renders", () => {
      showPage([["message", 1]]);

      assert.equal(
        ElementRefRegistry.missingElementHint(tuple("message", 99)),
        chainedActionHint,
      );
    });

    it("says how many parts the refs of the name take", () => {
      showPage([["item", 1]]);

      assert.equal(
        ElementRefRegistry.missingElementHint(tuple("item", 1, 2)),
        " - refs named :item take 1 part after the name",
      );
    });

    it("says the refs of the name take no parts", () => {
      showPage([["search", 0]]);

      assert.equal(
        ElementRefRegistry.missingElementHint(tuple("search", 1)),
        " - refs named :search take no parts after the name",
      );
    });

    // String.jaro_distance("serch", "perch") is 0.867, and ("serch", "search") 0.944.
    it("suggests the closest declared name", () => {
      showPage([
        ["perch", 0],
        ["search", 0],
      ]);

      assert.equal(
        ElementRefRegistry.missingElementHint(Type.atom("serch")),
        " - did you mean :search?",
      );
    });

    it("suggests a tuple ref as a template writes it", () => {
      showPage([["cell", 2]]);

      assert.equal(
        ElementRefRegistry.missingElementHint(tuple("cel", 1, 2)),
        " - did you mean {:cell, ..., ...}?",
      );
    });

    // String.jaro_distance("tutbon", "button") is 0.822, and ("massege", "message") 0.743: the
    // first would miss with each swap counted twice, and the second would be suggested with swaps
    // ignored.
    it("counts swapped letters as Elixir's suggestions do", () => {
      showPage([
        ["button", 0],
        ["message", 0],
      ]);

      assert.equal(
        ElementRefRegistry.missingElementHint(Type.atom("tutbon")),
        " - did you mean :button?",
      );

      assert.equal(
        ElementRefRegistry.missingElementHint(Type.atom("massege")),
        "",
      );
    });

    // String.jaro_distance("field", "fold") is 0.783, and ("header", "ader") 0.764.
    it("suggests a name only as close as Elixir's suggestions take it", () => {
      showPage([
        ["field", 0],
        ["header", 0],
      ]);

      assert.equal(
        ElementRefRegistry.missingElementHint(Type.atom("fold")),
        " - did you mean :field?",
      );

      assert.equal(
        ElementRefRegistry.missingElementHint(Type.atom("ader")),
        "",
      );
    });

    it("adds nothing when the page declares no refs", () => {
      showPage([]);

      assert.equal(
        ElementRefRegistry.missingElementHint(Type.atom("search")),
        "",
      );
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
