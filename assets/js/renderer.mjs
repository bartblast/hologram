// Based on Elixir Hologram.Template.Renderer

"use strict";

import Bitstring from "./bitstring.mjs";
import ComponentRegistry from "./component_registry.mjs";
import Debouncer from "./debouncer.mjs";
import EventListeners from "./event_listeners.mjs";
import GlobalRegistry from "./global_registry.mjs";
import Hologram from "./hologram.mjs";
import HologramInterpreterError from "./errors/interpreter_error.mjs";
import HologramRuntimeError from "./errors/runtime_error.mjs";
import InitActionQueue from "./init_action_queue.mjs";
import Interpreter from "./interpreter.mjs";
import KeyboardEvent from "./events/keyboard_event.mjs";
import LocalDatabase from "./local_database.mjs";
import ManuallyPortedElixirHologramQuery from "./elixir/hologram/query.mjs";
import Model from "./model.mjs";
import Once from "./once.mjs";
import QueryKernel from "./query_kernel.mjs";
import Throttler from "./throttler.mjs";
import Type from "./type.mjs";
import Utils from "./utils.mjs";
import Vdom from "./vdom.mjs";

import {h as vnode} from "./vendor/snabbdom/build/index.js";
import vnodeToHtml from "snabbdom-to-html";

export default class Renderer {
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

  // Deferred resize-observer bindings collected during the current render, each a {vnode, handler}.
  // An element's observer target is its live DOM node, which Snabbdom sets on the vnode only during
  // patch, so the binding is held here until resolveResizeBindings turns it into a registry binding
  // once `.elm` exists. renderPage() resets this.
  static resizeBindings = [];

  // Based on render_tree/3
  //
  // WARNING: on navigation the server ships this client the same render as an evaluated tree
  // (Renderer.render_tree/3), and the vnodes built from that tree must equal the vnodes this
  // renderer builds for the page's own render - otherwise hydration rebuilds nodes instead of
  // adopting them. Every normalization step here must therefore match render_tree/3, clause by
  // clause.
  static renderDom(dom, context, slots, defaultTarget, parentTagName) {
    if (Type.isList(dom)) {
      return Renderer.#renderNodes(
        dom,
        context,
        slots,
        defaultTarget,
        parentTagName,
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
        );

      case "component":
        return Renderer.#renderComponent(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
        );

      case "expression":
        // HTML escaping is done by Snabbdom.
        //
        // WARNING: the server's render_tree/3 diverges here on purpose: it entity-encodes an
        // expression evaluated inside a script element, because in its HTML projection an
        // interpolated value could otherwise break out of the script with a "</script" of its
        // own. This renderer sets text through the DOM, where no markup context exists to break
        // out of. Do not "fix" either side alone.
        return $.toText(dom.data[1].data[0]);

      case "page":
        return Renderer.renderDom(
          dom.data[1],
          context,
          slots,
          Type.bitstring("page"),
          parentTagName,
        );

      case "dynamic_tag":
        return Renderer.#renderDynamicTag(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
        );

      case "doctype":
        return Type.nil();

      case "public_comment":
        return Renderer.#renderPublicComment(
          dom,
          context,
          slots,
          defaultTarget,
          parentTagName,
        );
    }
  }

  // Based on: render_page/2
  static renderPage(pageModule, pageParams) {
    Renderer.listenerBindings = [];
    Renderer.reachBindings = [];
    Renderer.resizeBindings = [];

    const pageModuleProxy = Interpreter.moduleProxy(pageModule);

    const cid = Type.bitstring("page");
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
  // elements, text, comments and the doctype, and the clauses those reach in renderDom read
  // neither context nor slots. They are passed empty for that reason rather than as a stand-in
  // for a real render's own.
  //
  // WARNING: the vnodes this returns must equal the vnodes renderPage returns for the same page,
  // or the render that follows rebuilds nodes instead of adopting the ones this put on screen.
  // Both go through renderDom and both finalize the document's children the same way, which is
  // what holds the two together.
  static renderTree(tree) {
    const children = Vdom.finalizeChildren(
      Renderer.renderDom(
        tree,
        Type.map(),
        Type.keywordList(),
        Type.bitstring("page"),
        null,
      ),
    );

    return Renderer.#pageVnodeFromChildren(children);
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
        const expressionText = $.toText(valuePartData[1].data[0]);

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
  // A result node becomes the entity struct a template can read, its includes boxed with it.
  // The node carries the row and what was included of it, and the TERM says what each of those
  // is - a node has no type of its own.
  static #boxNode(term, node) {
    const includes = {};

    for (const [name, subTerm] of Object.entries(term.include)) {
      includes[name] = Renderer.#boxIncluded(subTerm, node.includes[name]);
    }

    return Model.box(term.entity, node.row, includes);
  }

  // A to-many include is a list of nodes, a to-one is one node or nothing at all - an absent
  // to-one is nil, which is what the relationship not being there means.
  static #boxIncluded(subTerm, included) {
    if (Array.isArray(included)) {
      return Type.list(
        included.map((subNode) => Renderer.#boxNode(subTerm, subNode)),
      );
    }

    return included === null
      ? Type.nil()
      : Renderer.#boxNode(subTerm, included);
  }

  // What the kernel evaluated to, in the form a template reads: a count is a number, a
  // single-result query is one struct or nil, and everything else is a list.
  static #boxResult(term, result) {
    if (term.cardinality === "count") {
      return Type.integer(result);
    }

    if (term.cardinality === "one") {
      return result === null ? Type.nil() : Renderer.#boxNode(term, result);
    }

    return Type.list(result.map((node) => Renderer.#boxNode(term, node)));
  }

  // What the render that handed this page over counted, for as long as this client's own database
  // cannot count for itself.
  //
  // A count has no rows behind it, so carrying rows cannot answer one: until the fill is complete
  // for the rows it counts, counting locally would count a pot that is still filling and report a
  // number climbing towards the truth. The marker says when that stops - the page's own scope for
  // the page this client connected on, whose rows the server declares complete first, and the
  // whole pot's for any page reached since, whose rows are only promised at "all".
  //
  // The key names the component, the prop and the arguments the builder was called with - which
  // is what tells two instances of one component apart, and what both tiers can spell alike.
  static #carriedCount(module, propName, args, term) {
    if (term.cardinality !== "count") {
      return null;
    }

    const scope =
      module === GlobalRegistry.get("connectPageModule") ? "page" : "all";

    if (LocalDatabase.isSynced(scope)) {
      return null;
    }

    const key = `${module}/${propName.value}/${args
      .map((arg) => Interpreter.inspect(arg))
      .join(",")}`;

    return LocalDatabase.syncCounts[key] ?? null;
  }

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

      const dispatchSpecDom = attrDom.data[1];
      const once = $.#onceFromModifiers(attrDom.data[2]);

      const handler = (event) => {
        if (elementVnode.elm.contains(event.target)) {
          return;
        }

        const dispatch = Hologram.handleUiEvent(
          event,
          "click_outside",
          dispatchSpecDom,
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

  // Records a <window>/<document> tag's event bindings into the per-render accumulator, tagged with
  // the target the listener attaches to. Each binding is keyed by its position across all listener
  // bindings this render, so debounce/throttle windows stay independent even though listeners on one
  // target share a currentTarget. A bare tag (no attributes) records nothing. A listener target has
  // no element tag name, so event-name mapping is skipped (passed null).
  static #collectListenerBindings(target, attrsDom, defaultTarget) {
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

        $.listenerBindings.push({
          target,
          key,
          attach,
          handler: binding.handler,
          slotKey,
          once: $.#onceFromModifiers(attrDom.data[2]),
        });
      }
    });
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

  // Based on compose_attribute_name/2
  // HTML attribute names are dash-separated, while Elixir identifiers can't contain dashes, so each
  // name segment converts to the convention of the namespace it lands in. Nesting composes the
  // segments with hyphens, e.g. %{data: %{user_id: 1}} becomes "data-user-id".
  static #composeAttributeName(key, namePrefix) {
    const segment = $.#validateSpreadKey($.toText(key)).replaceAll("_", "-");

    return namePrefix === null ? segment : `${namePrefix}-${segment}`;
  }

  static #contextKey(opts) {
    return Interpreter.accessKeywordListElement(
      opts,
      Type.atom("from_context"),
    );
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
      ([nameA], [nameB]) => (nameA < nameB ? -1 : nameA > nameB ? 1 : 0),
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

  // Based on expand_slots/2 (including fallback case)
  static #expandSlots(dom, slots) {
    if (Type.isList(dom)) {
      return Renderer.#expandSlotsInNodes(dom, slots);
    }

    if (dom.data[0].value === "component") {
      return Renderer.#expandSlotsInComponentNode(dom, slots);
    }

    if (dom.data[0].value === "dynamic_tag") {
      return Renderer.#expandSlotsInDynamicTagNode(dom, slots);
    }

    if (dom.data[0].value === "element") {
      return Renderer.#expandSlotsInElementNode(dom, slots);
    }

    return dom;
  }

  // Based on expand_slots/3 (component case)
  static #expandSlotsInComponentNode(dom, slots) {
    const [nodeType, moduleAlias, propsDom, childrenDom] = dom.data;

    return Type.tuple([
      nodeType,
      moduleAlias,
      propsDom,
      Renderer.#expandSlots(childrenDom, slots),
    ]);
  }

  // Based on expand_slots/3 (dynamic tag case)
  static #expandSlotsInDynamicTagNode(dom, slots) {
    const [nodeType, value, attrsDom, childrenDom] = dom.data;

    return Type.tuple([
      nodeType,
      value,
      attrsDom,
      Renderer.#expandSlots(childrenDom, slots),
    ]);
  }

  // Based on expand_slots/3 (element cases)
  static #expandSlotsInElementNode(dom, slots) {
    const [nodeType, tagName, attrsDom, childrenDom] = dom.data;

    if (Interpreter.isStrictlyEqual(tagName, Type.bitstring("slot"))) {
      const slotDom = Interpreter.accessKeywordListElement(
        slots,
        Type.atom("default"),
      );

      return slotDom ? slotDom : Type.nil();
    }

    return Type.tuple([
      nodeType,
      tagName,
      attrsDom,
      Renderer.#expandSlots(childrenDom, slots),
    ]);
  }

  // Based on expand_slots/3 (list case)
  // Deps: [:lists.flatten/1]
  static #expandSlotsInNodes(nodes, slots) {
    return Erlang_Lists["flatten/1"](
      Type.list(
        nodes.data
          .filter((node) => !Type.isNil(node))
          .map((node) => Renderer.#expandSlots(node, slots)),
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
      if (valueDom.data[0].data[1].data.length === 1) {
        evaluatedValue = valueDom.data[0].data[1].data[0];
      } else {
        evaluatedValue = valueDom.data[0].data[1];
      }
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

  // Based on filter_allowed_props/2
  // Takes an array of prop tuples, as returned by #expandPropSpreads().
  //
  // A from_query prop is not a prop a template may set, the way a from_context one is not: both
  // are resolved from a source of their own. Today the query stage overwrites whatever a template
  // passed anyway, so refusing it here changes no resolved value - it is the admission rule that
  // is kept identical to the server's, and it stops being redundant the moment a query prop can
  // answer from somewhere other than a fresh run.
  static #filterAllowedProps(propDoms, moduleProxy) {
    const registeredPropNames = Renderer.#getPropDefinitions(moduleProxy)
      .data.filter(
        (prop) =>
          Renderer.#contextKey(prop.data[2]) === null &&
          Renderer.#fromQueryCapture(prop.data[2]) === null,
      )
      .map((prop) => $.toBitstring(prop.data[0]));

    const allowedPropNames = registeredPropNames.concat(Type.bitstring("cid"));

    return propDoms.filter((propDom) =>
      allowedPropNames.some((name) =>
        Interpreter.isStrictlyEqual(name, propDom.data[0]),
      ),
    );
  }

  // Based on from_query_arg!/4
  static #fromQueryArg(module, propName, paramName, props) {
    if (paramName === null) {
      Interpreter.raiseArgumentError(
        `from_query capture for prop ${Interpreter.inspect(propName)} in ${module} has an argument position no clause names - it cannot bind a prop`,
      );
    }

    const name = Type.atom(paramName);
    const entry = props.data[Type.encodeMapKey(name)];

    if (!entry) {
      Interpreter.raiseArgumentError(
        `from_query for prop ${Interpreter.inspect(propName)} in ${module} binds argument ${Interpreter.inspect(name)} - no like-named prop is set`,
      );
    }

    return entry[1];
  }

  // Based on from_query_args!/4
  //
  // A capture takes its arguments from the like-named props, and which names those are is what
  // the build baked: an encoded function carries no argument names of its own. A zero-arity
  // capture asks for nothing, which is why it needs no baked entry.
  static #fromQueryArgs(module, propName, capture, props) {
    if (capture.arity === 0) {
      return [];
    }

    const paramNames =
      globalThis.Hologram.sync?.propParams?.[module]?.[propName.value];

    if (!paramNames) {
      Interpreter.raiseArgumentError(
        `no registered params for from_query prop ${Interpreter.inspect(propName)} in ${module} - the query cache holds no entry for it`,
      );
    }

    return paramNames.map((paramName) =>
      Renderer.#fromQueryArg(module, propName, paramName, props),
    );
  }

  static #fromQueryCapture(opts) {
    return Interpreter.accessKeywordListElement(opts, Type.atom("from_query"));
  }

  static #getPropDefinitions(moduleProxy) {
    if (!("__props__" in moduleProxy)) {
      moduleProxy.__props__ = moduleProxy["__props__/0"]();
    }

    return moduleProxy.__props__;
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

  // Based on run_prop_query!/4
  //
  // The builder is ordinary transpiled code piping the ported query stages, so calling it yields
  // the plain term the kernel evaluates - normalized first, exactly as the server normalizes
  // before running, so the client answers the same query the same way.
  //
  // The result is boxed here and nowhere else: rows live plain, and this is the boundary where
  // one becomes something a template can read.
  static #runPropQuery(alias, propName, capture, props) {
    const module = Interpreter.moduleExName(alias);
    const args = Renderer.#fromQueryArgs(module, propName, capture, props);

    const term = ManuallyPortedElixirHologramQuery["normalize/1"](
      Interpreter.callAnonymousFunction(capture, args),
    );

    const carried = Renderer.#carriedCount(module, propName, args, term);

    if (carried !== null) {
      return Type.integer(carried);
    }

    const result = QueryKernel.run(term, {
      actorUserId: LocalDatabase.actorUserId,
    });

    return Renderer.#boxResult(term, result);
  }

  // Based on inject_props_from_query/2
  //
  // The last prop source, as on the server: a parameterized capture binds like-named props, and
  // template values, context and defaults are what supply them - so they must all be in before
  // this runs. Each resolved query prop joins them, which is what lets a later one bind it.
  // Every query reads its arguments from the props the component was GIVEN, never from the
  // accumulator - so what one query answers can never reach another's arguments, and the order
  // these run in cannot change what any of them returns. The build refuses such a binding
  // outright; this is the same rule holding by construction rather than by check.
  static #injectPropsFromQuery(props, moduleProxy, alias) {
    return Renderer.#getPropDefinitions(moduleProxy).data.reduce(
      (acc, prop) => {
        const capture = Renderer.#fromQueryCapture(prop.data[2]);

        if (capture === null) {
          return acc;
        }

        const propName = prop.data[0];

        // Optimized (mutates map)
        acc.data[Type.encodeMapKey(propName)] = [
          propName,
          Renderer.#runPropQuery(alias, propName, capture, props),
        ];

        return acc;
      },
      Utils.shallowCloneObject(props),
    );
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
      if ("init/2" in moduleProxy) {
        const emptyComponentStruct = Type.componentStruct();

        const componentStruct = moduleProxy["init/2"](
          props,
          emptyComponentStruct,
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
        const message = `component ${Interpreter.inspectModuleJsName(
          moduleProxy.__jsName__,
        )} is initialized on the client, but doesn't have init/2 implemented`;

        throw new HologramInterpreterError(message);
      }
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

      InitActionQueue.enqueue(actionWithTarget);
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

  // Based on raise_invalid_spread_value/1
  static #raiseInvalidSpreadValue(value) {
    Interpreter.raiseArgumentError(
      `spread value must be a map or a keyword list, got: ${Interpreter.inspect(value)}`,
    );
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
    // (starting with $)
    const regularAttrs = $.#expandAttributeSpreads(attrsDom).filter(
      ([name]) => !name.startsWith("$"),
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
  static #renderComponent(dom, context, slots, defaultTarget, parentTagName) {
    const moduleProxy = Interpreter.moduleProxy(dom.data[1]);
    const propsDom = dom.data[2];
    let childrenDom = dom.data[3];

    const expandedChildrenDom = Renderer.#expandSlots(childrenDom, slots);

    let props = Renderer.#injectPropsFromContext(
      Renderer.#castProps(propsDom, moduleProxy),
      moduleProxy,
      context,
    );

    props = Renderer.#injectDefaultPropValues(props, moduleProxy);
    props = Renderer.#injectPropsFromQuery(props, moduleProxy, dom.data[1]);

    if (Renderer.#hasCidProp(props)) {
      return Renderer.#renderStatefulComponent(
        moduleProxy,
        props,
        expandedChildrenDom,
        context,
        parentTagName,
      );
    } else {
      return Renderer.#renderTemplate(
        moduleProxy,
        props,
        expandedChildrenDom,
        context,
        defaultTarget,
        parentTagName,
      );
    }
  }

  // Based on render_tree/3 (dynamic tag cases)
  static #renderDynamicTag(dom, context, slots, defaultTarget, parentTagName) {
    const value = dom.data[1].data[0];
    const attrsDom = dom.data[2];
    const childrenDom = dom.data[3];

    // Mirrors the server's is_binary/1 guard - a non-binary bitstring is not a tag name.
    if (Type.isBinary(value)) {
      return Renderer.renderDom(
        Type.tuple([Type.atom("element"), value, attrsDom, childrenDom]),
        context,
        slots,
        defaultTarget,
        parentTagName,
      );
    }

    if (!Type.isAtom(value)) {
      Interpreter.raiseArgumentError(
        Renderer.#invalidDynamicTagValueMessage(value),
      );
    }

    Renderer.#validateDynamicTagModule(value);

    return Renderer.renderDom(
      Type.tuple([Type.atom("component"), value, attrsDom, childrenDom]),
      context,
      slots,
      defaultTarget,
      parentTagName,
    );
  }

  // Based on render_tree/3 (element & slot case)
  static #renderElement(dom, context, slots, defaultTarget, parentTagName) {
    const currentTagName = Bitstring.toText(dom.data[1]);

    if (currentTagName === "slot") {
      return Renderer.#renderSlotElement(
        slots,
        context,
        defaultTarget,
        parentTagName,
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

    const eventListenersVdom = Renderer.#renderEventListeners(
      attrsDom,
      currentTagName,
      attrsVdom,
      defaultTarget,
    );

    const childrenDom = dom.data[3];

    // The element's children are complete here, whatever nesting of blocks, loops and components
    // produced them, so this is where a repeated key is settled against the rest of the list.
    const childrenVdom = Vdom.finalizeChildren(
      Renderer.renderDom(
        childrenDom,
        context,
        slots,
        defaultTarget,
        currentTagName,
      ),
    );

    const data = {attrs: attrsVdom, on: eventListenersVdom};

    if (Object.keys(propsVdom).length > 0) {
      data.props = propsVdom;
    }

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

      data.hook = {
        create: (_emptyVnode, newVnode) => {
          Renderer.#updateFormInputValue(newVnode.elm, hologramFormInputValue);
        },
        update: (_oldVnode, newVnode) => {
          const newValue = newVnode.data.hologramFormInputValue;
          Renderer.#updateFormInputValue(newVnode.elm, newValue);
        },
      };
    } else if (
      currentTagName === "input" &&
      attrsVdom["data-hologram-form-input-checked"] !== undefined
    ) {
      const hologramFormInputChecked =
        attrsVdom["data-hologram-form-input-checked"];
      delete attrsVdom["data-hologram-form-input-checked"];
      data.hologramFormInputChecked = hologramFormInputChecked;

      data.hook = {
        create: (_emptyVnode, newVnode) => {
          Renderer.#updateFormInputChecked(
            newVnode.elm,
            hologramFormInputChecked,
          );
        },
        update: (_oldVnode, newVnode) => {
          const newChecked = newVnode.data.hologramFormInputChecked;
          Renderer.#updateFormInputChecked(newVnode.elm, newChecked);
        },
      };
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
      const slotKey = $.#renderSlotKey(attrsDom);

      if (slotKey !== null) {
        data.key = slotKey;
      }
    }

    const elementVnode = vnode(currentTagName, data, childrenVdom);

    Renderer.#collectClickOutsideBindings(
      attrsDom,
      elementVnode,
      defaultTarget,
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

  // Based on render_tree/3 (list case)
  //
  // WARNING: must match render_tree/3's list clause step for step: filter out nil input nodes,
  // render each node, splice one level of node lists (a component renders to a list), then merge
  // adjacent text nodes.
  //
  // Blocks are left alone here: a block's body and a loop's iterations are lists of their own, and
  // the nodes they render are only ever part of the enclosing element's children. Numbering the
  // keys belongs to whoever owns that list - see Vdom.finalizeChildren.
  static #renderNodes(nodes, context, slots, defaultTarget, parentTagName) {
    return Renderer.#mergeNeighbouringTextNodes(
      nodes.data
        // There may be nil DOM nodes resulting from "if" blocks, e.g. {%if false}abc{/if} or DOCTYPE
        .filter((node) => !Type.isNil(node))
        .map((node) =>
          Renderer.renderDom(
            node,
            context,
            slots,
            defaultTarget,
            parentTagName,
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
    );
  }

  // Based on render_tree/3 (public comment case)
  static #renderPublicComment(
    dom,
    context,
    slots,
    defaultTarget,
    parentTagName,
  ) {
    const childrenDom = dom.data[1];

    let childrenVdom = Renderer.renderDom(
      childrenDom,
      context,
      slots,
      defaultTarget,
      parentTagName,
    );

    const commentContent = childrenVdom
      .map((child) => (typeof child === "string" ? child : vnodeToHtml(child)))
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
  static #renderSlotKey(attrsDom) {
    for (let index = attrsDom.data.length - 1; index >= 0; index -= 1) {
      const attrDom = attrsDom.data[index];

      if (Type.isRecordTuple(attrDom, "spread", 2)) {
        continue;
      }

      if (Bitstring.toText(attrDom.data[0]) === "$key") {
        return $.#valueDomToText(attrDom.data[1]);
      }
    }

    return null;
  }

  // Based on render_tree/3 (slot case)
  static #renderSlotElement(slots, context, defaultTarget, parentTagName) {
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
    );
  }

  // Based on render_stateful_component/4
  // Deps: [:maps.get/2, :maps.merge/2]
  static #renderStatefulComponent(
    moduleProxy,
    props,
    childrenDom,
    context,
    parentTagName,
  ) {
    const cid = Erlang_Maps["get/2"](Type.atom("cid"), props);

    const [componentState, componentEmittedContext] =
      Renderer.#maybeInitComponent(cid, moduleProxy, props);

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
    );
  }

  // Based on render_template/4
  static #renderTemplate(
    moduleProxy,
    vars,
    childrenDom,
    context,
    defaultTarget,
    parentTagName,
  ) {
    const dom = Renderer.#evaluateTemplate(moduleProxy, vars);
    const slots = Type.keywordList([[Type.atom("default"), childrenDom]]);

    return Renderer.renderDom(
      dom,
      context,
      slots,
      defaultTarget,
      parentTagName,
    );
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

  // WARNING: must match evaluate_attribute_value/1 on the server: parts evaluate raw and
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
}

const $ = Renderer;
