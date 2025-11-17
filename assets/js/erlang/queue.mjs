"use strict";

import Interpreter from "../interpreter.mjs";
import Type from "../type.mjs";

// IMPORTANT!
// If the given ported Erlang function calls other Erlang functions, then list such dependencies in the "Deps" comment (see :erlang./=/2 for an example).
// Also, in such case add respective call graph edges in Hologram.CallGraph.list_runtime_mfas/1.

// Erlang queue is represented as {queue, FrontList, RearList}
// Items are added to rear and removed from front

function isQueue(term) {
  if (!Type.isTuple(term) || term.data.length !== 3) {
    return false;
  }
  const marker = term.data[0];
  return Type.isAtom(marker) && marker.value === "queue";
}

function createQueue(front = [], rear = []) {
  return Type.tuple([
    Type.atom("queue"),
    Type.list(front),
    Type.list(rear)
  ]);
}

const Erlang_Queue = {
  // Start new/0
  "new/0": () => {
    return createQueue();
  },
  // End new/0
  // Deps: []

  // Start in/2
  "in/2": (item, queue) => {
    if (!isQueue(queue)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(2, "not a queue"),
      );
    }

    const front = queue.data[1].data;
    const rear = queue.data[2].data;

    // Add to rear
    return createQueue(front, [...rear, item]);
  },
  // End in/2
  // Deps: []

  // Start out/1
  "out/1": (queue) => {
    if (!isQueue(queue)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a queue"),
      );
    }

    let front = queue.data[1].data;
    let rear = queue.data[2].data;

    // If front is empty, reverse rear to front
    if (front.length === 0) {
      if (rear.length === 0) {
        // Queue is empty
        return Type.tuple([Type.atom("empty"), queue]);
      }
      front = [...rear].reverse();
      rear = [];
    }

    // Remove from front
    const [item, ...restFront] = front;
    const newQueue = createQueue(restFront, rear);

    return Type.tuple([
      Type.tuple([Type.atom("value"), item]),
      newQueue
    ]);
  },
  // End out/1
  // Deps: []

  // Start is_empty/1
  "is_empty/1": (queue) => {
    if (!isQueue(queue)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a queue"),
      );
    }

    const front = queue.data[1].data;
    const rear = queue.data[2].data;

    return Type.boolean(front.length === 0 && rear.length === 0);
  },
  // End is_empty/1
  // Deps: []

  // Start len/1
  "len/1": (queue) => {
    if (!isQueue(queue)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a queue"),
      );
    }

    const front = queue.data[1].data;
    const rear = queue.data[2].data;

    return Type.integer(front.length + rear.length);
  },
  // End len/1
  // Deps: []

  // Start to_list/1
  "to_list/1": (queue) => {
    if (!isQueue(queue)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a queue"),
      );
    }

    const front = queue.data[1].data;
    const rear = queue.data[2].data;

    // Front items first, then reversed rear items
    const items = [...front, ...[...rear].reverse()];
    return Type.list(items);
  },
  // End to_list/1
  // Deps: []

  // Start from_list/1
  "from_list/1": (list) => {
    if (!Type.isList(list)) {
      Interpreter.raiseArgumentError(
        Interpreter.buildArgumentErrorMsg(1, "not a list"),
      );
    }

    // Put all items in front (they're already in the right order)
    return createQueue(list.data, []);
  },
  // End from_list/1
  // Deps: []
};

export default Erlang_Queue;
