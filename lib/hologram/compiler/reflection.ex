defmodule Hologram.Compiler.Reflection do
  alias Hologram.Compiler.{Context, Helpers, Normalizer, Parser, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.{MixProject, Utils}

  @config Application.get_all_env(:hologram)
  @env Application.fetch_env!(:hologram, :env)
  @ignored_modules [Ecto.Changeset, Hologram.Runtime.JS] ++ Application.get_env(:hologram, :ignored_modules, [])
  @ignored_namespaces Application.get_env(:hologram, :ignored_namespaces, [])

  def app_path(opts \\ @config) do
    case Keyword.get(opts, :app_path) do
      nil -> "#{root_path()}/app"
      app_path -> app_path
    end
  end

  def ast(module) when is_atom(module) do
    source_path(module)
    |> Parser.parse_file!()
    |> Normalizer.normalize()
  end

  def ast(code) when is_binary(code) do
    Parser.parse!(code)
    |> Normalizer.normalize()
  end

  def ast(module_segs) when is_list(module_segs) do
    Helpers.module(module_segs)
    |> ast()
  end

  # DEFER: test
  def build_path do
    if MixProject.is_dep?() do
      "#{root_path()}/../../_build/#{@env}/hologram"
    else
      "#{root_path()}/_build/#{@env}/hologram"
    end
  end

  def components_path(opts \\ []) do
    resolve_path(opts, :components_path, :components)
  end

  # DEFER: optimize, e.g. load the manifest in config
  def get_page_digest(module) do
    "#{root_path()}/priv/static/hologram/manifest.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("#{module}")
  end

  # Kernel.function_exported?/3 does not load the module in case it is not loaded
  # (in such cases it would return false even when the module has the given function).
  def has_function?(module, function, arity) do
    module.module_info(:exports)
    |> Keyword.get_values(function)
    |> Enum.member?(arity)
  end

  # Kernel.macro_exported?/3 does not load the module in case it is not loaded
  # (in such cases it would return false even when the module has the given macro).
  def has_macro?(module, function, arity) do
    has_function?(module, :"MACRO-#{function}", arity + 1)
  end

  def has_template?(module) do
    has_function?(module, :template, 0)
  end

  def ir(code, context \\ %Context{}) do
    ast(code)
    |> Transformer.transform(context)
  end

  def is_alias?(term) do
    str = to_string(term)
    is_atom(term) && String.starts_with?(str, "Elixir.")
  end

  def is_ignored_module?(module) do
    if module in @ignored_modules do
      true
    else
      module_name = to_string(module)
      Enum.any?(@ignored_namespaces, fn namespace ->
        String.starts_with?(module_name, to_string(namespace) <> ".")
      end)
    end
  end

  def is_module?(term) do
    is_alias?(term) && !is_protocol?(term)
  end

  def is_protocol?(term) do
    is_alias?(term) && Keyword.has_key?(term.module_info(:exports), :__protocol__)
  end

  def layouts_path(opts \\ []) do
    resolve_path(opts, :layouts_path, :layouts)
  end

  def list_components(opts \\ []) do
    components_path = components_path(opts)
    list_modules_of_type(:component, components_path)
  end

  def list_layouts(opts \\ []) do
    layouts_path = layouts_path(opts)
    list_modules_of_type(:layout, layouts_path)
  end

  def list_modules(app) do
    Keyword.fetch!(Application.spec(app), :modules)
    |> Enum.reduce([], fn module, acc ->
      case Code.ensure_loaded(module) do
        {:module, _} ->
          acc ++ [module]
        _ ->
          acc
      end
    end)
  end

  defp list_modules_of_type(type, path) do
    app = @config[:otp_app]
    :ok = Application.ensure_loaded(app)

    Keyword.fetch!(Application.spec(app), :modules)
    |> Enum.reduce([], fn module, acc ->
      case Code.ensure_loaded(module) do
        {:module, _} ->
          funs = module.module_info(:exports)

          in_path? = String.starts_with?(source_path(module), path)
          type_check_function = :"is_#{type}?"

          if Keyword.get(funs, type_check_function) && apply(module, type_check_function, []) && in_path? do
            acc ++ [module]
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  def list_pages(opts \\ []) do
    pages_path = pages_path(opts)
    list_modules_of_type(:page, pages_path)
  end

  # DEFER: instead of matching the macro on arity, pattern match the args as well
  def macro_definition(module, name, args) do
    arity = Enum.count(args)

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

  def otp_app do
    @config[:otp_app]
  end

  def pages_path(opts \\ []) do
    resolve_path(opts, :pages_path, :pages)
  end

  defp resolve_path(opts, key, dir) do
    cond do
      Keyword.has_key?(opts, key) ->
        opts[key]

      path = Application.get_env(:hologram, key) ->
        path

      true ->
        "#{app_path()}/#{dir}"
    end
  end

  def root_path(opts \\ @config) do
    case Keyword.get(opts, :root_path) do
      nil -> File.cwd!()
      root_path -> root_path
    end
  end

  def router_module(opts \\ @config) do
    case Keyword.get(opts, :router_module) do
      nil ->
        app_web_namespace =
          otp_app()
          |> to_string()
          |> Utils.append("_web")
          |> Macro.camelize()
          |> String.to_atom()

        Helpers.module([app_web_namespace, :Router])

      router_module ->
        router_module
    end
  end

  def router_path do
    router_module() |> source_path()
  end

  def source_code(module) do
    source_path(module) |> File.read!()
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
    root_path = root_path()
    app_path = app_path()

    !String.starts_with?(source_path, "#{app_path}/") &&
      !String.starts_with?(source_path, "#{root_path}/lib/") &&
      !String.starts_with?(source_path, "#{root_path}/test/") &&
      !String.starts_with?(source_path, "#{root_path}/deps/")
  end

  def template_store_dump_path do
    "#{build_path()}/template_store.bin"
  end
end
