"use strict";

import {
  assert,
  buildComponentStruct,
  linkModules,
  unlinkModules,
} from "./support/helpers.mjs";

import Interpreter from "../../assets/js/interpreter.mjs";
import Store from "../../assets/js/store.mjs";
import Type from "../../assets/js/type.mjs";

before(() => linkModules());
after(() => unlinkModules());

beforeEach(() => {
  Store.data = Type.map([]);
});

afterEach(() => {
  Store.data = Type.map([]);
});

describe("getComponentEmittedContext()", () => {
  it("component struct exists", () => {
    const cid = Type.bitstring("my_component_2");

    Store.data = Type.map([
      [
        Type.bitstring("my_component_1"),
        Type.map([[Type.atom("emitted_context"), "dummy_1"]]),
      ],
      [cid, Type.map([[Type.atom("emitted_context"), "dummy_2"]])],
    ]);

    const result = Store.getComponentEmittedContext(cid);

    assert.equal(result, "dummy_2");
  });

  it("component struct doesn't exist", () => {
    const cid = Type.bitstring("my_component");
    const result = Store.getComponentEmittedContext(cid);

    assert.isNull(result);
  });
});

describe("getComponentStruct()", () => {
  it("component struct exists", () => {
    const cid = Type.bitstring("my_component_2");

    Store.data = Type.map([
      [Type.bitstring("my_component_1"), "dummy_1"],
      [cid, "dummy_2"],
    ]);

    const result = Store.getComponentStruct(cid);

    assert.equal(result, "dummy_2");
  });

  it("component struct doesn't exist", () => {
    const cid = Type.bitstring("my_component");
    const result = Store.getComponentStruct(cid);

    assert.isNull(result);
  });
});

describe("getComponentState()", () => {
  it("component struct exists", () => {
    const cid = Type.bitstring("my_component_2");

    Store.data = Type.map([
      [
        Type.bitstring("my_component_1"),
        Type.map([[Type.atom("state"), "dummy_1"]]),
      ],
      [cid, Type.map([[Type.atom("state"), "dummy_2"]])],
    ]);

    const result = Store.getComponentState(cid);

    assert.equal(result, "dummy_2");
  });

  it("component struct doesn't exist", () => {
    const cid = Type.bitstring("my_component");
    const result = Store.getComponentState(cid);

    assert.isNull(result);
  });
});

it("hydrate()", () => {
  Store.data = Type.map([
    [Type.atom("a"), Type.integer(1)],
    [Type.atom("b"), Type.integer(2)],
  ]);

  Store.hydrate(
    Type.map([
      [Type.atom("c"), Type.integer(3)],
      [Type.atom("a"), Type.integer(4)],
    ]),
  );

  assert.deepStrictEqual(
    Store.data,
    Type.map([
      [Type.atom("a"), Type.integer(4)],
      [Type.atom("b"), Type.integer(2)],
      [Type.atom("c"), Type.integer(3)],
    ]),
  );
});

describe("putComponentEmittedContext()", () => {
  const cid = Type.bitstring("my_component");

  it("when component struct exists", () => {
    Store.data = Type.map([
      [
        cid,
        Type.map([
          [Type.atom("emitted_context"), "dummy_context_1"],
          [Type.atom("state"), "dummy_state"],
        ]),
      ],
    ]);

    Store.putComponentEmittedContext(cid, "dummy_context_2");

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid,
          Type.map([
            [Type.atom("emitted_context"), "dummy_context_2"],
            [Type.atom("state"), "dummy_state"],
          ]),
        ],
      ]),
    );
  });

  it("when component struct doesn't exist", () => {
    Store.putComponentEmittedContext(cid, "dummy_context");

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [cid, buildComponentStruct({emittedContext: "dummy_context"})],
      ]),
    );
  });
});

describe("putComponentState()", () => {
  const cid = Type.bitstring("my_component");

  it("when component struct exists", () => {
    Store.data = Type.map([
      [
        cid,
        Type.map([
          [Type.atom("emitted_context"), "dummy_context"],
          [Type.atom("state"), "dummy_state_1"],
        ]),
      ],
    ]);

    Store.putComponentState(cid, "dummy_state_2");

    assert.deepStrictEqual(
      Store.data,
      Type.map([
        [
          cid,
          Type.map([
            [Type.atom("emitted_context"), "dummy_context"],
            [Type.atom("state"), "dummy_state_2"],
          ]),
        ],
      ]),
    );
  });

  it("when component struct doesn't exist", () => {
    Store.putComponentState(cid, "dummy_state");

    assert.deepStrictEqual(
      Store.data,
      Type.map([[cid, buildComponentStruct({state: "dummy_state"})]]),
    );
  });
});

it("putComponentStruct()", () => {
  Store.data = Type.map([
    [
      Type.bitstring("my_component_1"),
      Type.map([
        [Type.atom("emitted_context"), "dummy_context_1"],
        [Type.atom("state"), "dummy_state_1"],
      ]),
    ],
  ]);

  const cid = Type.bitstring("my_component_2");

  const componentData = Type.map([
    [Type.atom("emitted_context"), "dummy_context_2"],
    [Type.atom("state"), "dummy_state_2"],
  ]);

  Store.putComponentStruct(cid, componentData);

  assert.deepStrictEqual(
    Store.data,
    Type.map([
      [
        Type.bitstring("my_component_1"),
        Type.map([
          [Type.atom("emitted_context"), "dummy_context_1"],
          [Type.atom("state"), "dummy_state_1"],
        ]),
      ],
      [
        Type.bitstring("my_component_2"),
        Type.map([
          [Type.atom("emitted_context"), "dummy_context_2"],
          [Type.atom("state"), "dummy_state_2"],
        ]),
      ],
    ]),
  );
});
