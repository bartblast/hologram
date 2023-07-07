defmodule Hologram.Compiler.Helpers do
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.Reflection

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

  def alias_segments(module_name) when is_binary(module_name) do
    "Elixir.#{module_name}"
    |> Module.split()
    |> Enum.map(&String.to_existing_atom/1)
  end

  def alias_segments(module) do
    module
    |> Module.split()
    |> Enum.map(&String.to_existing_atom/1)
  end

  @doc """
  Builds module symbol from alias segments.

  ## Examples

      iex> module([:Aaa, :Bbb])
      Aaa.Bbb

      iex> module([:Elixir, :Aaa, :Bbb])
      Aaa.Bbb
  """
  @spec module(T.alias_segments()) :: module

  def module([term]) do
    if Reflection.alias?(term) do
      term
    else
      module([:"Elixir" | [term]])
    end
  end

  def module([:"Elixir" | _] = alias_segs) do
    alias_segs
    |> Enum.join(".")
    |> String.to_existing_atom()
  end

  def module(alias_segs) do
    module([:"Elixir" | alias_segs])
  end
end
