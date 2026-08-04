# snabbdom (vendored)

Version 3.6.4, MIT licensed - see LICENSE. Copied verbatim from the npm package's `build`
directory, which is the compiled ESM the package publishes.

The `.js.map` and `.d.ts` files are dropped. The source maps point at `../src/*.ts`, which the
package does not ship, so every one of them is broken, and nothing here reads the type
declarations. The `.js` files are untouched.

## Why it is vendored

Hologram renders template blocks as fragment vnodes, which snabbdom supports only behind
`experimental: {fragments: true}`. That support has a defect we need fixed now: removing a text
node from inside a fragment throws, because `removeVnodes` hands the removal the fragment's own
`DocumentFragment` rather than resolving the node's real parent, the way it already does for
elements. Template indentation puts whitespace text inside every block, so switching a block off
hits it on ordinary markup.

Vendoring keeps that fix in the repository and, more importantly, keeps it visible: the copy
landed byte-identical to upstream, and every deviation since is its own commit.

## Keeping it byte-identical

`assets/js/vendor/` is listed in the repository's `.prettierignore`. Without that, the formatter
reaches this directory through the `assets/js/**` glob in the `format.js` alias, reindents every
file, and a diff against upstream becomes unreadable.

## Deviations from upstream

Each one is marked in the source with a `HOLOGRAM PATCH` comment explaining what it changes and
why, and is covered by `test/javascript/vendor/snabbdom_test.mjs` - so an upgrade that drops one
fails there rather than in a browser.

- `build/init.js` - when removing a text node, resolve its own parent instead of using the one
  passed in. Inside a fragment the parent passed in is that fragment's `DocumentFragment`, which
  emptied itself into the page on insertion, so removal throws. The element branch already
  resolves the parent this way, through `createRmCb`.

## Updating

Replace `build/` and `LICENSE` with the new release verbatim, delete the `.js.map` and `.d.ts`
files, and commit that as one step. Then re-apply each deviation above in its own commit,
dropping anything since fixed upstream.
