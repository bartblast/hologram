defmodule Hologram.Compiler.Reflection do
  @doc """
  Determines whether the given term is an alias.

  ## Examples

      iex> is_alias?(Calendar.ISO)
      true

      iex> is_alias?(:abc)
      false
  """
  @spec is_alias?(any) :: boolean
  def is_alias?(term)

  def is_alias?(term) when is_atom(term) do
    term
    |> to_string()
    |> String.starts_with?("Elixir.")
  end

  def is_alias?(_), do: false
end
