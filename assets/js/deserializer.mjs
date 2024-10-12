"use strict";

export default class Deserializer {
  static deserialize(data) {
    if (typeof data === "string") {
      return JSON.parse(data);
    }
  }
}
