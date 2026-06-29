Hologram is a full-stack isomorphic Elixir web framework. It compiles Elixir to JavaScript for the browser. It is NOT Phoenix LiveView - it has its own template syntax (~HOLO), component model, and state management. Do not use Phoenix/LiveView patterns. Read documentation before attempting to use its features. Do not assume that you have prior knowledge of the framework or its conventions.

For additional details beyond these rules, see deps/hologram/llms-full.txt or https://hologram.page/llms.txt

## Common Pitfalls

- **Never** use Phoenix/LiveView syntax: no `<%= %>`, no `phx-click`, no `<.component>`, no `<:slot>`, no `to_form`, no `<.simple_form>`, no `live_redirect`, no `handle_event`, no `assign`.
- **Never** use HEEx templates. Hologram uses `~HOLO` sigil, not `~H`.
- Actions use `put_state`, not `assign`. State is accessed with `component.state.key`, not `socket.assigns.key`.
- Commands use `server` struct, not `socket`. Return `%Server{}`, not `{:noreply, socket}`.
- Cookie keys are strings (`"my_cookie"`), session keys are atoms or strings (`:user_id`). Mixing these up causes errors.
- `init/3` for pages receives URL params, not props. Don't confuse with component `init/3` which receives props.
- Stateless components cannot handle events. You need a `cid` to make a component stateful.
- The page cid is `"page"`, the layout cid is `"layout"`. Don't forget these when targeting actions.
- Not all Elixir standard library functions are available client-side yet. Check the Client Runtime reference for coverage.
- `try` (with `rescue`/`catch`/`else`/`after`), `raise`, `reraise`, `throw`, and `exit` work client-side. `__STACKTRACE__` is supported but always evaluates to an empty list, because the client does not have stacktraces yet.
- Realtime: inside `init/3`/commands use `put_subscription`/`put_broadcast` on the `server` struct (deferred until the handler succeeds). The `Hologram.Realtime.*` functions fire immediately and are only for code outside a handler (background jobs, workers).

## Architecture

- Hologram applications are built with two building blocks: **Pages** (route entry points) and **Components** (reusable UI elements).
- **Actions** run on the client (browser). Use them for state updates, navigation, and triggering commands.
- **Commands** run on the server. Use them for database access, API calls, session/cookie management, and other server-side operations.
- State lives in the browser, not on the server. This enables instant UI updates without network round-trips.
- Client-server communication happens automatically over HTTP/2 persistent connections. You never configure HTTP endpoints or write boilerplate for action-command interactions.
- Hologram automatically determines which code runs on the client vs server and compiles the client portions to JavaScript. You don't manually split code.

## Template Syntax

- Hologram templates use the `~HOLO` sigil, not HEEx. **Never** use HEEx syntax (`<%= %>`, `<.component>`, `<:slot>`).
- Access props and state with `@var` syntax: `{@name}`, `{@count}`.
- Interpolate Elixir expressions with curly braces: `{expression}`. **Not** `<%= expression %>`.
- Component nodes use module names: `<MyComponent prop="value" />`. **Not** `<.my_component>`.
- Conditional rendering uses `{%if condition}...{/if}` and `{%if condition}...{%else}...{/if}`. **Not** `:if` attribute.
- Iteration uses `{%for item <- @items}...{/for}`. **Not** `:for` attribute.
- Escape curly braces with backslash: `\{literal\}`.
- Raw output (no processing): `{%raw}...{/raw}`.
- When an attribute expression evaluates to `nil` or `false`, the attribute is not rendered at all.
- All interpolated expressions are automatically HTML-escaped to prevent XSS.

## Components

- Components use `use Hologram.Component`. **Not** `use Phoenix.Component` or `use Phoenix.LiveComponent`.
- Define props with `prop :name, :type` or `prop :name, :type, default: value`.
- Available prop types: `:any`, `:atom`, `:boolean`, `:bitstring`, `:float`, `:function`, `:integer`, `:list`, `:map`, `:pid`, `:port`, `:reference`, `:string`, `:tuple`.
- Source props from context: `prop :user, :map, from_context: :current_user`.
- Stateful components require a `cid` attribute: `<MyComponent cid="my_id" />`. Without `cid`, the component is stateless.
- Each stateful instance is initialized exactly once: `init/3` (props, component, server) runs when its lifecycle starts during server-side page rendering, `init/2` (props, component) when it is dynamically added to an already-loaded page.
- `init/3` can return a `Component` struct, a `Server` struct, or a `{component, server}` tuple.
- Both `init/3` and `init/2` are optional.
- Use `<slot />` for child content. **Not** `<:slot>` or `inner_block`.
- Templates can be defined as a `template/0` function with `~HOLO` sigil, or in a colocated `.holo` file (same name, same directory).
- Colocated `.holo` files contain only markup, without the `~HOLO` sigil wrapper.

## Pages

- Pages use `use Hologram.Page`. **Not** `use Phoenix.LiveView`.
- Every page must define a route: `route "/path"` or `route "/path/:param"`.
- Every page must specify a layout: `layout MyApp.MainLayout` or `layout MyApp.MainLayout, prop: value`.
- Pages are always stateful and always initialized server-side with `init/3` (params, component, server).
- `init/3` receives URL params, not props. Use `param :name, :type` to declare typed route parameters.
- Supported param types: `:atom`, `:float`, `:integer`, `:string`.
- The page's component ID (cid) is always `"page"`. Use `target: "page"` to target actions at it.
- Hologram uses a search tree router, not ordered routing. Static segments always match before parameterized ones. You cannot have two ambiguous parameterized routes at the same level (e.g. `/:username` and `/:post_slug`) - use distinct prefixes instead.

## Layouts

- Layouts are regular components using `use Hologram.Component`. There is no special layout module or macro.
- A layout template **must** include `<Hologram.UI.Runtime />` inside the `<head>` tag.
- A layout template **must** include `<slot />` where page content will be inserted.
- The layout's component ID (cid) is always `"layout"`. Use `target: "layout"` to target actions at it.
- Pass props to layouts via `layout MyApp.MainLayout, prop: value` or via `put_state/2` in the page's `init/3`.

## Events

- Bind events with `$` prefix: `$click`, `$click_outside`, `$change`, `$submit`, `$blur`, `$focus`, `$key_down`, `$key_up`, `$mouse_move`, `$pointer_down`, `$pointer_up`, `$pointer_move`, `$pointer_cancel`, `$resize`, `$scroll`, `$reach_bottom`, `$reach_left`, `$reach_right`, `$reach_top`, `$select`, `$transition_end`, `$transition_start`, `$transition_run`, `$transition_cancel`. **Not** `phx-click` or `phx-change`.
- Text syntax (actions only): `$click="my_action"`.
- Shorthand with params (actions only): `$click={:my_action, key: value}`.
- Longhand (actions or commands): `$click={action: :my_action, target: "cid", params: %{key: value}}`.
- Trigger commands with longhand: `$click={command: :my_command, params: %{key: value}}`.
- Delays (actions only): `$click={action: :my_action, delay: 1000}`.
- A binding that resolves to no operation is disabled: nothing dispatches and the browser's native default proceeds (no `preventDefault`, no `stopPropagation`). Covers a `nil` whole value (`$click={nil}`), a `nil` shorthand name slot (`$click={nil, x: 1}`), and a `nil` longhand `action:`/`command:` key (`$click={action: nil}`). The value is read at event time, so a re-render can enable or disable the binding: `$click={if @editable do :save end}`.
- Conditionals inside template braces need the `do...end` form: `{if @editable, do: :save}` fails the build (template braces are tuple braces, making the call ambiguous), `{if @editable do :save end}` works.
- Valid targets: `"page"`, `"layout"`, or a component's cid string. Default is the containing stateful component.
- Event data is available in `params.event` inside the action/command handler.
- A `$click` binding does not fire on a modified click (`Alt`, `Ctrl`, `Command`, or `Shift` held) - Hologram leaves the event to the browser so the user's shortcut (e.g. open in a new tab) still works.
- `$change` on an input fires on every keystroke (text inputs) or on selection change (checkboxes, radios, selects). On a form element, it fires on field blur.
- Bind global events (not tied to any element, e.g. a global keyboard shortcut) with the `<window>` or `<document>` tag, which attaches to the global `window` or `document`: `<window $key_down.ctrl+k="open_palette" />`. They render nothing and reuse the same `$event` syntax, key filters, and modifiers as element bindings.
- A `<window>` or `<document>` binding follows the same targeting rules as a regular element and accepts only event bindings (any other attribute fails the build). Its listener lives only while the tag renders, so one behind a conditional listens only while that condition holds.
- Use `<window>` for window events (resize, scroll) and `<document>` for document events (tab visibility). Bubbling events like keyboard and pointer reach both, so either tag works for a global shortcut.
- `$click_outside` fires when a click lands anywhere outside the bound element and its descendants - for dismissible UI like dropdowns, popovers, modals, and menus. A click on or inside the element does nothing. Usually rendered only while the element is open (behind a conditional) so it listens for outside clicks just then.
- `$resize` fires when the bound target's size changes (no initial dispatch on first render) - bind it to an element to track that element, or to `<window>` for the browser window. For an element, `params.event` has `border_box_size`, `content_box_size`, and `device_pixel_content_box_size`, each a `%{block_size, inline_size}` map (the device-pixel one is `nil` where unsupported - notably Safari and all iOS browsers). A window resize has an empty payload (the native event provides no size data). It fires rapidly, so pair it with `throttle(ms)` or `debounce(ms)`.
- `$scroll` fires when a scrollable element, or the page, is scrolled - bind it to an element to track that element, or to `<window>` / `<document>` to track the page. `params.event` has `scroll_left` and `scroll_top`. It fires rapidly, so pair it with `throttle(ms)` or `debounce(ms)`.
- `$reach_bottom`, `$reach_left`, `$reach_right`, `$reach_top` fire when a scroll container is scrolled so the matching edge comes into view (the basis for infinite scroll, load-more, pull-to-refresh) - bind them to the scrolling element, one per edge. They carry no `params.event` data (a pure trigger). Each also fires on mount when its edge is already in view, so resolve the binding to `nil` to stop it (e.g. at end-of-data). Append `within(<distance>)` to fire ahead of the edge - a length (`200px`) or a percentage of the container (`50%`), with a default of `100%` (the container's height for top/bottom, its width for left/right).
- Prepending content above the viewport (for `$reach_top`/`$reach_left`) does not yet preserve scroll position - the view stays at the top, showing the newly loaded content. Keyed lists will address this.
- Keyboard events (`$key_down`, `$key_up`): `params.event` has `key` (e.g. `"k"`, `"Enter"`, `"ArrowUp"`), `code`, `alt_key`, `ctrl_key`, `meta_key`, `shift_key`, `repeat`.
- Filter keyboard events to a key with a dot: `$key_down.enter="submit"`; combine modifiers with `+`: `$key_down.ctrl+enter="send"`. Works on `$key_down` and `$key_up`, case-insensitive, and matches a superset (extra held modifiers do not block it).
- Filter keys: letters/digits as the character (`k`, `7`); modifiers `alt`/`ctrl`/`meta`/`shift` (only when combined with a key); named keys (`arrow_up`, `enter`, `escape`, `space`, `tab`, `f1`-`f12`, ...); symbol keys as alias words (`slash`, `period`, `comma`, `minus`, ...) **not** raw characters.
- Key filters are validated at compile time - a misspelled key like `$key_down.entr` fails the build, **not** a silent runtime no-op.
- For runtime-determined keys, bind bare `$key_down` and match `params.event.key` in the handler.
- Debounce high-frequency events by appending `debounce(ms)`, coalescing a burst into one trailing dispatch that carries the last event's data: `$change.debounce(300)="search"`. Bare `debounce` uses a 250ms default. Works on any event, combines with key filters (`$key_down.enter.debounce(300)`), each binding keeps its own timer, and the window is validated at compile time (`$change.debounce(0)` fails the build).
- `debounce` is an event modifier (gates whether and when an event dispatches) - distinct from the `delay` action option (postpones an already-decided dispatch, also settable via `put_action`).
- Throttle high-frequency events by appending `throttle(ms)`, dispatching at most once per `ms` while events keep firing - the first immediately (leading edge) and the latest of each window on the trailing edge: `$mouse_move.throttle(100)="track"`. Bare `throttle` uses a 100ms default. Works on any event, combines with key filters, each binding keeps its own window, validated at compile time. Cannot be combined with `debounce` on one binding (opposite strategies, fails the build).
- `throttle` caps the dispatch rate during continuous activity, while `debounce` waits for it to stop and dispatches once - throttle for live updates (cursor, drag, scroll), debounce for a final value (search after typing stops).
- Append `allow_default` so Hologram does not call `preventDefault` for that binding, letting the browser's native default run while the action still dispatches: `$submit.allow_default="track"`. Hologram calls `preventDefault` by default only on `$submit`, so `allow_default` is meaningful only there - e.g. a form that posts to an external endpoint you also want to track. Composes with key filters, `stop_propagation`, `debounce`, and `throttle`.
- Append `prevent_default` so Hologram calls `preventDefault` for a binding - since `$submit` is the only event prevented by default, this is how you prevent the native default on any other event: `$key_down.enter.prevent_default="send_message"` fires the action without Enter inserting a newline or submitting the form. Only affects cancelable events (no-op on `$change`, `$input`, `$select`, `$scroll`, `$resize`, `$focus`, `$blur`, `$pointer_cancel`, `$transition_*`). It is the mirror of `allow_default`, and the two cannot combine on one binding (fails the build). Composes with key filters (only the matched key is prevented), `stop_propagation`, `debounce`, and `throttle`.
- Append `stop_propagation` to stop the event at the bound element, so ancestor bindings no longer fire while the action still dispatches: `<button $click.stop_propagation="delete_card">` inside a `$click` card fires only the button's action. Hologram never stops propagation on its own. A stopped event also never reaches `$click_outside` or `<window>`/`<document>` bindings (they listen at the document level). Composes with key filters (on keyboard events, propagation stops only for matching keys), `allow_default`, `prevent_default`, `debounce`, and `throttle`.
## Actions

- Actions are client-side. Define with `def action(name, params, component)`. **Not** `handle_event`.
- Actions must return a `%Component{}` struct. Chain operations with `|>`.
- Update state: `put_state(component, :key, value)` or `put_state(component, key: val1, key2: val2)`.
- Nested state update: `put_state(component, [:path, :key], value)`.
- Trigger a command: `put_command(component, :cmd_name)` or `put_command(component, :cmd_name, param: value)`.
- Navigate: `put_page(component, PageModule)` or `put_page(component, PageModule, param: value)`.
- Update context: `put_context(component, :key, value)`.
- Chain another action: `put_action(component, :action_name)` or `put_action(component, :action_name, param: value)`.
- Delays are available for actions only (not commands): `put_action(component, name: :my_action, delay: 750)`.

## Commands

- Commands are server-side. Define with `def command(name, params, server)`. **Not** `handle_event` or `handle_info`.
- Commands must return a `%Server{}` struct. Chain operations with `|>`.
- Commands are always executed asynchronously.
- Trigger a client action from a command: `put_action(server, :action_name)` or `put_action(server, :action_name, param: value)`.
- Manage session: `put_session(server, :key, value)`, `get_session(server, :key)`, `delete_session(server, :key)`.
- Manage cookies: `put_cookie(server, "key", value)`, `get_cookie(server, "key")`, `delete_cookie(server, "key")`.
- Commands can be triggered from templates via longhand event syntax or from actions via `put_command/2`/`put_command/3`.

## Navigation

- Use `Hologram.UI.Link` for navigation links: `<Link to={MyPage}>text</Link>`. **Not** `<.link navigate={...}>` or `live_redirect`.
- With params: `<Link to={MyPage, id: 123}>text</Link>`.
- Programmatic navigation from actions: `put_page(component, MyPage)` or `put_page(component, MyPage, id: 123)`.
- Hologram prefetches pages on `$pointer_down` for near-instant transitions.
- Each page is loaded fresh from the server. Browser history (back/forward) works automatically.

## Forms

- Use standard HTML `<form>`, `<input>`, `<select>`, `<textarea>` elements. **Not** Phoenix form helpers (`to_form`, `<.simple_form>`, `<.input>`).
- **Synchronized inputs** use `value={@state_var}` + `$change="handler"` on the input element. The component state is the single source of truth.
- **Non-synchronized inputs** omit `$change` on the input. Access values via form-level `$change` or `$submit` handlers from `params.event`.
- Text inputs, textareas, and selects sync with the `value` attribute. Checkboxes and radio buttons sync with the `checked` attribute.
- Input-level `$change` on text inputs fires on every keystroke. Form-level `$change` fires on field blur.
- `$submit` event data contains all form field values as a map: `params.event` => `%{field_name: value}`.
- Elixir validation code (including Ecto changesets) runs both client-side and server-side since Hologram runs Elixir in the browser.

## Context

- Context shares data down the component tree without prop drilling. **Not** a global store.
- Set context: `put_context(component, :key, value)` in actions or init functions.
- Namespaced keys to avoid conflicts: `put_context(component, {MyModule, :key}, value)`.
- Access context via props: `prop :user, :map, from_context: :current_user`.
- Context values are available to all descendant components, not siblings or ancestors.
- Prefer props for data passed to direct children. Use context for deeply nested data sharing.

## Middleware

- Middleware is reusable server-side logic that runs before a page renders (before `init/3`) and before commands execute - for authentication, authorization, request enrichment, rate limiting, audit logging. **Not** Phoenix `Plug` or router pipelines.
- Modules use `use Hologram.Middleware`. Three forms: an **inline function** on a page/component, a **leaf** module (does the work), or a **composite** module (combines other middleware).
- Inline: attach with `middleware :name` and define a public `def name(server, opts)` on the same page/component.
- Leaf: a `use Hologram.Middleware` module that defines `def call(server, opts)`.
- Composite: a `use Hologram.Middleware` module that declares a sub-chain with `middleware ...` lines and omits `call/2` (generated for you). It attaches anywhere a leaf can, including inside another composite.
- Attach to a page or component with `middleware SomeModule` or `middleware :some_function`, each with optional keyword opts (`middleware SomeModule, role: :admin`). Declarations run top to bottom.
- Every middleware receives and returns a `%Server{}` struct - the same one `init/3` and commands use. The `Server` helpers (`put_status`, `put_redirect`, `put_session`, `put_stash`, `get_request_header`, ...) are imported unqualified.
- Read the incoming request as `Server` struct fields: `method`, `scheme`, `host`, `port`, `path`, `query`, `raw_query`, `ip`. These are **not** authenticated - `host` is client-supplied and spoofable, so validate it against an allowlist before any security decision and never build security-sensitive URLs (password-reset links, emails) from it.
- Set or clear the authenticated user with `put_user_id(server, user_id)` / `delete_user_id(server)` (persisted to the session) - the canonical login/logout mechanism.
- Stop the chain by setting a status - `put_status(server, :forbidden)`, `put_status(server, 403)`, or `put_redirect(server, MyApp.LoginPage)`. There is no separate `halt`: a non-nil status is the signal, checked after each middleware returns (it does not abort on the spot).
- Pass data downstream with `put_stash(server, :key, value)`, read later with `get_stash` in middleware, `init/3`, or commands.
- Dispatch is flat: page middleware covers the page render and the page's own commands; component middleware covers only that component's commands. A page's middleware does **not** cover its components' commands - attach the gate to the component (or a shared composite) to protect them.
- Compose without a global registry: a base module's `__using__` can inject `middleware` lines into every page/component that uses it (parent first, then child). There is no forced global middleware list - app-wide concerns are plugged into the pages/components that need them.

## Session

- Session is server-side secure storage. Use it in `init/3` and commands only.
- Read: `get_session(server, :key)` or `get_session(server, :key, default)`.
- Write: `put_session(server, :key, value)`.
- Delete: `delete_session(server, :key)`.
- Session keys must be atoms or strings (atoms are converted to strings, so `:user_id` and `"user_id"` address the same value).
- Sessions can store any Elixir data type (maps, lists, tuples, etc.).
- Session data cannot be read by client-side code. Use cookies if you need client-side access.

## Cookies

- Cookies are managed server-side. Use them in `init/3` and commands only.
- Cookie keys must be **strings** (not atoms).
- Read: `get_cookie(server, "key")` or `get_cookie(server, "key", default)`.
- Write: `put_cookie(server, "key", value)` or `put_cookie(server, "key", value, opts)`.
- Delete: `delete_cookie(server, "key")`.
- Cookies can store complex Elixir data structures (maps, lists, etc.) - Hologram handles encoding/decoding automatically.
- Default cookie options: `http_only: true`, `path: "/"`, `same_site: :lax`, `secure: true`.
- Custom options: `http_only`, `path`, `same_site` (`:strict`, `:lax`, `:none`), `secure`, `max_age`, `domain`.
- Use sessions for sensitive data. Use cookies when you need client-side access or specific cookie behavior.

## Realtime

- Realtime lets server-side code push actions to connected clients without polling. A broadcast dispatches an action that runs in the client's `action/3` handler - the trigger just comes from the server. **Not** Phoenix Channels, `phx-join`, or calling `Phoenix.PubSub` directly.
- **In handlers (default):** call `put_subscription`, `delete_subscription`, `put_broadcast`, `put_broadcast_except` on the `server` struct inside `init/3` or `command/3`. They are deferred and transactional - applied only after the handler returns successfully, and discarded if it raises (like `put_session`/`put_cookie`).
- **Outside handlers (escape hatch - background jobs, workers, GenServers, incremental Phoenix adoption):** `Hologram.Realtime.broadcast_action`, `broadcast_action_except`, `subscribe`, `unsubscribe`, `unsubscribe_all`. These fire immediately and do not roll back, and `subscribe`/`unsubscribe` require an explicit cid (e.g. `"page"`). Prefer the in-handler API - reach for these only when there is genuinely no handler.
- Channels are structured values, never topic strings: a bare atom (`:notifications`) or a tuple of an atom tag plus one or more primitives (`{:room, 42}`, `{:doc, "abc-123", "v2"}`).
- Identity channels address recipients - `{:instance, id}` (one tab), `{:session, id}` (one session), `{:user, id}` (one user) - built from `server.instance_id`, `server.session_id`, `server.user_id`.
- Application channels (`:notifications`, `{:room, 42}`) fan a single broadcast out to every component subscribed to them.
- Subscriptions are per-component (cid). `put_subscription` always subscribes the current component - you cannot subscribe on another component's behalf. They are sticky for the page lifetime and auto-cleaned on navigation, so `delete_subscription` is only for removing one mid-page.
- A broadcast names only a channel and an action, never a component. `params` is a keyword list at the call site that arrives as a map in the `action/3` handler. The sender's own instance receives its broadcast too - exclude it with `put_broadcast_except`/`broadcast_action_except` and `{:instance, server.instance_id}`.
- `server.subscriptions` and `server.broadcasts` are readable public fields holding the current component's subscriptions and the broadcasts queued so far.
- Realtime does no authorization - check permissions yourself before any broadcast, subscribe, or unsubscribe.
- Delivery is fire-and-forget and subscription-driven (at-most-once, no acks, replay, or ordering guarantees). Treat broadcasts as live nudges to update already-loaded state and keep authoritative data in your data layer.

## JavaScript Interop

- Add `use Hologram.JS` to any module that needs JS interop. **Not** Phoenix hooks or `phx-hook`.
- Import JS modules: `js_import from: "decimal.js", as: :Decimal` (default export) or `js_import :multiply, from: "./helpers.mjs"` (named export).
- Relative paths (`./`, `../`) resolve relative to the Elixir source file. Bare specifiers resolve as npm packages.
- Call a function: `JS.call(:multiply, [4, 6])`. Call a method: `JS.call(:Math, :round, [3.7])`.
- Instantiate a class: `JS.new(:Calculator, [10])`. Chain with `|>`: `:Calculator |> JS.new([10]) |> JS.call(:add, [5])`.
- Get/set/delete properties: `JS.get(obj, :value)`, `JS.set(obj, :value, 20)`, `JS.delete(obj, :value)`. Inspect values: `JS.typeof(obj)`, `JS.instanceof(obj, :Class)`.
- Evaluate JS: `JS.eval("3 + 4")`. Execute JS: `JS.exec("const x = 2; return x + 3;")`. Inline JS: `~JS"""..."""`.
- Async: JS Promises become Elixir Tasks. Use `Task.await/1` to get the result.
- Dispatch actions from JS: `Hologram.dispatchAction("action_name", "page", {key: value})`. Available immediately - calls before the runtime loads are queued and replayed on mount (safe for inline `<script>`).
- Dispatch DOM events from Elixir: `JS.dispatch_event(target, "my:event", detail: %{value: 42})`.
- Direct DOM manipulation via JS interop is preserved across Hologram re-renders, as long as the container element stays in the template.
- Elixir anonymous functions can be passed as JS callbacks.
- JS interop only works in action handlers (client-side). It is a no-op during server-side rendering.
- Prefer `JS.call` over `JS.exec`/`JS.eval`. Isolate JS interop behind facade modules.
