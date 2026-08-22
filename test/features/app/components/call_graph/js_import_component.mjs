// Counts how many copies of this module the browser has evaluated, which is one per bundle that
// imports it. The runtime bundle owns this component's JS bindings, so a page bundle must never
// import a second copy - see the "split module" feature test.
globalThis.__jsImportComponentLoads__ =
  (globalThis.__jsImportComponentLoads__ ?? 0) + 1;

export function loadCount() {
  return globalThis.__jsImportComponentLoads__;
}

export function shout(text) {
  return text.toUpperCase();
}
