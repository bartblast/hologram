defmodule Hologram.Compiler.Helpers do
  alias Hologram.Typespecs, as: T

  @doc """
  Returns the corresponding class name which can be used in JavaScript.

  ## Examples
      iex> Helpers.class_name([:Abc, :Bcd])
      "AbcBcd"
  """
  @spec class_name(T.module_name_segments) :: String.t

  def class_name(segments) do
    module_name(segments)
    |> String.replace(".", "")
  end

  @doc """
  Returns the corresponding Elixir module.

  ## Examples
      iex> Helpers.module([:Abc, :Bcd])
      Elixir.Abc.Bcd
  """
  @spec module(T.module_name_segments) :: module()

  def module(segments) do
    [:Elixir | segments]
    |> Enum.join(".")
    |> String.to_existing_atom()
  end

  @doc """
  Returns the corresponding module name (without the "Elixir" segment at the beginning).

  ## Examples
      iex> Helpers.module_name([:Abc, :Bcd])
      "Abc.Bcd"
  """
  @spec module_name(T.module_name_segments) :: String.t

  def module_name(segments) do
    Enum.join(segments, ".")
  end

  @doc """
  Returns the corresponding module name atom (without the "Elixir" segment at the beginning).

  ## Examples
      iex> Helpers.module_name_atom([:Abc, :Bcd])
      :"Abc.Bcd"
  """
  @spec module_name(T.module_name_segments) :: atom()

  def module_name_atom(segments) do
    module_name(segments)
    |> String.to_atom()
  end

  @doc """
  Returns the corresponding module name segments (without the "Elixir" segment at the beginning).

  ## Examples
      iex> Helpers.module_name_segments(Abc.Bcd)
      [:Abc, :Bcd]
  """
  @spec module_name_segments(module()) :: T.module_name_segments

  def module_name_segments(module) do
    to_string(module)
    |> String.split(".")
    |> Enum.map(&String.to_atom/1)
    |> tl()
  end

  @doc """
  Returns the file path of the given module source code.

  ## Examples
      iex> Helpers.module_source_path([:Hologram, :Compiler, :Helpers])
      "/Users/bart/Files/Projects/hologram/lib/hologram/compiler/helpers.ex"
  """
  @spec module_source_path(T.module_name_segments) :: String.t

  def module_source_path(segments) do
    module(segments)
    |> apply(:module_info, [])
    |> get_in([:compile, :source])
    |> to_string()
  end
end
