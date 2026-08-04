# snabbdom (vendored)

Version 3.6.4, MIT licensed - see LICENSE. Copied verbatim from the npm package's `build`
directory, which is the compiled ESM the package publishes.

## Why it is vendored

Hologram renders template blocks as fragment vnodes, which snabbdom supports only behind
`experimental: {fragments: true}`. That support has a defect we need fixed now: removing a text
node from inside a fragment throws, because `removeVnodes` hands the removal the fragment's own
`DocumentFragment` rather than resolving the node's real parent, the way it already does for
elements. Template indentation puts whitespace text inside every block, so switching a block off
hits it on ordinary markup.

Vendoring keeps that fix in the repository and, more importantly, keeps it _visible_: the copy
landed byte-identical to upstream, and every deviation since is its own commit.

## Deviations from upstream

Each one is marked in the source with a `HOLOGRAM PATCH` comment explaining what it changes and
why.

- `build/init.js` - resolve a text node's real parent when removing it, so removal works inside a
  fragment.

## Updating

Replace `build/` and `LICENSE` with the new release verbatim in one commit, then re-apply each
deviation above in its own commit. Anything that has since been fixed upstream is simply dropped.
