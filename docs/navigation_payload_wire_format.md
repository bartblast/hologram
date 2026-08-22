# Navigation Payload Wire Format

A client-side navigation is answered with the page's evaluated tree. The tree is a closed vocabulary of four constructors with no Elixir semantics in it, so it does not need the boxed-term encoder - but it does need a shape. This records the full cross-product of the choices that shape is made of, measured on two real pages, so the one that was picked can be checked rather than taken on trust.

Related: issue #1068.

## Chosen format

`untagged` `bare` `flat` `none`. An element is `[tag, attributes, children]` and always has length 3. Attributes are one flat name/value run, with `null` for a boolean. A text node is a bare string. A comment is `["c", children]` and a doctype `["d", content]`. Nothing is interned.

```json
["div",["class","big","$key","k1:0","hidden",null],["Hologram",["c",[" x "]]]]
```

| | erlang | ++/2 |
|---|---|---|
| Size | 1,195.8 KB | 1,219.2 KB |
| Gzipped | 40.4 KB | 42.5 KB |
| Encode | 12.7 ms | 8.0 ms |
| Parse | 3.3 ms | 2.2 ms |
| Decode | 1.7 ms | 1.1 ms |

Against 4,273 KB and 124 ms on the erlang page today.

It is not the fastest variant measured. It was chosen because the client-side consumer is about to change and this format assumes the least about it.

## TODO: revisit this format when the reconciler is rewritten

The reconciler is planned to stop using boxed terms and walk a tree of plain JavaScript literals instead. **That change invalidates the decode half of every measurement here, and the format should be re-chosen against the new consumer rather than carried forward by default.**

What changes when it lands:

- **The decode step can go to zero.** Today the client parses JSON and then walks it to build boxed terms. If the parsed JSON is already what the reconciler walks, that second pass disappears, and the variant to want is the one whose parsed form *is* the target rather than the one that is cheapest to convert.
- **The object-attribute family becomes eligible.** All 12 of those variants are excluded here for losing duplicate attribute names and attribute order. But `Renderer.#renderAttributesAndProps` already collapses attributes into a plain object (`const attrs = {}`) and filters out `$`-prefixed names, so a consumer that wants an object discards exactly what the wire form would have dropped. Confirm attribute ordering is harmless for adoption before relying on this: `JSON.encode!/1` sorts map keys, so a payload's insertion order differs from a client-side render's.
- **The flat token stream becomes attractive again.** It is the fastest thing measured, and it loses here mainly because a cursor-based integer reader is precisely the code a reconciler rewrite would throw away. Its grammar and worked examples are kept below for that reason.
- **Interning changes value.** Most of what interning saves today is boxed-term construction, which goes away on its own. What remains is wire size, where interning tags and names helps and interning attribute values hurts.
- **Re-measure with the new target.** The ranking here scores each variant on parse plus the cost of reaching boxed terms. Re-run it scoring parse plus the cost of reaching whatever the new reconciler walks, which is zero for some variants.

The chosen format is deliberately cheap to leave: the encoder is one function and the decoder is one function.

## Measured results

Measured on the branch, against hologram_website built with `HOLOGRAM_START=1 MIX_ENV=dev`, served on localhost, driven by headless Chrome over CDP with a trusted click on a visible link. Client figures are the best of four runs; they were stable to within 10%.

### Server, both encodings from the same tree

| | erlang | ++/2 |
|---|---|---|
| Render | 73.4 ms | 84.4 ms |
| Boxed terms: encode | 167.6 ms | 115.4 ms |
| Boxed terms: size | 4,273.1 KB | 3,179.9 KB |
| Boxed terms: gzipped | 73.3 KB | 56.5 KB |
| **Wire form: encode** | **9.7 ms** | **9.4 ms** |
| **Wire form: size** | **1,195.7 KB** | **1,219.2 KB** |
| **Wire form: gzipped** | **40.4 KB** | **42.5 KB** |
| Ratio | 17.2x encode, 3.6x size, 1.8x gzipped | 12.3x encode, 2.6x size, 1.3x gzipped |

Both rows come from one process rendering one tree, so this is a like-for-like comparison rather than two checkouts measured apart. The boxed-terms row already has the linear escaping from #1067 merged, so the 17.2x is the tree encoding alone and does not double-count that fix.

Gzip helps more than expected: the design sketch assumed compression would hide most of the difference, but the wire form is 45% smaller than boxed terms even compressed.

### Client, navigating from `/reference/client-runtime/erlang` to `++/2`

| | |
|---|---|
| Click to "page rendered in" | 581.6 ms |
| `POST /hologram/page/<Module>` | 151.6 ms, 41.3 KB on the wire |
| Hologram's own `page rendered in` | 324 ms |

Against the numbers this branch was opened on: that navigation took **22,363 ms** on the regressed master and **571 ms** before #1027 introduced the tree. It is now **581.6 ms** - a 38x improvement that lands within 2% of the pre-regression figure while still shipping the whole render tree.

### What now dominates the client

`render()` logs "page rendered in", and it wraps `renderPage`, `patchVirtualDocument` and listener reconciliation - the client's own render after the mount. It is not the decode path. At 324 ms of a 581.6 ms navigation it is the largest single cost, and this branch does not touch it.

That answers the question the Method section flags as unmeasured. The reconciliation constant is large: roughly 55% of the navigation. Decode, by contrast, is 1.1 ms for the page being navigated to, and 1.7 ms for the larger of the two. Any further work on navigation cost belongs in the vdom path, not in the wire format.

These figures are dev-mode: unminified bundles with source maps, served from localhost with no network latency. Production numbers will differ, and the transfer column especially so.

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

One shape sits outside the grid: `stream`, described below. It is the ceiling rather than a point in the cross-product.

## Method

Both pages were rendered through `Renderer.render_page/4` against hologram_website with `deps/hologram` at `790de2b19`, and every variant encoded from the resulting tree. Server timings are the best of five runs of convert plus `JSON.encode!/1`. Client timings are the best of eight, taken three times and reduced to the minimum, running `JSON.parse` and then a decode walk that builds the same boxed terms `renderDom` already consumes. Sizes are bytes of UTF-8 JSON; the gzip column is `:zlib.gzip/1` at default level.

The client column is `JSON.parse` plus decode timed end to end. On a few rows it exceeds parse plus decode by more than measurement noise, because a 112-variant run builds and discards a 14 MB boxed tree each time and some rows absorb a collection. Parse and decode are the columns to trust; the client column is there for shape, not for differences under a millisecond.

Every variant's decoded output was fingerprinted and compared against the reference. 100 of 112 reproduce the tree exactly on both pages.

The envelope is always `[tags, names, values, texts, tree]`, with empty arrays where a variant does not intern, so the rows compare like for like. The 10 bytes that costs are within the noise of every measurement here.

### What is not measured

Nothing downstream of the decode. `renderDom`, `Vdom.finalizeChildren` and `patchVirtualDocument` are all outside the timed region.

That is defensible for ranking these variants and no further: all 100 valid variants decode to deep-equal boxed terms, so `renderTree` receives identical input whichever is chosen and everything after it is the same work. It is a constant, and constants do not reorder a ranking.

But the constant is unmeasured and may be large. If reconciliation costs tens of milliseconds, the differences ranked here are a small share of the navigation, and effort is better spent on the vdom path than on the wire format. The 124 ms quoted above is `evaluateJavaScriptExpression` alone - the part this branch deletes - not what happens after it.

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

## Is there a variant that wins on every axis?

No. Scoring the 100 valid variants on gzipped size, encode time, client time and uncompressed size, 17 are Pareto-optimal and each axis is won by a different one.

| Axis | Winner | Value |
|------|--------|-------|
| Gzipped, both pages | `untagged-bare-pairs-tn` | 81.9 KB |
| Encode, both pages | `untagged-interned-flat-none` | 17.3 ms |
| Parse + decode, both pages | `stream` | 4.4 ms |
| Uncompressed, both pages | `untagged-interned-flatcount-tnv` | 1,198.1 KB |

Two of those four axes do not deserve a vote.

**Encode is noise.** The four-axis frontier spans 17.3 to 26.6 ms of encode, but encode was best-of-five within a single run and the same variant was observed at 7.0 and 12.5 ms across two runs - about an 11 ms band once both pages are summed. The noise is wider than the spread. Dropping it takes the frontier from 17 to 9.

**Memory is not independent.** All valid variants decode to identical boxed terms, so retained heap is the same except for string sharing. Measured with `node --expose-gc` on the erlang page:

| | source | after parse | after decode | retained |
|---|---|---|---|---|
| not interned | 1.2 MB | +3.9 MB | +13.6 MB | 17.4 MB |
| interned | 0.5 MB | +2.3 MB | +10.0 MB | 12.3 MB |

The parsed part tracks uncompressed size; the boxed part differs only because interning lets one bitstring object serve every occurrence of a repeated string. So memory is uncompressed size plus whether you intern, both of which are already columns. Dropping it takes the frontier to 7.

What is left is a single monotone trade-off between wire size and client time.

| Variant | Gzipped, both pages | Parse + decode, both pages | Uncompressed, both pages |
|---------|---------------------|----------------------------|--------------------------|
| `stream` | 88.3 | 4.4 | 1,200.6 |
| `untagged-interned-flat-tnv` | 88.2 | 6.0 | 1,198.1 |
| `untagged-bare-flatcount-tnv` | 85.2 | 6.4 | 1,544.8 |
| `untagged-bare-flatcount-tn` | 82.1 | 7.5 | 2,239.3 |
| `tag-bare-flatcount-tn` | 81.9 | 7.8 | 2,297.2 |
| `tag-bare-flat-tn` | 81.9 | 8.1 | 2,297.2 |
| `untagged-bare-pairs-tn` | 81.9 | 8.3 | 2,293.2 |

End to end that is 6.4 KB of extra transfer against 3.9 ms of saved client work, which breaks even at about 13 Mbps. Above that the interned end wins; below it the plain end does. There is no third consideration.

## Findings

### Attributes as an object cannot reproduce the tree

All 12 combinations that key attributes by name fail to reproduce the tree, on both pages, for two independent reasons.

Duplicate attribute names survive into the tree. `dedupe_attributes/1` is only reached when a spread is present - `expand_attribute_spreads/1` returns the list untouched otherwise - so `<div class="x" class="y">` arrives at the encoder with both intact and an object keeps one. Verified by rendering `[{"$key", [text: "a"]}, {"$key", [text: "b"]}, {"class", [text: "x"]}, {"class", [text: "y"]}]`, which comes back with all four.

Attribute order is also lost. `JSON.encode!/1` sorts map keys, so the example above encodes as `{"$key":"k1:0","class":"big","hidden":null}` with `$key` ahead of `class`.

This rules the form out for a consumer that must reconstruct the tree. It does not rule it out for a consumer that collapses attributes into an object anyway - see the TODO above.

### Array count predicts parse time, byte count does not

`flat` and `flatcount` are byte-for-byte identical on both pages - `flat`'s two brackets around the attribute run cost exactly what `flatcount`'s count digits cost - yet `flatcount` parses faster: 2.9 ms against 3.3 ms. Identical bytes, different parse time. The difference is one array per element, 9,617 of them on the erlang page, which `flatcount` inlines away.

The same effect explains `pairs`. It allocates one two-element array per attribute - 15,832 on that page - and parses at 3.7 ms against `flat`'s 3.3 ms for 2.5% more bytes. Averaged across the whole matrix the three attribute forms parse at 4.3, 3.7 and 2.8 ms. Array count predicts parse time; uncompressed size does not.

### Interning trades wire size for memory, and hurts gzip

Interning values and text takes the erlang payload from 1,195.8 KB to 496.6 KB and cuts retained heap from 17.4 MB to 12.3 MB. But it deletes exactly the redundancy gzip was already exploiting for free: on `++/2` the gzipped payload goes up, from 42.5 KB to 48.7 KB.

Interning tags and names only (`tn`) is the best of both on the wire, since those dictionaries cost a few hundred bytes and remove tens of kilobytes. It is interning attribute *values* that destroys compressibility.

### The spread stops mattering early

Uncompressed size across all 112 variants ranges from 496.6 KB to 2,052.8 KB; gzipped it ranges from 38.9 KB to 49.0 KB. But once elements are untagged and text is not wrapped, every remaining option costs between 4.4 and 9.1 ms of parse and decode across both pages, against 124 ms today for the erlang page alone.

## Why this format, given the reconciler is about to change

`untagged` `bare` `flat` `none` is not the fastest variant here. `stream` is, at 4.4 ms against 8.4 ms. Four reasons the safer one was taken:

**It assumes nothing about the consumer.** It reproduces the tree exactly, so it serves a consumer that rebuilds boxed terms and one that walks plain literals equally well.

**No dictionary.** Every value in the parsed JSON is immediately usable. A dictionary forces an index-resolution step that has to fit a design that does not exist yet.

**Fixed arity.** `flatcount` is 0.4 ms faster at identical size, but it makes node length vary with attribute count, entangling the vocabulary with the dispatch. "An element is length 3" is worth that.

**It is the cheapest source for the shape the consumer most likely wants.** If the reconciler builds `{class: "big"}` - which `Renderer.#renderAttributesAndProps` already does - a flat run fills it with `for (i += 2) obj[a[i]] = a[i + 1]`, allocating nothing per attribute. `pairs` would allocate 15,832 two-element arrays only to discard them.

It also beats `stream` on the wire: 82.9 KB gzipped against 88.3 KB, so below about 13 Mbps it is the faster choice end to end anyway.

## The flat token stream

Kept here because it is the fastest variant measured and the one to reconsider first when the reconciler changes.

The whole tree becomes one preorder array of integers against four dictionaries:

```text
payload  =  [tags, names, values, texts, tokens]
tokens   =  nRoots, node*

node     =  text | element
text     =  a negative integer n, meaning texts[-1 - n]
element  =  tagIdx, nAttrs, (nameIdx, valIdx) * nAttrs, nChildren, node * nChildren
            valIdx of -1 means a boolean attribute

comment  =  an element whose tagIdx is the reserved " comment" code, always 0 attrs
doctype  =  an element whose tagIdx is the reserved " doctype" code, 0 attrs, 1 text child
```

Worked examples, each verified to decode back to the exact input tree:

```text
{:text, "Hologram"}
  [[],[],[],["Hologram"],[1,-1]]

<br>
  [["br"],[],[],[],[1,0,0,0]]

<p class="lead">Hi</p>
  [["p"],["class"],["lead"],["Hi"],[1,0,1,0,0,1,-1]]

<input disabled>
  [["input"],["disabled"],[],[],[1,0,1,0,-1,0]]

<div class="big" $key="k1:0" hidden>Hologram<!-- x --></div>
  [["div"," comment"],["class","$key","hidden"],["big","k1:0"],["Hologram"," x "],
   [1,0,3,0,0,1,1,2,-1,2,-1,1,0,1,-2]]

<ul><li class="row">a</li><li class="row">a</li></ul>
  [["ul","li"],["class"],["row"],["a"],[1,0,0,2,1,1,0,0,1,-1,1,1,0,0,1,-1]]

<!DOCTYPE html><html><body>hi</body></html>
  [[" doctype","html","body"],[],[],["html","hi"],[2,0,0,1,-1,1,0,1,2,0,1,-2]]
```

Reading the canonical one: `1` root; `0` is tags[0] = `div`; `3` attributes; `0,0` is names[0]=`class` with values[0]=`big`; `1,1` is `$key`=`k1:0`; `2,-1` is `hidden` as a boolean; `2` children; `-1` is texts[0]=`Hologram`; `1,0,1` is the comment with no attributes and one child; `-2` is texts[1]=` x `.

The second `li` in the list example costs six integers and repeats no string at all. That is both why it parses fastest and why it gzips worst.

One defect to fix before adopting it: the reserved codes are dictionary entries named `" comment"` and `" doctype"`. A leading space cannot come from a template, but `render_tree/3`'s `dynamic_tag` clause accepts any binary at runtime, so a computed tag name of exactly `" comment"` would collide. Reserve negative codes instead - comment `-1`, doctype `-2`, text `code <= -3` - for the same parse cost and no collision.

## Appendix A: all 112 variants

Sorted by uncompressed size on the erlang page. Sizes in KB, times in ms. The client column carries allocation noise; see Method.

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
| `untagged-bare-flat-none` | 1,195.8 | 40.4 | 12.7 | 3.3 | 5.2 | 1,219.2 | 42.5 | 3.3 | **chosen** |
| `untagged-bare-object-none` | 1,195.8 | 40.5 | 12.2 | - | - | 1,219.2 | 42.6 | - | lossy |
| `untagged-wrapped-flatcount-tn` | 1,205.0 | 40.4 | 21.7 | 3.6 | 5.7 | 1,207.7 | 42.3 | 3.6 |  |
| `untagged-wrapped-flat-tn` | 1,205.0 | 40.4 | 14.9 | 3.7 | 6.1 | 1,207.7 | 42.2 | 3.7 |  |
| `full-bare-pairs-tn` | 1,217.3 | 40.6 | 15.6 | 3.5 | 5.4 | 1,220.7 | 42.8 | 3.6 |  |
| `untagged-bare-pairs-none` | 1,226.7 | 40.7 | 12.8 | 3.7 | 8.2 | 1,242.2 | 43.0 | 3.7 |  |
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

```text
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
