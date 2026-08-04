"use strict";

import {
  attributesModule,
  eventListenersModule,
  h as vnode,
  init,
} from "snabbdom";

const patch = init([attributesModule, eventListenersModule]);

// Marker text of a block anchor comment, e.g. "[h:1a2b3c:0:o]" - four bracketed segments:
//
//   h       namespace, distinguishing an anchor from an ordinary comment
//   1a2b3c  hash of the template module the block was written in
//   0       index of the block within that template
//   o       side of the pair, "o" opening or "c" closing
//
// The module hash is what keeps keys unique: slot splicing merges nodes from different templates
// into one children list, where bare block indexes would collide.
//
// Anchors bracket a template block so that changing how many nodes the block renders can't shift
// the identity of the block's siblings. The diff pairs keyless children by tag and position, so
// an unbracketed block that starts rendering an extra node lets a sibling be matched against the
// block's content and rebuilt, destroying focus, scroll position and media state.
//
// The marker doubles as the vnode key: keys must survive HTML serialization, since the client
// diffs against a vdom derived from server-rendered markup, and a comment's own text is the only
// carrier that round-trips. Unkeyed anchors would be matched against unrelated comments, which
// desyncs the pairing and reopens the same failure.
const ANCHOR_KEY_REGEX = /^\[h:[a-z0-9]+:\d+:[oc]\]$/;

export default class Vdom {
  static addKeysToVnodes(node) {
    let key;

    switch (node.sel) {
      case "!":
        key = $.anchorKey(node.text);
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
    }
  }

  // Returns the vnode key carried by a block anchor comment's text, or null when the text belongs
  // to an ordinary comment.
  static anchorKey(text) {
    return typeof text === "string" && ANCHOR_KEY_REGEX.test(text)
      ? text
      : null;
  }

  static from(html) {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");

    return Vdom.#buildVnodeFromDomNode(doc.documentElement);
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
      const key = $.anchorKey(node.textContent);

      return key
        ? vnode("!", {key: key}, node.textContent)
        : vnode("!", node.textContent);
    }

    const children = Array.from(node.childNodes).map(
      Vdom.#buildVnodeFromDomNode,
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
}

const $ = Vdom;
