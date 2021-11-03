defmodule Hologram.Compiler.Helpers do
  alias Hologram.Compiler.{Binder, Context, Normalizer, Parser, Reflection, Transformer}
  alias Hologram.Compiler.IR.{FunctionDefinitionVariants, ModuleDefinition}
  alias Hologram.Typespecs, as: T

  def aggregate_bindings(params) do
    Enum.with_index(params)
    |> Enum.reduce([], fn {param, idx}, acc ->
      Binder.bind(param)
      |> Enum.reduce(acc, fn binding, acc ->
        name = List.last(binding).name
        if Keyword.has_key?(acc, name), do: acc, else: Keyword.put(acc, name, {idx, binding})
      end)
    end)
    |> Enum.sort()
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

  def fetch_block_body(ast) do
    case ast do
      {:__block__, _, body} ->
        body

      _ ->
        [ast]
    end
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

  @doc """
  Returns true if the given module is a component,
  i.e. it contains a use directive for the Hologram.Component module.

  ## Examples
      iex> module_definition = %ModuleDefinition{
      iex>   module: TestModule,
      iex>   uses: [%UseDirective{module: Hologram.Component}]
      iex> }
      iex> is_component?(module_definition)
      true
  """
  @spec is_component?(%ModuleDefinition{}) :: boolean()

  def is_component?(module_definition) do
    uses_module?(module_definition, Hologram.Component)
  end

  def is_layout?(module_def) do
    uses_module?(module_def, Hologram.Layout)
  end

  @doc """
  Returns true if the given module is a page,
  i.e. it contains a use directive for the Hologram.Page module.

  ## Examples
      iex> module_definition = %ModuleDefinition{
      iex>   module: TestModule,
      iex>   uses: [%UseDirective{module: Hologram.Page}]
      iex> }
      iex> is_page?(module_definition)
      true
  """
  @spec is_page?(%ModuleDefinition{}) :: boolean()

  def is_page?(module_definition) do
    uses_module?(module_definition, Hologram.Page)
  end

  @doc """
  Returns the corresponding Elixir module.

  ## Examples
      iex> Helpers.module([:Abc, :Bcd])
      Elixir.Abc.Bcd
  """
  @spec module(T.module_name_segments()) :: module()

  def module(module_segs) do
    [:"Elixir" | module_segs]
    |> Enum.join(".")
    |> String.to_existing_atom()
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

  @doc """
  Returns the corresponding module segments (without the "Elixir" segment at the beginning).

  ## Examples
      iex> Helpers.module_name_segments(Abc.Bcd)
      [:Abc, :Bcd]
  """
  @spec module_name_segments(module() | String.T) :: T.module_name_segments()

  def module_name_segments(module_name) when is_binary(module_name) do
    Module.split("Elixir.#{module_name}")
    |> Enum.map(&String.to_atom/1)
  end

  def module_name_segments(module) do
    Module.split(module)
    |> Enum.map(&String.to_atom/1)
  end

  def transform_params(params, context) do
    if(params, do: params, else: [])
    |> Enum.map(&Transformer.transform(&1, context))
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
