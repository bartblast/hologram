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

// Start intersection/2
export function intersection(set1, set2) {
  // Sets are stored internally as JS Maps representing Erlang sets
  const result = new Map();
  for (const elem of set1.keys()) {
    if (set2.has(elem)) {
      result.set(elem, true);
    }
  }
  return result;
}
// End intersection/2
// Deps: []

// Start union/2
export function union(set1, set2) {
  // Sets are stored internally as JS Maps representing Erlang sets
  const result = new Map(set1);
  for (const elem of set2.keys()) {
    result.set(elem, true);
  }
  return result;
}
// End union/2
// Deps: []

export default {
  "intersection/2": intersection,
  "subtract/2": subtract,
  "union/2": union,
};
