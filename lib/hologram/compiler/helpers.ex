defmodule Hologram.Compiler.Helpers do
  alias Hologram.Commons.StringUtils
  alias Hologram.Commons.Types

  @doc """
  Returns alias segments list (without the "Elixir" segment at the beginning).

  ## Examples

      iex> alias_segments("Aaa.Bbb")
      [:Aaa, :Bbb]

      iex> alias_segments(Aaa.Bbb)
      [:Aaa, :Bbb]
  """
  @spec alias_segments(binary | module) :: Types.alias_segments()
  # sobelow_skip ["DOS.StringToAtom"]
  def alias_segments(module_name) when is_binary(module_name) do
    module_name
    |> StringUtils.prepend("Elixir.")
    |> Module.split()
    |> Enum.map(&String.to_atom/1)
  end

  # sobelow_skip ["DOS.StringToAtom"]
  def alias_segments(module) do
    module
    |> Module.split()
    |> Enum.map(&String.to_atom/1)
  end

  @doc """
  Builds module atom from alias segments.

  ## Examples

      iex> module([:Aaa, :Bbb])
      Aaa.Bbb
  """
  @spec module(Types.alias_segments()) :: module
  def module(alias_segs) do
    Module.safe_concat(alias_segs)
  end
end
