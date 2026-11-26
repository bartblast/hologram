defmodule Hologram.Entity.ServerOnly do
  @moduledoc """
  The value of an attribute declared `server_only: true` where the real value isn't available,
  because the server never sends it to the browser.

  A server-only attribute holds `%ServerOnly{}` in the browser and in every template, including
  a template rendered on the server, since the HTML it renders goes to the browser. Server code,
  like `init/3`, a command or a job, gets the real value when it reads through `DB`.

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
