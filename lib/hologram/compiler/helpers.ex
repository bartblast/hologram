defmodule Hologram.Compiler.Helpers do
  alias Hologram.Typespecs, as: T

  def class_name(module) do
    module_name(module)
    |> String.replace(".", "")
  end

  @doc """
  Returns module atom containing "Elixir" segment at the beginning.

  ## Examples
      iex> Hologram.Compiler.Helpers.fully_qualified_module([:Abc, :Bcd])
      Elixir.Abc.Bcd
  """
  @spec fully_qualified_module(T.module_segments) :: module()

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

  def module_name_segments(module) do
    to_string(module)
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
    |> tl()
  end

  def module_source_path(module) do
    fully_qualified_module(module)
    |> apply(:module_info, [])
    |> get_in([:compile, :source])
    |> to_string()
  end
end
