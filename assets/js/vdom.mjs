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
  //
  // The children of <head> and <body> are the exception, since other tools add to them: a dev
  // toolbar's meta and script, a browser extension's nodes, wherever they please. There an element
  // enters the vdom only when the render has an element just like it (see #claimChildNodes), and
  // one that doesn't is left out, so no patch ever removes or moves it. That takes a render of the
  // same state the page was served with - a render from other state would leave Hologram's own
  // elements out wherever the state shows in their attributes.
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

  // Which child nodes of a <head> or <body> are Hologram's: the elements the rendered children
  // claim, each paired with the rendered element that claimed it, and every text and comment node.
  //
  // An element is claimed by a rendered element that matches it exactly (see #matchesExactly), each
  // rendered element taking the first one after the element the previous one took, so a tag another
  // tool put before Hologram's, of the same kind, is not taken for it. A rendered element that finds
  // none claims nothing, and the patch creates it.
  //
  // Text and comments say nothing about where they came from - any whitespace looks like any other
  // - so they stay Hologram's, as everywhere else. Tools add elements, not loose text.
  static #claimChildNodes(renderedChildren, domNode) {
    const childNodes = Array.from(domNode.childNodes);
    const claims = new Map();
    const claimedNodes = new Set();
    let searchIndex = 0;

    for (const renderedChild of renderedChildren) {
      if (renderedChild.sel === undefined || renderedChild.sel === "!") {
        continue;
      }

      for (let index = searchIndex; index < childNodes.length; index += 1) {
        if ($.#matchesExactly(renderedChild, childNodes[index])) {
          claims.set(renderedChild, childNodes[index]);
          claimedNodes.add(childNodes[index]);
          searchIndex = index + 1;
          break;
        }
      }
    }

    const domNodes = childNodes.filter(
      (childNode) =>
        childNode.nodeType !== Node.ELEMENT_NODE || claimedNodes.has(childNode),
    );

    return {claims, domNodes};
  }

  // The attributes of a rendered element or of the DOM node it stands for, in the form the two are
  // compared in: names in lowercase, since the parser lowercases an HTML attribute name the template
  // may spell otherwise, and without what the DOM doesn't report the way the render holds it. The
  // browser hides a nonce once the element is in the document, and the render keeps a form
  // control's value and checked state out of its attributes (see Renderer).
  static #comparableAttrs(attrs, renderedVnode) {
    const hasControlledValue =
      renderedVnode.data?.hologramFormInputValue !== undefined;

    const hasControlledChecked =
      renderedVnode.data?.hologramFormInputChecked !== undefined;

    const comparableAttrs = new Map();

    for (const [name, value] of Object.entries(attrs)) {
      const lowercaseName = name.toLowerCase();

      if (
        lowercaseName === "nonce" ||
        (hasControlledValue && lowercaseName === "value") ||
        (hasControlledChecked && lowercaseName === "checked")
      ) {
        continue;
      }

      comparableAttrs.set(lowercaseName, value);
    }

    return comparableAttrs;
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
  // In <head> and <body> an element is paired with the node it claimed, and with nothing when it
  // claimed none (see #claimChildNodes): pairing by tag there would hand it a node another element
  // claimed.
  //
  // Leftover DOM nodes are NOT consumed here: only the element owning the list knows the span is
  // exhausted, so #mirrorNode appends them after this returns.
  static #mirrorChildren(renderedChildren, domNodes, cursor, claims = null) {
    const mirroredChildren = [];

    for (const renderedChild of renderedChildren) {
      // The render is not always a prefix-by-prefix match for the page: a boot render omits the
      // runtime's own scripts, which the server did emit. So an element takes the first DOM node
      // it can correspond to rather than only the one at the cursor, and the nodes passed over are
      // mirrored as they are, for the patch to match or remove.
      const domIndex =
        claims !== null &&
        renderedChild.sel !== undefined &&
        renderedChild.sel !== "!"
          ? domNodes.indexOf(claims.get(renderedChild))
          : $.#correspondingIndex(renderedChild, domNodes, cursor);

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

    const renderedChildren = renderedVnode.children ?? [];

    // In <head> and <body> only Hologram's own nodes are mirrored (see mirror()).
    const {claims, domNodes} =
      domNode.localName === "head" || domNode.localName === "body"
        ? $.#claimChildNodes(renderedChildren, domNode)
        : {claims: null, domNodes: domNode.childNodes};

    const cursor = {index: 0};

    const mirroredChildren = $.#mirrorChildren(
      renderedChildren,
      domNodes,
      cursor,
      claims,
    );

    // DOM nodes past the rendered children - divergence, or nodes another tool added below <head>
    // and <body> - are mirrored as themselves, so the patch removes them. In <head> and <body>
    // themselves only Hologram's text and comments can be left over here.
    while (cursor.index < domNodes.length) {
      mirroredChildren.push($.#vnodeOfDomNode(domNodes[cursor.index]));
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

  // Whether a DOM node is exactly what a rendered element renders to, as far as one element goes.
  //
  // A link or script is told by its resource key alone - what it loads, or a script's code - since
  // one loading the same thing is the same element, and a script can change its own attributes
  // before the first render, like a stylesheet loaded with media="print" that switches itself on.
  // Pairing that one with a new copy would load the stylesheet twice, or run the script again.
  //
  // Anything else needs the same tag, the same attributes and, for a <style>, the same text. A
  // <style> has no attributes as a rule, and one a polyfill adds would otherwise pass for the
  // layout's.
  static #matchesExactly(renderedVnode, domNode) {
    if (
      domNode.nodeType !== Node.ELEMENT_NODE ||
      !$.#correspondsTo(renderedVnode, domNode)
    ) {
      return false;
    }

    if ($.#isResourceKey(renderedVnode.key)) {
      return true;
    }

    const renderedAttrs = $.#comparableAttrs(
      renderedVnode.data?.attrs ?? {},
      renderedVnode,
    );

    const domAttrs = $.#comparableAttrs(
      $.#domNodeAttrs(domNode),
      renderedVnode,
    );

    if (renderedAttrs.size !== domAttrs.size) {
      return false;
    }

    for (const [name, value] of renderedAttrs) {
      if (domAttrs.get(name) !== value) {
        return false;
      }
    }

    return (
      domNode.localName !== "style" ||
      $.#renderedText(renderedVnode) === domNode.textContent
    );
  }

  static #isResourceKey(key) {
    return (
      typeof key === "string" &&
      (key.startsWith("__hologramLink__:") ||
        key.startsWith("__hologramScript__:"))
    );
  }

  // The text of a rendered element's children, the way the DOM reads it back as textContent.
  static #renderedText(renderedVnode) {
    return (renderedVnode.children ?? [])
      .map((child) =>
        child.sel === undefined ? (child.text ?? "") : $.#renderedText(child),
      )
      .join("");
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
  //
  // The tag is named the way its namespace spells it - localName is lowercase for HTML, whose tag
  // names have no case, and verbatim for SVG and MathML, whose do. Lowercasing everything would
  // name an element that does not exist.
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

    return rawVnode(domNode.localName, data, children, undefined, domNode);
  }
}

const $ = Vdom;
