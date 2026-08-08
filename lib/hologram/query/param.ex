defmodule Hologram.Query.Param do
  @moduledoc false

  # Sentinel standing for a runtime-bound value in filter value positions - the
  # builder stores it as a {:param, name} leaf in the predicate triple. The name
  # is the param name the value binds under at execution.

  @enforce_keys [:name]

  defstruct [:name]

  @type t :: %__MODULE__{name: atom}
end
