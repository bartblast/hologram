defmodule Hologram.Compiler.Helpers do
  alias Hologram.Compiler.IR.{Binding, FunctionDefinitionVariants, ModuleDefinition, ParamAccess}
  alias Hologram.Compiler.Normalizer
  alias Hologram.Compiler.Transformer
  alias Hologram.Typespecs, as: T
  alias Hologram.Utils

  def aggregate_bindings_from_expression(expr) do
    PatternDeconstructor.deconstruct(expr)
    |> Enum.reduce([], fn binding, acc ->
      name = List.last(binding).name
      maybe_add_binding(acc, name, binding)
    end)
    |> Enum.sort()
    |> Enum.map(fn {name, path} ->
      %Binding{name: name, access_path: build_binding_access_path(path)}
    end)
  end

  def aggregate_bindings_from_params(params) do
    params
    |> Enum.with_index()
    |> Enum.reduce([], &aggregate_bindings_from_param/2)
    |> Enum.sort()
    |> Enum.map(fn {name, {index, path}} ->
      %Binding{name: name, access_path: build_param_binding_access_path(path, index)}
    end)
  end

  defp build_binding_access_path(pattern_path) do
    pattern_path
    |> Enum.reverse()
    |> tl()
    |> Enum.reverse()
  end

  defp build_param_binding_access_path(pattern_path, param_index) do
    [%ParamAccess{index: param_index} | build_binding_access_path(pattern_path)]
  end

  defp aggregate_bindings_from_param({param, idx}, acc) do
    PatternDeconstructor.deconstruct(param)
    |> Enum.reduce(acc, fn binding, acc ->
      name = List.last(binding).name
      maybe_add_binding(acc, name, {idx, binding})
    end)
  end

  def aggregate_function_def_variants(function_defs) do
    Enum.reduce(function_defs, %{}, fn fd, acc ->
      if Map.has_key?(acc, fd.name) do
        Map.put(acc, fd.name, acc[fd.name] ++ [fd])
      else
        Map.put(acc, fd.name, [fd])
      end
    end)
    |> Enum.map(fn {name, variants} ->
      {name, %FunctionDefinitionVariants{name: name, variants: variants}}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns the corresponding class name which can be used in JavaScript.
  ## Examples
      iex> Helpers.class_name(Abc.Bcd)
      "Elixir_Abc_Bcd"
  """
  @spec class_name(module()) :: String.t()

  def class_name(module) do
    [:"Elixir" | Module.split(module)]
    |> Enum.join("_")
  end

  def erlang_module(atom) do
    atom
    |> to_string()
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
    |> Utils.string_prepend("Erlang.")
    |> String.to_atom()
  end

  @spec get_components(T.module_definitions_map()) :: list(%ModuleDefinition{})
  def get_components(module_defs_map) do
    module_defs_map
    |> Enum.filter(fn {_, module_def} -> module_def.component? end)
    |> Enum.map(fn {_, module_def} -> module_def end)
  end

  @spec get_pages(T.module_definitions_map()) :: list(%ModuleDefinition{})
  def get_pages(module_defs_map) do
    module_defs_map
    |> Enum.filter(fn {_, module_def} -> module_def.page? end)
    |> Enum.map(fn {_, module_def} -> module_def end)
  end

  defp maybe_add_binding(acc, name, binding) do
    if Keyword.has_key?(acc, name) do
      acc
    else
      Keyword.put(acc, name, binding)
    end
  end

  @doc """
  Returns the corresponding Elixir module.
  ## Examples
      iex> Helpers.module([:Abc, :Bcd])
      Elixir.Abc.Bcd
  """
  @spec module(T.alias_segments()) :: module()

  def module([]), do: nil

  def module(alias_segs) do
    [:"Elixir" | alias_segs]
    |> Enum.join(".")
    |> String.to_atom()
  end

  @doc """
  Returns the corresponding module name (without the "Elixir" segment at the beginning).
  ## Examples
      iex> Helpers.module_name(Abc.Bcd)
      "Abc.Bcd"
  """
  @spec module_name(module()) :: String.t()

  def module_name(module) do
    Module.split(module)
    |> Enum.join(".")
  end

  def term_to_ir(term) do
    term
    |> Macro.escape()
    |> Normalizer.normalize()
    |> Transformer.transform()
  end

  @doc """
  Returns true if the first module has a "use" directive for the second module.
  ## Examples
      iex> user_module = %ModuleDefinition{module: Hologram.Compiler.Parser, ...}
      iex> Helpers.uses_module?(user_module, Hologram.Commons.Parser)
      true
  """
  @spec uses_module?(%ModuleDefinition{}, module()) :: boolean()

  def uses_module?(user_module_def, used_module) do
    Enum.any?(user_module_def.uses, &(&1.module == used_module))
  end
end
