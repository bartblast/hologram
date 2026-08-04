export interface SnabbdomFragment extends DocumentFragment {
    parent: Node | null;
    firstChildNode: ChildNode | null;
    lastChildNode: ChildNode | null;
}
export interface DOMAPI {
    createElement: (tagName: any, options?: ElementCreationOptions) => HTMLElement;
    createElementNS: (namespaceURI: string, qualifiedName: string, options?: ElementCreationOptions) => Element;
    /**
     * @experimental
     * @todo Make it required when the fragment is considered stable.
     */
    createDocumentFragment?: () => SnabbdomFragment;
    createTextNode: (text: string) => Text;
    createComment: (text: string) => Comment;
    insertBefore: (parentNode: Node, newNode: Node, referenceNode: Node | null) => void;
    removeChild: (node: Node, child: Node) => void;
    appendChild: (node: Node, child: Node) => void;
    parentNode: (node: Node) => Node | null;
    nextSibling: (node: Node) => Node | null;
    tagName: (elm: Element) => string;
    setTextContent: (node: Node, text: string | null) => void;
    getTextContent: (node: Node) => string | null;
    isElement: (node: Node) => node is Element;
    isText: (node: Node) => node is Text;
    isComment: (node: Node) => node is Comment;
    /**
     * @experimental
     * @todo Make it required when the fragment is considered stable.
     */
    isDocumentFragment?: (node: Node) => node is DocumentFragment;
}
export declare const htmlDomApi: DOMAPI;
