import { Module } from "./module.js";
type ElementStyle = {
    [K in keyof CSSStyleDeclaration]?: string;
};
interface InnerStyle extends ElementStyle {
    [K: string]: string | undefined;
}
export interface VNodeStyle extends ElementStyle {
    delayed?: InnerStyle;
    remove?: InnerStyle;
    [K: string]: InnerStyle | string | undefined;
}
export declare const styleModule: Module;
export {};
