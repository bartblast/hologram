defmodule Hologram.Query.Placeholder do
  @moduledoc false

  # Stands for a value the build cannot know. It exists only for the build's chain check
  # (Hologram.Compiler.QueryChains), which replays the queries browser code writes through
  # Hologram.Query.Stage with one wherever a value is pinned (`^x`), so the stages can check
  # everything around it - it becomes a {:placeholder, name} leaf wherever it lands. The name is
  # the pinned variable's, or :pinned for any other expression.
  #
  # It is never bound to a value, and a term holding one never runs: both tiers build the query
  # from its real values, and the database executor and the reference interpreter refuse a term
  # with a leaf left in it (see Hologram.Query.Stage.assert_no_placeholders!/1).

  @enforce_keys [:name]

  defstruct [:name]

  @type t :: %__MODULE__{name: atom}
end
