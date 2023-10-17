export default class HologramError extends Error {
  constructor(message) {
    super(message);
    this.name = "HologramError";
  }
}
