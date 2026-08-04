import { Module } from "./modules/module.js";
import { VNode } from "./vnode.js";
import { DOMAPI } from "./htmldomapi.js";
export type Options = {
    experimental?: {
        fragments?: boolean;
    };
};
export declare function init(modules: Array<Partial<Module>>, domApi?: DOMAPI, options?: Options): (oldVnode: VNode | Element | DocumentFragment, vnode: VNode) => VNode;
