# Navigation Payload Wire Format

A client-side navigation is answered with the page's evaluated tree. The tree is a closed vocabulary of four constructors with no Elixir semantics in it, so it does not need the boxed-term encoder - but it does need a shape. This records the full cross-product of the choices that shape is made of, measured on two real pages, so the one that was picked can be checked rather than taken on trust.

Related: issue #1068.

## Background

Today `Hologram.Controller.build_page_data_payload/1` encodes the tree with `Encoder.encode_term!/1`, producing JavaScript source that reconstructs it - `Type.tuple([Type.atom("element"), Type.bitstring("div"), ...])` - which the client hands to `Interpreter.evaluateJavaScriptExpression` before anything is painted.

| Page | HTML | Elements | Text nodes | Attributes | Comments | Payload today |
|------|------|----------|------------|------------|----------|---------------|
| `/reference/client-runtime/erlang` | 901.6 KB | 9,617 | 19,210 | 15,835 | 5 | 4,273 KB |
| `/reference/client-runtime/erlang/erlang/++/2` | 1,030.9 KB | 5,208 | 10,395 | 11,785 | 3 | 3,179 KB |

The erlang page also costs 124 ms in `evaluateJavaScriptExpression` on the client.

## The vocabulary being encoded

From `lib/hologram/template/renderer.ex`:

```elixir
@type tree_node ::
        {:doctype, String.t()}
        | {:element, String.t(), [{String.t(), [] | [text: String.t()]}], [tree_node]}
        | {:public_comment, [tree_node]}
        | {:text, String.t()}
```

Every dynamic thing is already resolved. `$key` is present; all other `$`-prefixed attributes were dropped by `render_tree_attributes/1`.

## The four axes

The design space factorises into four independent choices. Each fragment below is lifted from a real generated payload for the same node, `<div class="big" $key="k1:0" hidden>Hologram<!-- x --></div>`.

### node - how a node announces what it is

| Value | Element encoding |
|-------|------------------|
| `tag` | `["e","div",...,...]` |
| `full` | `["element","div",...,...]` |
| `untagged` | `["div",...,...]` - an element is the only node of length 3 |
| `object` | `{"type":"element","tag":"div","attrs":...,"children":...}` |

### text - how a text node is carried

| Value | Text node encoding |
|-------|--------------------|
| `wrapped` | `["t","Hologram"]` |
| `bare` | `"Hologram"` |
| `interned` | `0`, with `["Hologram"," x "]` carried once |

### attrs - how attributes are laid out

| Value | Attribute encoding |
|-------|--------------------|
| `pairs` | `[["class","big"],["$key","k1:0"],["hidden"]]` |
| `flat` | `["class","big","$key","k1:0","hidden",null]` |
| `flatcount` | `...,3,"class","big","$key","k1:0","hidden",null,...` inlined in the node array |
| `object` | `{"$key":"k1:0","class":"big","hidden":null}` - lossy, see Findings |

### intern - what moves into a dictionary

| Value | Interned |
|-------|----------|
| `none` | nothing; every string written out at every occurrence |
| `tn` | tag names and attribute names |
| `tnv` | tag names, attribute names and attribute values |

One shape sits outside the grid. `stream` flattens the whole tree into a single preorder array of integers against four dictionaries: an element is `tagIdx, nAttrs, (nameIdx, valIdx)*, nChildren, children...`, a text node is a single negative integer, and comment and doctype are reserved tag codes. It is the ceiling rather than a point in the cross-product.

## Method

Both pages were rendered through `Renderer.render_page/4` against hologram_website with `deps/hologram` at `790de2b19`, and every variant encoded from the resulting tree. Server timings are the best of five runs of convert plus `JSON.encode!/1`. Client timings are the best of eight, taken three times and reduced to the minimum, running `JSON.parse` and then a decode walk that builds the same boxed terms `renderDom` already consumes. Sizes are bytes of UTF-8 JSON; the gzip column is `:zlib.gzip/1` at default level.

The client column is `JSON.parse` plus decode timed end to end. On a few rows it exceeds parse plus decode by more than measurement noise, because a 112-variant run builds and discards a 14 MB boxed tree each time and some rows absorb a collection. Parse and decode are the columns to trust; the client column is there for shape, not for differences under a millisecond.

Every variant's decoded output was fingerprinted and compared against the reference. 100 of 112 reproduce the tree exactly on both pages.

The envelope is always `[tags, names, values, texts, tree]`, with empty arrays where a variant does not intern, so the rows compare like for like. The 10 bytes that costs are within the noise of every measurement here.

## Marginal effect of each axis

Each row is the mean across every valid combination holding that one choice fixed, so the axes compare without picking a variant first. Lossy combinations are excluded. Sizes in KB, times in ms.

| Axis | Value | n | erlang size | erlang gzip | erlang client | ++/2 size | ++/2 gzip |
|------|-------|---|-------------|-------------|---------------|-----------|-----------|
| `node` | `tag` | 27 | 1,013.7 | 41.5 | 5.2 | 1,070.8 | 45.2 |
| `node` | `full` | 27 | 1,088.8 | 42.2 | 5.3 | 1,111.5 | 45.5 |
| `node` | `untagged` | 27 | 976.1 | 41.2 | 5.2 | 1,050.5 | 45.0 |
| `node` | `object` | 18 | 1,482.2 | 45.8 | 8.1 | 1,325.6 | 47.3 |
| `text` | `wrapped` | 33 | 1,312.1 | 42.4 | 7.0 | 1,226.2 | 45.1 |
| `text` | `bare` | 33 | 1,126.2 | 40.8 | 5.4 | 1,125.6 | 44.2 |
| `text` | `interned` | 33 | 888.9 | 43.9 | 4.9 | 1,016.2 | 47.5 |
| `attrs` | `pairs` | 36 | 1,159.5 | 42.8 | 6.5 | 1,154.0 | 45.9 |
| `attrs` | `flat` | 36 | 1,128.6 | 42.5 | 5.8 | 1,131.0 | 45.6 |
| `attrs` | `flatcount` | 27 | 1,015.9 | 41.5 | 4.8 | 1,070.0 | 45.2 |
| `intern` | `none` | 33 | 1,297.5 | 43.6 | 6.2 | 1,282.9 | 44.6 |
| `intern` | `tn` | 33 | 1,194.2 | 42.8 | 5.9 | 1,210.5 | 44.1 |
| `intern` | `tnv` | 33 | 835.6 | 40.7 | 5.1 | 874.7 | 48.0 |

## Why a dictionary works at all

Attribute values are 39% of the erlang payload and there are only 838 distinct ones. The most repeated appears 613 times and costs 75.4 KB on its own - it is a Tailwind class list. "Inline" is what those strings cost repeated at every occurrence; "dict" is what they cost listed once.

| | erlang distinct | erlang occurrences | erlang inline | erlang dict | ++/2 distinct | ++/2 occurrences | ++/2 inline | ++/2 dict |
|---|---|---|---|---|---|---|---|---|
| Tag names | 29 | 9,617 | 53.3 KB | 0.2 KB | 23 | 5,208 | 29.1 KB | 0.1 KB |
| Attribute names | 27 | 15,835 | 113.1 KB | 0.2 KB | 28 | 11,785 | 85.7 KB | 0.3 KB |
| Attribute values | 838 | 15,832 | 464.2 KB | 45.2 KB | 1,470 | 11,782 | 461.3 KB | 80.5 KB |
| Text | 1,604 | 19,210 | 468.6 KB | 196.0 KB | 1,362 | 10,395 | 569.2 KB | 443.3 KB |

## Findings

### Attributes as an object cannot work

All 12 combinations that key attributes by name fail to reproduce the tree, on both pages, for two independent reasons.

Duplicate attribute names survive into the tree. `dedupe_attributes/1` is only reached when a spread is present - `expand_attribute_spreads/1` returns the list untouched otherwise - so `<div class="x" class="y">` arrives at the encoder with both intact and an object keeps one. Verified by rendering `[{"$key", [text: "a"]}, {"$key", [text: "b"]}, {"class", [text: "x"]}, {"class", [text: "y"]}]`, which comes back with all four.

Attribute order is also lost. `JSON.encode!/1` sorts map keys, so the example above encodes as `{"$key":"k1:0","class":"big","hidden":null}` with `$key` ahead of `class`.

### Array count predicts parse time, byte count does not

`flat` and `flatcount` are byte-for-byte identical on both pages - `flat`'s two brackets around the attribute run cost exactly what `flatcount`'s count digits cost - yet `flatcount` parses faster: 2.9 ms against 3.3 ms. Identical bytes, different parse time. The difference is one array per element, 9,617 of them on the erlang page, which `flatcount` inlines away.

The same effect explains `pairs`. It allocates one two-element array per attribute - 15,832 on that page - and parses at 3.7 ms against `flat`'s 3.3 ms for 2.5% more bytes. Averaged across the whole matrix the three attribute forms parse at 4.3, 3.7 and 2.8 ms. Array count predicts parse time; uncompressed size does not.

### Interning trades wire size for memory

Interning values and text takes the erlang payload from 1,195.8 KB to 496.6 KB and cuts retained heap from 17.4 MB to 12.3 MB. But it deletes exactly the redundancy gzip was already exploiting for free: on `++/2` the gzipped payload goes up, from 42.5 KB to 48.7 KB.

Note also where the heap is. Of the 17.4 MB retained by the non-interned form, 13.6 MB is the boxed terms themselves rather than the strings, so no dictionary reaches most of it. Retained heap measured with `node --expose-gc`.

### The spread stops mattering early

Uncompressed size across all 112 variants ranges from 496.6 KB to 2,052.8 KB; gzipped it ranges from 38.9 KB to 49.0 KB. But once elements are untagged and text is not wrapped, every remaining option costs between 2.4 and 5.4 ms of parse and decode on the erlang page, against 124 ms today. The whole dictionary tier buys about 3.0 ms out of a navigation that will be roughly 250 ms once the tree stops being boxed terms.

## Recommendation

DECIDE-1 is still open; this is what the matrix argues for.

`untagged` `bare` `pairs` `none`: 1,226.7 KB, and 3.7 ms of parse plus 1.7 ms of decode, against 4,273 KB and 124 ms today.

It gives up 730.1 KB and 2.1 ms to the interned variants and takes back the property that outlives them. `[["class","big"],["hidden"]]` is the same structure as the Elixir `[{"class", [text: "big"]}, {"hidden", []}]` it comes from, so the encoder's clauses, its tests, and the mirrored tests on the client read as one specification of the same vocabulary. An element is the only node of length 3, a comment and a doctype are length 2, and a text node is a bare string - that arity contract is what the decoder dispatches on, and it is stated in a comment on both sides.

`untagged` `bare` `flat` `none` is the next step if bytes win the argument, and costs nothing structural: identical size to `flatcount`, no length prefix to step past, element arity still fixed at 3.

The dictionary tier is worth revisiting only if peak memory on low-end devices becomes the constraint, and even then it addresses under a third of the heap.

## Appendix A: all 112 variants

Sorted by uncompressed size on the erlang page. Sizes in KB, times in ms.

| Variant | erlang size | erlang gzip | encode | parse | client | ++/2 size | ++/2 gzip | ++/2 client | |
|---------|-------------|-------------|--------|-------|--------|-----------|-----------|-------------|---|
| `untagged-interned-flatcount-tnv` | 496.6 | 39.6 | 12.2 | 1.5 | 3.4 | 701.5 | 48.7 | 2.5 |  |
| `untagged-interned-flat-tnv` | 496.6 | 39.6 | 13.4 | 1.8 | 3.6 | 701.5 | 48.7 | 2.7 |  |
| `stream` | 497.8 | 39.7 | 12.3 | 1.1 | 2.5 | 702.8 | 48.6 | 2.0 |  |
| `untagged-interned-pairs-tnv` | 527.5 | 40.0 | 11.2 | 2.2 | 4.1 | 724.5 | 48.9 | 3.0 |  |
| `tag-interned-flatcount-tnv` | 534.1 | 39.9 | 14.6 | 1.7 | 3.7 | 721.9 | 48.9 | 2.6 |  |
| `tag-interned-flat-tnv` | 534.2 | 39.9 | 16.6 | 1.9 | 3.9 | 721.9 | 48.9 | 2.7 |  |
| `tag-interned-pairs-tnv` | 565.1 | 40.3 | 13.9 | 2.5 | 4.4 | 744.9 | 49.0 | 3.1 |  |
| `full-interned-flatcount-tnv` | 590.6 | 40.4 | 16.0 | 1.7 | 3.5 | 752.4 | 49.0 | 2.6 |  |
| `full-interned-flat-tnv` | 590.6 | 40.3 | 14.6 | 2.0 | 3.8 | 752.4 | 48.9 | 2.8 |  |
| `full-interned-pairs-tnv` | 621.5 | 40.7 | 16.7 | 2.5 | 4.4 | 775.4 | 49.2 | 3.1 |  |
| `untagged-bare-flatcount-tnv` | 733.9 | 38.9 | 15.3 | 2.0 | 3.9 | 810.9 | 46.3 | 2.7 |  |
| `untagged-bare-flat-tnv` | 733.9 | 38.9 | 12.6 | 2.3 | 4.0 | 810.9 | 46.3 | 2.8 |  |
| `untagged-bare-pairs-tnv` | 764.8 | 39.2 | 15.9 | 2.7 | 4.5 | 833.9 | 46.6 | 3.1 |  |
| `tag-bare-flatcount-tnv` | 771.5 | 39.2 | 16.6 | 2.3 | 4.2 | 831.3 | 46.4 | 2.7 |  |
| `tag-bare-flat-tnv` | 771.5 | 39.2 | 16.0 | 2.5 | 4.4 | 831.3 | 46.4 | 2.9 |  |
| `tag-bare-pairs-tnv` | 802.4 | 39.6 | 15.2 | 3.1 | 5.0 | 854.3 | 46.7 | 3.3 |  |
| `full-bare-flatcount-tnv` | 827.9 | 40.0 | 16.5 | 2.2 | 3.9 | 861.8 | 46.7 | 2.7 |  |
| `full-bare-flat-tnv` | 827.9 | 40.0 | 14.6 | 2.5 | 4.2 | 861.8 | 46.7 | 3.0 |  |
| `untagged-wrapped-flatcount-tnv` | 846.5 | 40.4 | 19.2 | 3.1 | 5.1 | 871.8 | 46.9 | 3.2 |  |
| `untagged-wrapped-flat-tnv` | 846.5 | 40.3 | 16.8 | 3.3 | 5.3 | 871.8 | 46.9 | 3.5 |  |
| `untagged-interned-flatcount-tn` | 855.1 | 44.0 | 11.8 | 2.0 | 4.0 | 1,037.4 | 46.3 | 2.8 |  |
| `untagged-interned-flat-tn` | 855.1 | 44.0 | 11.7 | 2.3 | 4.2 | 1,037.4 | 46.2 | 2.9 |  |
| `full-bare-pairs-tnv` | 858.8 | 40.4 | 16.8 | 3.1 | 4.9 | 884.9 | 47.0 | 3.3 |  |
| `untagged-wrapped-pairs-tnv` | 877.4 | 39.9 | 16.1 | 3.8 | 6.0 | 894.9 | 47.1 | 3.8 |  |
| `tag-wrapped-flatcount-tnv` | 884.0 | 40.0 | 21.3 | 3.3 | 5.3 | 892.2 | 47.1 | 3.4 |  |
| `tag-wrapped-flat-tnv` | 884.0 | 40.0 | 22.2 | 3.4 | 5.4 | 892.2 | 47.1 | 3.5 |  |
| `untagged-interned-pairs-tn` | 886.0 | 44.2 | 12.7 | 2.8 | 4.7 | 1,060.4 | 46.3 | 3.3 |  |
| `object-interned-flat-tnv` | 891.2 | 42.8 | 18.2 | 3.5 | 5.4 | 915.2 | 50.0 | 3.5 |  |
| `tag-interned-flatcount-tn` | 892.7 | 44.3 | 12.7 | 2.2 | 4.2 | 1,057.7 | 46.3 | 2.9 |  |
| `tag-interned-flat-tn` | 892.7 | 44.3 | 13.1 | 2.6 | 4.4 | 1,057.7 | 46.2 | 3.1 |  |
| `tag-wrapped-pairs-tnv` | 914.9 | 40.6 | 19.2 | 3.9 | 6.2 | 915.2 | 47.7 | 4.0 |  |
| `object-interned-pairs-tnv` | 922.1 | 43.3 | 17.6 | 4.0 | 6.7 | 938.2 | 50.3 | 3.9 |  |
| `tag-interned-pairs-tn` | 923.6 | 44.5 | 14.6 | 3.0 | 5.0 | 1,080.7 | 46.1 | 3.5 |  |
| `full-interned-flatcount-tn` | 949.1 | 44.9 | 12.8 | 2.3 | 4.2 | 1,088.3 | 46.2 | 2.9 |  |
| `full-interned-flat-tn` | 949.1 | 44.9 | 13.3 | 2.5 | 4.4 | 1,088.3 | 46.1 | 3.1 |  |
| `untagged-interned-flatcount-none` | 958.5 | 44.9 | 10.3 | 2.5 | 4.3 | 1,109.8 | 46.2 | 3.0 |  |
| `untagged-interned-flat-none` | 958.5 | 44.8 | 9.1 | 2.7 | 4.7 | 1,109.8 | 46.2 | 3.2 |  |
| `untagged-interned-object-none` | 958.5 | 44.6 | 10.5 | - | - | 1,109.8 | 45.8 | - | lossy |
| `full-interned-pairs-tn` | 980.0 | 45.0 | 14.8 | 3.0 | 7.7 | 1,111.3 | 46.3 | 3.5 |  |
| `untagged-interned-pairs-none` | 989.4 | 45.2 | 13.8 | 3.3 | 5.2 | 1,132.8 | 46.5 | 3.6 |  |
| `tag-interned-flatcount-none` | 996.0 | 45.0 | 18.2 | 2.7 | 4.6 | 1,130.1 | 46.5 | 3.1 |  |
| `tag-interned-flat-none` | 996.0 | 45.0 | 10.7 | 2.9 | 4.9 | 1,130.1 | 46.4 | 3.4 |  |
| `tag-interned-object-none` | 996.0 | 45.0 | 10.9 | - | - | 1,130.1 | 46.0 | - | lossy |
| `full-wrapped-flatcount-tnv` | 996.7 | 41.0 | 19.1 | 3.3 | 5.4 | 953.2 | 48.0 | 3.4 |  |
| `full-wrapped-flat-tnv` | 996.7 | 41.0 | 18.1 | 3.6 | 5.7 | 953.2 | 48.0 | 3.5 |  |
| `tag-interned-pairs-none` | 1,026.9 | 45.5 | 13.0 | 3.5 | 5.5 | 1,153.1 | 46.5 | 3.8 |  |
| `full-wrapped-pairs-tnv` | 1,027.6 | 41.4 | 16.4 | 4.1 | 6.2 | 976.2 | 48.1 | 3.9 |  |
| `full-interned-flatcount-none` | 1,052.4 | 45.9 | 14.8 | 2.7 | 4.4 | 1,160.7 | 46.4 | 3.2 |  |
| `full-interned-flat-none` | 1,052.4 | 45.9 | 14.0 | 2.9 | 5.0 | 1,160.7 | 46.4 | 3.2 |  |
| `full-interned-object-none` | 1,052.4 | 46.0 | 14.5 | - | - | 1,160.7 | 47.0 | - | lossy |
| `full-interned-pairs-none` | 1,083.4 | 46.1 | 13.9 | 3.5 | 5.7 | 1,183.7 | 46.6 | 3.8 |  |
| `untagged-bare-flatcount-tn` | 1,092.4 | 40.3 | 16.3 | 2.5 | 4.5 | 1,146.8 | 41.8 | 3.0 |  |
| `untagged-bare-flat-tn` | 1,092.4 | 40.3 | 14.2 | 2.8 | 4.6 | 1,146.8 | 41.8 | 3.1 |  |
| `untagged-bare-pairs-tn` | 1,123.4 | 40.0 | 15.3 | 3.3 | 7.3 | 1,169.8 | 41.9 | 3.5 |  |
| `object-bare-flat-tnv` | 1,128.5 | 42.6 | 21.2 | 4.2 | 5.9 | 1,024.7 | 48.4 | 3.8 |  |
| `tag-bare-flatcount-tn` | 1,130.0 | 40.1 | 14.5 | 2.7 | 4.6 | 1,167.2 | 41.9 | 3.1 |  |
| `tag-bare-flat-tn` | 1,130.0 | 40.0 | 13.5 | 3.0 | 5.1 | 1,167.2 | 41.9 | 3.2 |  |
| `object-bare-pairs-tnv` | 1,159.4 | 42.4 | 21.8 | 4.7 | 6.2 | 1,047.7 | 48.7 | 4.2 |  |
| `tag-bare-pairs-tn` | 1,160.9 | 40.2 | 14.9 | 3.6 | 5.7 | 1,190.2 | 41.9 | 3.7 |  |
| `full-bare-flatcount-tn` | 1,186.4 | 40.3 | 15.0 | 2.8 | 4.6 | 1,197.7 | 42.1 | 3.1 |  |
| `full-bare-flat-tn` | 1,186.4 | 40.3 | 13.2 | 3.0 | 5.1 | 1,197.7 | 42.1 | 3.3 |  |
| `untagged-bare-flatcount-none` | 1,195.8 | 40.5 | 11.7 | 2.9 | 4.8 | 1,219.2 | 42.6 | 3.2 |  |
| `untagged-bare-flat-none` | 1,195.8 | 40.4 | 12.7 | 3.3 | 5.2 | 1,219.2 | 42.5 | 3.3 |  |
| `untagged-bare-object-none` | 1,195.8 | 40.5 | 12.2 | - | - | 1,219.2 | 42.6 | - | lossy |
| `untagged-wrapped-flatcount-tn` | 1,205.0 | 40.4 | 21.7 | 3.6 | 5.7 | 1,207.7 | 42.3 | 3.6 |  |
| `untagged-wrapped-flat-tn` | 1,205.0 | 40.4 | 14.9 | 3.7 | 6.1 | 1,207.7 | 42.2 | 3.7 |  |
| `full-bare-pairs-tn` | 1,217.3 | 40.6 | 15.6 | 3.5 | 5.4 | 1,220.7 | 42.8 | 3.6 |  |
| `untagged-bare-pairs-none` | 1,226.7 | 40.7 | 12.8 | 3.7 | 8.2 | 1,242.2 | 43.0 | 3.7 | **pick** |
| `tag-bare-flatcount-none` | 1,233.3 | 40.8 | 18.4 | 3.2 | 5.1 | 1,239.6 | 43.0 | 3.3 |  |
| `tag-bare-flat-none` | 1,233.3 | 40.8 | 12.7 | 3.5 | 5.3 | 1,239.6 | 43.0 | 3.4 |  |
| `tag-bare-object-none` | 1,233.3 | 40.9 | 12.3 | - | - | 1,239.6 | 42.6 | - | lossy |
| `untagged-wrapped-pairs-tn` | 1,235.9 | 41.0 | 17.0 | 4.4 | 6.4 | 1,230.7 | 43.0 | 4.4 |  |
| `tag-wrapped-flatcount-tn` | 1,242.6 | 41.2 | 17.7 | 3.8 | 5.9 | 1,228.1 | 43.0 | 3.8 |  |
| `tag-wrapped-flat-tn` | 1,242.6 | 41.1 | 16.8 | 4.0 | 5.9 | 1,228.1 | 43.0 | 3.8 |  |
| `object-interned-flat-tn` | 1,249.7 | 48.3 | 22.4 | 4.2 | 6.1 | 1,251.1 | 48.3 | 3.9 |  |
| `tag-bare-pairs-none` | 1,264.3 | 41.4 | 13.6 | 4.0 | 6.4 | 1,262.6 | 43.3 | 3.9 |  |
| `tag-wrapped-pairs-tn` | 1,273.5 | 41.7 | 18.9 | 4.5 | 6.5 | 1,251.1 | 43.2 | 4.1 |  |
| `object-interned-pairs-tn` | 1,280.7 | 48.4 | 19.1 | 4.8 | 6.6 | 1,274.1 | 48.4 | 4.3 |  |
| `full-bare-flatcount-none` | 1,289.8 | 41.5 | 15.4 | 3.1 | 5.0 | 1,270.1 | 43.3 | 3.4 |  |
| `full-bare-flat-none` | 1,289.8 | 41.5 | 11.9 | 3.6 | 5.6 | 1,270.1 | 43.2 | 3.4 |  |
| `full-bare-object-none` | 1,289.8 | 41.5 | 13.1 | - | - | 1,270.1 | 42.7 | - | lossy |
| `untagged-wrapped-flatcount-none` | 1,308.3 | 41.6 | 19.3 | 4.0 | 5.9 | 1,280.1 | 43.3 | 4.0 |  |
| `untagged-wrapped-flat-none` | 1,308.3 | 41.5 | 13.6 | 4.2 | 6.5 | 1,280.1 | 43.2 | 4.0 |  |
| `untagged-wrapped-object-none` | 1,308.3 | 41.6 | 15.4 | - | - | 1,280.1 | 43.0 | - | lossy |
| `full-bare-pairs-none` | 1,320.7 | 41.8 | 14.6 | 4.0 | 5.9 | 1,293.1 | 43.3 | 3.9 |  |
| `untagged-wrapped-pairs-none` | 1,339.2 | 41.9 | 16.6 | 4.8 | 7.4 | 1,303.1 | 43.4 | 4.4 |  |
| `tag-wrapped-flatcount-none` | 1,345.9 | 41.9 | 21.1 | 4.2 | 6.1 | 1,300.5 | 43.3 | 3.9 |  |
| `tag-wrapped-flat-none` | 1,345.9 | 41.8 | 19.7 | 4.5 | 6.1 | 1,300.5 | 43.3 | 4.1 |  |
| `tag-wrapped-object-none` | 1,345.9 | 41.8 | 19.8 | - | - | 1,300.5 | 43.1 | - | lossy |
| `object-interned-flat-none` | 1,353.1 | 48.8 | 19.8 | 4.7 | 7.0 | 1,323.5 | 48.6 | 4.2 |  |
| `object-interned-object-none` | 1,353.1 | 48.7 | 21.6 | - | - | 1,323.5 | 48.5 | - | lossy |
| `full-wrapped-flatcount-tn` | 1,355.3 | 42.1 | 19.7 | 3.8 | 5.7 | 1,289.1 | 43.3 | 3.8 |  |
| `full-wrapped-flat-tn` | 1,355.3 | 42.1 | 20.1 | 4.1 | 6.1 | 1,289.1 | 43.3 | 4.0 |  |
| `tag-wrapped-pairs-none` | 1,376.8 | 42.0 | 17.1 | 4.9 | 6.8 | 1,323.5 | 43.3 | 4.5 |  |
| `object-interned-pairs-none` | 1,384.0 | 49.0 | 16.9 | 5.1 | 7.1 | 1,346.5 | 48.6 | 4.5 |  |
| `full-wrapped-pairs-tn` | 1,386.2 | 42.4 | 18.4 | 4.7 | 7.2 | 1,312.1 | 43.4 | 4.3 |  |
| `full-wrapped-flatcount-none` | 1,458.6 | 42.5 | 21.0 | 4.3 | 6.3 | 1,361.5 | 43.6 | 4.0 |  |
| `full-wrapped-flat-none` | 1,458.6 | 42.5 | 15.7 | 4.7 | 6.5 | 1,361.5 | 43.6 | 4.1 |  |
| `full-wrapped-object-none` | 1,458.6 | 42.8 | 22.7 | - | - | 1,361.5 | 43.6 | - | lossy |
| `object-bare-flat-tn` | 1,487.1 | 43.7 | 20.8 | 4.7 | 6.8 | 1,360.5 | 43.7 | 4.1 |  |
| `full-wrapped-pairs-none` | 1,489.5 | 43.0 | 15.7 | 5.2 | 7.1 | 1,384.5 | 43.9 | 4.5 |  |
| `object-bare-pairs-tn` | 1,518.0 | 43.8 | 23.9 | 5.2 | 7.1 | 1,383.6 | 44.0 | 4.6 |  |
| `object-wrapped-flat-tnv` | 1,560.0 | 46.0 | 36.4 | 7.5 | 9.9 | 1,258.1 | 50.3 | 5.7 |  |
| `object-bare-flat-none` | 1,590.4 | 44.1 | 21.2 | 5.1 | 7.3 | 1,432.9 | 44.3 | 4.4 |  |
| `object-bare-object-none` | 1,590.4 | 44.0 | 19.1 | - | - | 1,432.9 | 44.3 | - | lossy |
| `object-wrapped-pairs-tnv` | 1,590.9 | 46.4 | 29.0 | 8.0 | 10.1 | 1,281.2 | 50.4 | 5.8 |  |
| `object-bare-pairs-none` | 1,621.3 | 44.1 | 21.5 | 5.6 | 8.0 | 1,455.9 | 44.3 | 4.7 |  |
| `object-wrapped-flat-tn` | 1,918.5 | 47.1 | 39.6 | 8.1 | 13.0 | 1,594.0 | 45.7 | 6.0 |  |
| `object-wrapped-pairs-tn` | 1,949.4 | 47.1 | 30.4 | 8.9 | 11.0 | 1,617.0 | 45.7 | 6.4 |  |
| `object-wrapped-flat-none` | 2,021.9 | 47.7 | 22.9 | 8.7 | 10.5 | 1,666.4 | 45.7 | 6.1 |  |
| `object-wrapped-object-none` | 2,021.9 | 47.8 | 28.0 | - | - | 1,666.4 | 45.8 | - | lossy |
| `object-wrapped-pairs-none` | 2,052.8 | 48.1 | 32.6 | 9.2 | 11.2 | 1,689.4 | 45.7 | 6.7 |  |

## Appendix B: what each variant emits

The same node under every variant, envelope included: `[tags, names, values, texts, tree]`.

```
full-bare-flat-none               [[],[],[],[],[["element","div",["class","big","$key","k1:0","hidden",null],["Hologram",["public_comment",[" x "]]]]]]
full-bare-flat-tn                 [["div"],["class","$key","hidden"],[],[],[["element",0,[0,"big",1,"k1:0",2,null],["Hologram",["public_comment",[" x "]]]]]]
full-bare-flat-tnv                [["div"],["class","$key","hidden"],["big","k1:0"],[],[["element",0,[0,0,1,1,2,-1],["Hologram",["public_comment",[" x "]]]]]]
full-bare-flatcount-none          [[],[],[],[],[["element","div",3,"class","big","$key","k1:0","hidden",null,["Hologram",["public_comment",[" x "]]]]]]
full-bare-flatcount-tn            [["div"],["class","$key","hidden"],[],[],[["element",0,3,0,"big",1,"k1:0",2,null,["Hologram",["public_comment",[" x "]]]]]]
full-bare-flatcount-tnv           [["div"],["class","$key","hidden"],["big","k1:0"],[],[["element",0,3,0,0,1,1,2,-1,["Hologram",["public_comment",[" x "]]]]]]
full-bare-object-none             [[],[],[],[],[["element","div",{"$key":"k1:0","class":"big","hidden":null},["Hologram",["public_comment",[" x "]]]]]]
full-bare-pairs-none              [[],[],[],[],[["element","div",[["class","big"],["$key","k1:0"],["hidden"]],["Hologram",["public_comment",[" x "]]]]]]
full-bare-pairs-tn                [["div"],["class","$key","hidden"],[],[],[["element",0,[[0,"big"],[1,"k1:0"],[2]],["Hologram",["public_comment",[" x "]]]]]]
full-bare-pairs-tnv               [["div"],["class","$key","hidden"],["big","k1:0"],[],[["element",0,[[0,0],[1,1],[2]],["Hologram",["public_comment",[" x "]]]]]]
full-interned-flat-none           [[],[],[],["Hologram"," x "],[["element","div",["class","big","$key","k1:0","hidden",null],[0,["public_comment",[1]]]]]]
full-interned-flat-tn             [["div"],["class","$key","hidden"],[],["Hologram"," x "],[["element",0,[0,"big",1,"k1:0",2,null],[0,["public_comment",[1]]]]]]
full-interned-flat-tnv            [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[["element",0,[0,0,1,1,2,-1],[0,["public_comment",[1]]]]]]
full-interned-flatcount-none      [[],[],[],["Hologram"," x "],[["element","div",3,"class","big","$key","k1:0","hidden",null,[0,["public_comment",[1]]]]]]
full-interned-flatcount-tn        [["div"],["class","$key","hidden"],[],["Hologram"," x "],[["element",0,3,0,"big",1,"k1:0",2,null,[0,["public_comment",[1]]]]]]
full-interned-flatcount-tnv       [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[["element",0,3,0,0,1,1,2,-1,[0,["public_comment",[1]]]]]]
full-interned-object-none         [[],[],[],["Hologram"," x "],[["element","div",{"$key":"k1:0","class":"big","hidden":null},[0,["public_comment",[1]]]]]]
full-interned-pairs-none          [[],[],[],["Hologram"," x "],[["element","div",[["class","big"],["$key","k1:0"],["hidden"]],[0,["public_comment",[1]]]]]]
full-interned-pairs-tn            [["div"],["class","$key","hidden"],[],["Hologram"," x "],[["element",0,[[0,"big"],[1,"k1:0"],[2]],[0,["public_comment",[1]]]]]]
full-interned-pairs-tnv           [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[["element",0,[[0,0],[1,1],[2]],[0,["public_comment",[1]]]]]]
full-wrapped-flat-none            [[],[],[],[],[["element","div",["class","big","$key","k1:0","hidden",null],[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-flat-tn              [["div"],["class","$key","hidden"],[],[],[["element",0,[0,"big",1,"k1:0",2,null],[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-flat-tnv             [["div"],["class","$key","hidden"],["big","k1:0"],[],[["element",0,[0,0,1,1,2,-1],[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-flatcount-none       [[],[],[],[],[["element","div",3,"class","big","$key","k1:0","hidden",null,[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-flatcount-tn         [["div"],["class","$key","hidden"],[],[],[["element",0,3,0,"big",1,"k1:0",2,null,[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-flatcount-tnv        [["div"],["class","$key","hidden"],["big","k1:0"],[],[["element",0,3,0,0,1,1,2,-1,[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-object-none          [[],[],[],[],[["element","div",{"$key":"k1:0","class":"big","hidden":null},[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-pairs-none           [[],[],[],[],[["element","div",[["class","big"],["$key","k1:0"],["hidden"]],[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-pairs-tn             [["div"],["class","$key","hidden"],[],[],[["element",0,[[0,"big"],[1,"k1:0"],[2]],[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
full-wrapped-pairs-tnv            [["div"],["class","$key","hidden"],["big","k1:0"],[],[["element",0,[[0,0],[1,1],[2]],[["text","Hologram"],["public_comment",[["text"," x "]]]]]]]
object-bare-flat-none             [[],[],[],[],[{"attrs":["class","big","$key","k1:0","hidden",null],"children":["Hologram",{"children":[" x "],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-bare-flat-tn               [["div"],["class","$key","hidden"],[],[],[{"attrs":[0,"big",1,"k1:0",2,null],"children":["Hologram",{"children":[" x "],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-bare-flat-tnv              [["div"],["class","$key","hidden"],["big","k1:0"],[],[{"attrs":[0,0,1,1,2,-1],"children":["Hologram",{"children":[" x "],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-bare-object-none           [[],[],[],[],[{"attrs":{"$key":"k1:0","class":"big","hidden":null},"children":["Hologram",{"children":[" x "],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-bare-pairs-none            [[],[],[],[],[{"attrs":[["class","big"],["$key","k1:0"],["hidden"]],"children":["Hologram",{"children":[" x "],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-bare-pairs-tn              [["div"],["class","$key","hidden"],[],[],[{"attrs":[[0,"big"],[1,"k1:0"],[2]],"children":["Hologram",{"children":[" x "],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-bare-pairs-tnv             [["div"],["class","$key","hidden"],["big","k1:0"],[],[{"attrs":[[0,0],[1,1],[2]],"children":["Hologram",{"children":[" x "],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-interned-flat-none         [[],[],[],["Hologram"," x "],[{"attrs":["class","big","$key","k1:0","hidden",null],"children":[0,{"children":[1],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-interned-flat-tn           [["div"],["class","$key","hidden"],[],["Hologram"," x "],[{"attrs":[0,"big",1,"k1:0",2,null],"children":[0,{"children":[1],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-interned-flat-tnv          [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[{"attrs":[0,0,1,1,2,-1],"children":[0,{"children":[1],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-interned-object-none       [[],[],[],["Hologram"," x "],[{"attrs":{"$key":"k1:0","class":"big","hidden":null},"children":[0,{"children":[1],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-interned-pairs-none        [[],[],[],["Hologram"," x "],[{"attrs":[["class","big"],["$key","k1:0"],["hidden"]],"children":[0,{"children":[1],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-interned-pairs-tn          [["div"],["class","$key","hidden"],[],["Hologram"," x "],[{"attrs":[[0,"big"],[1,"k1:0"],[2]],"children":[0,{"children":[1],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-interned-pairs-tnv         [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[{"attrs":[[0,0],[1,1],[2]],"children":[0,{"children":[1],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-wrapped-flat-none          [[],[],[],[],[{"attrs":["class","big","$key","k1:0","hidden",null],"children":[{"text":"Hologram","type":"text"},{"children":[{"text":" x ","type":"text"}],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-wrapped-flat-tn            [["div"],["class","$key","hidden"],[],[],[{"attrs":[0,"big",1,"k1:0",2,null],"children":[{"text":"Hologram","type":"text"},{"children":[{"text":" x ","type":"text"}],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-wrapped-flat-tnv           [["div"],["class","$key","hidden"],["big","k1:0"],[],[{"attrs":[0,0,1,1,2,-1],"children":[{"text":"Hologram","type":"text"},{"children":[{"text":" x ","type":"text"}],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-wrapped-object-none        [[],[],[],[],[{"attrs":{"$key":"k1:0","class":"big","hidden":null},"children":[{"text":"Hologram","type":"text"},{"children":[{"text":" x ","type":"text"}],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-wrapped-pairs-none         [[],[],[],[],[{"attrs":[["class","big"],["$key","k1:0"],["hidden"]],"children":[{"text":"Hologram","type":"text"},{"children":[{"text":" x ","type":"text"}],"type":"public_comment"}],"tag":"div","type":"element"}]]
object-wrapped-pairs-tn           [["div"],["class","$key","hidden"],[],[],[{"attrs":[[0,"big"],[1,"k1:0"],[2]],"children":[{"text":"Hologram","type":"text"},{"children":[{"text":" x ","type":"text"}],"type":"public_comment"}],"tag":0,"type":"element"}]]
object-wrapped-pairs-tnv          [["div"],["class","$key","hidden"],["big","k1:0"],[],[{"attrs":[[0,0],[1,1],[2]],"children":[{"text":"Hologram","type":"text"},{"children":[{"text":" x ","type":"text"}],"type":"public_comment"}],"tag":0,"type":"element"}]]
stream                            [["div"," comment"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[1,0,3,0,0,1,1,2,-1,2,-1,1,0,1,-2]]
tag-bare-flat-none                [[],[],[],[],[["e","div",["class","big","$key","k1:0","hidden",null],["Hologram",["c",[" x "]]]]]]
tag-bare-flat-tn                  [["div"],["class","$key","hidden"],[],[],[["e",0,[0,"big",1,"k1:0",2,null],["Hologram",["c",[" x "]]]]]]
tag-bare-flat-tnv                 [["div"],["class","$key","hidden"],["big","k1:0"],[],[["e",0,[0,0,1,1,2,-1],["Hologram",["c",[" x "]]]]]]
tag-bare-flatcount-none           [[],[],[],[],[["e","div",3,"class","big","$key","k1:0","hidden",null,["Hologram",["c",[" x "]]]]]]
tag-bare-flatcount-tn             [["div"],["class","$key","hidden"],[],[],[["e",0,3,0,"big",1,"k1:0",2,null,["Hologram",["c",[" x "]]]]]]
tag-bare-flatcount-tnv            [["div"],["class","$key","hidden"],["big","k1:0"],[],[["e",0,3,0,0,1,1,2,-1,["Hologram",["c",[" x "]]]]]]
tag-bare-object-none              [[],[],[],[],[["e","div",{"$key":"k1:0","class":"big","hidden":null},["Hologram",["c",[" x "]]]]]]
tag-bare-pairs-none               [[],[],[],[],[["e","div",[["class","big"],["$key","k1:0"],["hidden"]],["Hologram",["c",[" x "]]]]]]
tag-bare-pairs-tn                 [["div"],["class","$key","hidden"],[],[],[["e",0,[[0,"big"],[1,"k1:0"],[2]],["Hologram",["c",[" x "]]]]]]
tag-bare-pairs-tnv                [["div"],["class","$key","hidden"],["big","k1:0"],[],[["e",0,[[0,0],[1,1],[2]],["Hologram",["c",[" x "]]]]]]
tag-interned-flat-none            [[],[],[],["Hologram"," x "],[["e","div",["class","big","$key","k1:0","hidden",null],[0,["c",[1]]]]]]
tag-interned-flat-tn              [["div"],["class","$key","hidden"],[],["Hologram"," x "],[["e",0,[0,"big",1,"k1:0",2,null],[0,["c",[1]]]]]]
tag-interned-flat-tnv             [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[["e",0,[0,0,1,1,2,-1],[0,["c",[1]]]]]]
tag-interned-flatcount-none       [[],[],[],["Hologram"," x "],[["e","div",3,"class","big","$key","k1:0","hidden",null,[0,["c",[1]]]]]]
tag-interned-flatcount-tn         [["div"],["class","$key","hidden"],[],["Hologram"," x "],[["e",0,3,0,"big",1,"k1:0",2,null,[0,["c",[1]]]]]]
tag-interned-flatcount-tnv        [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[["e",0,3,0,0,1,1,2,-1,[0,["c",[1]]]]]]
tag-interned-object-none          [[],[],[],["Hologram"," x "],[["e","div",{"$key":"k1:0","class":"big","hidden":null},[0,["c",[1]]]]]]
tag-interned-pairs-none           [[],[],[],["Hologram"," x "],[["e","div",[["class","big"],["$key","k1:0"],["hidden"]],[0,["c",[1]]]]]]
tag-interned-pairs-tn             [["div"],["class","$key","hidden"],[],["Hologram"," x "],[["e",0,[[0,"big"],[1,"k1:0"],[2]],[0,["c",[1]]]]]]
tag-interned-pairs-tnv            [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[["e",0,[[0,0],[1,1],[2]],[0,["c",[1]]]]]]
tag-wrapped-flat-none             [[],[],[],[],[["e","div",["class","big","$key","k1:0","hidden",null],[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-flat-tn               [["div"],["class","$key","hidden"],[],[],[["e",0,[0,"big",1,"k1:0",2,null],[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-flat-tnv              [["div"],["class","$key","hidden"],["big","k1:0"],[],[["e",0,[0,0,1,1,2,-1],[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-flatcount-none        [[],[],[],[],[["e","div",3,"class","big","$key","k1:0","hidden",null,[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-flatcount-tn          [["div"],["class","$key","hidden"],[],[],[["e",0,3,0,"big",1,"k1:0",2,null,[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-flatcount-tnv         [["div"],["class","$key","hidden"],["big","k1:0"],[],[["e",0,3,0,0,1,1,2,-1,[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-object-none           [[],[],[],[],[["e","div",{"$key":"k1:0","class":"big","hidden":null},[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-pairs-none            [[],[],[],[],[["e","div",[["class","big"],["$key","k1:0"],["hidden"]],[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-pairs-tn              [["div"],["class","$key","hidden"],[],[],[["e",0,[[0,"big"],[1,"k1:0"],[2]],[["t","Hologram"],["c",[["t"," x "]]]]]]]
tag-wrapped-pairs-tnv             [["div"],["class","$key","hidden"],["big","k1:0"],[],[["e",0,[[0,0],[1,1],[2]],[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-bare-flat-none           [[],[],[],[],[["div",["class","big","$key","k1:0","hidden",null],["Hologram",["c",[" x "]]]]]]
untagged-bare-flat-tn             [["div"],["class","$key","hidden"],[],[],[[0,[0,"big",1,"k1:0",2,null],["Hologram",["c",[" x "]]]]]]
untagged-bare-flat-tnv            [["div"],["class","$key","hidden"],["big","k1:0"],[],[[0,[0,0,1,1,2,-1],["Hologram",["c",[" x "]]]]]]
untagged-bare-flatcount-none      [[],[],[],[],[["div",3,"class","big","$key","k1:0","hidden",null,["Hologram",["c",[" x "]]]]]]
untagged-bare-flatcount-tn        [["div"],["class","$key","hidden"],[],[],[[0,3,0,"big",1,"k1:0",2,null,["Hologram",["c",[" x "]]]]]]
untagged-bare-flatcount-tnv       [["div"],["class","$key","hidden"],["big","k1:0"],[],[[0,3,0,0,1,1,2,-1,["Hologram",["c",[" x "]]]]]]
untagged-bare-object-none         [[],[],[],[],[["div",{"$key":"k1:0","class":"big","hidden":null},["Hologram",["c",[" x "]]]]]]
untagged-bare-pairs-none          [[],[],[],[],[["div",[["class","big"],["$key","k1:0"],["hidden"]],["Hologram",["c",[" x "]]]]]]
untagged-bare-pairs-tn            [["div"],["class","$key","hidden"],[],[],[[0,[[0,"big"],[1,"k1:0"],[2]],["Hologram",["c",[" x "]]]]]]
untagged-bare-pairs-tnv           [["div"],["class","$key","hidden"],["big","k1:0"],[],[[0,[[0,0],[1,1],[2]],["Hologram",["c",[" x "]]]]]]
untagged-interned-flat-none       [[],[],[],["Hologram"," x "],[["div",["class","big","$key","k1:0","hidden",null],[0,["c",[1]]]]]]
untagged-interned-flat-tn         [["div"],["class","$key","hidden"],[],["Hologram"," x "],[[0,[0,"big",1,"k1:0",2,null],[0,["c",[1]]]]]]
untagged-interned-flat-tnv        [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[[0,[0,0,1,1,2,-1],[0,["c",[1]]]]]]
untagged-interned-flatcount-none  [[],[],[],["Hologram"," x "],[["div",3,"class","big","$key","k1:0","hidden",null,[0,["c",[1]]]]]]
untagged-interned-flatcount-tn    [["div"],["class","$key","hidden"],[],["Hologram"," x "],[[0,3,0,"big",1,"k1:0",2,null,[0,["c",[1]]]]]]
untagged-interned-flatcount-tnv   [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[[0,3,0,0,1,1,2,-1,[0,["c",[1]]]]]]
untagged-interned-object-none     [[],[],[],["Hologram"," x "],[["div",{"$key":"k1:0","class":"big","hidden":null},[0,["c",[1]]]]]]
untagged-interned-pairs-none      [[],[],[],["Hologram"," x "],[["div",[["class","big"],["$key","k1:0"],["hidden"]],[0,["c",[1]]]]]]
untagged-interned-pairs-tn        [["div"],["class","$key","hidden"],[],["Hologram"," x "],[[0,[[0,"big"],[1,"k1:0"],[2]],[0,["c",[1]]]]]]
untagged-interned-pairs-tnv       [["div"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],[[0,[[0,0],[1,1],[2]],[0,["c",[1]]]]]]
untagged-wrapped-flat-none        [[],[],[],[],[["div",["class","big","$key","k1:0","hidden",null],[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-flat-tn          [["div"],["class","$key","hidden"],[],[],[[0,[0,"big",1,"k1:0",2,null],[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-flat-tnv         [["div"],["class","$key","hidden"],["big","k1:0"],[],[[0,[0,0,1,1,2,-1],[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-flatcount-none   [[],[],[],[],[["div",3,"class","big","$key","k1:0","hidden",null,[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-flatcount-tn     [["div"],["class","$key","hidden"],[],[],[[0,3,0,"big",1,"k1:0",2,null,[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-flatcount-tnv    [["div"],["class","$key","hidden"],["big","k1:0"],[],[[0,3,0,0,1,1,2,-1,[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-object-none      [[],[],[],[],[["div",{"$key":"k1:0","class":"big","hidden":null},[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-pairs-none       [[],[],[],[],[["div",[["class","big"],["$key","k1:0"],["hidden"]],[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-pairs-tn         [["div"],["class","$key","hidden"],[],[],[[0,[[0,"big"],[1,"k1:0"],[2]],[["t","Hologram"],["c",[["t"," x "]]]]]]]
untagged-wrapped-pairs-tnv        [["div"],["class","$key","hidden"],["big","k1:0"],[],[[0,[[0,0],[1,1],[2]],[["t","Hologram"],["c",[["t"," x "]]]]]]]
```
