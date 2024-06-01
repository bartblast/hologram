"use strict";

import {h as vnode} from "snabbdom";

export default class Vdom {
  static addKeysToScriptVnodes(node) {
    if (
      node.sel === "script" &&
      node.data?.attrs?.src &&
      typeof node.data.attrs.src === "string"
    ) {
      node.key = `__hologramScript__:${node.data.attrs.src}`;
      node.data.key = node.key;
    }

    if (Array.isArray(node.children)) {
      for (const childNode of node.children) {
        Vdom.addKeysToScriptVnodes(childNode);
      }
    }
  }

  static from(html) {
    const parser = new DOMParser();
    const doc = parser.parseFromString(html, "text/html");

    return Vdom.#buildVnodeFromDomNode(doc.documentElement);
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

    let data;

    if (tagName === "script" && typeof attrs.src === "string") {
      data = {key: `__hologramScript__:${attrs.src}`, attrs: attrs};
    } else {
      data = {attrs: attrs};
    }

    return vnode(tagName, data, children);
  }
}
