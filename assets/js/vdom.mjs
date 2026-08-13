"use strict";

import {
  attributesModule,
  eventListenersModule,
  fragment,
  h as vnode,
  init,
  vnode as rawVnode,
} from "./vendor/snabbdom/build/index.js";

// Fragments let a block occupy exactly one position in its parent's children list however many
// nodes it renders, so its siblings never shift and never get paired with the block's content.
// The flag is opt-in upstream, which is why the library version is pinned exactly.
const patch = init([attributesModule, eventListenersModule], undefined, {
  experimental: {fragments: true},
});

// Text of a block marker comment, e.g. "[h:1a2b3c:0:o]" - four bracketed segments:
//
//   h       namespace, distinguishing a marker from an ordinary comment
//   1a2b3c  hash of the template module the block was written in
//   0       index of the block within that template
//   o       side of the pair, "o" opening or "c" closing
//
// The module hash is what keeps keys unique: slot splicing merges nodes from different templates
// into one children list, where bare block indexes would collide.
//
// Markers bracket a template block so that changing how many nodes the block renders can't shift
// the identity of the block's siblings. The diff pairs keyless children by tag and position, so
// an unbracketed block that starts rendering an extra node lets a sibling be matched against the
// block's content and rebuilt, destroying focus, scroll position and media state.
//
// The marker doubles as the vnode key: keys must survive HTML serialization, since the client
// diffs against a vdom derived from server-rendered markup, and a comment's own text is the only
// carrier that round-trips. Unkeyed markers would be matched against unrelated comments, which
// desyncs the pairing and reopens the same failure.
const MARKER_KEY_REGEX = /^\[h:[a-z0-9]+:\d+:[oc]\]$/;

export default class Vdom {
  static addKeysToVnodes(node) {
    let key;

    switch (node.sel) {
      case "!":
        key = $.markerKey(node.text);
        break;

      case "link":
        if (
          node.data?.attrs?.href &&
          typeof node.data.attrs.href === "string"
        ) {
          key = `__hologramLink__:${node.data.attrs.href}`;
        }
        break;

      case "script":
        if (typeof node.data?.attrs?.src === "string" && node.data.attrs.src) {
          key = `__hologramScript__:${node.data.attrs.src}`;
        } else if (node.textContent) {
          // Make sure the script is executed if the code changes.
          key = `__hologramScript__:${node.textContent}`;
        }
        break;
    }

    if (key) {
      node.key = key;
      node.data.key = key;
    }

    if (Array.isArray(node.children)) {
      for (const childNode of node.children) {
        Vdom.addKeysToVnodes(childNode);
      }

      node.children = $.finalizeChildren(node.children);
    }
  }

  // Numbers repeats of a marker key within one children list, in document order: the second
  // occurrence becomes "<key>:1", the third "<key>:2".
  //
  // A block carries one marker from the compiler, but it can be rendered more than once into the
  // same list - a loop whose body holds a block, or the same component placed twice. Keys have to
  // be unique among siblings, since the diff indexes them by key and a repeat makes it reach for a
  // node it has already consumed.
  //
  // Only the vnode key is renumbered, never the comment's text, so server-rendered and
  // client-rendered markup stay byte-identical. Both sides walk a children list in document order,
  // so both arrive at the same keys.
  static dedupeMarkerKeys(children) {
    const counts = new Map();

    for (const child of children) {
      if (child?.sel !== "!" || !child.key) {
        continue;
      }

      const count = counts.get(child.key) ?? 0;
      counts.set(child.key, count + 1);

      if (count > 0) {
        const dedupedKey = `${child.key}:${count}`;

        child.key = dedupedKey;
        child.data.key = dedupedKey;
      }
    }

    return children;
  }

  // Turns a complete children list into the form the diff works on: repeated marker keys numbered,
  // then each marked span gathered into a fragment.
  //
  // Numbering runs first: a fragment pairs its markers by key, and a repeat's key is only unique
  // once numbered.
  //
  // This runs on the children of one element, never on a part of them, which is what makes the two
  // sides of a diff agree: the keys a repeat gets depend on what else the list holds, and the side
  // read back from server-rendered markup only ever sees whole children lists. Numbering a loop's
  // body on its own would give every iteration the same keys, since a block occurs once in the body
  // however many times the body is rendered.
  static finalizeChildren(children) {
    return $.groupBlockFragments($.dedupeMarkerKeys(children));
  }

  static from(html) {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");

    return Vdom.#buildVnodeFromDomNode(doc.documentElement);
  }

  // Wraps each marked span into a keyed fragment, so a block takes one position in its parent's
  // children list whatever it renders. Positions of the nodes around it then hold still, which is
  // what stops them being paired with the block's own content.
  //
  // The markers stay as the fragment's first and last children, so this models the same nodes the
  // markup has, and both sides of a diff can be built the same way. An open marker with no
  // matching close leaves the list flat - the behaviour from before fragments rather than a broken
  // tree. Interiors are grouped recursively, since blocks nest.
  //
  // The list is only copied once a fragment is actually found: most children lists contain no
  // blocks at all, and this runs on every one of them.
  static groupBlockFragments(children) {
    let grouped = null;
    let index = 0;

    while (index < children.length) {
      const child = children[index];
      const openKey = $.#markerOpenKey(child);

      const closeIndex =
        openKey === null ? -1 : $.#matchingCloseIndex(children, index, openKey);

      if (closeIndex === -1) {
        if (grouped !== null) {
          grouped.push(child);
        }

        index += 1;
        continue;
      }

      if (grouped === null) {
        grouped = children.slice(0, index);
      }

      const interior = $.groupBlockFragments(
        children.slice(index + 1, closeIndex),
      );

      const closingChild = children[closeIndex];

      const blockFragment = fragment([child, ...interior, closingChild]);

      blockFragment.key = openKey;
      blockFragment.data.key = openKey;
      blockFragment.elm = $.#fragmentElm(child, closingChild);

      grouped.push(blockFragment);
      index = closeIndex + 1;
    }

    return grouped ?? children;
  }

  // Returns the vnode key carried by a block marker comment's text, or null when the text belongs
  // to an ordinary comment.
  static markerKey(text) {
    return typeof text === "string" && MARKER_KEY_REGEX.test(text)
      ? text
      : null;
  }

  // Builds the old side of the boot patch: the rendered vdom mirrored onto the live DOM, sel and
  // key copied from the rendered side and elm taken from the page, so the first patch adopts the
  // server-rendered nodes instead of recreating them. The patch then does the rest through its
  // ordinary machinery - attributes are re-set idempotently, event listeners attach, and the
  // rendered side's stylesheet and script keys compare equal by construction, so neither is
  // re-fetched or re-executed.
  //
  // Nodes the render has no counterpart for are mirrored as they really are, children and
  // resource keys included, so the patch aligns and repairs that region on its own terms through
  // the same create, move and remove paths every later patch runs. Repair is not implemented
  // here.
  static mirror(renderedVnode, domNode) {
    return $.#correspondsTo(renderedVnode, domNode)
      ? $.#mirrorNode(renderedVnode, domNode)
      : $.#vnodeOfDomNode(domNode);
  }

  // Covered in feature tests
  static patchVirtualDocument(oldVirtualDocument, newVirtualDocument) {
    const newRootVNode = {
      // Keep the same selector (tag name, id, classes)
      sel: oldVirtualDocument.sel,
      // Update only the attributes
      data: {attrs: newVirtualDocument.data.attrs || {}},
      // Keep the same children
      children: oldVirtualDocument.children,
    };

    // Patch only the root vnode attributes
    const patchedVirtualDocument = patch(oldVirtualDocument, newRootVNode);

    // Then patch head and body separately to preserve JavaScript/CSS handling

    const oldHead = oldVirtualDocument.children.find($.#isHeadVnode);

    const newHead = newVirtualDocument.children.find($.#isHeadVnode);

    const oldBody = oldVirtualDocument.children.find($.#isBodyVnode);

    const newBody = newVirtualDocument.children.find($.#isBodyVnode);

    patchedVirtualDocument.children = oldVirtualDocument.children.map(
      (child) => {
        if ($.#isHeadVnode(child)) {
          return patch(oldHead, newHead);
        } else if ($.#isBodyVnode(child)) {
          return patch(oldBody, newBody);
        } else {
          return child;
        }
      },
    );

    return patchedVirtualDocument;
  }

  static #buildVnodeFromDomNode(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return node.textContent;
    }

    if (node.nodeType === Node.COMMENT_NODE) {
      const key = $.markerKey(node.textContent);

      return key
        ? vnode("!", {key: key}, node.textContent)
        : vnode("!", node.textContent);
    }

    const children = $.finalizeChildren(
      Array.from(node.childNodes).map(Vdom.#buildVnodeFromDomNode),
    );

    const attrs = $.#domNodeAttrs(node);
    const data = {attrs: attrs};
    const key = $.#resourceKey(node, attrs);

    if (key) {
      data.key = key;
    }

    return vnode(node.tagName.toLowerCase(), data, children);
  }

  // An element's attributes in the vdom convention: a valueless attribute reads as true.
  static #domNodeAttrs(domNode) {
    const attrs = {};

    for (const attr of domNode.attributes) {
      attrs[attr.name] = attr.value === "" ? true : attr.value;
    }

    return attrs;
  }

  // The live node a fragment stands for, or undefined when there isn't one.
  //
  // A fragment grouped out of vnodes that already carry live nodes - the boot walk over the
  // server-rendered page - has to stand for the span those nodes occupy, because it is the old
  // side of the first patch and the diff resolves a fragment's real parent through it. A
  // DocumentFragment empties itself once inserted, so the boundary nodes and the parent are
  // recorded on it, which is the same bookkeeping the diff does for fragments it creates itself.
  //
  // Vnodes built from parsed markup carry no live nodes: they are only ever the new side of a
  // patch, where the diff assigns them.
  static #fragmentElm(openingChild, closingChild) {
    if (!openingChild.elm) {
      return undefined;
    }

    const elm = document.createDocumentFragment();

    elm.parent = openingChild.elm.parentNode;
    elm.firstChildNode = openingChild.elm;
    elm.lastChildNode = closingChild.elm;

    return elm;
  }

  // We're checking html element children,
  // so the nodes are either: head element, body element or text (whitespace) nodes
  static #isBodyVnode(vnode) {
    return vnode.sel?.[0] === "b";
  }

  // We're checking html element children,
  // so the nodes are either: head element, body element or text (whitespace) nodes
  static #isHeadVnode(vnode) {
    return vnode.sel?.[0] === "h";
  }

  // The marker text a key was built from, with any number added for a repeat dropped, so that
  // every rendering of one block compares equal.
  static #markerBaseKey(key) {
    return key.slice(0, key.indexOf("]") + 1);
  }

  // The opening side of a marker pair, or null for anything else. Read off the key rather than
  // the comment's text, so a key renumbered for a repeat still pairs with its own closing side.
  static #markerOpenKey(child) {
    return child?.sel === "!" &&
      typeof child.key === "string" &&
      child.key.includes(":o]")
      ? child.key
      : null;
  }

  // The closing side matching the given opening key, or -1.
  //
  // Counts depth rather than taking the first close, because a block can contain itself: a
  // component whose template holds a block that renders the component again, with nothing between
  // them, splices both renderings into one children list, and both carry the block's marker. The
  // numbering that keeps their keys unique runs outwards on the opening sides and inwards on the
  // closing ones, so an opening side cannot find its own close by name either.
  static #matchingCloseIndex(children, openIndex, openKey) {
    const baseOpenKey = $.#markerBaseKey(openKey);
    const baseCloseKey = baseOpenKey.replace(":o]", ":c]");

    let depth = 1;

    for (let index = openIndex + 1; index < children.length; index += 1) {
      const child = children[index];

      if (child?.sel !== "!" || typeof child.key !== "string") {
        continue;
      }

      const baseKey = $.#markerBaseKey(child.key);

      if (baseKey === baseOpenKey) {
        depth += 1;
      } else if (baseKey === baseCloseKey) {
        depth -= 1;

        if (depth === 0) {
          return index;
        }
      }
    }

    return -1;
  }

  // Mirrors a rendered children list against a span of DOM nodes, advancing the shared cursor as
  // nodes are consumed.
  //
  // A fragment shares its parent's DOM level - its children are the parent's real child nodes -
  // so it recurses with the same cursor rather than descending, and is rebuilt around the
  // mirrored span with the same elm bookkeeping the render side gets in groupBlockFragments.
  //
  // Leftover DOM nodes are NOT consumed here: only the element owning the list knows the span is
  // exhausted, so #mirrorNode appends them after this returns.
  static #mirrorChildren(renderedChildren, domNodes, cursor) {
    const mirroredChildren = [];

    for (const renderedChild of renderedChildren) {
      if (
        renderedChild.sel === undefined &&
        Array.isArray(renderedChild.children)
      ) {
        const mirroredKids = $.#mirrorChildren(
          renderedChild.children,
          domNodes,
          cursor,
        );

        const mirroredFragment = fragment(mirroredKids);

        mirroredFragment.key = renderedChild.key;
        mirroredFragment.data.key = renderedChild.key;

        mirroredFragment.elm = $.#fragmentElm(
          mirroredKids[0] ?? {},
          mirroredKids[mirroredKids.length - 1] ?? {},
        );

        mirroredChildren.push(mirroredFragment);
        continue;
      }

      // The render is not always a prefix-by-prefix match for the page: a boot render omits the
      // runtime's own scripts, which the server did emit. So the rendered child takes the first
      // DOM node it can correspond to rather than only the one at the cursor, and the nodes
      // passed over are mirrored as they are, for the patch to match or remove.
      const domIndex = $.#correspondingIndex(renderedChild, domNodes, cursor);

      if (domIndex === -1) {
        // Nothing left this child could be: the patch creates it.
        continue;
      }

      while (cursor.index < domIndex) {
        mirroredChildren.push($.#vnodeOfDomNode(domNodes[cursor.index]));
        cursor.index += 1;
      }

      mirroredChildren.push($.#mirrorNode(renderedChild, domNodes[domIndex]));
      cursor.index = domIndex + 1;
    }

    return mirroredChildren;
  }

  // The old-side vnode for one rendered vnode paired with the DOM node it corresponds to.
  static #mirrorNode(renderedVnode, domNode) {
    // Text is adopted whatever it says: the patch rewrites text in place, which keeps the node,
    // so differing content is not a reason to rebuild.
    if (renderedVnode.sel === undefined) {
      return rawVnode(
        undefined,
        undefined,
        undefined,
        domNode.textContent,
        domNode,
      );
    }

    if (renderedVnode.sel === "!") {
      const data = renderedVnode.key ? {key: renderedVnode.key} : {};

      return rawVnode("!", data, undefined, domNode.textContent, domNode);
    }

    // Attributes are read from the DOM, not copied from the rendered side, so the patch sees what
    // is really there: stale attributes are removed, missing ones added.
    const data = {attrs: $.#domNodeAttrs(domNode)};

    if (renderedVnode.key) {
      data.key = renderedVnode.key;
    }

    const cursor = {index: 0};

    const mirroredChildren = $.#mirrorChildren(
      renderedVnode.children ?? [],
      domNode.childNodes,
      cursor,
    );

    // DOM nodes past the rendered children - third-party insertions or divergence - are mirrored
    // as themselves, so the patch removes them.
    while (cursor.index < domNode.childNodes.length) {
      mirroredChildren.push(
        $.#vnodeOfDomNode(domNode.childNodes[cursor.index]),
      );
      cursor.index += 1;
    }

    return rawVnode(
      renderedVnode.sel,
      data,
      mirroredChildren,
      undefined,
      domNode,
    );
  }

  // Whether a rendered vnode can stand for a DOM node, which is what makes adopting it safe.
  //
  // A resource key names what the element loads, and is the one thing a tag match is not enough
  // for: adopting a script element for a different src would leave the old code running, since a
  // script that has already executed does not run again when its src changes. Keys the DOM cannot
  // carry - a block marker's, a slot's - do not constrain the pairing, being identity rather than
  // content.
  static #correspondsTo(renderedVnode, domNode) {
    if (renderedVnode.sel === undefined) {
      return (
        !Array.isArray(renderedVnode.children) &&
        domNode.nodeType === Node.TEXT_NODE
      );
    }

    if (renderedVnode.sel === "!") {
      return domNode.nodeType === Node.COMMENT_NODE;
    }

    if (
      domNode.nodeType !== Node.ELEMENT_NODE ||
      domNode.tagName.toLowerCase() !== renderedVnode.sel
    ) {
      return false;
    }

    return $.#isResourceKey(renderedVnode.key)
      ? $.#resourceKey(domNode, $.#domNodeAttrs(domNode)) === renderedVnode.key
      : true;
  }

  // The index of the first DOM node from the cursor on that the rendered vnode can stand for, or
  // -1 when there is none left.
  static #correspondingIndex(renderedVnode, domNodes, cursor) {
    for (let index = cursor.index; index < domNodes.length; index += 1) {
      if ($.#correspondsTo(renderedVnode, domNodes[index])) {
        return index;
      }
    }

    return -1;
  }

  static #isResourceKey(key) {
    return (
      typeof key === "string" &&
      (key.startsWith("__hologramLink__:") ||
        key.startsWith("__hologramScript__:"))
    );
  }

  // The key a link or script element carries by what it loads, or null for anything else. Mirrors
  // what the renderer derives for the same element, so the two sides compare equal.
  static #resourceKey(domNode, attrs) {
    const tagName = domNode.tagName.toLowerCase();

    if (tagName === "link" && typeof attrs.href === "string") {
      return `__hologramLink__:${attrs.href}`;
    }

    if (tagName === "script" && typeof attrs.src === "string" && attrs.src) {
      return `__hologramScript__:${attrs.src}`;
    }

    if (tagName === "script" && domNode.textContent) {
      // Make sure the script is executed if the code changes.
      return `__hologramScript__:${domNode.textContent}`;
    }

    return null;
  }

  // A vnode standing for a DOM node on its own terms: its own tag, attributes, children and
  // resource key, with the live node attached. Used wherever the rendered side has no counterpart,
  // so the patch decides what happens to it - matching it by tag or key and keeping it, or
  // removing it. It has to describe the node truthfully, children included: a vnode that claims
  // to be empty makes the patch append content the node already has.
  static #vnodeOfDomNode(domNode) {
    if (domNode.nodeType === Node.TEXT_NODE) {
      return rawVnode(
        undefined,
        undefined,
        undefined,
        domNode.textContent,
        domNode,
      );
    }

    if (domNode.nodeType === Node.COMMENT_NODE) {
      const key = $.markerKey(domNode.textContent);
      const data = key ? {key: key} : {};

      return rawVnode("!", data, undefined, domNode.textContent, domNode);
    }

    const attrs = $.#domNodeAttrs(domNode);
    const data = {attrs: attrs};
    const key = $.#resourceKey(domNode, attrs);

    if (key) {
      data.key = key;
    }

    const children = $.finalizeChildren(
      Array.from(domNode.childNodes).map((childNode) =>
        $.#vnodeOfDomNode(childNode),
      ),
    );

    return rawVnode(
      domNode.tagName.toLowerCase(),
      data,
      children,
      undefined,
      domNode,
    );
  }
}

const $ = Vdom;
