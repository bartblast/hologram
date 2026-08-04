import { VNode } from "../vnode.js";
import { Module } from "./module.js";
type Listener<T> = (this: VNode, ev: T, vnode: VNode) => void;
export type On = {
    [N in keyof HTMLElementEventMap]?: Listener<HTMLElementEventMap[N]> | Array<Listener<HTMLElementEventMap[N]>>;
} & {
    [event: string]: Listener<any> | Array<Listener<any>>;
};
export declare const eventListenersModule: Module;
export {};
