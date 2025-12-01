// Start subtract/2
export function subtract(set1, set2) {
  // Sets are stored internally as JS Maps representing Erlang sets
  const result = new Map(set1);
  for (const elem of set2.keys()) {
    result.delete(elem);
  }
  return result;
}
// End subtract/2
// Deps: []

export default {
  "subtract/2": subtract,
};
