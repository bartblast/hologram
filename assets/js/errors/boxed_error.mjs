export default class HologramBoxedError extends Error {
  constructor(struct) {
    super("");

    this.name = "HologramBoxedError";
    this.struct = struct;
  }
}
