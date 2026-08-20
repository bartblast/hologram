defmodule Hologram.Query.Placeholder do
  @moduledoc false

  # Stands for what a build cannot know. The symbolic evaluator gives one to every argument of a
  # from_query builder, and to every value computed from one, so a term can be extracted from a
  # builder nobody has called yet - it becomes a {:placeholder, name} leaf wherever it lands.
  #
  # It is never bound to a value. Both tiers run the REAL builder with the component's REAL props
  # and normalize THAT, so a placeholder exists only between extraction and the window derivation
  # that drops it. The name says which argument the value came from, for reading a term.
  #
  # Every position a placeholder may occupy is one the window discards or empties - a filter
  # attribute or value, an ordering key or direction, a view bound. A position that decides the
  # download instead has a finite candidate set the build forks over.

  @enforce_keys [:name]

  defstruct [:name]

  @type t :: %__MODULE__{name: atom}
end
