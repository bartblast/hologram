# snabbdom (vendored)

Version 3.6.4, MIT licensed - see LICENSE. Copied verbatim from the npm package's `build`
directory, which is the compiled ESM the package publishes.

The `.js.map` and `.d.ts` files are dropped. The source maps point at `../src/*.ts`, which the
package does not ship, so every one of them is broken, and nothing here reads the type
declarations. The `.js` files are untouched.

## Deviations from upstream

None. `build/` is byte-identical to the published package.

It has not always been: Hologram used to render template blocks as fragment vnodes, which
snabbdom supports only behind `experimental: {fragments: true}`, and that support needed two
fixes to be usable. Blocks are no longer fragments - every element carries the key of its place
in its template, so the diff pairs it with itself without anything bracketing it - and both
fixes went back to upstream code with the fragments they served.

## Keeping it byte-identical

`assets/js/vendor/` is listed in the repository's `.prettierignore`. Without that, the formatter
reaches this directory through the `assets/js/**` glob in the `format.js` alias, reindents every
file, and a diff against upstream becomes unreadable.

## Updating

Replace `build/` and `LICENSE` with the new release verbatim and delete the `.js.map` and `.d.ts`
files. With no deviations to re-apply, that is the whole update. Should one ever be needed again,
give it its own commit and a `HOLOGRAM PATCH` comment in the source saying what it changes and
why, so the next upgrade can tell what has to survive it.
