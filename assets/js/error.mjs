export default class HologramError extends Error {
  constructor(struct) {
    super("");

    this.name = "HologramError";
    this.struct = struct;
  }
}
