const CAPS_REGEX = /[A-Z]/g;
function updateDataset(oldVnode, vnode) {
    const elm = vnode.elm;
    let oldDataset = oldVnode.data.dataset;
    let dataset = vnode.data.dataset;
    let key;
    if (!oldDataset && !dataset)
        return;
    if (oldDataset === dataset)
        return;
    oldDataset = oldDataset || {};
    dataset = dataset || {};
    const d = elm.dataset;
    for (key in oldDataset) {
        if (!(key in dataset)) {
            if (d) {
                if (key in d) {
                    delete d[key];
                }
            }
            else {
                elm.removeAttribute("data-" + key.replace(CAPS_REGEX, "-$&").toLowerCase());
            }
        }
    }
    for (key in dataset) {
        if (oldDataset[key] !== dataset[key]) {
            if (d) {
                d[key] = dataset[key];
            }
            else {
                elm.setAttribute("data-" + key.replace(CAPS_REGEX, "-$&").toLowerCase(), dataset[key]);
            }
        }
    }
}
export const datasetModule = {
    create: updateDataset,
    update: updateDataset
};
//# sourceMappingURL=dataset.js.map