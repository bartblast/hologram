defmodule Hologram.Commons.StringUtils do
  @doc """
  Wraps the given string with one string on the left side and another string on the right side.

  ## Examples

      iex> wrap("ab", "cd", "ef")
      "cdabef"
  """
  @spec wrap(String.t(), String.t(), String.t()) :: String.t()
  def wrap(str, left, right) do
    left <> str <> right
  end
end
