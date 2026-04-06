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
