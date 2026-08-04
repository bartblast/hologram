import { VNode, VNodeData } from "./vnode.js";
export interface ThunkData extends VNodeData {
    fn: () => VNode;
    args: any[];
}
export interface Thunk extends VNode {
    data: ThunkData;
}
export interface ThunkFn {
    (sel: string, fn: (...args: any[]) => any, args: any[]): Thunk;
    (sel: string, key: any, fn: (...args: any[]) => any, args: any[]): Thunk;
}
export declare const thunk: ThunkFn;
