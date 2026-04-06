# Hologram Usage Rules

For full documentation, see deps/hologram/llms-full.txt or https://hologram.page/llms.txt

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
- Server-side init uses `init/3` (props, component, server). Client-side init uses `init/2` (props, component).
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

- Bind events with `$` prefix: `$click`, `$change`, `$submit`, `$blur`, `$focus`, `$mouse_move`, `$pointer_down`, `$pointer_up`, `$pointer_move`, `$pointer_cancel`, `$select`, `$transition_end`, `$transition_start`, `$transition_run`, `$transition_cancel`. **Not** `phx-click` or `phx-change`.
- Text syntax (actions only): `$click="my_action"`.
- Shorthand with params (actions only): `$click={:my_action, key: value}`.
- Longhand (actions or commands): `$click={action: :my_action, target: "cid", params: %{key: value}}`.
- Trigger commands with longhand: `$click={command: :my_command, params: %{key: value}}`.
- Delays (actions only): `$click={action: :my_action, delay: 1000}`.
- Event data is available in `params.event` inside the action/command handler.
- `$change` on an input fires on every keystroke (text inputs) or on selection change (checkboxes, radios, selects). On a form element, it fires on field blur.
- Valid targets: `"page"`, `"layout"`, or a component's cid string. Default is the containing stateful component.

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
- Text inputs and textareas sync with `value` attribute. Checkboxes and radio buttons sync with `checked` attribute.
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

## Session

- Session is server-side secure storage. Use it in `init/3` and commands only.
- Read: `get_session(server, :key)` or `get_session(server, :key, default)`.
- Write: `put_session(server, :key, value)`.
- Delete: `delete_session(server, :key)`.
- Session keys must be atoms or strings.
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

## JavaScript Interop

- Add `use Hologram.JS` to any module that needs JS interop. **Not** Phoenix hooks or `phx-hook`.
- Import JS modules: `js_import from: "decimal.js", as: :Decimal` (default export) or `js_import :multiply, from: "./helpers.mjs"` (named export).
- Relative paths (`./`, `../`) resolve relative to the Elixir source file. Bare specifiers resolve as npm packages.
- Call a function: `JS.call(:multiply, [4, 6])`. Call a method: `JS.call(:Math, :round, [3.7])`.
- Instantiate a class: `JS.new(:Calculator, [10])`. Chain with `|>`: `:Calculator |> JS.new([10]) |> JS.call(:add, [5])`.
- Get/set properties: `JS.get(obj, :value)`, `JS.set(obj, :value, 20)`.
- Evaluate JS: `JS.eval("3 + 4")`. Execute JS: `JS.exec("const x = 2; return x + 3;")`. Inline JS: `~JS"""..."""`.
- Async: JS Promises become Elixir Tasks. Use `Task.await/1` to get the result.
- Dispatch actions from JS: `Hologram.dispatchAction("action_name", "page", {key: value})`.
- Dispatch DOM events from Elixir: `JS.dispatch_event(target, "my:event", detail: %{value: 42})`.
- Elixir anonymous functions can be passed as JS callbacks.
- JS interop only works in action handlers (client-side). It is a no-op during server-side rendering.
- Prefer `JS.call` over `JS.exec`/`JS.eval`. Isolate JS interop behind facade modules.
