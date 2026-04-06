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
