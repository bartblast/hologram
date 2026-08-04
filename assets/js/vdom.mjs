"use strict";

import {
  attributesModule,
  eventListenersModule,
  fragment,
  h as vnode,
  init,
} from "snabbdom";

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

      node.children = $.groupBlockFragments($.dedupeMarkerKeys(node.children));
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

    const children = $.groupBlockFragments(
      $.dedupeMarkerKeys(
        Array.from(node.childNodes).map(Vdom.#buildVnodeFromDomNode),
      ),
    );

    const attrs = {};

    for (let attr of node.attributes) {
      attrs[attr.name] = attr.value === "" ? true : attr.value;
    }

    const tagName = node.tagName.toLowerCase();
    const data = {attrs: attrs};

    if (tagName === "link" && typeof attrs.href === "string") {
      data.key = `__hologramLink__:${attrs.href}`;
    } else if (
      tagName === "script" &&
      typeof attrs.src === "string" &&
      attrs.src
    ) {
      data.key = `__hologramScript__:${attrs.src}`;
    } else if (tagName === "script" && node.textContent) {
      // Make sure the script is executed if the code changes.
      data.key = `__hologramScript__:${node.textContent}`;
    }

    return vnode(tagName, data, children);
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

  // The opening side of a marker pair, or null for anything else. Read off the key rather than
  // the comment's text, so a key renumbered for a repeat still pairs with its own closing side.
  static #markerOpenKey(child) {
    return child?.sel === "!" &&
      typeof child.key === "string" &&
      child.key.includes(":o]")
      ? child.key
      : null;
  }

  // The closing side matching the given opening key, or -1. A block never contains itself and
  // repeats are renumbered before this runs, so the first key match is the right one.
  static #matchingCloseIndex(children, openIndex, openKey) {
    const closeKey = openKey.replace(":o]", ":c]");

    for (let index = openIndex + 1; index < children.length; index += 1) {
      const child = children[index];

      if (child?.sel === "!" && child.key === closeKey) {
        return index;
      }
    }

    return -1;
  }
}

const $ = Vdom;
