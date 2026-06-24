"use strict";

import MouseEvent from "./mouse_event.mjs";
import Type from "../type.mjs";

class BaseDragEvent {
  static buildOperationParam(event) {
    const mouseEventDetails = MouseEvent.buildOperationParam(event);

    const dragEventDetails = Type.map([
      [Type.atom("alt_key"), Type.boolean(Boolean(event.altKey))],
      [Type.atom("button"), Type.integer(event.button ?? 0)],
      [Type.atom("buttons"), Type.integer(event.buttons ?? 0)],
      [Type.atom("ctrl_key"), Type.boolean(Boolean(event.ctrlKey))],
      [
        Type.atom("data_transfer"),
        BaseDragEvent.#buildDataTransferParam(event.dataTransfer),
      ],
      [Type.atom("meta_key"), Type.boolean(Boolean(event.metaKey))],
      [Type.atom("shift_key"), Type.boolean(Boolean(event.shiftKey))],
    ]);

    return Erlang_Maps["merge/2"](mouseEventDetails, dragEventDetails);
  }

  static isEventIgnored(event) {
    return MouseEvent.isEventIgnored(event);
  }

  static #buildDataTransferItemsParam(dataTransfer) {
    return Type.list(
      Array.from(dataTransfer.items ?? []).map((item) =>
        Type.map([
          [Type.atom("kind"), Type.bitstring(BaseDragEvent.#toText(item.kind))],
          [Type.atom("type"), Type.bitstring(BaseDragEvent.#toText(item.type))],
        ]),
      ),
    );
  }

  static #buildDataTransferParam(dataTransfer) {
    if (!dataTransfer) {
      return Type.nil();
    }

    return Type.map([
      [
        Type.atom("drop_effect"),
        Type.bitstring(BaseDragEvent.#toText(dataTransfer.dropEffect)),
      ],
      [
        Type.atom("effect_allowed"),
        Type.bitstring(BaseDragEvent.#toText(dataTransfer.effectAllowed)),
      ],
      [
        Type.atom("types"),
        BaseDragEvent.#buildDataTransferTypesParam(dataTransfer),
      ],
      [
        Type.atom("items"),
        BaseDragEvent.#buildDataTransferItemsParam(dataTransfer),
      ],
    ]);
  }

  static #buildDataTransferTypesParam(dataTransfer) {
    return Type.list(
      Array.from(dataTransfer.types ?? []).map((type) =>
        Type.bitstring(BaseDragEvent.#toText(type)),
      ),
    );
  }

  static #toText(value) {
    return value === null || typeof value === "undefined"
      ? ""
      : value.toString();
  }
}

export default class DragEvent extends BaseDragEvent {
  static isDefaultAllowed = true;
}

export class DropTargetDragEvent extends BaseDragEvent {
  static isDefaultAllowed = false;
}
