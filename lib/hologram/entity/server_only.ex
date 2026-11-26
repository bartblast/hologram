defmodule Hologram.Entity.ServerOnly do
  @moduledoc false

  # The client-side value of an attribute declared server_only: true - it marks a value the
  # server holds and never hands to the client. Sibling of NotIncluded, and the pair tells the
  # reader WHY a value is absent: NotIncluded means "you didn't ask for it", fixable by including
  # the relationship in the query, while ServerOnly means "you can't have it, it lives on the
  # server", fixable only by remodeling. The internal __meta__ map names the attribute, as
  # %{field: name}, so that a misuse error inspecting the placeholder names the attribute that
  # is hidden.

  defstruct __meta__: %{}

  @type t :: %__MODULE__{__meta__: map}
end
