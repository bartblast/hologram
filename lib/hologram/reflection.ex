defmodule Hologram.Reflection do
  @moduledoc false

  @call_graph_dump_file_name "call_graph.bin"

  @compiler_lock_file_name "hologram_compiler.lock"

  @ignored_modules [Kernel.SpecialForms]

  @ir_plt_dump_file_name "ir.plt"

  @module_digest_plt_dump_file_name "module_digest.plt"

  @page_digest_plt_dump_file_name "page_digest.plt"

  @doc """
  Determines whether the given term is an alias.

  ## Examples

      iex> alias?(Calendar.ISO)
      true

      iex> alias?(:abc)
      false
  """
  @spec alias?(any) :: boolean
  def alias?(term)

  def alias?(term) when is_atom(term) do
    term
    |> Atom.to_string()
    |> String.starts_with?("Elixir.")
  end

  def alias?(_term), do: false

  @doc """
  Returns BEAM definitions for the given BEAM file path.

  ## Examples

      iex> beam_path = ~c"/Users/bartblast/Projects/hologram/_build/dev/lib/hologram/ebin/Elixir.Hologram.Reflection.beam"  
      iex> beam_defs()
      [
        ...,
        {{:alias?, 1}, :def, [line: 14],
        [
          {[line: 16], [{:term, [version: 0, line: 16], nil}],
            [
              {{:., [line: 16], [:erlang, :is_atom]}, [line: 16],
              [{:term, [version: 0, line: 16], nil}]}
            ],
            {{:., [line: 19], [String, :starts_with?]}, [line: 19],
            [
              {{:., [line: 18], [String.Chars, :to_string]}, [line: 18],
                [{:term, [version: 0, line: 17], nil}]},
              "Elixir."
            ]}},
          {[line: 22], [{:_, [line: 22], nil}], [], false}
        ]}
      ]
  """
  @spec beam_defs(charlist) :: list(tuple)
  def beam_defs(beam_path) do
    {:ok, %{definitions: definitions}} = BeamFile.debug_info(beam_path)
    definitions
  end

  @doc """
  Returns the build directory path.
  """
  @spec build_dir() :: String.t()
  def build_dir do
    :hologram
    |> :code.priv_dir()
    |> to_string()
  end

  @doc """
  Returns the call graph dump file name.
  """
  @spec call_graph_dump_file_name() :: String.t()
  def call_graph_dump_file_name do
    @call_graph_dump_file_name
  end

  @doc "Returns Hologram compiler lock file name."
  @spec compiler_lock_file_name :: String.t()
  def compiler_lock_file_name do
    @compiler_lock_file_name
  end

  @doc """
  Returns true if the given term is a component module (a module that has a "use Hologram.Component" directive)
  Otherwise false is returned.

  ## Examples

      iex> component?(MyComponent)
      true

      iex> component?(Hologram.Reflection)
      false
  """
  @spec component?(term) :: boolean
  def component?(term) do
    elixir_module?(term) && has_function?(term, :__is_hologram_component__, 0)
  end

  @doc """
  Returns true if the given term is an Ecto schema module, or false otherwise.
  """
  @spec ecto_schema?(any) :: boolean
  def ecto_schema?(term) do
    elixir_module?(term) && has_function?(term, :__schema__, 1) &&
      has_function?(term, :__changeset__, 0)
  end

  @doc """
  Returns true if the given term is an existing Elixir module, or false otherwise.

  Some Erlang modules use Elixir-style naming for interop (e.g. the atom `Luerl`,
  whose source is the Erlang file `Elixir.Luerl.erl`). Such modules are compiled by
  the Erlang compiler and are not Elixir modules, so they return false even though
  their names look like Elixir aliases. They are detected by the absence of the
  `__info__/1` function that the Elixir compiler injects into every Elixir module.

  ## Examples

      iex> elixir_module?(Calendar.ISO)
      true

      iex> elixir_module?(MyModule)
      false

      iex> elixir_module?(:my_module)
      false

      iex> elixir_module?(123)
      false
  """
  @spec elixir_module?(term) :: boolean
  def elixir_module?(term)

  def elixir_module?(term) when is_atom(term) do
    alias?(term) &&
      case Code.ensure_loaded(term) do
        {:module, _module} ->
          function_exported?(term, :__info__, 1)

        _fallback ->
          false
      end
  end

  def elixir_module?(_term), do: false

  @doc """
  Returns true if the given term is an existing Erlang module, or false otherwise.

  An Erlang module is detected by the absence of the `__info__/1` function that the
  Elixir compiler injects into every Elixir module. This means Erlang modules that
  use Elixir-style naming for interop (e.g. the atom `Luerl`, whose source is the
  Erlang file `Elixir.Luerl.erl`) are correctly recognized as Erlang modules.

  ## Examples

      iex> erlang_module?(:maps)
      true

      iex> erlang_module?(:my_module)
      false

      iex> erlang_module?(Calendar.ISO)
      false

      iex> erlang_module?(123)
      false
  """
  @spec erlang_module?(term) :: boolean
  def erlang_module?(term)

  def erlang_module?(term) when is_atom(term) do
    case Code.ensure_loaded(term) do
      {:module, _module} ->
        !function_exported?(term, :__info__, 1)

      _fallback ->
        false
    end
  end

  def erlang_module?(_term), do: false

  @doc """
  Returns true if module contains a public function with the given arity, otherwise false.

  Kernel.function_exported?/3 does not load the module in case it is not loaded
  (in such cases it would return false even when the module has the given function).
  """
  @spec has_function?(module, atom, integer) :: boolean
  def has_function?(module, function, arity) do
    Code.ensure_loaded(module)
    function_exported?(module, function, arity)
  end

  @doc """
  Determines whether the given module defines its struct.
  """
  @spec has_struct?(module) :: boolean
  def has_struct?(module) do
    has_function?(module, :__struct__, 0) && has_function?(module, :__struct__, 1)
  end

  @doc """
  Returns the absolute path of the Hologram dependency directory.

  Resolves through `Mix.Project.deps_paths/0`, which yields the correct
  location for any dependency type (Hex, Git or path) in both single-app and
  umbrella projects. Falls back to `<deps path>/hologram` when Hologram itself
  is not among the current project's dependencies (e.g. inside the Hologram
  repo itself).

  Requires a Mix project context (compilation or Mix tasks in any Mix env) -
  not callable inside a release, where Mix is unavailable.
  """
  @spec hologram_dep_dir() :: String.t()
  def hologram_dep_dir do
    fallback_dir = Path.join(Mix.Project.deps_path(), "hologram")
    Map.get(Mix.Project.deps_paths(), :hologram, fallback_dir)
  end

  @doc """
  Returns the IR PLT dump file name.
  """
  @spec ir_plt_dump_file_name() :: String.t()
  def ir_plt_dump_file_name do
    @ir_plt_dump_file_name
  end

  @doc """
  Lists all OTP applications, both loaded and not loaded.
  """
  @spec list_all_otp_apps() :: list(atom)
  # sobelow_skip ["DOS.StringToAtom"]
  def list_all_otp_apps do
    [root_dir(), "_build", to_string(Hologram.env()), "**", "ebin", "*.app"]
    |> Path.join()
    |> Path.wildcard()
    |> Stream.map(&Path.basename(&1, ".app"))
    |> Stream.map(&String.to_atom/1)
    |> Enum.to_list()
    |> Kernel.++(list_loaded_otp_apps())
    |> Enum.uniq()
  end

  @doc """
  Lists modules by scanning BEAM files in the given OTP app's ebin directory.
  This is useful for detecting newly compiled modules that haven't been added to
  Application.spec yet during development.
  """
  @spec list_ebin_modules(atom) :: list(module)
  # sobelow_skip ["DOS.StringToAtom"]
  def list_ebin_modules(app) do
    case :code.lib_dir(app) do
      {:error, :bad_name} ->
        []

      lib_dir ->
        ebin_path = Path.join([lib_dir, "ebin"])

        [ebin_path, "*.beam"]
        |> Path.join()
        |> Path.wildcard()
        |> Enum.map(&Path.basename(&1, ".beam"))
        |> Enum.map(&String.to_atom/1)
    end
  end

  @doc """
  Lists Elixir modules belonging to any of the loaded OTP applications used by the project (except :hex).
  Elixir modules listed in @ignored_modules module attribute, Elixir modules without a BEAM file, and Erlang modules are filtered out.
  The project OTP application is included.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/reflection/list_elixir_modules_0/README.md
  """
  @spec list_elixir_modules() :: list(module)
  def list_elixir_modules do
    Application.ensure_loaded(otp_app())

    list_loaded_otp_apps()
    |> Kernel.--([:hex])
    |> list_elixir_modules()
  end

  @doc """
  Lists Elixir modules belonging to the given OTP apps.
  Elixir modules listed in @ignored_modules module attribute and Erlang modules are filtered out.
  """
  @spec list_elixir_modules(list(atom)) :: list(module)
  def list_elixir_modules(apps) do
    apps
    |> Enum.reduce([], &include_app_elixir_modules/2)
    |> Enum.filter(&elixir_module?/1)
    |> Kernel.--(@ignored_modules)
  end

  @doc """
  Lists loaded OTP applications.

  ## Examples

    iex> list_loaded_otp_apps()
    [
      :inets,
      :logger,
      :stdlib,
      :file_system,
      ...
    ]
  """
  @spec list_loaded_otp_apps() :: list(:atom)
  def list_loaded_otp_apps do
    apps_info = Application.loaded_applications()
    Enum.map(apps_info, fn {app, _description, _version} -> app end)
  end

  @doc """
  Lists Elixir modules which are Hologram pages and that belong to any of the OTP apps in the project.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/reflection/list_pages_0/README.md
  """
  @spec list_pages() :: list(module)
  def list_pages do
    Enum.filter(list_elixir_modules(), &page?/1)
  end

  @doc """
  Returns the list of modules that are implementations of the given protocol.
  """
  @spec list_protocol_implementations(module) :: list(module)
  def list_protocol_implementations(protocol) do
    paths =
      Enum.reduce(list_loaded_otp_apps(), [], fn app, acc ->
        case :code.lib_dir(app) do
          {:error, :bad_name} ->
            acc

          path ->
            [Path.join(path, "ebin") | acc]
        end
      end)

    protocol
    |> Protocol.extract_impls(paths)
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    |> Enum.map(&Module.concat(protocol, &1))
  end

  @doc """
  Lists standard library Elixir modules, e.g. DateTime, Kernel, Calendar.ISO, etc.
  Elixir modules listed in @ignored_modules module attribute, Elixir modules without a BEAM file, and Erlang modules are filtered out.
  """
  @spec list_std_lib_elixir_modules() :: list(module)
  def list_std_lib_elixir_modules do
    list_elixir_modules([:elixir])
  end

  @doc """
  Returns true if the given term is an existing (Elixir or Erlang) module, or false otherwise.

  ## Examples

      iex> module?(Calendar.ISO)
      true

      iex> module?(MyModule)
      false
      
      iex> module?(:maps)
      true

      iex> module?(:my_module)
      false
      
      iex> module?(123)
      false
  """
  @spec module?(term) :: boolean
  def module?(term)

  def module?(term) when is_atom(term) do
    case Code.ensure_loaded(term) do
      {:module, _module} ->
        true

      _fallback ->
        false
    end
  end

  def module?(_term), do: false

  @doc """
  Returns the module digest PLT dump file name.
  """
  @spec module_digest_plt_dump_file_name() :: String.t()
  def module_digest_plt_dump_file_name do
    @module_digest_plt_dump_file_name
  end

  @doc """
  Returns the module name without "Elixir" prefix at the beginning.

  ## Examples

      iex> module_name(Aaa.Bbb)
      "Aaa.Bbb"
  """
  @spec module_name(module()) :: String.t()
  def module_name(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  @doc """
  Returns the project OTP application name.

  Resolved from the active Mix project when it defines an `:app`. Otherwise
  (umbrella root, releases) it is identified among the loaded applications as
  the one that depends on `:hologram`, disambiguated by Phoenix endpoint
  ownership when several do.
  """
  @spec otp_app() :: atom
  def otp_app do
    otp_app_from_mix_project() || otp_app_from_loaded_apps()
  end

  @doc """
  Returns the absolute path of the priv dir of the project OTP application.

  Resolved through the code path (`:code.priv_dir/1`), so it points at the
  build dir in Mix environments and at the release dir in releases.
  """
  @spec otp_app_priv_dir() :: String.t()
  def otp_app_priv_dir do
    otp_app()
    |> :code.priv_dir()
    |> to_string()
  end

  @doc """
  Returns the absolute path of the static dir of the project OTP application.
  """
  @spec otp_app_static_dir() :: String.t()
  def otp_app_static_dir do
    Path.join(otp_app_priv_dir(), "static")
  end

  @doc """
  Returns true if the given term is a page module (a module that has a "use Hologram.Page" directive)
  Otherwise false is returned.

  ## Examples

      iex> page?(MyPage)
      true

      iex> page?(Hologram.Reflection)
      false
  """
  @spec page?(term) :: boolean
  def page?(term) do
    elixir_module?(term) && has_function?(term, :__is_hologram_page__, 0)
  end

  @doc """
  Returns the page digest PLT dump file name.
  """
  @spec page_digest_plt_dump_file_name() :: String.t()
  def page_digest_plt_dump_file_name do
    @page_digest_plt_dump_file_name
  end

  @doc """
  Determines the project's Phoenix endpoint module - the module implementing
  the `Phoenix.Endpoint` behaviour that is configured in the project OTP
  application's environment.
  """
  @spec phoenix_endpoint :: module | nil
  def phoenix_endpoint do
    phoenix_endpoint_for_app(otp_app())
  end

  @doc """
  Returns true if the given term is a protocol module, or false otherwise.
  """
  @spec protocol?(any) :: boolean
  def protocol?(term) do
    elixir_module?(term) && has_function?(term, :__protocol__, 1)
  end

  @doc """
  Returns the protocol module that the given module implements, or nil if it's not a protocol implementation.
  """
  @spec protocol_impl(module) :: module | nil
  def protocol_impl(module) do
    if has_function?(module, :__impl__, 1) do
      module.__impl__(:protocol)
    end
  end

  @doc """
  Returns the absolute dir path of the project.

  ## Examples

      iex> root_dir()
      "/Users/bartblast/Projects/my_project"
  """
  @spec root_dir() :: String.t()
  def root_dir do
    File.cwd!()
  end

  @doc """
  Returns the file path of the given module's source code.
  """
  @spec source_path(module()) :: String.t()
  def source_path(module) do
    to_string(module.module_info()[:compile][:source])
  end

  @doc """
  Returns true if the given term is a component (a module that has a "use Hologram.Component" directive)
  or a page (a module that has a "use Hologram.Page" directive).
  Otherwise false is returned.

  ## Examples

      iex> component?(MyComponent)
      true
      
      iex> component?(MyPage)
      true

      iex> component?(Hologram.Reflection)
      false
  """
  @spec templatable?(term) :: boolean
  def templatable?(term) do
    component?(term) || page?(term)
  end

  @doc """
  Returns the absolute path of the tmp directory.

  ## Examples

      iex> tmp_dir()
      "/Users/bartblast/Projects/my_project/tmp"
  """
  @spec tmp_dir() :: String.t()
  def tmp_dir do
    Path.join(root_dir(), "tmp")
  end

  defp apps_depending_on_hologram do
    apps =
      for {app, _description, _version} <- Application.loaded_applications(),
          deps = Application.spec(app)[:applications],
          :hologram in deps do
        app
      end

    Enum.sort(apps)
  end

  defp include_app_elixir_modules(app, modules) do
    # Get modules from Application.spec (faster, but may miss newly compiled modules)
    spec_modules =
      app
      |> Application.spec()
      |> Keyword.fetch!(:modules)

    # For dev and test environments, also scan ebin directory BEAM files to catch newly compiled modules
    # that haven't been added to Application.spec yet
    env = Hologram.env()

    ebin_modules =
      if env == :dev || env == :test do
        list_ebin_modules(app)
      else
        []
      end

    # Combine both sources and remove duplicates
    Enum.uniq(modules ++ spec_modules ++ ebin_modules)
  end

  defp otp_app_from_loaded_apps do
    case apps_depending_on_hologram() do
      [app] ->
        app

      [] ->
        raise "Hologram could not determine the project OTP application: " <>
                "no loaded application depends on :hologram."

      apps ->
        case Enum.filter(apps, &phoenix_endpoint_for_app/1) do
          [app] ->
            app

          [] ->
            raise "Hologram could not determine the project OTP application: " <>
                    "multiple loaded applications depend on :hologram (#{inspect(apps)}), " <>
                    "but none of them has a configured Phoenix endpoint."

          endpoint_apps ->
            raise "Hologram found multiple applications with configured Phoenix endpoints " <>
                    "(#{inspect(endpoint_apps)}). Hologram supports one endpoint app " <>
                    "per running BEAM instance."
        end
    end
  end

  defp otp_app_from_mix_project do
    if Code.ensure_loaded?(Mix.Project), do: Mix.Project.config()[:app]
  end

  defp phoenix_endpoint?(module) do
    elixir_module?(module) &&
      :attributes
      |> module.module_info()
      |> Keyword.get_values(:behaviour)
      |> List.flatten()
      |> Enum.member?(Phoenix.Endpoint)
  end

  defp phoenix_endpoint_for_app(app) do
    app
    |> Application.get_all_env()
    |> Enum.find_value(fn {key, value} ->
      if value && phoenix_endpoint?(key), do: key
    end)
  end
end
