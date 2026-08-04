/* eslint-disable @typescript-eslint/no-namespace */
import { vnode } from "./vnode.js";
import { h } from "./h.js";
export function Fragment(data, ...children) {
    const flatChildren = flattenAndFilter(children, []);
    if (flatChildren.length === 1 &&
        !flatChildren[0].sel &&
        flatChildren[0].text) {
        // only child is a simple text node, pass as text for a simpler vtree
        return vnode(undefined, undefined, undefined, flatChildren[0].text, undefined);
    }
    else {
        return vnode(undefined, data !== null && data !== void 0 ? data : {}, flatChildren, undefined, undefined);
    }
}
function flattenAndFilter(children, flattened) {
    for (const child of children) {
        // filter out falsey children, except 0 since zero can be a valid value e.g inside a chart
        if (child !== undefined &&
            child !== null &&
            child !== false &&
            child !== "") {
            if (Array.isArray(child)) {
                flattenAndFilter(child, flattened);
            }
            else if (typeof child === "string" ||
                typeof child === "number" ||
                typeof child === "boolean") {
                flattened.push(vnode(undefined, undefined, undefined, String(child), undefined));
            }
            else {
                flattened.push(child);
            }
        }
    }
    return flattened;
}
/**
 * jsx/tsx compatible factory function
 * see: https://www.typescriptlang.org/docs/handbook/jsx.html#factory-functions
 */
export function jsx(tag, data, ...children) {
    const flatChildren = flattenAndFilter(children, []);
    if (typeof tag === "function") {
        // tag is a function component
        return tag(data, flatChildren);
    }
    else {
        if (flatChildren.length === 1 &&
            !flatChildren[0].sel &&
            flatChildren[0].text) {
            // only child is a simple text node, pass as text for a simpler vtree
            return h(tag, data, flatChildren[0].text);
        }
        else {
            return h(tag, data, flatChildren);
        }
    }
}
//# sourceMappingURL=jsx.js.map
