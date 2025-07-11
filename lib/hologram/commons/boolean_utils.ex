defmodule Hologram.Commons.BooleanUtils do
  @moduledoc false

  @doc "Converts a boolean to an integer (false -> 0, true -> 1)."
  @spec to_integer(boolean) :: 0 | 1
  def to_integer(boolean)

  def to_integer(false), do: 0

  def to_integer(true), do: 1
end
