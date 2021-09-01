defmodule Hologram.Compiler.Reflection do
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Compiler.{Context, Helpers, Normalizer, Parser, Transformer}

  # TODO: refactor & test
  def app_name do
    Mix.Project.get().project[:app]
  end

  # TODO: refactor & test
  def app_path do
    File.cwd!()
  end

  def ast(module_segs) when is_list(module_segs) do
    Helpers.module(module_segs)
    |> ast()
  end

  def ast(module) do
    source_path(module)
    |> Parser.parse_file!()
    |> Normalizer.normalize()
  end

  # DEFER: optimize, e.g. load the manifest in config
  def get_page_digest(module) do
    File.cwd!() <> "/priv/static/hologram/manifest.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("#{module}")
  end

  def has_template?(module) do
    function_exported?(module, :template, 0)
  end

  # TODO: refactor & test
  def list_pages(opts \\ []) do
    glob = "#{pages_path(opts)}/**/*.ex"
    regex = ~r/defmodule\s+([\w\.]+)\s+do\s+/

    Path.wildcard(glob)
    |> Enum.map(fn filepath ->
      code = File.read!(filepath)
      [_, module] = Regex.run(regex, code)
      String.to_atom("Elixir.#{module}")
    end)
  end

  # DEFER: instead of matching the macro on arity, pattern match the params as well
  def macro_definition(module, name, params) do
    arity = Enum.count(params)

    module_definition(module).macros
    |> Enum.filter(&(&1.name == name && &1.arity == arity))
    |> hd()
  end

  def module?(arg) do
    if Code.ensure_loaded?(arg) do
      to_string(arg)
      |> String.split(".")
      |> hd()
      |> Kernel.==("Elixir")
    else
      false
    end
  end

  @doc """
  Returns the corresponding module definition.

  ## Examples
      iex> Reflection.get_module_definition(Abc.Bcd)
      %ModuleDefinition{module: Abc.Bcd, ...}
  """
  @spec module_definition(module()) :: %ModuleDefinition{}

  def module_definition(module) do
    ast(module)
    |> Transformer.transform(%Context{})
  end

  # TODO: refactor & test
  def pages_path(opts \\ []) do
    config_pages_path = Application.get_env(:hologram, :pages_path)

    cond do
      opts[:pages_path] ->
        opts[:pages_path]

      config_pages_path ->
        config_pages_path

      true ->
        "#{app_path()}/lib/#{app_name()}_web/hologram/pages"
    end
  end

  @doc """
  Returns the file path of the given module's source code.

  ## Examples
      iex> Reflection.source_path(Hologram.Compiler.Reflection)
      "/Users/bart/Files/Projects/hologram/lib/hologram/compiler/reflection.ex"
  """
  @spec source_path(module()) :: String.t()

  def source_path(module) do
    module.module_info()[:compile][:source]
    |> to_string()
  end

  def standard_lib?(module) do
    source_path = source_path(module)
    app_path = app_path()

    !String.starts_with?(source_path, "#{app_path}/deps/")
    && !String.starts_with?(source_path, "#{app_path}/lib/")
    && !String.starts_with?(source_path, "#{app_path}/test/")
  end

  def templatable?(module_def) do
    Helpers.is_component?(module_def)
    || Helpers.is_page?(module_def)
    || Helpers.is_layout?(module_def)
  end
end
