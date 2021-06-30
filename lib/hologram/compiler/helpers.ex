defmodule Hologram.Compiler.Helpers do
  @typedoc """
  e.g. [:Hologram, :Compiler, :Helpers]
  """
  @type module_segments :: list(atom())

  def class_name(module) do
    module_name(module)
    |> String.replace(".", "")
  end

  @doc """
  ## Example
      iex> Hologram.Compiler.Helpers.fully_qualified_module([:Abc, :Bcd])
      Elixir.Abc.Bcd
  """
  @spec fully_qualified_module(module_segments) :: module()

  def fully_qualified_module(module) do
    [:Elixir | module]
    |> Enum.join(".")
    |> String.to_existing_atom()
  end

  def module_name(module) do
    Enum.join(module, ".")
  end

  def module_name_atom(module) do
    module_name(module)
    |> String.to_atom()
  end

  def module_name_parts(module) do
    to_string(module)
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
    |> tl()
  end
end
