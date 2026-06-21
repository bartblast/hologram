"use strict";

const DOCUMENT_POSITION_PRECEDING = 2;
const DOCUMENT_POSITION_FOLLOWING = 4;

export default class DomSelection {
  static buildDomSelection(root, selection = window.getSelection?.()) {
    if (!root || !selection || selection.rangeCount === 0) {
      return null;
    }

    const {anchorNode, anchorOffset, focusNode, focusOffset} = selection;

    if (!$.contains(root, anchorNode) || !$.contains(root, focusNode)) {
      return null;
    }

    const anchorPath = $.nodePath(root, anchorNode);
    const focusPath = $.nodePath(root, focusNode);

    if (anchorPath === null || focusPath === null) {
      return null;
    }

    return {
      anchorPath,
      anchorOffset,
      focusPath,
      focusOffset,
      direction: $.direction(selection),
      value: selection.toString(),
    };
  }

  static buildTextControlSelection(element) {
    if (!$.isTextControl(element)) {
      return null;
    }

    const selectionStart = $.readSelectionNumber(element, "selectionStart");
    const selectionEnd = $.readSelectionNumber(element, "selectionEnd");

    if (selectionStart === null || selectionEnd === null) {
      return null;
    }

    return {
      selectionStart,
      selectionEnd,
      selectionDirection: $.readSelectionDirection(element),
    };
  }

  static contains(root, node) {
    return !!root && !!node && (root === node || root.contains(node));
  }

  static direction(selection) {
    if (selection.isCollapsed) {
      return "none";
    }

    const {anchorNode, anchorOffset, focusNode, focusOffset} = selection;

    if (anchorNode === focusNode) {
      return anchorOffset <= focusOffset ? "forward" : "backward";
    }

    const position = anchorNode.compareDocumentPosition(focusNode);

    if (position & DOCUMENT_POSITION_FOLLOWING) {
      return "forward";
    }

    if (position & DOCUMENT_POSITION_PRECEDING) {
      return "backward";
    }

    return "none";
  }

  static isTextControl(element) {
    return (
      !!element &&
      (element.tagName === "INPUT" || element.tagName === "TEXTAREA") &&
      typeof element.value === "string"
    );
  }

  static nodeFromPath(root, path) {
    if (!root || !Array.isArray(path)) {
      return null;
    }

    let node = root;

    for (const index of path) {
      node = node.childNodes[index];

      if (!node) {
        return null;
      }
    }

    return node;
  }

  static nodePath(root, node) {
    if (!$.contains(root, node)) {
      return null;
    }

    const path = [];
    let current = node;

    while (current !== root) {
      const parent = current.parentNode;

      if (!parent) {
        return null;
      }

      path.unshift(Array.prototype.indexOf.call(parent.childNodes, current));
      current = parent;
    }

    return path;
  }

  static readSelectionDirection(element) {
    try {
      return typeof element.selectionDirection === "string"
        ? element.selectionDirection
        : "none";
    } catch {
      return "none";
    }
  }

  static readSelectionNumber(element, property) {
    try {
      const value = element[property];
      return Number.isInteger(value) ? value : null;
    } catch {
      return null;
    }
  }

  static restoreDomSelection(root, domSelection) {
    const selection = window.getSelection?.();

    if (!selection) {
      return false;
    }

    const anchorNode = $.nodeFromPath(root, domSelection.anchorPath);
    const focusNode = $.nodeFromPath(root, domSelection.focusPath);

    if (!anchorNode || !focusNode) {
      return false;
    }

    root.focus?.();
    selection.removeAllRanges();

    if (typeof selection.setBaseAndExtent === "function") {
      try {
        selection.setBaseAndExtent(
          anchorNode,
          domSelection.anchorOffset,
          focusNode,
          domSelection.focusOffset,
        );
        return true;
      } catch {
        return false;
      }
    }

    const range = document.createRange();

    try {
      range.setStart(anchorNode, domSelection.anchorOffset);
      range.setEnd(focusNode, domSelection.focusOffset);
    } catch {
      try {
        range.setStart(focusNode, domSelection.focusOffset);
        range.setEnd(anchorNode, domSelection.anchorOffset);
      } catch {
        return false;
      }
    }

    selection.addRange(range);
    return true;
  }
}

const $ = DomSelection;
