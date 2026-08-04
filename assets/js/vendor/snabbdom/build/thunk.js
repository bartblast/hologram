import { h, addNS } from "./h.js";
function copyToThunk(vnode, thunk) {
    var _a;
    const ns = (_a = thunk.data) === null || _a === void 0 ? void 0 : _a.ns;
    vnode.data.fn = thunk.data.fn;
    vnode.data.args = thunk.data.args;
    thunk.data = vnode.data;
    thunk.children = vnode.children;
    thunk.text = vnode.text;
    thunk.elm = vnode.elm;
    if (ns)
        addNS(thunk.data, thunk.children, thunk.sel);
}
function init(thunk) {
    const cur = thunk.data;
    const vnode = cur.fn(...cur.args);
    copyToThunk(vnode, thunk);
}
function prepatch(oldVnode, thunk) {
    let i;
    const old = oldVnode.data;
    const cur = thunk.data;
    const oldArgs = old.args;
    const args = cur.args;
    if (old.fn !== cur.fn || oldArgs.length !== args.length) {
        copyToThunk(cur.fn(...args), thunk);
        return;
    }
    for (i = 0; i < args.length; ++i) {
        if (oldArgs[i] !== args[i]) {
            copyToThunk(cur.fn(...args), thunk);
            return;
        }
    }
    copyToThunk(oldVnode, thunk);
}
export const thunk = function thunk(sel, key, fn, args) {
    if (args === undefined) {
        args = fn;
        fn = key;
        key = undefined;
    }
    return h(sel, {
        key: key,
        hook: { init, prepatch },
        fn: fn,
        args: args
    });
};
//# sourceMappingURL=thunk.js.map
