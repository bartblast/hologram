defmodule Hologram.Component.NotComputed do
  @moduledoc """
  What a derived field that reads state holds in `init`: such a field is computed from the state
  `init` returns, once it has returned, so while `init` runs it holds this placeholder instead.
  """

  @enforce_keys [:field]

  defstruct [:field]

  @type t :: %__MODULE__{field: atom}

  defimpl Inspect do
    @impl Inspect
    def inspect(%{field: field}, _opts) do
      "#Hologram.Component.NotComputed<#{Kernel.inspect(field)} reads state, so it's computed after init>"
    end
  end
end
