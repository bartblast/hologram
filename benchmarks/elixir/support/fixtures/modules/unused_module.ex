defmodule Hologram.Benchmarks.Fixtures.UnusedModule do
  @moduledoc false

  # A module no page, no component and no runtime function reaches: what a save of a module the
  # pages do not use edits.

  @doc """
  Returns the given value.
  """
  @spec identity(any) :: any
  def identity(value), do: value
end
