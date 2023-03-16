defmodule Hologram.Compiler.Helpers do
  @doc """
  Returns alias segments list (without the "Elixir" segment at the beginning).

  ## Examples

      iex> Helpers.alias_segments("Aaa.Bbb")
      [:Aaa, :Bbb]
      
      iex> Helpers.alias_segments(Aaa.Bbb)
      [:Aaa, :Bbb]
  """
  def alias_segments(term)

  def alias_segments(module_name) when is_binary(module_name) do
    Module.split("Elixir.#{module_name}")
    |> Enum.map(&String.to_atom/1)
  end

  def alias_segments(module) do
    Module.split(module)
    |> Enum.map(&String.to_atom/1)
  end
end
