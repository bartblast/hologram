"use strict";

import {
  attributesModule,
  eventListenersModule,
  init,
  vnode as rawVnode,
} from "./vendor/snabbdom/build/index.js";

const patch = init([attributesModule, eventListenersModule]);

export default class Vdom {
  // Numbers repeats of a key within one children list, in document order: the second occurrence
  // becomes "<key>:1", the third "<key>:2".
  //
  // A key names a place in a template, and one place can be rendered into the same list more than
  // once - a loop's body, or the same component placed twice. Keys have to be unique among
  // siblings, since the diff indexes them by key and a repeat makes it reach for a node it has
  // already consumed.
  //
  // Every kind of key is numbered by the same rule, since every kind can repeat: the key an
  // element carries for its place, and the href or src a resource is named by.
  //
  // Only the vnode key is renumbered, never anything in the markup, so server-rendered and
  // client-rendered pages stay byte-identical. Both sides walk a children list in document order,
  // so both arrive at the same keys.
  static dedupeKeys(children) {
    // Nothing can repeat on its own, and a children list of one is the common case.
    if (children.length < 2) {
      return children;
    }

    const counts = new Map();

    for (const child of children) {
      if (!child?.key) {
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

  // Turns a complete children list into the form the diff works on: repeated keys numbered.
  //
  // This runs on the children of one element, never on a part of them: the keys a repeat gets
  // depend on what else the list holds, so numbering a loop's body on its own would give every
  // iteration the same keys, a block occurring once in the body however many times the body is
  // rendered.
  static finalizeChildren(children) {
    return $.dedupeKeys(children);
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

  // An element's attributes in the vdom convention: a valueless attribute reads as true.
  static #domNodeAttrs(domNode) {
    const attrs = {};

    for (const attr of domNode.attributes) {
      attrs[attr.name] = attr.value === "" ? true : attr.value;
    }

    return attrs;
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

  // Mirrors a rendered children list against a span of DOM nodes, advancing the shared cursor as
  // nodes are consumed.
  //
  // Leftover DOM nodes are NOT consumed here: only the element owning the list knows the span is
  // exhausted, so #mirrorNode appends them after this returns.
  static #mirrorChildren(renderedChildren, domNodes, cursor) {
    const mirroredChildren = [];

    for (const renderedChild of renderedChildren) {
      // The render is not always a prefix-by-prefix match for the page: a boot render omits the
      // runtime's own scripts, which the server did emit. So an element takes the first DOM node
      // it can correspond to rather than only the one at the cursor, and the nodes passed over are
      // mirrored as they are, for the patch to match or remove.
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
  // script that has already executed does not run again when its src changes. The key an element
  // carries for its place, which the DOM never held, does not constrain the pairing - it is
  // identity rather than content.
  //
  // Case is dropped on both sides. An HTML tag name has no case - the DOM reads it back uppercase
  // whatever the markup wrote - while an SVG or MathML one keeps the case the spec gives it, and
  // the parser corrects the markup's spelling to that. So the two sides can disagree on case
  // alone, and case is the only thing being ignored: no two elements differ by it.
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
      domNode.tagName.toLowerCase() !== renderedVnode.sel.toLowerCase()
    ) {
      return false;
    }

    return $.#isResourceKey(renderedVnode.key)
      ? $.#resourceKey(domNode, $.#domNodeAttrs(domNode)) === renderedVnode.key
      : true;
  }

  // The index of the first DOM node from the cursor on that the rendered vnode can stand for, or
  // -1 when there is none left.
  //
  // Only an element looks past the cursor. An element names what it is, so the nodes it steps over
  // are ones the render genuinely does not have. Text and comments name nothing - any text node
  // stands for any other - so one that looked ahead would claim a node further along and orphan
  // every element in between, which the patch would then rebuild.
  //
  // The root is where that is guaranteed rather than incidental: the parser puts the whitespace
  // between </head> and <body> inside <html>, so the rendered text that precedes <head> finds its
  // counterpart only after it, and a scanning text vnode would pass over the entire head.
  static #correspondingIndex(renderedVnode, domNodes, cursor) {
    if (renderedVnode.sel === undefined || renderedVnode.sel === "!") {
      return cursor.index < domNodes.length &&
        $.#correspondsTo(renderedVnode, domNodes[cursor.index])
        ? cursor.index
        : -1;
    }

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
      return rawVnode("!", {}, undefined, domNode.textContent, domNode);
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
