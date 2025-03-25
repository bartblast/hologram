"use strict";

import {
  attributesModule,
  eventListenersModule,
  h as vnode,
  init,
} from "snabbdom";

const patch = init([attributesModule, eventListenersModule]);

export default class Vdom {
  static addKeysToLinkAndScriptVnodes(node) {
    let key;

    switch (node.sel) {
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
        Vdom.addKeysToLinkAndScriptVnodes(childNode);
      }
    }
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

    const oldHead = oldVirtualDocument.children.find(
      (child) => child.sel === "head",
    );

    const newHead = newVirtualDocument.children.find(
      (child) => child.sel === "head",
    );

    const oldBody = oldVirtualDocument.children.find(
      (child) => child.sel === "body",
    );

    const newBody = newVirtualDocument.children.find(
      (child) => child.sel === "body",
    );

    patchedVirtualDocument.children = oldVirtualDocument.children.map(
      (child) => {
        switch (child.sel) {
          case "body":
            return patch(oldBody, newBody);

          case "head":
            return patch(oldHead, newHead);

          default:
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
      return vnode("!", node.textContent);
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
}
