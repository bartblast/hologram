defmodule Hologram.Reflection do
  @moduledoc false

  alias Hologram.Commons.StringUtils

  @call_graph_dump_file_name "call_graph.bin"

  @ignored_modules [Kernel.SpecialForms]

  @ir_plt_dump_file_name "ir.plt"

  @module_beam_path_plt_dump_file_name "module_beam_path.plt"

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
    |> to_string()
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
    elixir_module?(term) && {:__is_hologram_component__, 0} in term.__info__(:functions)
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
    if alias?(term) do
      case Code.ensure_loaded(term) do
        {:module, ^term} ->
          true

        _fallback ->
          false
      end
    else
      false
    end
  end

  def elixir_module?(_term), do: false

  @doc """
  Returns true if the given term is an existing Erlang module, or false otherwise.

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
    starts_with_lowercase? =
      term
      |> to_string()
      |> StringUtils.starts_with_lowercase?()

    if starts_with_lowercase? do
      case Code.ensure_loaded(term) do
        {:module, ^term} ->
          true

        _fallback ->
          false
      end
    else
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
    :exports
    |> module.module_info()
    |> Keyword.get_values(function)
    |> Enum.member?(arity)
  end

  @doc """
  Determines whether the given module defines its struct.
  """
  @spec has_struct?(module) :: boolean
  def has_struct?(module) do
    has_function?(module, :__struct__, 0) && has_function?(module, :__struct__, 1)
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
    |> Enum.reduce([], fn app, acc ->
      app
      |> Application.spec()
      |> Keyword.fetch!(:modules)
      |> Kernel.++(acc)
    end)
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
  def module?(term) do
    elixir_module?(term) || erlang_module?(term)
  end

  @doc """
  Returns the module BEAM path PLT dump file name.
  """
  @spec module_beam_path_plt_dump_file_name() :: String.t()
  def module_beam_path_plt_dump_file_name do
    @module_beam_path_plt_dump_file_name
  end

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
  """
  @spec otp_app() :: atom
  def otp_app do
    if Code.ensure_loaded?(Mix.Project) do
      Mix.Project.config()[:app]
    else
      [project_app] =
        for {app, _description, _vsn} <- Application.loaded_applications(),
            deps = Application.spec(app)[:applications],
            :hologram in deps do
          app
        end

      project_app
    end
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
    elixir_module?(term) && {:__is_hologram_page__, 0} in term.__info__(:functions)
  end

  @doc """
  Returns the page digest PLT dump file name.
  """
  @spec page_digest_plt_dump_file_name() :: String.t()
  def page_digest_plt_dump_file_name do
    @page_digest_plt_dump_file_name
  end

  @doc """
  Determines the app's Phoenix endpoint module.
  """
  @spec phoenix_endpoint :: module | nil
  def phoenix_endpoint do
    modules = list_elixir_modules([otp_app()])

    Enum.find(modules, fn module ->
      has_phoenix_endpoint_behaviour? =
        :attributes
        |> module.module_info()
        |> Keyword.get_values(:behaviour)
        |> List.flatten()
        |> Enum.member?(Phoenix.Endpoint)

      has_phoenix_endpoint_behaviour? && Application.get_env(otp_app(), module)
    end)
  end

  @doc """
  Returns true if the given term is a protocol module, or false otherwise.
  """
  @spec protocol?(any) :: boolean
  def protocol?(term) do
    elixir_module?(term) && has_function?(term, :__protocol__, 1)
  end

  @doc """
  Returns the release priv dir path.
  """
  @spec release_priv_dir() :: String.t()
  def release_priv_dir do
    otp_app()
    |> :code.priv_dir()
    |> to_string()
  end

  @doc """
  Returns the release static dir path.
  """
  @spec release_static_dir() :: String.t()
  def release_static_dir do
    Path.join(release_priv_dir(), "static")
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
  Returns the absolute path of the project priv dir for Hologram.

  ## Examples

      iex> root_priv_dir()
      "/Users/bartblast/Projects/my_project/priv/hologram"
  """
  @spec root_priv_dir() :: String.t()
  def root_priv_dir do
    Path.join([root_dir(), "priv", "hologram"])
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
end
