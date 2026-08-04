import { VNode, VNodeData } from "./vnode.js";
export type VNodes = VNode[];
export type VNodeChildElement = VNode | string | number | String | Number | undefined | null;
export type ArrayOrElement<T> = T | T[];
export type VNodeChildren = ArrayOrElement<VNodeChildElement>;
export declare function addNS(data: any, children: Array<VNode | string> | undefined, sel: string | undefined): void;
export declare function h(sel: string): VNode;
export declare function h(sel: string, data: VNodeData | null): VNode;
export declare function h(sel: string, children: VNodeChildren): VNode;
export declare function h(sel: string, data: VNodeData | null, children: VNodeChildren): VNode;
/**
 * @experimental
 */
export declare function fragment(children: VNodeChildren): VNode;
