defmodule Hologram.Compiler.Helpers do
  @moduledoc false

  alias Hologram.Commons.Types, as: T

  @doc """
  Returns alias segments list (without the "Elixir" segment at the beginning).

  ## Examples

      iex> alias_segments("Aaa.Bbb")
      [:Aaa, :Bbb]

      iex> alias_segments(Aaa.Bbb)
      [:Aaa, :Bbb]
  """
  @spec alias_segments(binary | module) :: T.alias_segments()
  def alias_segments(term)

  # sobelow_skip ["DOS.StringToAtom"]
  def alias_segments(module_name) when is_binary(module_name) do
    "Elixir.#{module_name}"
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
  @spec module(T.alias_segments()) :: module
  def module(alias_segs) do
    [:"Elixir" | alias_segs]
    |> Enum.join(".")
    |> String.to_existing_atom()
  end
end
