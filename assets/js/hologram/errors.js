export default class HologramNotImplementedError extends Error {
  constructor(message) {
    super(message);
    this.name = "HologramNotImplementedError";
  }
}