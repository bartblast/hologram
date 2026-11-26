defmodule Hologram.Entity.ServerOnly do
  @moduledoc """
  The value of an attribute declared `server_only: true` where the real value isn't available,
  because the server never sends it to the browser.

  Hologram removes server-only values from the entities it sends to the browser, on its own. That
  covers the HTML the server renders, page and component state, props, context, and every row the
  data layer syncs: wherever such a value would leave the server, Hologram puts `%ServerOnly{}` in
  its place. So in the browser, and in any template, even one rendered on the server, a
  server-only attribute holds `%ServerOnly{}`.

  This works on entities. A value you copy out of one, like
  `put_state(component, :token, user.api_token)`, is a plain value, and Hologram sends it to the
  browser like any other. Keep server-only values in server code, and put the entity in state, not
  the value.

  Your server code works with the real value. An entity that `init/3`, a command or a job reads
  through `DB` holds it, and you don't need to remove it yourself before putting the entity in
  state or passing it as a prop.

  Browser code can't write a server-only attribute. Set it in a command or a job.

  `NotIncluded` means the query didn't ask for a field, and adding it to the query's `include`
  fixes that. `ServerOnly` means the value lives on the server and is never sent to the browser,
  whatever the query.

  Tell a placeholder from a value with `Hologram.Entity.server_only?/1`, which pages and
  components import, or by matching on the struct alone. The struct's `__meta__` key is internal
  and may change, so don't read it or match on it.

  ## Examples

  In a template:

      {%if server_only?(@user.api_token)}
        <p>Token hidden</p>
      {/if}

  Matching on the struct works too, in a `case` or a function head in browser code:

      alias Hologram.Entity.ServerOnly

      case user.api_token do
        %ServerOnly{} -> :hidden
        token -> token
      end
  """

  # Sibling of NotIncluded. The internal __meta__ map names the attribute, as %{field: name}, so
  # that a misuse error inspecting the placeholder names the attribute that is hidden.

  defstruct __meta__: %{}

  @typedoc """
  A server-only attribute's value, hidden. Match on the struct alone, `__meta__` is internal.
  """
  @type t :: %__MODULE__{__meta__: map}
end
