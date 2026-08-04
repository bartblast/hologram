import { Key, VNode, VNodeData } from "./vnode.js";
import { ArrayOrElement } from "./h.js";
import { Props } from "./modules/props.js";
export type JsxVNodeChild = VNode | string | number | boolean | undefined | null;
export type JsxVNodeChildren = ArrayOrElement<JsxVNodeChild>;
export type FunctionComponent = (props: {
    [prop: string]: any;
} | null, children?: VNode[]) => VNode;
export declare function Fragment(data: {
    key?: Key;
} | null, ...children: JsxVNodeChildren[]): VNode;
/**
 * jsx/tsx compatible factory function
 * see: https://www.typescriptlang.org/docs/handbook/jsx.html#factory-functions
 */
export declare function jsx(tag: string | FunctionComponent, data: VNodeData | null, ...children: JsxVNodeChildren[]): VNode;
declare namespace JSXTypes {
    type Element = VNode;
    type ElementProperties<T> = {
        [P in keyof T as T[P] extends string | number | null | undefined ? P : never]?: T[P];
    };
    type HtmlElements = {
        [Property in keyof HTMLElementTagNameMap]: VNodeData<ElementProperties<HTMLElementTagNameMap[Property]> & Props>;
    };
    interface IntrinsicElements extends HtmlElements {
        [elemName: string]: VNodeData;
    }
}
export declare namespace jsx {
    namespace JSX {
        interface IntrinsicElements extends JSXTypes.IntrinsicElements {
        }
    }
}
export {};
