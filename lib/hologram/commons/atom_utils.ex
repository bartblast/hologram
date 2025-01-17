defmodule Hologram.Commons.AtomUtils do
  @moduledoc false

  @doc """
  Returns `true` if `atom` starts with the given prefix.
  """
  @spec starts_with?(atom, String.t()) :: boolean
  def starts_with?(atom, prefix) do
    atom
    |> to_string()
    |> String.starts_with?(prefix)
  end
end
