// Based on Elixir Hologram.Template.Renderer

"use strict";

import Bitstring from "./bitstring.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Debouncer from "./debouncer.mjs";
import EventListeners from "./event_listeners.mjs";
import FocusEvent from "./events/focus_event.mjs";
import Hologram from "./hologram.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import Identifier from "./identifier.mjs";
import Interpreter from "./interpreter.mjs";
import KeyboardEvent from "./events/keyboard_event.mjs";
import Once from "./once.mjs";
import Operation from "./operation.mjs";
import StringOrder from "./string_order.mjs";
import Throttler from "./throttler.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";
import Vdom, {TRUSTED_HTML_SEL} from "./vdom.mjs";

import {h as vnode} from "./vendor/snabbdom/build/index.js";
import vnodeToHtml from "snabbdom-to-html";

// The drop effects a $data_transfer drop_effect takes.
//
// WARNING: must match Hologram.Template.DataTransfer.drop_effects/0.
const DROP_EFFECTS = ["none", "copy", "move", "link"];

// An element ref and an Elixir reference are both called a ref, so a reference passed as one gets
// this hint.
//
// WARNING: must match @elixir_reference_hint in Hologram.Template.Renderer, and the copy in
// Elixir_Hologram_JS (elixir/hologram/js.mjs).
const ELIXIR_REFERENCE_HINT =
  "an element ref is an identifier, not an Elixir reference";

// WARNING: must match @ref_expectation in Hologram.Template.Renderer.
const REF_EXPECTATION =
  "$ref takes an identifier, like :search or {:message, 42}";

// The characters a value cannot carry into a script element as the text of a JavaScript string
// literal, each with the escape sequence it is written as instead. Every sequence is valid inside
// all three kinds of literal - double-quoted, single-quoted and template - and reads back as the
// character it stands for, so the value arrives unchanged whichever quotes the template wrote
// around it.
//
//   \    would eat the character after it
//   "    '    `    would close the literal
//   $    would open an expression inside a template literal
//   \n   and \r are not allowed inside a literal at all
//   NUL  is rewritten to U+FFFD by the HTML parser inside script data
//   <    so that "</script" can never form in a page's inline script
//
// WARNING: must match @script_text_escapes in Hologram.Template.Renderer. The text the two sides
// put inside a script element has to be identical, or the boot patch rebuilds the element
// instead of adopting it, and the script runs twice.
const SCRIPT_TEXT_ESCAPES = {
  "\\": "\\\\",
  '"': '\\"',
  "'": "\\'",
  "`": "\\`",
  $: "\\$",
  "\n": "\\n",
  "\r": "\\r",
  "\0": "\\u{0}",
  "<": "\\u{3C}",
};

// One character class over the keys above, so the replace is a single pass.
const SCRIPT_TEXT_ESCAPABLE_CHARS = /[\\"'`$\n\r\0<]/g;

// The characters a value cannot carry into a style element as the text of a CSS string literal,
// each with the escape sequence it is written as instead. Every sequence is valid inside both
// kinds of literal - double-quoted and single-quoted - and reads back as the character it stands
// for, so the value arrives unchanged whichever quotes the template wrote around it.
//
//   \    would eat the character after it
//   "    '    would close the literal
//   \n   \r and \f are not allowed inside a literal at all - CSS preprocessing folds CR
//        and FF into LF before tokenizing, so a form feed breaks a string as a newline does
//   NUL  is rewritten to U+FFFD by the CSS tokenizer, so it cannot travel as itself
//   <    so that "</style" can never form in a page's inline stylesheet
//
// ">" and "&" are absent on purpose: neither can end a raw text element, and writing ">" as an
// escape would break a child combinator in an interpolated selector.
//
// A hex escape is six digits long, so a hex digit following it in the value is never absorbed
// into it, and it ends with a space of its own: the CSS tokenizer consumes one whitespace
// character after an escape, and that space is there to be the one it eats. DO NOT trim it - a
// space that was in the value would be swallowed in its place.
//
// WARNING: must match @style_text_escapes in Hologram.Template.Renderer. The text the two sides
// put inside a style element has to be identical, or the boot patch rewrites it.
const STYLE_TEXT_ESCAPES = {
  "\\": "\\\\",
  '"': '\\"',
  "'": "\\'",
  "\n": "\\00000A ",
  "\r": "\\00000D ",
  "\f": "\\00000C ",
  "\0": "\\00FFFD ",
  "<": "\\00003C ",
};

// One character class over the keys above, so the replace is a single pass.
const STYLE_TEXT_ESCAPABLE_CHARS = /[\\"'\n\r\f\0<]/g;

// The tag names whose case the HTML parser restores inside <svg>. Everywhere else a tag name has
// no case at all: the tokenizer lowercases it before anything else sees it, and only these names
// are given their spelling back.
//
// Reached only for a tag name that comes from a value, since a name written in a template is
// spelled by the compiler instead.
//
// WARNING: must match @svg_adjusted_tag_names in Hologram.Template.Helpers. The two sides have to
// spell an element the same way, or the boot patch rebuilds it instead of adopting it.
//
// See: https://html.spec.whatwg.org/multipage/parsing.html#adjust-svg-tag-name
const SVG_ADJUSTED_TAG_NAMES = {
  altglyph: "altGlyph",
  altglyphdef: "altGlyphDef",
  altglyphitem: "altGlyphItem",
  animatecolor: "animateColor",
  animatemotion: "animateMotion",
  animatetransform: "animateTransform",
  clippath: "clipPath",
  feblend: "feBlend",
  fecolormatrix: "feColorMatrix",
  fecomponenttransfer: "feComponentTransfer",
  fecomposite: "feComposite",
  feconvolvematrix: "feConvolveMatrix",
  fediffuselighting: "feDiffuseLighting",
  fedisplacementmap: "feDisplacementMap",
  fedistantlight: "feDistantLight",
  feflood: "feFlood",
  fefunca: "feFuncA",
  fefuncb: "feFuncB",
  fefuncg: "feFuncG",
  fefuncr: "feFuncR",
  fegaussianblur: "feGaussianBlur",
  feimage: "feImage",
  femerge: "feMerge",
  femergenode: "feMergeNode",
  femorphology: "feMorphology",
  feoffset: "feOffset",
  fepointlight: "fePointLight",
  fespecularlighting: "feSpecularLighting",
  fespotlight: "feSpotLight",
  fetile: "feTile",
  feturbulence: "feTurbulence",
  foreignobject: "foreignObject",
  glyphref: "glyphRef",
  lineargradient: "linearGradient",
  radialgradient: "radialGradient",
  textpath: "textPath",
};

// The elements trusted HTML can't be interpolated in: the HTML parser reads their content as text.
//
// WARNING: must match @trusted_html_refused_parents in Hologram.Template.Renderer.
const TRUSTED_HTML_REFUSED_PARENTS = new Set([
  "iframe",
  "noembed",
  "noframes",
  "noscript",
  "plaintext",
  "script",
  "style",
  "textarea",
  "title",
  "xmp",
]);

export default class Renderer {
  // Capture-phase drag listeners collected during the current render: an element's is a
  // {vnode, eventName, handler}, since its live DOM node exists only after the patch, and a
  // <window>/<document> tag's is a {target, eventName, handler, dropSlots}, where dropSlots holds the
  // slot key and once flag of each of the tag's enabled $drop bindings. They run as the event travels
  // down from the window to the element, before any event binding on its path. They are kept apart
  // from listenerBindings, whose positional slot keys must not shift when a $drop binding is enabled
  // or disabled. resolveDragBindings turns them into registry bindings after the patch, and
  // renderPage() resets this.
  static dragBindings = [];

  // Event listener bindings collected during the current render, each a {target, key, attach,
  // handler} descriptor (see EventListenerRegistry). A <window> or <document> tag pushes here (with
  // the window or document target) instead of producing a vnode. renderPage() resets this, and the
  // render loop drains it after patching to reconcile real listeners on each binding's target.
  static listenerBindings = [];

  // Deferred reach (scroll-edge) bindings collected during the current render, each a
  // {vnode, edge, handler, within}. The listener reads the container's own scroll metrics, a live
  // DOM node Snabbdom sets on the vnode only during patch, so the binding is held here until
  // resolveReachBindings turns it into a registry binding once `.elm` exists. renderPage() resets
  // this.
  static reachBindings = [];

  // The refs collected during the current render, each a {ref, module, vnode} under the ref's
  // encoded map key, where module is the one whose template wrote the element. The vnode is set
  // once the element's vnode exists, and resolveRefBindings reads its live element after the patch.
  // renderPage() resets this.
  static refBindings = new Map();

  // Deferred resize-observer bindings collected during the current render, each a {vnode, handler}.
  // An element's observer target is its live DOM node, which Snabbdom sets on the vnode only during
  // patch, so the binding is held here until resolveResizeBindings turns it into a registry binding
  // once `.elm` exists. renderPage() resets this.
  static resizeBindings = [];

  // Elements this patch asked to take focus, and elements it asked to give focus up, in hook
  // order. The hooks only collect: which element takes focus is settled once per patch by
  // settleFocus(), after it, when every candidate is in the document and the document order
  // between an inserted element and an updated one can be read. Whoever patches resets both
  // first: Hologram.render(), and the interim patch of a navigation.
  static focusCandidates = [];
  static blurCandidates = [];

  // Set around a patch that puts a page on screen: a navigation's interim patch, or the mount's
  // first render when no interim patch came before it (a history restore). A page that appears is
  // a page load however the diff reused its nodes, so every element it declares focused is a
  // candidate, not only one whose declaration changed. settleFocus() clears it.
  static isPageArrival = false;

  // Based on Elixir Renderer.encode_tree/1, which it inverts clause for clause.
  //
  // The payload arrives already parsed out of the response body, so this is not a parse: it is
  // the walk that turns plain JavaScript values into the boxed terms renderDom was built to
  // consume. A node's shape says what it is - an element is the only node of length 3, a comment,
  // a doctype and trusted HTML are length 2, and text is a bare string.
  //
  // TODO: delete this once the vdom renderer walks plain JavaScript literals instead of boxed
  // terms. It exists only to bridge the wire form to renderDom, and renderDom then walks what it
  // builds a second time to produce vnodes - two passes and 13.6 MB of boxed terms on the largest
  // page measured, all of which a reconciler reading the payload directly would skip.
  // See: docs/navigation_payload_wire_format.md
  static decodeTree(tree) {
    return Type.list(tree.map(Renderer.#decodeNode));
  }

  // Based on render_tree/3
  //
  // WARNING: on navigation the server ships this client the same render as an evaluated tree
  // (Renderer.render_tree/3), and the vnodes built from that tree must equal the vnodes this
  // renderer builds for the page's own render - otherwise hydration rebuilds nodes instead of
  // adopting them. Every normalization step here must therefore match render_tree/3, clause by
  // clause.
  //
  // keyScope mirrors the server's Env.key_scope: null wherever no loop item's key reaches, and
  // {level, outer} where one does - see #renderLoopItem.
  static renderDom(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
    parentModule,
    slotsParentModule,
    keyScope = null,
  ) {
    if (Type.isList(dom)) {
      return Renderer.#renderNodes(
        dom,
        context,
        slots,
        defaultTarget,
        parentTagName,
        parentModule,
        slotsParentModule,
        keyScope,
      );
    }

    const nodeType = dom.data[0].value;

    // Cases ordered by expected frequency (most common first)
    switch (nodeType) {
      case "text":
        return Bitstring.toText(dom.data[1]);

      case "element":
        return Renderer.#renderElement(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
          parentModule,
          slotsParentModule,
          keyScope,
        );

      case "component":
        return Renderer.#renderComponent(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
          parentModule,
          slotsParentModule,
          keyScope,
        );

      case "loop_item":
        return Renderer.#renderLoopItem(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
          parentModule,
          slotsParentModule,
          keyScope,
        );

      case "expression": {
        const value = dom.data[1].data[0];

        // WARNING: must match render_tree/3's trusted HTML and safe tuple clauses on the server,
        // which come before the script and style ones, as these checks come before the value is
        // stringified. Trusted HTML inside an element whose content is text is refused by
        // #renderElement.
        if ($.#isTrustedHtml(value)) {
          return $.#trustedHtmlVnode(value, parentModule);
        }

        if ($.#isPhoenixSafeTuple(value)) {
          $.#raisePhoenixSafeTuple();
        }

        // HTML escaping is done by Snabbdom.
        const text = $.toText(value);

        // WARNING: must match render_tree/3's script and style clauses on the server: inside a
        // raw text element both sides write the value as the text of a string literal of the
        // language that element holds, escaped the same way - see SCRIPT_TEXT_ESCAPES and
        // STYLE_TEXT_ESCAPES.
        switch (parentTagName) {
          case "script":
            return $.#escapeScriptText(text);

          case "style":
            return $.#escapeStyleText(text);

          default:
            return text;
        }
      }

      case "page":
        return Renderer.renderDom(
          dom.data[1],
          context,
          slots,
          Type.bitstring("page"),
          parentTagName,
          parentModule,
          slotsParentModule,
          keyScope,
        );

      // Slot content passed on through a nested slot renders as written by the template that
      // supplied it.
      //
      // WARNING: must match render_tree/3's slot_content clause on the server.
      case "slot_content":
        return Renderer.renderDom(
          dom.data[2],
          context,
          slots,
          defaultTarget,
          parentTagName,
          dom.data[1],
          slotsParentModule,
          keyScope,
        );

      case "dynamic_tag":
        return Renderer.#renderDynamicTag(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
          parentModule,
          slotsParentModule,
          keyScope,
        );

      case "doctype":
        return Type.nil();

      // A node of an evaluated tree the server shipped on navigation, holding the string trust_html/1
      // was given. The module that rendered it isn't on the wire, and nothing compares it: the diff
      // compares the HTML, and only a hydration error names the module, which a navigation never
      // raises.
      case "trusted_html":
        return Vdom.trustedHtmlVnode(Bitstring.toText(dom.data[1]), null);

      case "public_comment":
        return Renderer.#renderPublicComment(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
          parentModule,
          slotsParentModule,
        );
    }
  }

  // Based on: render_page/2
  static renderPage(pageModule, pageParams) {
    Renderer.dragBindings = [];
    Renderer.listenerBindings = [];
    Renderer.reachBindings = [];
    Renderer.refBindings = new Map();
    Renderer.resizeBindings = [];

    const pageModuleProxy = Interpreter.moduleProxy(pageModule);

    const cid = Type.bitstring("page");

    // A page's params are its props, and it is re-rendered on every action like everything else,
    // so they are rewritten here for the same reason a component's are.
    ComponentRegistry.putComponentProps(cid, pageParams);

    const pageComponentStruct = ComponentRegistry.getComponentStruct(cid);

    // The document's own children, the one children list with no element to own it.
    const pageVdom = Vdom.finalizeChildren(
      Renderer.#renderPageInsideLayout(
        pageModuleProxy,
        pageParams,
        pageComponentStruct,
      ),
    );

    return Renderer.#pageVnodeFromChildren(pageVdom);
  }

  // Based on the tree Renderer.render_tree/3 evaluates on the server, converted to the vnodes a
  // patch works on.
  //
  // The tree is a render the server already performed, so nothing here evaluates: it holds only
  // elements, text, comments, the doctype and trusted HTML, and the clauses those reach in renderDom
  // read neither context nor slots. They are passed empty for that reason rather than as a stand-in
  // for a real render's own.
  //
  // WARNING: the vnodes this returns must equal the vnodes renderPage returns for the same page,
  // or the render that follows rebuilds nodes instead of adopting the ones this put on screen.
  // Both go through renderDom and both finalize the document's children the same way, which is
  // what holds the two together.
  //
  // TODO: when the vdom renderer is rewritten, the decodeTree/renderDom pair collapses into one
  // walk. Sharing renderDom is what keeps this equal to renderPage today; a second walker would
  // have to reproduce every rule renderDom applies to a tree - the boolean attribute rule, the
  // controlled value/checked staging and its hooks, the focus hooks, the three resource-key rules,
  // $key resolving to the last one and read verbatim, since the server already composed a loop
  // item's parts into it, and finalizeChildren settling repeats - and drift in any of them shows
  // up as a silently rebuilt DOM rather than a failing test.
  // See: docs/navigation_payload_wire_format.md
  static renderTree(tree) {
    const children = Vdom.finalizeChildren(
      Renderer.renderDom(
        tree,
        Type.map(),
        Type.keywordList(),
        Type.bitstring("page"),
        null,
        null,
        null,
      ),
    );

    return Renderer.#pageVnodeFromChildren(children);
  }

  static resetFocusCandidates() {
    $.focusCandidates = [];
    $.blurCandidates = [];
  }

  // Resolves this render's capture-phase drag listeners into {target, key, attach, handler} registry
  // bindings, called after Snabbdom has patched so each carried vnode's `.elm` is live. A target's
  // bindings for one event share one registry listener, which reconcile keeps across renders and
  // only swaps its handlers.
  //
  // A <window>/<document> tag whose $drop bindings are all spent once bindings is no longer a drop
  // target: resolveListenerBindings drops those bindings, so nothing would prevent the drop's
  // default, and a drag the page accepts would then open the dropped file or link. An element keeps
  // its spent once binding, which goes on preventing the drop's default, so it stays a drop target.
  static resolveDragBindings() {
    return $.dragBindings
      .filter(
        ({target, dropSlots}) =>
          !dropSlots?.every(
            ({once, slotKey}) => once && Once.hasFired(target, slotKey),
          ),
      )
      .map(({vnode, target, eventName, handler}) => {
        const bindingTarget = vnode ? vnode.elm : target;

        const {key, attach} = EventListeners.domEvent(
          bindingTarget,
          eventName,
          true,
        );

        return {target: bindingTarget, key, attach, handler};
      });
  }

  // Resolves this render's <window>/<document> listener bindings, dropping any spent once binding so
  // reconcile detaches its real listener through the same path that removes a vanished binding. The
  // fired-state is keyed by the binding's target and slot, both carried on the binding. The drop is
  // gated on the binding's own once flag: a listener slot is positional across this render's listener
  // bindings, so a non-once binding can reuse a spent once binding's slot on the shared target, and
  // the gate keeps it from inheriting that permanent fired-state.
  static resolveListenerBindings() {
    return $.listenerBindings.filter(
      ({target, slotKey, once}) => !(once && Once.hasFired(target, slotKey)),
    );
  }

  // Resolves this render's deferred reach bindings into {target, key, attach, handler} registry
  // bindings, called after Snabbdom has patched so each carried vnode's `.elm` is live. The target
  // is the container itself, whose own scroll metrics the listener reads, so the registry keeps one
  // listener per container edge across renders rather than re-pointing it. Per-edge keys keep a
  // container's bindings reconciling independently. A binding whose once modifier has fired is
  // dropped, so reconcile detaches its scroll listener.
  static resolveReachBindings() {
    return $.reachBindings
      .filter(
        ({vnode, slotKey, once}) =>
          !(once && Once.hasFired(vnode.elm, slotKey)),
      )
      .map(({vnode, edge, handler, within}) => {
        const {key, attach} = EventListeners.scrollEdge(
          vnode.elm,
          edge,
          within,
        );

        return {target: vnode.elm, key, attach, handler};
      });
  }

  // Resolves this render's refs into the elements rendered under them, by the ref's encoded map
  // key, called after Snabbdom has patched so each carried vnode's `.elm` is live.
  static resolveRefBindings() {
    return new Map(
      Array.from($.refBindings, ([key, {vnode}]) => [key, vnode.elm]),
    );
  }

  // Resolves this render's deferred resize bindings into {target, key, attach, handler} registry
  // bindings, called after Snabbdom has patched so each carried vnode's `.elm` is live. The observer
  // target and its attach are built here from that element; a persistent element keeps the same
  // `.elm`, so the registry keeps its observer across renders and only swaps the handler. A binding
  // whose once modifier has fired is dropped, so reconcile disconnects its observer.
  static resolveResizeBindings() {
    return $.resizeBindings
      .filter(
        ({vnode, slotKey, once}) =>
          !(once && Once.hasFired(vnode.elm, slotKey)),
      )
      .map(({vnode, handler}) => {
        const element = vnode.elm;
        const {key, attach} = EventListeners.resizeObserver(element);

        return {target: element, key, attach, handler};
      });
  }

  // Moves focus where the patch asked, then clears the candidates.
  //
  // The boot render claims nothing: the browser already applied autofocus from the markup the server
  // sent, and the user may have moved on before the runtime started.
  //
  // A blur applies only to an element that still has focus, so a field the render stops declaring
  // focused gives focus up even when no other element takes it, and a render that blurs one element
  // and focuses another ends on the focused one in either order. Of the focus candidates, the first
  // in document order that can take focus takes it - one that is disabled, hidden or not focusable
  // at all is passed over, the way the browser passes over it for autofocus on a page load. A
  // candidate the same patch removed again is skipped.
  //
  // A page that appears is a page load, and a page load starts with nothing focused: on a page
  // arrival that no candidate claims, whatever has focus - the link the user clicked, or a field
  // of the left page the diff kept - gives it up.
  static settleFocus(isBootRender) {
    const focusCandidates = $.focusCandidates;
    const blurCandidates = $.blurCandidates;
    const isPageArrival = $.isPageArrival;

    $.resetFocusCandidates();
    $.isPageArrival = false;

    if (isBootRender) {
      return;
    }

    // Focus moved here is the state's doing, so the $focus and $blur bindings it would trigger
    // stay quiet (see FocusEvent.isRuntimeFocusChange).
    const wasRuntimeFocusChange = FocusEvent.isRuntimeFocusChange;
    FocusEvent.isRuntimeFocusChange = true;

    try {
      $.#moveFocus(focusCandidates, blurCandidates, isPageArrival);
    } finally {
      FocusEvent.isRuntimeFocusChange = wasRuntimeFocusChange;
    }
  }

  static toBitstring(term) {
    return Type.isBitstring(term) ? term : Type.bitstring($.toText(term));
  }

  // Similar to Kernel.to_string/1
  // (it is supposed to be a fast alternative to Kernel.to_string/1 for the client-side renderer only)
  // Deps: [String.Chars.to_string/1]
  static toText(term) {
    // Cases ordered by expected frequency (most common first)
    switch (term.type) {
      case "atom":
        return term.value === "nil" ? "" : term.value;

      case "bitstring":
        if (Type.isBinary(term)) {
          return Bitstring.toText(term);
        }
        break;

      case "integer":
      case "float":
        return term.value.toString();
    }

    return Bitstring.toText(Elixir_String_Chars["to_string/1"](term));
  }

  // Based on validate_declared_state/3
  //
  // put_state/2,3 can't tell which module it runs in, so the state is checked where the struct comes
  // back from the module's own code. Of several undeclared keys the smallest in term order is named,
  // so the message doesn't depend on map order.
  //
  // WARNING: must match validate_declared_state/3 on the server.
  static validateDeclaredState(state, moduleProxy, handler) {
    const declaredNames = Renderer.#getDeclaredStateNames(moduleProxy);

    // The map's data is keyed by encoded keys already.
    const undeclaredKeys = Object.entries(state.data)
      .filter(([encodedKey, _entry]) => !declaredNames.has(encodedKey))
      .map(([_encodedKey, [key, _value]]) => key);

    if (undeclaredKeys.length === 0) {
      return;
    }

    Interpreter.raiseError(
      "Hologram.StateError",
      Renderer.#undeclaredStateMessage(
        Renderer.#smallestStateKey(undeclaredKeys),
        moduleProxy,
        handler,
      ),
    );
  }

  static valueDomToBitstring(valueDom) {
    // Cache the property access
    const valueParts = valueDom.data;

    // Early exit for empty case
    if (valueParts.length === 0) {
      return Type.bitstring("");
    }

    const bitstringChunks = new Array(valueParts.length);

    for (let i = 0; i < valueParts.length; ++i) {
      // Cache the property access
      const valuePartData = valueParts[i].data;

      if (valuePartData[0].value === "text") {
        bitstringChunks[i] = valuePartData[1];
      } else {
        // expression
        const value = valuePartData[1].data[0];

        $.#refuseMarkupValue(value);

        const expressionText = $.toText(value);

        bitstringChunks[i] = Type.bitstring(expressionText);
      }
    }

    return Bitstring.concat(bitstringChunks);
  }

  // Returns true when the modifiers map carries an allow_default modifier, which opts the binding
  // out of the framework's preventDefault.
  // Deps: [:maps.is_key/2]
  static #allowDefaultFromModifiers(modifiersDom) {
    if (!modifiersDom) {
      return false;
    }

    return Type.isTrue(
      Erlang_Maps["is_key/2"](Type.atom("allow_default"), modifiersDom),
    );
  }

  // Builds one event binding from a "$"-prefixed attribute, shared by element and window bindings.
  // Returns an {eventName, handler} descriptor (the handler runs modifier matching, dispatch, and
  // debounce/throttle), or null when the attribute is not an event binding. slotKey identifies the
  // binding for debounce/throttle windows - the attribute index for elements, the binding index for
  // window bindings, which all share the same currentTarget.
  static #buildEventBinding(
    attrDom,
    slotKey,
    tagName,
    attrsVdom,
    defaultTarget,
  ) {
    const attributeName = $.#eventAttributeName(attrDom);

    if (attributeName === null || !attributeName.startsWith("$")) {
      return null;
    }

    const originalEventName = attributeName.substring(1);

    // $key names the place an element holds in its template rather than something that happens to
    // it, so it binds nothing. Without this it would register a listener for an event called "key",
    // which no browser fires.
    if (originalEventName === "key") {
      return null;
    }

    // $data_transfer declares what a drag carries and how a drop target takes it, which the drag
    // listeners apply, so it binds nothing either. Without this it would register a listener for an
    // event called "datatransfer", which no browser fires.
    if (originalEventName === "data_transfer") {
      return null;
    }

    // $focused says whether the element should have focus rather than something that happens to it,
    // so it binds nothing either. Without this it would register a listener for an event called
    // "focused", which no browser fires.
    if (originalEventName === "focused") {
      return null;
    }

    // $ref names the element for a lookup rather than something that happens to it, so it binds
    // nothing either. Without this it would register a listener for an event called "ref", which no
    // browser fires.
    if (originalEventName === "ref") {
      return null;
    }

    // click_outside is not a per-element listener: the dismissing click lands on another element,
    // so it is collected as a document-level "click" binding in #renderElement. Returning null here
    // keeps it out of the element's "on" map.
    if (originalEventName === "click_outside") {
      return null;
    }

    // A scroll-edge reach ($reach_top/bottom/left/right) is delivered by a scroll listener reading
    // the container's own scroll metrics, not a DOM event, so it is collected as a deferred binding
    // in #renderElement. Returning null keeps it out of the element's "on" map, where the browser
    // would never fire it.
    if (originalEventName.startsWith("reach_") && tagName !== null) {
      return null;
    }

    // resize on a real element is delivered by a ResizeObserver, not a DOM event, so it is collected
    // as an observer binding in #renderElement. Returning null keeps it out of the element's "on"
    // map, where the browser would never fire it. A <window> binding (tagName null) keeps flowing
    // through here onto the native resize DOM event.
    if (originalEventName === "resize" && tagName !== null) {
      return null;
    }

    const normalizedEventName = $.#normalizeEventName(originalEventName);

    const effectiveDomEventName = $.#mapEventName(
      normalizedEventName,
      tagName,
      attrsVdom,
    );

    const handler = $.#buildEventHandler(
      attrDom,
      slotKey,
      effectiveDomEventName,
      defaultTarget,
    );

    return {eventName: effectiveDomEventName, handler};
  }

  // Builds the handler an event binding fans an event into: it matches the event against any filter
  // modifiers, dispatches through handleUiEvent, and runs the dispatch under the binding's
  // debounce/throttle window. slotKey scopes that window within getThrottleTarget(event) - the
  // object whose timers the window lives on. A DOM event reads its currentTarget there (the default);
  // a ResizeObserverEntry has none, so the observer path passes a getter reading the entry's target.
  static #buildEventHandler(
    attrDom,
    slotKey,
    effectiveDomEventName,
    defaultTarget,
    getThrottleTarget = (event) => event.currentTarget,
  ) {
    const modifiersDom = attrDom.data[2];
    const allowDefault = $.#allowDefaultFromModifiers(modifiersDom);
    const debounceMs = $.#debounceMsFromModifiers(modifiersDom);
    const forcePreventDefault = $.#preventDefaultFromModifiers(modifiersDom);
    const once = $.#onceFromModifiers(modifiersDom);
    const stopPropagation = $.#stopPropagationFromModifiers(modifiersDom);
    const throttleMs = $.#throttleMsFromModifiers(modifiersDom);

    return (event) => {
      if (modifiersDom && !$.#eventMatchesModifiers(modifiersDom, event)) {
        return;
      }

      // Process the event synchronously: handleUiEvent runs preventDefault and reads the event
      // payload now, while the event is live, then returns the dispatch (or null when ignored).
      // Only the dispatch is debounced - deferring preventDefault would let the browser's native
      // default fire before it could be blocked.
      const dispatch = Hologram.handleUiEvent(
        event,
        effectiveDomEventName,
        attrDom.data[1],
        defaultTarget,
        allowDefault,
        stopPropagation,
        forcePreventDefault,
      );

      if (dispatch === null) {
        return;
      }

      // The throttle target is read synchronously here - a DOM event nulls its currentTarget after
      // dispatch. Debounce and throttle are mutually exclusive (enforced at compile time), so at
      // most one applies. It doubles as the once key: the bound element for DOM and window/document,
      // the observed element or reach container for the observer transports.
      const throttleTarget = getThrottleTarget(event);

      // A spent once binding has already run preventDefault / stop_propagation above, so it only
      // stops re-dispatching: return before routing the dispatch.
      if (once && Once.hasFired(throttleTarget, slotKey)) {
        return;
      }

      // Mark fired when the dispatch actually runs, not when the event arrives, so once is spent on
      // the real fire: a debounce coalesces the burst into one trailing fire that spends it, and a
      // throttle leading edge spends it before the next event so the trailing edge never fires.
      const finalDispatch = once
        ? () => {
            Once.markFired(throttleTarget, slotKey);
            dispatch();
          }
        : dispatch;

      if (debounceMs !== null) {
        Debouncer.run(throttleTarget, slotKey, debounceMs, finalDispatch);
      } else if (throttleMs !== null) {
        Throttler.run(throttleTarget, slotKey, throttleMs, finalDispatch);
      } else {
        finalDispatch();
      }
    };
  }

  // Based on build_layout_props_dom/2
  // Deps: [:maps.from_list/1, :maps.merge/2]
  static #buildLayoutPropsDom(pageModuleProxy, pageState) {
    const propsFromPage = Erlang_Maps["from_list/1"](
      pageModuleProxy["__layout_props__/0"](),
    );

    const propsWithCid = Erlang_Maps["merge/2"](
      propsFromPage,
      Type.map([[Type.atom("cid"), Type.bitstring("layout")]]),
    );

    const propsWithPageState = Erlang_Maps["merge/2"](propsWithCid, pageState);

    return Type.list(
      Object.values(propsWithPageState.data).map(([name, value]) =>
        Type.tuple([
          Type.bitstring(name.value),
          Type.keywordList([[Type.atom("expression"), Type.tuple([value])]]),
        ]),
      ),
    );
  }

  // Based on cast_props/2
  // Deps: [:maps.from_list/1]
  static #castProps(propsDom, moduleProxy) {
    const propsTuples = Renderer.#filterAllowedProps(
      Renderer.#expandPropSpreads(propsDom),
      moduleProxy,
    )
      .map((propDom) => Renderer.#evalutatePropValue(propDom))
      .map((propDom) => Renderer.#normalizePropName(propDom));

    return Erlang_Maps["from_list/1"](Type.list(propsTuples));
  }

  // Records each $click_outside attribute on the element as a document-level "click" binding: it
  // listens on the document (the dismissing click lands on another element) and dispatches only when
  // the click target is outside the bound element's subtree. The element is read from the vnode's
  // live `.elm` at dispatch - Snabbdom sets it during patch, and the binding is only reconciled into
  // a real listener after that. The Hologram event type is the synthetic "click_outside" - the DSL
  // name unchanged, deliberately not run through #normalizeEventName, since there is no DOM event to
  // map to. A once modifier keys on the bound element (re-arming when it is re-created) and stays
  // inert until then, like a DOM-element once binding - click_outside does not go through
  // #buildEventHandler, so its once is wired here rather than inheriting the shared dispatch path.
  static #collectClickOutsideBindings(attrsDom, elementVnode, defaultTarget) {
    attrsDom.data.forEach((attrDom, attrIndex) => {
      if ($.#eventAttributeName(attrDom) !== "$click_outside") {
        return;
      }

      const operationSpecDom = attrDom.data[1];
      const once = $.#onceFromModifiers(attrDom.data[2]);

      const handler = (event) => {
        if (elementVnode.elm.contains(event.target)) {
          return;
        }

        const dispatch = Hologram.handleUiEvent(
          event,
          "click_outside",
          operationSpecDom,
          defaultTarget,
        );

        if (dispatch === null) {
          return;
        }

        // once keys on the bound element and its attribute index, so it re-arms only when the
        // element is re-created (a new node, a fresh fired-state) and stays spent across re-renders.
        if (once && Once.hasFired(elementVnode.elm, attrIndex)) {
          return;
        }

        if (once) {
          Once.markFired(elementVnode.elm, attrIndex);
        }

        dispatch();
      };

      // Capture phase: Hologram renders synchronously inside the click handler, so a bubble-phase
      // listener installed while the opening click is still bubbling would fire for that very click
      // and self-dismiss. Capture sidesteps it - that phase has already passed by install time.
      const {key, attach} = EventListeners.domEvent(document, "click", true);

      $.listenerBindings.push({
        target: document,
        key,
        attach,
        handler,
        slotKey: $.listenerBindings.length,
        // click_outside once is keyed on the bound element and torn down when that element is
        // removed (its handler drops out of the shared document listener), not proactively filtered
        // here - so resolveListenerBindings must never drop it for a reused positional slot.
        once: false,
      });
    });
  }

  // An element or a <window>/<document> tag with an enabled $drop binding is a drop target. The
  // browser fires drop only on an element whose dragenter and dragover defaults were prevented, so
  // both are, by one pair of capture-phase listeners however many $drop bindings the tag has. A
  // disabled $drop leaves the drag alone. The drop's own default is the $drop binding's to prevent
  // (see DropEvent), so allow_default can let it through.
  //
  // A drop target's declared drop effect is set by the same listeners. They run from the window
  // inward, so the nearest drop target that declares one has the last word.
  static #collectDropTargetBindings(attrsDom, place, dataTransfer) {
    if (!attrsDom.data.some((attrDom) => $.#isEnabledDropBinding(attrDom))) {
      return;
    }

    const dropEffect = dataTransfer?.dropEffect ?? null;

    const handler =
      dropEffect === null
        ? $.#preventDefault
        : (event) => {
            $.#preventDefault(event);

            if (event.dataTransfer) {
              event.dataTransfer.dropEffect = dropEffect;
            }
          };

    for (const eventName of ["dragenter", "dragover"]) {
      $.dragBindings.push({...place, eventName, handler});
    }
  }

  // Snabbdom insert hook: runs once the whole patch is in the document, where .focus() can work -
  // the create hook runs before the element is attached. An element that enters the page carrying
  // autofocus takes focus, whether $focused put it there or the template wrote it, on a mount and
  // after an action alike. That is what autofocus means when the page loads, so it means the same
  // when an element appears later.
  static #collectInsertedFocus(vnode) {
    if ($.#hasAutofocus(vnode)) {
      $.focusCandidates.push(vnode.elm);
    }
  }

  // Records a <window>/<document> tag's event bindings into the per-render accumulator, tagged with
  // the target the listener attaches to. Each binding is keyed by its position across all listener
  // bindings this render, so debounce/throttle windows stay independent even though listeners on one
  // target share a currentTarget. A bare tag (no attributes) records nothing. A listener target has
  // no element tag name, so event-name mapping is skipped (passed null).
  static #collectListenerBindings(target, attrsDom, defaultTarget) {
    const dataTransfer = $.#renderDataTransfer(attrsDom);
    const dropSlots = [];

    attrsDom.data.forEach((attrDom) => {
      const slotKey = $.listenerBindings.length;

      const binding = $.#buildEventBinding(
        attrDom,
        slotKey,
        null,
        {},
        defaultTarget,
      );

      if (binding !== null) {
        const {key, attach} = EventListeners.domEvent(
          target,
          binding.eventName,
        );

        const once = $.#onceFromModifiers(attrDom.data[2]);

        $.listenerBindings.push({
          target,
          key,
          attach,
          handler: binding.handler,
          slotKey,
          once,
        });

        if ($.#isEnabledDropBinding(attrDom)) {
          dropSlots.push({once, slotKey});
        }
      }
    });

    $.#collectDropTargetBindings(attrsDom, {target, dropSlots}, dataTransfer);
  }

  // Records each $reach_<edge> attribute on the element as a deferred scroll-edge binding. A reach
  // is delivered by a scroll listener reading the container's own scroll metrics, not a DOM event,
  // so it cannot ride the element's "on" map, and the container is a live DOM node Snabbdom sets on
  // the vnode only during patch. So the binding carries the vnode, the edge, its handler, and the
  // within modifier's distance, and resolveReachBindings turns it into a registry binding once `.elm`
  // exists. The handler keys its debounce/throttle window on the dispatched event's target (the
  // container). The Hologram event type is "reach_<edge>", which selects ReachEvent and carries the
  // edge for a handler that branches on it.
  static #collectReachBindings(attrsDom, elementVnode, defaultTarget) {
    attrsDom.data.forEach((attrDom, attrIndex) => {
      const attributeName = $.#eventAttributeName(attrDom);

      if (attributeName === null) {
        return;
      }

      const eventName = attributeName.substring(1);

      if (!eventName.startsWith("reach_")) {
        return;
      }

      const edge = eventName.substring("reach_".length);
      const within = $.#withinFromModifiers(attrDom.data[2]);

      const handler = $.#buildEventHandler(
        attrDom,
        attrIndex,
        eventName,
        defaultTarget,
        (event) => event.target,
      );

      $.reachBindings.push({
        vnode: elementVnode,
        edge,
        handler,
        within,
        slotKey: attrIndex,
        once: $.#onceFromModifiers(attrDom.data[2]),
      });
    });
  }

  // Records each $resize attribute on the element as a deferred resize-observer binding. Element
  // resize is delivered by a ResizeObserver, not a DOM event, so it cannot ride the element's "on"
  // map, and the observer's target is the element's live DOM node, which Snabbdom sets on the vnode
  // only during patch. So the binding carries the vnode and its handler, and resolveResizeBindings
  // turns it into a registry binding once `.elm` exists. The handler keys its debounce/throttle
  // window on the entry's target (the observed element), as a ResizeObserverEntry has no
  // currentTarget. The Hologram event type is "resize", the same one the window binding dispatches.
  static #collectResizeBindings(attrsDom, elementVnode, defaultTarget) {
    attrsDom.data.forEach((attrDom, attrIndex) => {
      if ($.#eventAttributeName(attrDom) !== "$resize") {
        return;
      }

      const handler = $.#buildEventHandler(
        attrDom,
        attrIndex,
        "resize",
        defaultTarget,
        (event) => event.target,
      );

      $.resizeBindings.push({
        vnode: elementVnode,
        handler,
        slotKey: attrIndex,
        once: $.#onceFromModifiers(attrDom.data[2]),
      });
    });
  }

  // Snabbdom update hook, for an element the diff kept. Only a change asks for focus: a re-render
  // that declares the same thing again leaves focus where the user put it. A page arrival is the
  // exception, see isPageArrival.
  //
  // What the previous render declared is read off its autofocus attribute rather than its
  // hologramFocused: an element kept from a navigation's interim page carries the attribute the
  // server rendered and no hologramFocused, and it was focused when that page appeared, so the
  // mount's render must see no change on it.
  static #collectUpdatedFocus(oldVnode, newVnode) {
    const hadAutofocus = $.#hasAutofocus(oldVnode);

    if ($.#hasAutofocus(newVnode) && ($.isPageArrival || !hadAutofocus)) {
      $.focusCandidates.push(newVnode.elm);
    }

    if (hadAutofocus && newVnode.data.hologramFocused === false) {
      $.blurCandidates.push(newVnode.elm);
    }
  }

  // Based on compose_attribute_name/2
  // HTML attribute names are dash-separated, while Elixir identifiers can't contain dashes, so each
  // name segment converts to the convention of the namespace it lands in. Nesting composes the
  // segments with hyphens, e.g. %{data: %{user_id: 1}} becomes "data-user-id".
  static #composeAttributeName(key, namePrefix) {
    const segment = $.#validateSpreadKey($.toText(key)).replaceAll("_", "-");

    return namePrefix === null ? segment : `${namePrefix}-${segment}`;
  }

  // Based on component_key_scope/3
  //
  // The key scope a component's template renders in. A $key on the component takes the place of
  // the item's own part, and so does the cid of a stateful component placed in a loop item, since
  // the cid already is that component's identity. A stateful component can't take both: two
  // identities could disagree. An override is a scope of its own, never a change to the one the
  // component was given.
  //
  // WARNING: must match component_key_scope/3 on the server.
  // Deps: [:maps.get/2]
  static #componentKeyScope(explicitKey, props, keyScope) {
    const hasCid = Renderer.#hasCidProp(props);

    if (explicitKey !== null) {
      if (hasCid) {
        Interpreter.raiseArgumentError(
          "a stateful component is keyed by its cid, so it can't take $key",
        );
      }

      return $.#putKeyScopeLevel(keyScope, $.#explicitKeyPart(explicitKey));
    }

    if (hasCid && keyScope) {
      const body = $.#keyBody(Erlang_Maps["get/2"](Type.atom("cid"), props));

      return body === null
        ? keyScope
        : $.#putKeyScopeLevel(keyScope, `#${body}`);
    }

    return keyScope;
  }

  // Whether rendered children hold trusted HTML, at any depth.
  static #containsTrustedHtml(childrenVdom) {
    return childrenVdom.some(
      (child) =>
        typeof child === "object" &&
        child !== null &&
        (child.sel === TRUSTED_HTML_SEL ||
          (Array.isArray(child.children) &&
            $.#containsTrustedHtml(child.children))),
    );
  }

  static #contextKey(opts) {
    return Interpreter.accessKeywordListElement(
      opts,
      Type.atom("from_context"),
    );
  }

  // Based on data_transfer_entries/1
  // The entries of a $data_transfer value: a keyword list's, each key once, in the order written, or
  // a map's, in the order of their keys, which both renderers can reproduce.
  static #dataTransferEntries(value) {
    if (Type.isMap(value) && !Type.isStruct(value)) {
      return Object.values(value.data).sort(([keyA], [keyB]) =>
        Interpreter.compareTerms(keyA, keyB),
      );
    }

    if (!Type.isProperList(value) || !Type.isKeywordList(value)) {
      Interpreter.raiseMisuseError(
        `the $data_transfer attribute takes a keyword list or a map, got ${Interpreter.inspect(value)}`,
      );
    }

    const entries = value.data.map((entry) => entry.data);
    const seenKeys = new Set();

    for (const [key] of entries) {
      if (seenKeys.has(key.value)) {
        Interpreter.raiseMisuseError(
          `the $data_transfer attribute takes each key once, but got the ${Interpreter.inspect(key)} key twice`,
        );
      }

      seenKeys.add(key.value);
    }

    return entries;
  }

  // Returns the debounce window in milliseconds from a modifiers map, or null when there is no
  // debounce modifier.
  // Deps: [:maps.get/3]
  static #debounceMsFromModifiers(modifiersDom) {
    if (!modifiersDom) {
      return null;
    }

    const debounce = Erlang_Maps["get/3"](
      Type.atom("debounce"),
      modifiersDom,
      null,
    );

    return debounce === null ? null : Number(debounce.value);
  }

  // Based on dedupe_attributes/1
  // Event attributes are exempt, because a tag may carry multiple bindings which share a base name
  // once their modifiers are decomposed at compile time, e.g. both $key_down.enter and
  // $key_down.escape are named "$key_down".
  // A flat run of alternating names and values, with null for an attribute that has no value.
  static #decodeAttributes(attributes) {
    const decoded = new Array(attributes.length / 2);

    for (let i = 0, j = 0; i < attributes.length; i += 2, j += 1) {
      const value = attributes[i + 1];

      decoded[j] = Type.tuple([
        Type.bitstring(attributes[i]),
        value === null
          ? Type.list([])
          : Type.keywordList([[Type.atom("text"), Type.bitstring(value)]]),
      ]);
    }

    return decoded;
  }

  static #decodeNode(node) {
    if (typeof node === "string") {
      return Type.tuple([Type.atom("text"), Type.bitstring(node)]);
    }

    if (node.length === 3) {
      return Type.tuple([
        Type.atom("element"),
        Type.bitstring(node[0]),
        Type.list(Renderer.#decodeAttributes(node[1])),
        Type.list(node[2].map(Renderer.#decodeNode)),
      ]);
    }

    if (node[0] === "c") {
      return Type.tuple([
        Type.atom("public_comment"),
        Type.list(node[1].map(Renderer.#decodeNode)),
      ]);
    }

    if (node[0] === "h") {
      return Type.tuple([Type.atom("trusted_html"), Type.bitstring(node[1])]);
    }

    return Type.tuple([Type.atom("doctype"), Type.bitstring(node[1])]);
  }

  static #dedupeAttributes(attrs) {
    const lastIndexByName = new Map();

    attrs.forEach(([name], index) => {
      if (!name.startsWith("$")) {
        lastIndexByName.set(name, index);
      }
    });

    return attrs.filter(
      ([name], index) =>
        name.startsWith("$") || lastIndexByName.get(name) === index,
    );
  }

  static #determineInputType(tagName, attrs) {
    let typeAttr;

    switch (tagName) {
      case "input":
        typeAttr = attrs.find(([name, _valueDom]) => name === "type");
        return typeAttr ? Renderer.#valueDomToText(typeAttr[1]) : "text";

      case "select":
        return "select";

      case "textarea":
        return "textarea";
    }

    return null;
  }

  // Based on duplicate_ref_message/3
  //
  // WARNING: must match duplicate_ref_message/3 on the server.
  static #duplicateRefMessage(ref, firstModule, secondModule) {
    return (
      `two elements are rendered under the ref ${Interpreter.inspect(ref)}${$.#refWriters(firstModule, secondModule)} - ` +
      "a ref names one element, so give each element a ref of its own, " +
      `like ${$.#refExample(ref)} for the items of a loop`
    );
  }

  // Based on escape_key_text/1
  //
  // Backslash-escapes the characters key parts are delimited by. The slot key holds no "#", its
  // hash being base 36, so with values escaped every unescaped "#" after it starts a part, every
  // unescaped ":" is a suffix Vdom.dedupeKeys adds, and every unescaped "," inside a tuple's body
  // ends one of its elements. A value can therefore never pose as another part, as a repeat's
  // number or as two elements of a tuple.
  //
  // WARNING: must match escape_key_text/1 on the server.
  static #escapeKeyText(text) {
    return text.replace(/[\\#:,]/g, "\\$&");
  }

  // Based on stringify_for_script_interpolation/1
  static #escapeScriptText(text) {
    return text.replace(
      SCRIPT_TEXT_ESCAPABLE_CHARS,
      (char) => SCRIPT_TEXT_ESCAPES[char],
    );
  }

  // Based on stringify_for_style_interpolation/1
  static #escapeStyleText(text) {
    return text.replace(
      STYLE_TEXT_ESCAPABLE_CHARS,
      (char) => STYLE_TEXT_ESCAPES[char],
    );
  }

  // A spread entry is {:spread, {value}} - its name slot holds the :spread atom rather than a
  // bitstring name. Event bindings can never come from a spread, since "$"-prefixed keys are
  // rejected during expansion, so the binding collectors read names through this and skip spreads.
  // They walk the unexpanded attribute list on purpose: their positional slot keys (debounce and
  // throttle windows, once state) must not shift when a spread's entry count changes.
  static #eventAttributeName(attrDom) {
    return Type.isRecordTuple(attrDom, "spread", 2)
      ? null
      : Bitstring.toText(attrDom.data[0]);
  }

  // Based on expand_attribute/1
  // Returns unboxed [name, valueDom] pairs, since every caller unboxes the name anyway.
  //
  // A spread's own entries are sorted by name, so that rendering is reproducible: map key order is
  // undefined in Erlang, and a keyword list's order decides only which duplicate key wins, never how
  // the surviving entries are laid out. Array.prototype.sort() is stable, which is what keeps that
  // later-wins rule intact. Only the block a single spread expands to is sorted, so attributes
  // written literally in the markup keep their authored position.
  static #expandAttribute(attrDom) {
    if (!Type.isRecordTuple(attrDom, "spread", 2)) {
      return [[Bitstring.toText(attrDom.data[0]), attrDom.data[1]]];
    }

    return $.#expandSpreadAttributes(attrDom.data[1].data[0], null).sort(
      ([nameA], [nameB]) => StringOrder.compare(nameA, nameB),
    );
  }

  // Based on expand_attribute_spreads/1
  // Spread entries are splatted into synthetic named attributes at the spread's position, so that
  // everything downstream (event attribute filtering, boolean attribute rules, value rendering) is
  // reached through the same path as attributes written literally in the markup. Names then resolve
  // positionally, last one wins. A tag with no spread is left alone, so that duplicate names written
  // literally keep behaving as they did.
  static #expandAttributeSpreads(attrsDom) {
    const hasSpread = attrsDom.data.some((attrDom) =>
      Type.isRecordTuple(attrDom, "spread", 2),
    );

    const expanded = attrsDom.data.flatMap((attrDom) =>
      $.#expandAttribute(attrDom),
    );

    return hasSpread ? $.#dedupeAttributes(expanded) : expanded;
  }

  // Based on expand_prop/1
  static #expandProp(propDom) {
    return Type.isRecordTuple(propDom, "spread", 2)
      ? $.#expandSpreadProps(propDom.data[1].data[0])
      : [propDom];
  }

  // Based on expand_prop_spreads/1
  // Spread entries are splatted into synthetic named props at the spread's position, so that
  // everything downstream (filtering to declared props, name normalization, context injection,
  // defaults, cid detection) is reached through the same path as props written literally in the
  // markup. Names then resolve positionally, last one wins, which the final collapse into a map
  // already does - no deduplication step is needed here.
  //
  // Returns an array of prop tuples rather than a boxed list, since the caller iterates it anyway.
  static #expandPropSpreads(propsDom) {
    const hasSpread = propsDom.data.some((propDom) =>
      Type.isRecordTuple(propDom, "spread", 2),
    );

    return hasSpread
      ? propsDom.data.flatMap((propDom) => $.#expandProp(propDom))
      : propsDom.data;
  }

  // Based on expand_slots/3 (including fallback case)
  static #expandSlots(dom, slots, supplier) {
    if (Type.isList(dom)) {
      return Renderer.#expandSlotsInNodes(dom, slots, supplier);
    }

    if (dom.data[0].value === "component") {
      return Renderer.#expandSlotsInComponentNode(dom, slots, supplier);
    }

    if (dom.data[0].value === "dynamic_tag") {
      return Renderer.#expandSlotsInDynamicTagNode(dom, slots, supplier);
    }

    if (dom.data[0].value === "element") {
      return Renderer.#expandSlotsInElementNode(dom, slots, supplier);
    }

    if (dom.data[0].value === "loop_item") {
      return Renderer.#expandSlotsInLoopItemNode(dom, slots, supplier);
    }

    return dom;
  }

  // Based on expand_slots/3 (component case)
  static #expandSlotsInComponentNode(dom, slots, supplier) {
    const [nodeType, moduleAlias, propsDom, childrenDom] = dom.data;

    return Type.tuple([
      nodeType,
      moduleAlias,
      propsDom,
      Renderer.#expandSlots(childrenDom, slots, supplier),
    ]);
  }

  // Based on expand_slots/3 (dynamic tag case)
  static #expandSlotsInDynamicTagNode(dom, slots, supplier) {
    const [nodeType, value, attrsDom, childrenDom] = dom.data;

    return Type.tuple([
      nodeType,
      value,
      attrsDom,
      Renderer.#expandSlots(childrenDom, slots, supplier),
    ]);
  }

  // Based on expand_slots/3 (element cases)
  //
  // The content goes on rendering as written by the template that supplied it, though it now sits
  // in the children of a usage another template wrote.
  static #expandSlotsInElementNode(dom, slots, supplier) {
    const [nodeType, tagName, attrsDom, childrenDom] = dom.data;

    if (Interpreter.isStrictlyEqual(tagName, Type.bitstring("slot"))) {
      const slotDom = Interpreter.accessKeywordListElement(
        slots,
        Type.atom("default"),
      );

      return slotDom
        ? Type.tuple([Type.atom("slot_content"), supplier, slotDom])
        : Type.nil();
    }

    return Type.tuple([
      nodeType,
      tagName,
      attrsDom,
      Renderer.#expandSlots(childrenDom, slots, supplier),
    ]);
  }

  // Based on expand_slots/3 (loop item case)
  static #expandSlotsInLoopItemNode(dom, slots, supplier) {
    const [nodeType, source, nodes] = dom.data;

    return Type.tuple([
      nodeType,
      source,
      Renderer.#expandSlots(nodes, slots, supplier),
    ]);
  }

  // Based on expand_slots/3 (list case)
  // Deps: [:lists.flatten/1]
  static #expandSlotsInNodes(nodes, slots, supplier) {
    return Erlang_Lists["flatten/1"](
      Type.list(
        nodes.data
          .filter((node) => !Type.isNil(node))
          .map((node) => Renderer.#expandSlots(node, slots, supplier)),
      ),
    );
  }

  // Based on expand_spread_attribute/2
  static #expandSpreadAttribute(key, value, namePrefix) {
    const name = $.#composeAttributeName(key, namePrefix);

    if ($.#isNestedSpreadValue(value)) {
      return $.#expandSpreadAttributes(value, name);
    }

    return [
      [
        name,
        Type.list([Type.tuple([Type.atom("expression"), Type.tuple([value])])]),
      ],
    ];
  }

  // Based on expand_spread_attributes/2
  static #expandSpreadAttributes(value, namePrefix) {
    return $.#spreadEntries(value).flatMap(([key, entryValue]) =>
      $.#expandSpreadAttribute(key, entryValue, namePrefix),
    );
  }

  // Based on expand_spread_props/1
  // Props live in the Elixir namespace, so unlike attribute names they are verbatim and flat - a map
  // or keyword list entry value is simply a raw prop value, and doesn't compose a nested name.
  static #expandSpreadProps(value) {
    return $.#spreadEntries(value).map(([key, entryValue]) => {
      const name = $.#validateSpreadKey($.toText(key));

      return Type.tuple([
        Type.bitstring(name),
        Type.list([
          Type.tuple([Type.atom("expression"), Type.tuple([entryValue])]),
        ]),
      ]);
    });
  }

  // Based on evaluate_prop_value/2
  static #evalutatePropValue(propDom) {
    const [name, valueDom] = propDom.data;
    let evaluatedValue;

    if (
      valueDom.data.length === 1 &&
      Interpreter.isStrictlyEqual(
        valueDom.data[0].data[0],
        Type.atom("expression"),
      )
    ) {
      evaluatedValue = $.#expressionValue(valueDom.data[0].data[1]);
    } else {
      evaluatedValue = Renderer.valueDomToBitstring(valueDom);
    }

    return Type.tuple([name, evaluatedValue]);
  }

  static #evaluateTemplate(moduleProxy, vars) {
    return Interpreter.callAnonymousFunction(moduleProxy["template/0"](), [
      vars,
    ]);
  }

  // Decides whether a live event satisfies an attribute's modifier filters. Modifiers are a
  // tagged list; a {:key, values} modifier is matched by the keyboard matcher, and any other
  // kind does not gate dispatch.
  // Deps: [:maps.get/3]
  static #eventMatchesModifiers(modifiersDom, event) {
    const keyFilters = Erlang_Maps["get/3"](
      Type.atom("key"),
      modifiersDom,
      Type.list(),
    );

    return keyFilters.data.every((keyFilter) =>
      KeyboardEvent.matchesKeyFilter(keyFilter, event),
    );
  }

  // Based on explicit_key/1
  //
  // The template author's $key among a component's props: the expression part of its value, which
  // on a dynamic tag follows the key of the tag's place. Null when there is none.
  static #explicitKey(propsDom) {
    for (const propDom of propsDom.data) {
      if (
        Type.isRecordTuple(propDom, "spread", 2) ||
        Bitstring.toText(propDom.data[0]) !== "$key"
      ) {
        continue;
      }

      for (const partDom of propDom.data[1].data) {
        if (Type.isRecordTuple(partDom, "expression", 2)) {
          return $.#expressionValue(partDom.data[1]);
        }
      }
    }

    return null;
  }

  // Based on explicit_key_hint/1
  //
  // Why a value that can't be a key can't be one, for the $key error. Only a binary that isn't
  // valid UTF-8 gets here among strings, and only a map whose :id can't be a key among maps.
  //
  // WARNING: must match explicit_key_hint/1 on the server.
  static #explicitKeyHint(value) {
    if (Type.isBinary(value)) {
      return "strings must be valid UTF-8";
    }

    if (Type.isMap(value)) {
      return "the map has no :id that can be a key";
    }

    return Identifier.check(value).hint;
  }

  // Based on explicit_key_part/1
  //
  // The key part of a $key the template author wrote, which raises for a value that can't be a
  // key, since the author asked for that key. A map or struct gives the part a loop over it would
  // give it, so $key={comment} keys a comment the way the automatic key does.
  //
  // WARNING: must match explicit_key_part/1 on the server.
  static #explicitKeyPart(value) {
    if (Type.isMap(value)) {
      const part = $.#itemKeyPart(Type.tuple([value]));

      if (part === null) {
        $.#raiseInvalidExplicitKey(value);
      }

      return part;
    }

    const body = $.#keyBody(value);

    if (body === null) {
      $.#raiseInvalidExplicitKey(value);
    }

    return `#${body}`;
  }

  // Based on expression_value/1
  //
  // The value an expression evaluates to: the one value of {value}, or the whole tuple when the
  // braces hold none or several, so $key={:post, id} and $key={{:post, id}} give the same key.
  //
  // WARNING: must match expression_value/1 on the server.
  static #expressionValue(expression) {
    return expression.data.length === 1 ? expression.data[0] : expression;
  }

  // Based on filter_allowed_props/2
  // Takes an array of prop tuples, as returned by #expandPropSpreads().
  static #filterAllowedProps(propDoms, moduleProxy) {
    const registeredPropNames = Renderer.#getPropDefinitions(moduleProxy)
      .data.filter((prop) => Renderer.#contextKey(prop.data[2]) === null)
      .map((prop) => $.toBitstring(prop.data[0]));

    const allowedPropNames = registeredPropNames.concat(Type.bitstring("cid"));

    return propDoms.filter((propDom) =>
      allowedPropNames.some((name) =>
        Interpreter.isStrictlyEqual(name, propDom.data[0]),
      ),
    );
  }

  // The first "$"-prefixed attribute of the given name a tag carries, or null. Spread entries can't
  // carry such names, so they are passed over.
  static #findAttribute(attrsDom, name) {
    return (
      attrsDom.data.find(
        (attrDom) => $.#eventAttributeName(attrDom) === name,
      ) ?? null
    );
  }

  // Which props carry a required: or values: option is a property of the module, not of the render,
  // so it is derived once and cached on the module proxy the way __props__ already is. Most
  // components constrain nothing, which leaves the per-render cost at a single length check.
  // Deps: [:lists.keyfind/3]
  static #getConstrainedProps(moduleProxy) {
    if (!("__constrainedProps__" in moduleProxy)) {
      moduleProxy.__constrainedProps__ = Renderer.#getPropDefinitions(
        moduleProxy,
      )
        .data.map((prop) => {
          const opts = prop.data[2];

          const requiredEntry = Erlang_Lists["keyfind/3"](
            Type.atom("required"),
            Type.integer(1),
            opts,
          );

          const valuesEntry = Erlang_Lists["keyfind/3"](
            Type.atom("values"),
            Type.integer(1),
            opts,
          );

          const required =
            !Type.isFalse(requiredEntry) && Type.isTrue(requiredEntry.data[1]);

          const values = Type.isFalse(valuesEntry) ? null : valuesEntry.data[1];

          return required || values !== null
            ? {name: prop.data[0], required: required, values: values}
            : null;
        })
        .filter((entry) => entry !== null);
    }

    return moduleProxy.__constrainedProps__;
  }

  // The names of the module's declared state entries, as encoded map keys, cached on the module
  // proxy like the defaults.
  static #getDeclaredStateNames(moduleProxy) {
    if (!("__declaredStateNames__" in moduleProxy)) {
      moduleProxy.__declaredStateNames__ = new Set(
        moduleProxy["__state__/0"]().data.map((definition) =>
          Type.encodeMapKey(definition.data[0]),
        ),
      );
    }

    return moduleProxy.__declaredStateNames__;
  }

  static #getPropDefinitions(moduleProxy) {
    if (!("__props__" in moduleProxy)) {
      moduleProxy.__props__ = moduleProxy["__props__/0"]();
    }

    return moduleProxy.__props__;
  }

  // Based on state_defaults/1
  //
  // The declared defaults are a property of the module, so the map is built once and cached on the
  // module proxy. Every component initialized from it shares the map, which is safe since nothing
  // changes a state map in place: every write builds a new one.
  // Deps: [:lists.keyfind/3]
  static #getStateDefaults(moduleProxy) {
    if (!("__stateDefaults__" in moduleProxy)) {
      const entries = moduleProxy["__state__/0"]()
        .data.map((definition) => {
          const defaultEntry = Erlang_Lists["keyfind/3"](
            Type.atom("default"),
            Type.integer(1),
            definition.data[2],
          );

          return Type.isFalse(defaultEntry)
            ? null
            : [definition.data[0], defaultEntry.data[1]];
        })
        .filter((entry) => entry !== null);

      moduleProxy.__stateDefaults__ = Type.map(entries);
    }

    return moduleProxy.__stateDefaults__;
  }

  // autofocus is a boolean attribute, so its presence is what counts: a bare attribute renders as
  // true, while autofocus={true} and autofocus="autofocus" render as text, and a falsy expression
  // leaves the attribute out entirely.
  static #hasAutofocus(vnode) {
    return vnode.data.attrs?.autofocus !== undefined;
  }

  // Based on has_cid_prop?/1
  static #hasCidProp(props) {
    return "atom(cid)" in props.data;
  }

  // Based on inject_default_prop_values/2
  // Deps: [:lists.keyfind/3, :lists.keymember/3, :maps.is_key/2]
  static #injectDefaultPropValues(props, moduleProxy) {
    return Renderer.#getPropDefinitions(moduleProxy).data.reduce(
      (acc, prop) => {
        if (
          Type.isFalse(Erlang_Maps["is_key/2"](prop.data[0], acc)) &&
          Type.isTrue(
            Erlang_Lists["keymember/3"](
              Type.atom("default"),
              Type.integer(1),
              prop.data[2],
            ),
          )
        ) {
          // Optimized (mutates map)
          acc.data[Type.encodeMapKey(prop.data[0])] = [
            prop.data[0],
            Erlang_Lists["keyfind/3"](
              Type.atom("default"),
              Type.integer(1),
              prop.data[2],
            ).data[1],
          ];
        }

        return acc;
      },
      Utils.shallowCloneObject(props),
    );
  }

  // Based on inject_props_from_context/3
  // Deps: [:maps.from_list/1, :maps.get/2, :maps.is_key/2, :maps.merge/2]
  static #injectPropsFromContext(propsFromTemplate, moduleProxy, context) {
    const propsFromContextTuples = Renderer.#getPropDefinitions(moduleProxy)
      .data.filter((prop) => {
        const contextKey = Renderer.#contextKey(prop.data[2]);
        return (
          contextKey !== null &&
          Type.isTrue(Erlang_Maps["is_key/2"](contextKey, context))
        );
      })
      .map((prop) => {
        const contextKey = Renderer.#contextKey(prop.data[2]);

        return Type.tuple([
          prop.data[0],
          Erlang_Maps["get/2"](contextKey, context),
        ]);
      });

    const propsFromContext = Erlang_Maps["from_list/1"](
      Type.list(propsFromContextTuples),
    );

    return Erlang_Maps["merge/2"](propsFromTemplate, propsFromContext);
  }

  // Based on invalid_dynamic_tag_value_message/1
  static #invalidDynamicTagValueMessage(value) {
    return `dynamic tag expression must evaluate to a component module or an HTML tag name string, got: ${Interpreter.inspect(value)}`;
  }

  static #isControlledValueInputType(inputType) {
    // Control value for all input types except radio and checkbox
    // Radios and checkboxes use value attribute for submit value, not display value
    // Also control value for textarea and select elements
    return inputType !== "checkbox" && inputType !== "radio";
  }

  // Based on nested_spread_value?/1
  // Maps and keyword lists compose nested attribute names, everything else is a leaf value. Structs
  // are excluded, since they are ordinary values which stringify through String.Chars, e.g. Date.
  // Whether the attribute is a $drop binding that isn't disabled ($drop={nil}).
  static #isEnabledDropBinding(attrDom) {
    return (
      $.#eventAttributeName(attrDom) === "$drop" &&
      !Operation.isDisabled(attrDom.data[1])
    );
  }

  static #isModuleRegisteredForCid(cid, moduleProxy) {
    const registeredModule = ComponentRegistry.getComponentModule(cid);

    return (
      registeredModule !== null &&
      Interpreter.isStrictlyEqual(registeredModule, moduleProxy.__exModule__)
    );
  }

  static #isNestedSpreadValue(value) {
    return (
      (Type.isMap(value) && !Type.isStruct(value)) || Type.isKeywordList(value)
    );
  }

  // Whether the value is what Phoenix.HTML.raw/1 returns.
  static #isPhoenixSafeTuple(value) {
    return (
      Type.isTuple(value) &&
      value.data.length === 2 &&
      Interpreter.isStrictlyEqual(value.data[0], Type.atom("safe"))
    );
  }

  static #isTrustedHtml(value) {
    return Type.isStruct(value, "Hologram.Template.TrustedHTML");
  }

  // Based on item_key_part/1
  //
  // The key part of a loop item: its :id, behind the struct's module for a struct, so that items
  // of two struct types sharing an id stay apart. An item whose :id can't be a key gets none and
  // falls back to its position, since nobody asked for that key. The source is the one-tuple
  // holding the item, or nil for a loop the compiler gives no item.
  //
  // WARNING: must match item_key_part/1 on the server.
  // Deps: [:maps.get/3]
  static #itemKeyPart(source) {
    if (!Type.isTuple(source) || source.data.length !== 1) {
      return null;
    }

    const item = source.data[0];

    if (!Type.isMap(item)) {
      return null;
    }

    const id = Erlang_Maps["get/3"](Type.atom("id"), item, null);

    if (id === null) {
      return null;
    }

    const body = $.#keyBody(id);

    return body === null ? null : `${$.#structKeyPart(item)}#${body}`;
  }

  // Based on key_body/1
  //
  // A key value as text, tagged by its type so that 1, "1" and :"1" stay apart, or null for a
  // value that can't be a key. Only an integer, a valid UTF-8 string or an identifier can be one,
  // so nil, true and false can't. An identifier tuple is "t" followed by its elements, each tagged
  // by its type and separated by ",".
  //
  // WARNING: must match key_body/1 on the server.
  static #keyBody(value) {
    if (Type.isInteger(value)) {
      return `i${value.value.toString()}`;
    }

    if (Type.isTuple(value)) {
      return Identifier.check(value) === null
        ? `t${value.data.map((element) => $.#keyBody(element)).join(",")}`
        : null;
    }

    if (Type.isBinary(value) && Bitstring.isText(value)) {
      return `s${$.#escapeKeyText(Bitstring.toText(value))}`;
    }

    if (
      Type.isAtom(value) &&
      value.value !== "nil" &&
      value.value !== "true" &&
      value.value !== "false"
    ) {
      return `a${$.#escapeKeyText(value.value)}`;
    }

    return null;
  }

  // Based on key_scope_parts/1
  //
  // The key parts a node in the given scope carries after its slot key: its item's own part, then
  // those of the enclosing items it also belongs to the top level of.
  //
  // WARNING: must match key_scope_parts/1 on the server.
  static #keyScopeParts(keyScope) {
    if (!keyScope) {
      return "";
    }

    return (keyScope.level ?? "") + keyScope.outer;
  }

  static #mapEventName(eventName, tagName, attrsVdom) {
    if (eventName === "change") {
      if (tagName === "input") {
        const inputType = attrsVdom?.type || "text";

        if (inputType !== "checkbox" && inputType !== "radio") {
          return "input";
        }
      } else if (tagName === "textarea") {
        return "input";
      }

      // Select elements keep the original change event (no mapping needed)
    }

    return eventName;
  }

  // A stateful component's identity is {module, cid}. When the module rendered under a cid changes
  // between renders, the registered entry describes a different component, so it is discarded and
  // the new module initializes fresh - state, emitted context, and action/command targeting all
  // follow the new module.
  // Deps: [:maps.get/2]
  static #maybeInitComponent(cid, moduleProxy, props) {
    let componentState = Renderer.#isModuleRegisteredForCid(cid, moduleProxy)
      ? ComponentRegistry.getComponentState(cid)
      : null;

    let componentEmittedContext;

    if (componentState === null) {
      // The declared defaults are in place before init/2 runs, so init/2 sees them and can override
      // them.
      //
      // WARNING: must match the struct init_component/3 starts from on the server.
      const initialComponentStruct = Type.componentStruct({
        props,
        state: Renderer.#getStateDefaults(moduleProxy),
      });

      const componentStruct = moduleProxy["init/2"](
        props,
        initialComponentStruct,
      );

      Renderer.validateDeclaredState(
        Erlang_Maps["get/2"](Type.atom("state"), componentStruct),
        moduleProxy,
        "init/2",
      );

      ComponentRegistry.putEntry(
        cid,
        Type.map([
          [Type.atom("module"), moduleProxy.__exModule__],
          [Type.atom("struct"), componentStruct],
        ]),
      );

      componentState = Erlang_Maps["get/2"](
        Type.atom("state"),
        componentStruct,
      );

      componentEmittedContext = Erlang_Maps["get/2"](
        Type.atom("emitted_context"),
        componentStruct,
      );

      Renderer.#maybeQueueActionFromClientInit(componentStruct, cid);
    } else {
      componentEmittedContext =
        ComponentRegistry.getComponentEmittedContext(cid);
    }

    return [componentState, componentEmittedContext];
  }

  // Deps: [:maps.get/2, :maps.get/3, :maps.put/3]
  static #maybeQueueActionFromClientInit(componentStruct, cid) {
    const nextAction = Erlang_Maps["get/2"](
      Type.atom("next_action"),
      componentStruct,
    );

    if (!Type.isNil(nextAction)) {
      ComponentRegistry.clearNextAction(cid);

      let actionWithTarget = nextAction;

      const existingTarget = Erlang_Maps["get/3"](
        Type.atom("target"),
        nextAction,
        Type.nil(),
      );

      if (Type.isNil(existingTarget)) {
        actionWithTarget = Erlang_Maps["put/3"](
          Type.atom("target"),
          cid,
          nextAction,
        );
      }

      // The render on the stack holds the queue, so the action runs once this render is done, with
      // the page it rendered into - or once its delay has elapsed, when it has one.
      Hologram.enqueueActionAfterDelay(
        actionWithTarget,
        Hologram.registryEpoch,
      );
    }
  }

  // WARNING: must match merge_neighbouring_text_nodes/1 on the server: adjacent text nodes join
  // into one, other nodes pass through.
  static #mergeNeighbouringTextNodes(nodes) {
    return nodes.reduce((acc, node) => {
      // Drop nil render results (e.g. <window>/<document> tags render to nil), otherwise
      // Snabbdom renders the boxed nil term as a stray "undefined" text node.
      if (Type.isNil(node)) {
        return acc;
      }

      if (
        typeof node === "string" &&
        acc.length > 0 &&
        typeof acc[acc.length - 1] === "string"
      ) {
        acc[acc.length - 1] = acc[acc.length - 1] + node;
      } else {
        acc.push(node);
      }

      return acc;
    }, []);
  }

  // The moves settleFocus() decides on, made while FocusEvent.isRuntimeFocusChange is set.
  static #moveFocus(focusCandidates, blurCandidates, isPageArrival) {
    for (const element of blurCandidates) {
      if (document.activeElement === element) {
        element.blur();
      }
    }

    // Whether an element can take focus depends on more than its tag - disabled, hidden by CSS,
    // inert, a tabindex - so each candidate is asked the only reliable way: by trying. A try that
    // moves focus anywhere counts, not only onto the candidate: a candidate's own focus handler
    // may pass focus on to a field inside it, and a candidate in a shadow root shows up as its
    // host.
    const candidates = focusCandidates
      .filter((element) => element.isConnected)
      .sort((a, b) => {
        if (a === b) {
          return 0;
        }

        return a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING
          ? -1
          : 1;
      });

    for (const element of candidates) {
      const previousActiveElement = document.activeElement;

      element.focus();

      if (
        document.activeElement === element ||
        document.activeElement !== previousActiveElement
      ) {
        return;
      }
    }

    if (isPageArrival) {
      document.activeElement?.blur();
    }
  }

  static #normalizeEventName(eventName) {
    return eventName.replace(/_/g, "");
  }

  // Based on normalize_prop_name/1
  // Deps: [:erlang.binary_to_atom/1]
  static #normalizePropName(propDom) {
    return Type.tuple([
      Erlang["binary_to_atom/1"](propDom.data[0]),
      propDom.data[1],
    ]);
  }

  // Spells a tag name the way the HTML parser would. A name written in a template is spelled by
  // the compiler; a name that first exists at render time is spelled here.
  //
  // The table is keyed by tag names taken from a value, so a lookup goes through Object.hasOwn - a
  // tag named like an Object.prototype member would otherwise resolve to the inherited value
  // instead of to itself.
  static #normalizeTagName(tagName) {
    const downcased = tagName.toLowerCase();

    return Object.hasOwn(SVG_ADJUSTED_TAG_NAMES, downcased)
      ? SVG_ADJUSTED_TAG_NAMES[downcased]
      : downcased;
  }

  // Returns true when the modifiers map carries a once modifier, which fires the binding a single
  // time then stops re-dispatching.
  // Deps: [:maps.is_key/2]
  static #onceFromModifiers(modifiersDom) {
    if (!modifiersDom) {
      return false;
    }

    return Type.isTrue(
      Erlang_Maps["is_key/2"](Type.atom("once"), modifiersDom),
    );
  }

  // Based on outer_key_parts/1
  static #outerKeyParts(keyScope) {
    return keyScope ? keyScope.outer : "";
  }

  // The single vnode a document is patched from, given the children a render produced.
  //
  // A render that names no <html> element describes a fragment rather than a document, so it is
  // wrapped in the elements a document must have. The wrappers carry no key: head and body are
  // each the only one of their kind, reached by name rather than through a children diff.
  static #pageVnodeFromChildren(children) {
    const htmlVnode = children.find((childVnode) => childVnode.sel === "html");

    if (typeof htmlVnode === "undefined") {
      return vnode("html", {attrs: {}, on: {}}, [
        vnode("body", {attrs: {}, on: {}}, children),
      ]);
    }

    return htmlVnode;
  }

  // One handler for every drop target that declares no drop effect, so a re-render hands the
  // registry the same function.
  static #preventDefault(event) {
    event.preventDefault();
  }

  // Returns true when the modifiers map carries a prevent_default modifier, which forces the
  // framework's preventDefault even on events that allow the default by design.
  // Deps: [:maps.is_key/2]
  static #preventDefaultFromModifiers(modifiersDom) {
    if (!modifiersDom) {
      return false;
    }

    return Type.isTrue(
      Erlang_Maps["is_key/2"](Type.atom("prevent_default"), modifiersDom),
    );
  }

  // Based on put_key_scope_level/2
  //
  // A new scope rather than a changed one, since the scope a component was given is shared with
  // its siblings.
  static #putKeyScopeLevel(keyScope, level) {
    return {level, outer: keyScope ? keyScope.outer : "", loop: keyScope?.loop};
  }

  // Based on put_rendered_ref/2
  //
  // Checks the element's ref and claims it for the element in the render in progress, returning the
  // binding the element's vnode goes into, or null when the element has no ref.
  //
  // WARNING: must match put_rendered_ref/2 on the server.
  static #putRenderedRef(attrsDom, module) {
    const attrDom = $.#findAttribute(attrsDom, "$ref");

    if (attrDom === null) {
      return null;
    }

    const ref = $.#validateRef(
      $.#expressionValue(attrDom.data[1].data[0].data[1]),
    );

    const key = Type.encodeMapKey(ref);
    const claimed = $.refBindings.get(key);

    if (claimed !== undefined) {
      Interpreter.raiseMisuseError(
        $.#duplicateRefMessage(ref, claimed.module, module),
      );
    }

    const binding = {ref, module, vnode: null};
    $.refBindings.set(key, binding);

    return binding;
  }

  // Based on raise_invalid_explicit_key/1
  //
  // WARNING: must match raise_invalid_explicit_key/1 on the server.
  static #raiseInvalidExplicitKey(value) {
    Interpreter.raiseArgumentError(
      Identifier.message(
        "$key takes an integer, a string, an identifier, like :search or {:message, 42}, or a map or struct with an :id that can be a key",
        value,
        $.#explicitKeyHint(value),
      ),
    );
  }

  // Based on raise_invalid_spread_value/1
  static #raiseInvalidSpreadValue(value) {
    Interpreter.raiseArgumentError(
      `spread value must be a map or a keyword list, got: ${Interpreter.inspect(value)}`,
    );
  }

  static #raisePhoenixSafeTuple() {
    Interpreter.raiseArgumentError(
      "Phoenix.HTML safe tuples aren't supported in Hologram templates, use trust_html/1 instead",
    );
  }

  // Based on ref_example/1
  static #refExample(ref) {
    const text = Interpreter.inspect(ref);

    return Type.isTuple(ref)
      ? `${text.slice(0, -1)}, item.id}`
      : `{${text}, item.id}`;
  }

  // Raises for a value that stands for markup where a value becomes text: an attribute value or a
  // prop value made of several parts.
  //
  // WARNING: must match value_dom_to_text/1 on the server.
  static #refuseMarkupValue(value) {
    if ($.#isTrustedHtml(value)) {
      Interpreter.raiseArgumentError(
        "trusted HTML can't be interpolated in an attribute value or in a prop value made of several parts, only as an element's content",
      );
    }

    if ($.#isPhoenixSafeTuple(value)) {
      $.#raisePhoenixSafeTuple();
    }
  }

  // Based on ref_writers/2
  static #refWriters(firstModule, secondModule) {
    if (!firstModule || !secondModule) {
      return "";
    }

    const firstName = Interpreter.moduleExName(firstModule);
    const secondName = Interpreter.moduleExName(secondModule);

    return firstName === secondName
      ? `, both from "${firstName}"`
      : `, one from "${firstName}" and one from "${secondName}"`;
  }

  // Based on render_tree_attribute/1
  //
  // WARNING: must match render_tree_attribute/1: an empty value list is a boolean attribute, a
  // nil or false expression value removes the attribute, and everything else collapses to one
  // unescaped string.
  static #renderAttribute(
    name,
    valueDom,
    isControlledValueAttr,
    isControlledCheckedAttr,
  ) {
    // Handle empty attribute: []
    if (valueDom.data.length === 0) {
      return [name, true];
    }

    // Handle single expressions: [expression: {value}]
    if (
      valueDom.data.length === 1 &&
      Type.isTuple(valueDom.data[0].data[1]) &&
      valueDom.data[0].data[1].data.length === 1
    ) {
      const expressionValue = valueDom.data[0].data[1].data[0];

      // Refused before a checked attribute reads only the value's truthiness, as the server, which
      // stringifies every attribute value, refuses it.
      $.#refuseMarkupValue(expressionValue);

      // Checkbox & radio checked attribute: preserve boolean semantics
      if (isControlledCheckedAttr) {
        return [name, Type.isTruthy(expressionValue)];
      }

      // Other attributes: nil/false removes the attribute
      if (Type.isFalsy(expressionValue)) {
        return [name, null];
      }
    }

    // Convert to text for remaining cases
    const valueText = Renderer.#valueDomToText(valueDom);

    // Input value attribute: preserve strings (including empty strings)
    if (isControlledValueAttr) {
      return [name, valueText];
    }

    // Checkbox & radio checked attribute: everything else is truthy (HTML-like behavior)
    if (isControlledCheckedAttr) {
      return [name, true];
    }

    // Other attributes: empty string becomes boolean true
    return [name, valueText === "" ? true : valueText];
  }

  // Based on render_tree_attributes/1
  // "props" are Snabbdom props, not Hologram component props
  static #renderAttributesAndProps(attrsDom, tagName) {
    const attrs = {};
    const props = {};

    if (attrsDom.data.length === 0) {
      return {attrs, props};
    }

    // Expand spreads into unboxed [name, valueDom] pairs, then filter out event attributes
    // (starting with $).
    //
    // A nonce the template wrote on a link, script or style element is dropped, as the server's
    // print_dom/2 drops it: only the document's nonce is in the policy, and the diff sets that one
    // on the element itself. Set as an attribute it would replace the document's nonce.
    const isNoncedElement = Vdom.isNoncedElement(tagName);

    const regularAttrs = $.#expandAttributeSpreads(attrsDom).filter(
      ([name]) =>
        !name.startsWith("$") &&
        !(isNoncedElement && name.toLowerCase() === "nonce"),
    );

    // Check if this is a form element with special handling of checked and value attributes
    const isFormInput =
      tagName === "input" || tagName === "textarea" || tagName === "select";

    let inputType;
    if (isFormInput) {
      inputType = $.#determineInputType(tagName, regularAttrs);
    }

    for (const [name, valueDom] of regularAttrs) {
      // Text-based inputs should have controlled value behavior
      // Radio and checkbox inputs use their value attribute as a regular HTML attribute
      let isControlledCheckedAttr, isControlledValueAttr;

      if (isFormInput) {
        if (name === "value" && $.#isControlledValueInputType(inputType)) {
          isControlledValueAttr = true;
        } else if (name === "checked" && tagName === "input") {
          isControlledCheckedAttr = true;
        }
      }

      const [, valueText] = Renderer.#renderAttribute(
        name,
        valueDom,
        isControlledValueAttr,
        isControlledCheckedAttr,
      );

      if (valueText !== null) {
        // For form element values: only set the property, never the attribute to maintain proper form behavior
        // - Preserves the browser's dirty flag tracking
        // - Ensures correct form reset behavior (resets to original defaultValue)
        // - Maintains proper autocomplete/autofill behavior
        // See: https://html.spec.whatwg.org/multipage/form-control-infrastructure.html#concept-fe-dirty
        if (isControlledValueAttr) {
          // Store the value for later use in hooks
          attrs["data-hologram-form-input-value"] = valueText;
        } else if (isControlledCheckedAttr) {
          // Store the checked state for later use in hooks
          attrs["data-hologram-form-input-checked"] = valueText;
        } else {
          attrs[name] = valueText;
        }
      }
    }

    return {attrs, props};
  }

  // Based on render_tree/3 (component case)
  static #renderComponent(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
    parentModule,
    slotsParentModule,
    keyScope,
  ) {
    const moduleProxy = Interpreter.moduleProxy(dom.data[1]);
    const propsDom = dom.data[2];
    let childrenDom = dom.data[3];

    const expandedChildrenDom = Renderer.#expandSlots(
      childrenDom,
      slots,
      slotsParentModule,
    );

    let props = Renderer.#injectPropsFromContext(
      Renderer.#castProps(propsDom, moduleProxy),
      moduleProxy,
      context,
    );

    props = Renderer.#injectDefaultPropValues(props, moduleProxy);

    Renderer.#validateProps(props, moduleProxy, dom.data[1], parentModule);

    const componentKeyScope = Renderer.#componentKeyScope(
      Renderer.#explicitKey(propsDom),
      props,
      keyScope,
    );

    if (Renderer.#hasCidProp(props)) {
      return Renderer.#renderStatefulComponent(
        moduleProxy,
        props,
        expandedChildrenDom,
        context,
        parentTagName,
        parentModule,
        componentKeyScope,
      );
    } else {
      return Renderer.#renderTemplate(
        moduleProxy,
        props,
        expandedChildrenDom,
        context,
        defaultTarget,
        parentTagName,
        parentModule,
        componentKeyScope,
      );
    }
  }

  // Based on validate_data_transfer/1
  // Returns what the tag's $data_transfer declares, as {dropEffect}, or null when the tag doesn't
  // declare it. The value it renders with must be a keyword list or a map of the keys the attribute
  // takes, each given once, with a drop effect only on a tag with a $drop binding (a disabled one
  // included).
  //
  // WARNING: must match validate_data_transfer/1 on the server, and the messages
  // Hologram.Template.DataTransfer builds.
  static #renderDataTransfer(attrsDom) {
    const attrDom = $.#findAttribute(attrsDom, "$data_transfer");

    if (attrDom === null) {
      return null;
    }

    const value = $.#expressionValue(attrDom.data[1].data[0].data[1]);
    const dataTransfer = {dropEffect: null};

    for (const [key, entryValue] of $.#dataTransferEntries(value)) {
      if (Type.isAtom(key) && key.value === "drop_effect") {
        if (
          !Type.isAtom(entryValue) ||
          !DROP_EFFECTS.includes(entryValue.value)
        ) {
          Interpreter.raiseMisuseError(
            `the $data_transfer drop_effect takes :none, :copy, :move or :link, got ${Interpreter.inspect(entryValue)}`,
          );
        }

        if (
          !attrsDom.data.some((attr) => $.#eventAttributeName(attr) === "$drop")
        ) {
          Interpreter.raiseMisuseError(
            "the $data_transfer drop_effect goes on a tag with a $drop binding, which makes it a drop target",
          );
        }

        dataTransfer.dropEffect = entryValue.value;
      } else {
        Interpreter.raiseMisuseError(
          `the $data_transfer attribute takes the :drop_effect key, got ${Interpreter.inspect(key)}`,
        );
      }
    }

    return dataTransfer;
  }

  // Based on render_tree/3 (dynamic tag cases)
  static #renderDynamicTag(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
    parentModule,
    slotsParentModule,
    keyScope,
  ) {
    const value = dom.data[1].data[0];
    const attrsDom = dom.data[2];
    const childrenDom = dom.data[3];

    // Mirrors the server's is_binary/1 guard - a non-binary bitstring is not a tag name.
    if (Type.isBinary(value)) {
      const tagNameText = Renderer.#normalizeTagName(Bitstring.toText(value));

      if ($.#findAttribute(attrsDom, "$ref") !== null) {
        $.#validateRefTag(tagNameText);
      }

      const tagName = Type.bitstring(tagNameText);

      return Renderer.renderDom(
        Type.tuple([Type.atom("element"), tagName, attrsDom, childrenDom]),
        context,
        slots,
        defaultTarget,
        parentTagName,
        parentModule,
        slotsParentModule,
        keyScope,
      );
    }

    if (!Type.isAtom(value)) {
      Interpreter.raiseArgumentError(
        Renderer.#invalidDynamicTagValueMessage(value),
      );
    }

    Renderer.#validateDynamicTagModule(value);

    // WARNING: must match render_tree/3's dynamic tag component clause on the server.
    if ($.#findAttribute(attrsDom, "$ref") !== null) {
      Interpreter.raiseMisuseError(
        `$ref can't go on the ${Interpreter.moduleExName(value)} component a dynamic tag renders - ` +
          "a component renders no element of its own, so put $ref on an element in its template " +
          "and pass the ref as a prop, like input_ref={:search}",
      );
    }

    return Renderer.renderDom(
      Type.tuple([Type.atom("component"), value, attrsDom, childrenDom]),
      context,
      slots,
      defaultTarget,
      parentTagName,
      parentModule,
      slotsParentModule,
      keyScope,
    );
  }

  // Based on rendered_from/1
  static #renderedFrom(parentModule) {
    return parentModule === null || typeof parentModule === "undefined"
      ? ""
      : `, rendered from "${Interpreter.moduleExName(parentModule)}"`;
  }

  // Based on render_tree/3 (element & slot case)
  static #renderElement(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
    parentModule,
    slotsParentModule,
    keyScope,
  ) {
    const currentTagName = Bitstring.toText(dom.data[1]);

    if (currentTagName === "slot") {
      return Renderer.#renderSlotElement(
        slots,
        context,
        defaultTarget,
        parentTagName,
        slotsParentModule,
        keyScope,
      );
    }

    // A <window> or <document> tag has no DOM node: it records its event bindings for the render loop
    // to reconcile into real listeners on the window or document, with the enclosing component
    // (defaultTarget) as the default dispatch target, and renders nil.
    if (currentTagName === "window" || currentTagName === "document") {
      const target = currentTagName === "window" ? window : document;
      Renderer.#collectListenerBindings(target, dom.data[2], defaultTarget);
      return Type.nil();
    }

    const attrsDom = dom.data[2];

    const {attrs: attrsVdom, props: propsVdom} =
      Renderer.#renderAttributesAndProps(attrsDom, currentTagName);

    // Read right after the other attributes, before the children render, so that a $key which can't
    // be a key raises where render_tree_attributes/2 raises on the server - also on an element that
    // takes a resource key instead.
    const slotKey = $.#renderSlotKey(attrsDom, keyScope);

    // Before the children, so an element is claimed ahead of the elements inside it, as the server
    // claims it.
    const refBinding = $.#putRenderedRef(attrsDom, parentModule);

    // $focused renders as autofocus, the way the server renders it, so the boot patch finds the
    // attribute the server sent and the focus hooks read one attribute either way. An autofocus
    // from a spread yields to $focused.
    //
    // WARNING: must match apply_focused_attribute/1 on the server.
    const focused = Renderer.#renderFocused(attrsDom);

    if (focused === true) {
      attrsVdom.autofocus = true;
    } else if (focused === false) {
      delete attrsVdom.autofocus;
    }

    const dataTransfer = Renderer.#renderDataTransfer(attrsDom);

    const eventListenersVdom = Renderer.#renderEventListeners(
      attrsDom,
      currentTagName,
      attrsVdom,
      defaultTarget,
    );

    const childrenDom = dom.data[3];

    // The element's children are complete here, whatever nesting of blocks, loops and components
    // produced them, so this is where a repeated key is settled against the rest of the list.
    //
    // The element is one node of whatever children list it sits in, so a loop item's key reaches
    // the element and stops there: its children are rendered without a key scope, as
    // render_tree/3's element clause renders them on the server.
    let childrenVdom = Vdom.finalizeChildren(
      Renderer.renderDom(
        childrenDom,
        context,
        slots,
        defaultTarget,
        currentTagName,
        parentModule,
        slotsParentModule,
        null,
      ),
    );

    // Checked on the rendered children rather than where the value is interpolated, since the value
    // can get here through a component, a slot or a nested element, none of which carry this tag
    // name, and the browser reads all of it as text all the same.
    //
    // WARNING: must match render_tree/3's element clause on the server.
    if (
      TRUSTED_HTML_REFUSED_PARENTS.has(currentTagName) &&
      $.#containsTrustedHtml(childrenVdom)
    ) {
      Interpreter.raiseArgumentError(
        `trusted HTML can't be interpolated inside a <${currentTagName}> element, whose content the browser reads as text`,
      );
    }

    const data = {attrs: attrsVdom, on: eventListenersVdom};

    if (Object.keys(propsVdom).length > 0) {
      data.props = propsVdom;
    }

    if (focused !== null) {
      data.hologramFocused = focused;
    }

    // One hook object per element, assembled in steps, so that an input can carry a controlled
    // value and focus hooks at once.
    const hook = {};

    // Handle controlled form inputs (value for text inputs/textareas/selects, checked for checkboxes/radios)
    // Radio/checkbox inputs use regular value attributes and controlled checked attributes
    // An element has either controlled value OR controlled checked, never both

    if (
      (currentTagName === "input" ||
        currentTagName === "textarea" ||
        currentTagName === "select") &&
      attrsVdom["data-hologram-form-input-value"] !== undefined
    ) {
      const hologramFormInputValue =
        attrsVdom["data-hologram-form-input-value"];
      delete attrsVdom["data-hologram-form-input-value"];
      data.hologramFormInputValue = hologramFormInputValue;

      hook.create = (_emptyVnode, newVnode) => {
        Renderer.#updateFormInputValue(newVnode.elm, hologramFormInputValue);
      };

      hook.update = (_oldVnode, newVnode) => {
        const newValue = newVnode.data.hologramFormInputValue;
        Renderer.#updateFormInputValue(newVnode.elm, newValue);
      };
    } else if (
      currentTagName === "input" &&
      attrsVdom["data-hologram-form-input-checked"] !== undefined
    ) {
      const hologramFormInputChecked =
        attrsVdom["data-hologram-form-input-checked"];
      delete attrsVdom["data-hologram-form-input-checked"];
      data.hologramFormInputChecked = hologramFormInputChecked;

      hook.create = (_emptyVnode, newVnode) => {
        Renderer.#updateFormInputChecked(
          newVnode.elm,
          hologramFormInputChecked,
        );
      };

      hook.update = (_oldVnode, newVnode) => {
        const newChecked = newVnode.data.hologramFormInputChecked;
        Renderer.#updateFormInputChecked(newVnode.elm, newChecked);
      };
    }

    // Only an element that can ask for focus carries the focus hooks, so every other element costs
    // nothing extra. A $focused that is false still needs the update hook, since its turning false
    // is what gives focus up.
    if (attrsVdom.autofocus !== undefined || focused !== null) {
      const updateFormInput = hook.update;

      hook.insert = $.#collectInsertedFocus;

      hook.update = (oldVnode, newVnode) => {
        updateFormInput?.(oldVnode, newVnode);
        $.#collectUpdatedFocus(oldVnode, newVnode);
      };
    }

    if (Object.keys(hook).length > 0) {
      data.hook = hook;
    }

    if (
      currentTagName === "link" &&
      typeof attrsVdom.href === "string" &&
      attrsVdom.href
    ) {
      data.key = `__hologramLink__:${attrsVdom.href}`;
    } else if (
      currentTagName === "script" &&
      typeof attrsVdom.src === "string" &&
      attrsVdom.src
    ) {
      data.key = `__hologramScript__:${attrsVdom.src}`;
    } else if (currentTagName === "script" && childrenVdom[0]) {
      // Make sure the script is executed if the code changes.
      //
      // The one child is the whole body: everything a script can hold renders to text, and
      // #mergeNeighbouringTextNodes joins adjacent text into a single child. That is what lets
      // this equal the textContent Vdom.#resourceKey reads off the live node, which is what the
      // boot patch compares the two sides by. Splitting a script body into more than one child
      // would part the two keys and make the page re-run its own scripts on boot.
      data.key = `__hologramScript__:${childrenVdom[0]}`;
    } else {
      // What the element loads names it better than where it sits, so a slot key only applies to
      // elements that load nothing.
      if (slotKey !== null) {
        data.key = slotKey.key;

        // An element keyed by its item's identity carries the item's key scope, which tells two
        // items of one loop that claim the same identity apart from one item rendering a place
        // twice, or one loop rendered twice - see Vdom.dedupeKeys.
        if (slotKey.isItemKeyed) {
          data.hologramKeyScope = keyScope;
        }
      }
    }

    // A script's URL and code go to a script sink Trusted Types guards, which takes them only through
    // a policy, while the diff would set the URL as a plain attribute and the code as a text child.
    // So they travel beside the attributes and children, and the vdom assigns them through the
    // runtime's policy when it creates the element. Its key, read from them above, names the
    // element by what it runs.
    if (currentTagName === "script") {
      data.hologramScript = {
        code: typeof childrenVdom[0] === "string" ? childrenVdom[0] : null,
        src: Vdom.scriptSrc(attrsVdom.src),
      };

      delete attrsVdom.src;
      childrenVdom = [];
    }

    const elementVnode = vnode(currentTagName, data, childrenVdom);

    if (refBinding !== null) {
      refBinding.vnode = elementVnode;
    }

    Renderer.#collectClickOutsideBindings(
      attrsDom,
      elementVnode,
      defaultTarget,
    );

    Renderer.#collectDropTargetBindings(
      attrsDom,
      {vnode: elementVnode},
      dataTransfer,
    );

    Renderer.#collectReachBindings(attrsDom, elementVnode, defaultTarget);

    Renderer.#collectResizeBindings(attrsDom, elementVnode, defaultTarget);

    return elementVnode;
  }

  static #renderEventListeners(attrsDom, tagName, attrsVdom, defaultTarget) {
    if (attrsDom.data.length === 0) {
      return {};
    }

    // Slot key = the attribute's position: stable across re-renders (attributes are never removed,
    // only nilled in place) and independent of the action spec's evaluated params.
    const handlersByEvent = attrsDom.data.reduce((acc, attrDom, attrIndex) => {
      const binding = $.#buildEventBinding(
        attrDom,
        attrIndex,
        tagName,
        attrsVdom,
        defaultTarget,
      );

      if (binding === null) {
        return acc;
      }

      acc[binding.eventName] = acc[binding.eventName] || [];
      acc[binding.eventName].push(binding.handler);

      return acc;
    }, {});

    // A DOM event name can have several bindings on one element (e.g. multiple keyboard key
    // filters), so each event maps to a single dispatcher that runs every registered handler.
    return Object.fromEntries(
      Object.entries(handlersByEvent).map(([eventName, handlers]) => [
        eventName,
        (event) => handlers.forEach((handler) => handler(event)),
      ]),
    );
  }

  // Based on apply_focused_attribute/1
  // Returns the element's $focused as a boolean, or null when the element doesn't declare it. The
  // last one wins, the way the server resolves it, so the scan runs from the end and stops at the
  // first one it meets. The build guarantees $focused carries no value (true, as for any boolean
  // attribute) or a single expression.
  static #renderFocused(attrsDom) {
    for (let index = attrsDom.data.length - 1; index >= 0; index -= 1) {
      const attrDom = attrsDom.data[index];

      if (Type.isRecordTuple(attrDom, "spread", 2)) {
        continue;
      }

      if (Bitstring.toText(attrDom.data[0]) === "$focused") {
        const valueDom = attrDom.data[1];

        return (
          valueDom.data.length === 0 ||
          Type.isTruthy(valueDom.data[0].data[1].data[0])
        );
      }
    }

    return null;
  }

  // Based on render_tree/3 (loop item case)
  //
  // A loop's iteration renders into the children list the loop sits in, so the nodes it places
  // there carry the item's key on top of the place they hold in the template. Its scope starts
  // afresh even when the item has no key, so an enclosing item's part stays an outer part.
  //
  // The loop is the run of items one evaluation of a for block produced, shared by its items' scopes
  // (and by the scopes components in them override), so that Vdom.dedupeKeys tells two items of one
  // loop claiming the same identity apart from the same loop rendered twice into one list. The
  // server has no such check, so it keeps no loop.
  //
  // WARNING: the key parts must match render_tree/3's loop item clause on the server.
  static #renderLoopItem(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
    parentModule,
    slotsParentModule,
    keyScope,
    loop = {},
  ) {
    const itemKeyScope = {
      level: $.#itemKeyPart(dom.data[1]),
      outer: $.#keyScopeParts(keyScope),
      loop,
    };

    return Renderer.renderDom(
      dom.data[2],
      context,
      slots,
      defaultTarget,
      parentTagName,
      parentModule,
      slotsParentModule,
      itemKeyScope,
    );
  }

  // Based on render_tree/3 (list case)
  //
  // WARNING: must match render_tree/3's list clause step for step: filter out nil input nodes,
  // render each node, splice one level of node lists (a component renders to a list), then merge
  // adjacent text nodes.
  //
  // Blocks are left alone here: a block's body and a loop's iterations are lists of their own, and
  // the nodes they render are only ever part of the enclosing element's children. Numbering the
  // keys belongs to whoever owns that list - see Vdom.finalizeChildren.
  static #renderNodes(
    nodes,
    context,
    slots,
    defaultTarget,
    parentTagName,
    parentModule,
    slotsParentModule,
    keyScope,
  ) {
    // The loop items of one list are one evaluation of a for block - see #renderLoopItem.
    const loop = {};

    return Renderer.#mergeNeighbouringTextNodes(
      nodes.data
        // There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if} or DOCTYPE
        .filter((node) => !Type.isNil(node))
        .map((node) =>
          Type.isRecordTuple(node, "loop_item", 3)
            ? Renderer.#renderLoopItem(
                node,
                context,
                slots,
                defaultTarget,
                parentTagName,
                parentModule,
                slotsParentModule,
                keyScope,
                loop,
              )
            : Renderer.renderDom(
                node,
                context,
                slots,
                defaultTarget,
                parentTagName,
                parentModule,
                slotsParentModule,
                keyScope,
              ),
        )
        .flat(),
    );
  }

  // Based on render_page_inside_layout/3
  // Deps: [:maps.get/2, :maps.merge/2]
  static #renderPageInsideLayout(
    pageModuleProxy,
    pageParams,
    pageComponentStruct,
  ) {
    const pageEmittedContext = Erlang_Maps["get/2"](
      Type.atom("emitted_context"),
      pageComponentStruct,
    );

    const pageState = Erlang_Maps["get/2"](
      Type.atom("state"),
      pageComponentStruct,
    );

    const vars = Erlang_Maps["merge/2"](pageParams, pageState);
    const pageDom = Renderer.#evaluateTemplate(pageModuleProxy, vars);

    const layoutModule = pageModuleProxy["__layout_module__/0"]();

    const layoutPropsDom = Renderer.#buildLayoutPropsDom(
      pageModuleProxy,
      pageState,
    );

    const pageNodes = Type.tuple([Type.atom("page"), pageDom]);

    const layoutNode = Type.tuple([
      Type.atom("component"),
      layoutModule,
      layoutPropsDom,
      pageNodes,
    ]);

    return Renderer.renderDom(
      layoutNode,
      pageEmittedContext,
      Type.keywordList(),
      Type.bitstring("layout"),
      null,
      pageModuleProxy.__exModule__,
      null,
    );
  }

  // Based on render_tree/3 (public comment case)
  static #renderPublicComment(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
    parentModule,
    slotsParentModule,
  ) {
    const childrenDom = dom.data[1];

    // Rendered without a key scope, as render_tree/3's public comment clause renders them: the
    // comment is one node, and its children are markup inside it.
    let childrenVdom = Renderer.renderDom(
      childrenDom,
      context,
      slots,
      defaultTarget,
      parentTagName,
      parentModule,
      slotsParentModule,
      null,
    );

    // WARNING: must match render_tree/3's public comment clause on the server.
    if ($.#containsTrustedHtml(childrenVdom)) {
      Interpreter.raiseArgumentError(
        "trusted HTML can't be interpolated inside an HTML comment, only as an element's content",
      );
    }

    const commentContent = childrenVdom
      .map((child) =>
        typeof child === "string"
          ? child
          : vnodeToHtml(Renderer.#withScriptsInMarkup(child)),
      )
      .join("");

    return vnode("!", commentContent);
  }

  // The key an element carries for the place it holds in its template, or null when it has none.
  //
  // The key is written as an attribute because that is how a value reaches an element through
  // every path a template has - spreads, dynamic tags, a component passing attributes on - but it
  // is never one: the server leaves it out of the markup and the client turns it into the vnode's
  // key here, so it exists only between the two renderers.
  //
  // Read straight off the attributes rather than through expand_attribute_spreads/1, which
  // #renderAttributesAndProps has already run over the same list: this runs for every element of
  // every render, and no spread has to be expanded to find the key. Spread entries are skipped
  // rather than looked into, since a spread carrying a $-prefixed name is refused before it gets
  // here.
  //
  // Scanned from the end because the compiler appends the key after everything the template author
  // wrote, so the scan ends on its first step.
  //
  // Inside a loop item the item's key parts follow the key of the element's place, as
  // render_tree_attribute/2 composes it on the server. A server tree carries the composed key as
  // the attribute's text and renders without a key scope, so it reads back unchanged.
  //
  // Returns {key, isItemKeyed}, where isItemKeyed says the element is keyed by the identity of the
  // item whose top level it belongs to - its own $key, the item's :id, or a component's $key or cid
  // - rather than only by its place and the parts of enclosing items.
  //
  // WARNING: the key must match render_tree_attribute/2's $key clause on the server.
  static #renderSlotKey(attrsDom, keyScope) {
    for (let index = attrsDom.data.length - 1; index >= 0; index -= 1) {
      const attrDom = attrsDom.data[index];

      if (Type.isRecordTuple(attrDom, "spread", 2)) {
        continue;
      }

      if (Bitstring.toText(attrDom.data[0]) === "$key") {
        const valueDom = attrDom.data[1];

        if (
          valueDom.data.length === 1 &&
          Type.isRecordTuple(valueDom.data[0], "text", 2)
        ) {
          return {
            key:
              Bitstring.toText(valueDom.data[0].data[1]) +
              $.#keyScopeParts(keyScope),
            isItemKeyed: Boolean(keyScope) && keyScope.level !== null,
          };
        }

        // The template author's own $key, which the compiler puts behind the key of the element's
        // place. It takes the place of the item's own part, and the parts of enclosing items still
        // follow it.
        if (
          valueDom.data.length === 2 &&
          Type.isRecordTuple(valueDom.data[0], "text", 2) &&
          Type.isRecordTuple(valueDom.data[1], "expression", 2)
        ) {
          return {
            key:
              Bitstring.toText(valueDom.data[0].data[1]) +
              $.#explicitKeyPart($.#expressionValue(valueDom.data[1].data[1])) +
              $.#outerKeyParts(keyScope),
            isItemKeyed: Boolean(keyScope),
          };
        }

        return {key: $.#valueDomToText(valueDom), isItemKeyed: false};
      }
    }

    return null;
  }

  // Based on render_tree/3 (slot case)
  static #renderSlotElement(
    slots,
    context,
    defaultTarget,
    parentTagName,
    slotsParentModule,
    keyScope,
  ) {
    const slotDom = Interpreter.accessKeywordListElement(
      slots,
      Type.atom("default"),
    );

    return Renderer.renderDom(
      slotDom,
      context,
      Type.keywordList(),
      defaultTarget,
      parentTagName,
      slotsParentModule,
      slotsParentModule,
      keyScope,
    );
  }

  // Based on render_stateful_component/7
  // Deps: [:maps.get/2, :maps.merge/2]
  static #renderStatefulComponent(
    moduleProxy,
    props,
    childrenDom,
    context,
    parentTagName,
    parentModule,
    keyScope,
  ) {
    const cid = Erlang_Maps["get/2"](Type.atom("cid"), props);

    const [componentState, componentEmittedContext] =
      Renderer.#maybeInitComponent(cid, moduleProxy, props);

    // Rewritten on every render rather than only at init, so a handler reading a prop gets the
    // value the latest render used rather than one taken when the component mounted. Runs after
    // #maybeInitComponent, which is what creates the registry entry on a first render.
    ComponentRegistry.putComponentProps(cid, props);

    const vars = Erlang_Maps["merge/2"](props, componentState);
    const mergedContext = Erlang_Maps["merge/2"](
      context,
      componentEmittedContext,
    );

    return Renderer.#renderTemplate(
      moduleProxy,
      vars,
      childrenDom,
      mergedContext,
      cid,
      parentTagName,
      parentModule,
      keyScope,
    );
  }

  // Based on render_template/7
  //
  // A component has no node of its own: the nodes its template renders sit in the children list
  // the component is placed in, so they take the key scope the component was given.
  static #renderTemplate(
    moduleProxy,
    vars,
    childrenDom,
    context,
    defaultTarget,
    parentTagName,
    parentModule,
    keyScope,
  ) {
    const dom = Renderer.#evaluateTemplate(moduleProxy, vars);
    const slots = Type.keywordList([[Type.atom("default"), childrenDom]]);

    return Renderer.renderDom(
      dom,
      context,
      slots,
      defaultTarget,
      parentTagName,
      moduleProxy.__exModule__,
      parentModule,
      keyScope,
    );
  }

  // Enum.min/1 over the keys, in term order. Equal keys of different types, like 1 and 1.0, give
  // the integer, which sorts first among map keys on the BEAM. compareTerms doesn't compare every
  // type yet, and a key it can't compare leaves the first key standing rather than raising in
  // place of the StateError.
  static #smallestStateKey(keys) {
    return keys.reduce((min, candidate) => {
      let order;

      try {
        order = Interpreter.compareTerms(candidate, min);
      } catch {
        return min;
      }

      return order < 0 || (order === 0 && Type.isInteger(candidate))
        ? candidate
        : min;
    });
  }

  // Based on spread_entries/1
  // Returns [key, value] term pairs. Structs are maps, but their __struct__ key is not a name.
  static #spreadEntries(value) {
    if (Type.isMap(value) && !Type.isStruct(value)) {
      return Object.values(value.data);
    }

    if (Type.isKeywordList(value)) {
      return value.data.map((entryDom) => entryDom.data);
    }

    return $.#raiseInvalidSpreadValue(value);
  }

  // Returns true when the modifiers map carries a stop_propagation modifier, which stops the
  // event from bubbling past the bound element.
  // Deps: [:maps.is_key/2]
  static #stopPropagationFromModifiers(modifiersDom) {
    if (!modifiersDom) {
      return false;
    }

    return Type.isTrue(
      Erlang_Maps["is_key/2"](Type.atom("stop_propagation"), modifiersDom),
    );
  }

  // Based on struct_key_part/1
  //
  // WARNING: must match struct_key_part/1 on the server.
  // Deps: [:maps.get/3]
  static #structKeyPart(item) {
    const module = Erlang_Maps["get/3"](Type.atom("__struct__"), item, null);

    return module !== null && Type.isAtom(module)
      ? `#m${$.#escapeKeyText(module.value)}`
      : "";
  }

  // Returns the throttle window in milliseconds from a modifiers map, or null when there is no
  // throttle modifier.
  // Deps: [:maps.get/3]
  static #throttleMsFromModifiers(modifiersDom) {
    if (!modifiersDom) {
      return null;
    }

    const throttle = Erlang_Maps["get/3"](
      Type.atom("throttle"),
      modifiersDom,
      null,
    );

    return throttle === null ? null : Number(throttle.value);
  }

  // Deps: [:maps.get/2]
  static #trustedHtmlVnode(trustedHtml, parentModule) {
    const html = Erlang_Maps["get/2"](Type.atom("html"), trustedHtml);

    const module =
      parentModule === null || typeof parentModule === "undefined"
        ? null
        : Interpreter.moduleExName(parentModule);

    return Vdom.trustedHtmlVnode(Bitstring.toText(html), module);
  }

  // Based on undeclared_state_hint/2
  static #undeclaredStateHint(key, moduleProxy) {
    const isPage = "__params__/0" in moduleProxy;

    if (isPage && key.value === "cid") {
      return `"cid" is the layout's cid prop, put the value under another name`;
    }

    const holder = isPage ? "param" : "prop";

    const holderNames = (
      isPage ? moduleProxy["__params__/0"]() : moduleProxy["__props__/0"]()
    ).data.map((definition) => definition.data[0].value);

    if (!isPage) {
      holderNames.push("cid");
    }

    return holderNames.includes(key.value)
      ? `"${key.value}" is a ${holder}, read it from component.props instead`
      : "declare it with state/2 or state/3";
  }

  // Based on undeclared_state_message/3
  static #undeclaredStateMessage(key, moduleProxy, handler) {
    const moduleName = Interpreter.moduleExName(moduleProxy.__exModule__);

    if (!Type.isAtom(key)) {
      return (
        `state key ${Interpreter.inspect(key)} isn't an atom, but ${handler} put it in ` +
        `"${moduleName}" - state is declared with atom names`
      );
    }

    return (
      `state "${key.value}" isn't declared in "${moduleName}", but ${handler} put it - ` +
      Renderer.#undeclaredStateHint(key, moduleProxy)
    );
  }

  static #updateFormInputChecked(element, newChecked) {
    // Skip redundant DOM writes
    if (newChecked === element.checked) {
      return;
    }

    element.checked = newChecked;
  }

  static #updateFormInputValue(element, newValue) {
    // Skip redundant DOM writes
    if (newValue === element.value) {
      return;
    }

    element.value = newValue;
  }

  // A component module is recognized by its __props__/0 function, which the compiler bundles for
  // every component it reaches (a page module carries __params__/0 instead). A module that isn't in
  // the bundle at all has no proxy: the compiler can follow only module atoms appearing as literals
  // in client-reachable code, so a module reached any other way never made it into the page bundle.
  static #validateDynamicTagModule(module) {
    if (Type.isAlias(module)) {
      const moduleProxy = Interpreter.moduleProxy(module);

      if (typeof moduleProxy === "undefined") {
        throw new HologramRuntimeError(
          `module ${Interpreter.inspect(module)} is not available on the client, because it was not reachable from client code at compile time`,
        );
      }

      if ("__props__/0" in moduleProxy) {
        return;
      }
    }

    Interpreter.raiseArgumentError(
      Renderer.#invalidDynamicTagValueMessage(module) +
        ", which is not a component module",
    );
  }

  // Based on validate_props/3
  // Runs last in the props pipeline, so the map it sees is exactly what the component's template
  // will see. The compiler judges what a template spells out and what a declaration defaults to, so
  // what reaches here is what only exists once the page runs: a value from context, or one arriving
  // through a spread.
  // Deps: [:lists.member/2, :maps.get/2, :maps.is_key/2]
  static #validateProps(props, moduleProxy, module, parentModule) {
    const constrainedProps = Renderer.#getConstrainedProps(moduleProxy);

    if (constrainedProps.length === 0) {
      return;
    }

    const moduleName = Interpreter.moduleExName(module);

    for (const {name, required, values} of constrainedProps) {
      const isPresent = Type.isTrue(Erlang_Maps["is_key/2"](name, props));

      if (required && !isPresent) {
        Interpreter.raiseError(
          "Hologram.PropError",
          `component "${moduleName}" is missing required prop "${name.value}"` +
            Renderer.#renderedFrom(parentModule),
        );
      }

      if (values !== null && isPresent) {
        const value = Erlang_Maps["get/2"](name, props);

        if (Type.isFalse(Erlang_Lists["member/2"](value, values))) {
          Interpreter.raiseError(
            "Hologram.PropError",
            `prop "${name.value}" of component "${moduleName}" must be one of ` +
              `${Interpreter.inspect(values)}, got: ${Interpreter.inspect(value)}` +
              Renderer.#renderedFrom(parentModule),
          );
        }
      }
    }
  }

  // Based on validate_ref/1
  //
  // WARNING: must match validate_ref/1 on the server.
  static #validateRef(ref) {
    if (
      Type.isAtom(ref) &&
      (ref.value === "window" || ref.value === "document")
    ) {
      Interpreter.raiseMisuseError(
        `:${ref.value} is a built-in ref, so a template can't name an element with it - JS.element(:${ref.value}) returns the ${ref.value}`,
      );
    }

    const result = Identifier.check(ref);

    if (result !== null) {
      const hint = Type.isReference(ref) ? ELIXIR_REFERENCE_HINT : result.hint;

      Interpreter.raiseMisuseError(
        Identifier.message(REF_EXPECTATION, ref, hint),
      );
    }

    return ref;
  }

  // Based on validate_ref_tag/1
  //
  // WARNING: must match validate_ref_tag/1 on the server.
  static #validateRefTag(tagName) {
    switch (tagName) {
      case "window":
      case "document":
        Interpreter.raiseMisuseError(
          `$ref can't go on a <${tagName}> tag, which renders no element - JS.element(:${tagName}) returns the ${tagName}`,
        );
        break;

      case "slot":
        Interpreter.raiseMisuseError(
          "$ref can't go on a <slot> tag, which renders no element of its own - put it on an element in the slot content",
        );
        break;

      case "html":
        Interpreter.raiseMisuseError(
          "$ref can't go on the <html> tag - JS.element(:document) returns the document, whose documentElement is the <html> element",
        );
    }
  }

  // Based on validate_spread_key/1
  // Event bindings require compile-time modifier parsing and listener collection, so they can be
  // written only as literal attributes. Silently not binding an intended event would be worse than
  // erroring here.
  static #validateSpreadKey(key) {
    if (key.startsWith("$")) {
      Interpreter.raiseArgumentError(
        `event bindings can't be set through a spread, got the "${key}" key`,
      );
    }

    return key;
  }

  // WARNING: must match value_dom_to_text/1 on the server: parts evaluate raw and
  // concatenate, with no escaping.
  static #valueDomToText(valueDom) {
    return Bitstring.toText(Renderer.valueDomToBitstring(valueDom));
  }

  // Returns the within modifier's CSS distance (e.g. "200px", "50%") from a modifiers map, or
  // undefined when there is no within modifier, so the scroll-edge listener falls back to its
  // default within (100%).
  // Deps: [:maps.get/3]
  static #withinFromModifiers(modifiersDom) {
    if (!modifiersDom) {
      return undefined;
    }

    const within = Erlang_Maps["get/3"](
      Type.atom("within"),
      modifiersDom,
      null,
    );

    return within === null ? undefined : Bitstring.toText(within);
  }

  // A vnode printed as markup, the way the server prints it, with every script's URL and code put
  // back where markup has them: data.hologramScript is the vdom's carrier for them, which
  // snabbdom-to-html does not read.
  static #withScriptsInMarkup(vnodeOrText) {
    if (typeof vnodeOrText === "string" || vnodeOrText.sel === undefined) {
      return vnodeOrText;
    }

    const children = (vnodeOrText.children ?? []).map((child) =>
      Renderer.#withScriptsInMarkup(child),
    );

    const script = vnodeOrText.data?.hologramScript;

    if (script === undefined) {
      return {...vnodeOrText, children};
    }

    const attrs =
      script.src === null
        ? vnodeOrText.data.attrs
        : {
            ...vnodeOrText.data.attrs,
            src: script.src === "" ? true : script.src,
          };

    return vnode(
      vnodeOrText.sel,
      {...vnodeOrText.data, attrs},
      script.code === null ? [] : [script.code],
    );
  }
}

const $ = Renderer;
