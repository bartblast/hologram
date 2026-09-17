defmodule Hologram.Reflection do
  @moduledoc false

  alias Hologram.Commons.PLT

  @beam_info_keys [
    :digest,
    :mtime,
    :size,
    :page?,
    :component?,
    :protocol?,
    :protocol_implementation?,
    :struct?,
    :exception?,
    :ecto_schema?,
    :source_path,
    :layout_module,
    :protocol_functions,
    :implementation_for,
    :implemented_protocol
  ]

  @call_graph_dump_file_name "call_graph.bin"

  @compiler_lock_file_name "hologram_compiler.lock"

  @ignored_modules [Kernel.SpecialForms]

  @ir_plt_dump_file_name "ir.plt"

  @module_info_plt_dump_file_name "module_info.plt"

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
  Returns what the compiler needs to know about a module, read from its BEAM file in one pass and without
  loading it: a digest of the raw `Dbgi` chunk bytes for change detection, the BEAM file's mtime (posix
  seconds) and size for skipping unchanged files, and whether the module is a Hologram page or component,
  a protocol, a protocol implementation, a struct, an exception or an Ecto schema. Each flag is the export
  table check that the `Reflection` predicate of the same name performs after loading the module, read from
  the file instead. The source path is the `:source` of the BEAM's compile info, the value
  `module.module_info(:compile)[:source]` returns once the module is loaded, as a string (nil when the
  compile info has none).
  A page's layout module, a protocol's functions, and the target and protocol of a protocol implementation
  are read from the debug info, where `__layout_module__/0`, `__protocol__(:functions)`, `__impl__(:for)`
  and `__impl__(:protocol)` return them as literals. They are nil for every other kind of module, and nil
  when the function is missing or returns something that is not a literal.
  Returns nil when the BEAM is not an Elixir module (no `__info__/1` in its export table, as for an Erlang
  source named `Elixir.Something.erl`). Accepts the BEAM file path or the BEAM binary; with a binary, mtime
  and size are nil.

  ## Examples

      iex> beam_info(~c"/path/to/Elixir.MyPage.beam")
      %{
        digest: 56860599,
        mtime: 1789514623,
        size: 1355821,
        page?: true,
        component?: false,
        protocol?: false,
        protocol_implementation?: false,
        struct?: false,
        exception?: false,
        ecto_schema?: false,
        source_path: "/path/to/lib/my_page.ex",
        layout_module: MyLayout,
        protocol_functions: nil,
        implementation_for: nil,
        implemented_protocol: nil
      }
  """
  # TODO: Narrow the spec back to charlist, and rename the param back to
  # beam_path, when beam_source/1 goes (see the removal note there) - nothing
  # passes a BEAM binary here once the umbrella fallback is gone.
  @spec beam_info(charlist | binary) ::
          %{
            digest: non_neg_integer,
            mtime: non_neg_integer | nil,
            size: non_neg_integer | nil,
            page?: boolean,
            component?: boolean,
            protocol?: boolean,
            protocol_implementation?: boolean,
            struct?: boolean,
            exception?: boolean,
            ecto_schema?: boolean,
            source_path: String.t() | nil,
            layout_module: module | nil,
            protocol_functions: list({atom, arity}) | nil,
            implementation_for: module | nil,
            implemented_protocol: module | nil
          }
          | nil
  def beam_info(beam_source) do
    # The stat comes before the read on purpose. If a writer replaces the file in between, the
    # entry pairs the old mtime and size with the new digest, and the next compile sees the file
    # differ from the entry and reads it again. The other order could pair the new mtime and
    # size with the old digest, and that entry would be reused as long as the file stood still.
    {mtime, size} = beam_mtime_and_size(beam_source)

    {:ok, {_module, [{:exports, exports}, {~c"Dbgi", dbgi_chunk}, {:compile_info, compile_info}]}} =
      :beam_lib.chunks(beam_source, [:exports, ~c"Dbgi", :compile_info])

    if {:__info__, 1} in exports do
      page? = {:__is_hologram_page__, 0} in exports
      protocol? = {:__protocol__, 1} in exports
      protocol_implementation? = {:__impl__, 1} in exports

      # Only the kinds of module that have literals to read get their debug info decoded; a plain
      # module's chunk is hashed as bytes and never decoded.
      definitions =
        if page? or protocol? or protocol_implementation? do
          debug_info_definitions(dbgi_chunk)
        else
          []
        end

      %{
        digest: :erlang.phash2(dbgi_chunk),
        mtime: mtime,
        size: size,
        page?: page?,
        component?: {:__is_hologram_component__, 0} in exports,
        protocol?: protocol?,
        protocol_implementation?: protocol_implementation?,
        struct?: {:__struct__, 0} in exports and {:__struct__, 1} in exports,
        exception?: {:exception, 1} in exports and {:message, 1} in exports,
        ecto_schema?: {:__schema__, 1} in exports and {:__changeset__, 0} in exports,
        source_path: compile_info_source(compile_info),
        layout_module: literal_return(definitions, :__layout_module__, []),
        protocol_functions: literal_return(definitions, :__protocol__, [:functions]),
        implementation_for: literal_return(definitions, :__impl__, [:for]),
        implemented_protocol: literal_return(definitions, :__impl__, [:protocol])
      }
    end
  end

  @doc """
  Returns the keys of a map returned by beam_info/1. A stored entry that lacks one of them was
  written by an older Hologram and has to be read again.
  """
  @spec beam_info_keys() :: [atom, ...]
  def beam_info_keys, do: @beam_info_keys

  # TODO: Remove together with Hologram.Compiler.resolve_beam_source/2 (see the
  # removal note there), consolidated_beam_removed?/1 and object_code/1 included.
  @doc """
  Returns the given module's BEAM code in a form accepted by BeamFile - the beam
  file path in the common case, or the module's object code found in the code
  path when the module was loaded from a consolidated protocol beam that no
  longer exists. Returns nil when the BEAM code can't be located at all.

  The fallback matters during dev-time recompiles: Phoenix's code reloader purges
  stale consolidated protocol beams while the modules stay loaded, with
  `:code.which/1` still pointing at the removed files. Only consolidated beam
  paths are checked for existence (with a raw stat), so the per-module cost on
  regular beams stays a substring scan without any syscall.
  """
  @spec beam_source(module) :: charlist | binary | nil
  def beam_source(module) do
    beam_path = :code.which(module)

    cond do
      not is_list(beam_path) ->
        object_code(module)

      consolidated_beam_removed?(beam_path) ->
        object_code(module)

      true ->
        beam_path
    end
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
  The module is not loaded to find out (see `has_function?/3`).

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
    alias?(term) and has_function?(term, :__info__, 1)
  end

  def elixir_module?(_term), do: false

  @doc """
  Like elixir_module?/1, but answered from the given IR PLT when it can be: the IR PLT holds IR
  for exactly the Elixir modules the compiler knows, so a module it holds is an Elixir module and
  its code path is not consulted. A term it does not hold (an Erlang module, an Elixir-named Erlang
  module, Kernel.SpecialForms, a name with no BEAM) is decided the elixir_module?/1 way. A nil PLT
  is the same as elixir_module?/1.
  """
  @spec elixir_module?(term, PLT.t() | nil) :: boolean
  def elixir_module?(term, nil), do: elixir_module?(term)

  def elixir_module?(term, ir_plt), do: PLT.member?(ir_plt, term) or elixir_module?(term)

  @doc """
  Returns true if the given term is an existing Erlang module, or false otherwise.

  An Erlang module is detected by the absence of the `__info__/1` function that the
  Elixir compiler injects into every Elixir module. This means Erlang modules that
  use Elixir-style naming for interop (e.g. the atom `Luerl`, whose source is the
  Erlang file `Elixir.Luerl.erl`) are correctly recognized as Erlang modules.
  The module is not loaded to find out (see `module?/1` and `has_function?/3`).

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
    module?(term) and not has_function?(term, :__info__, 1)
  end

  def erlang_module?(_term), do: false

  @doc """
  Like erlang_module?/1, but answered from the given IR PLT when it can be: a module the IR PLT
  holds is an Elixir module, so it is not an Erlang one and its code path is not consulted. A term
  it does not hold is decided the erlang_module?/1 way. A nil PLT is the same as erlang_module?/1.
  """
  @spec erlang_module?(term, PLT.t() | nil) :: boolean
  def erlang_module?(term, nil), do: erlang_module?(term)

  def erlang_module?(term, ir_plt), do: not PLT.member?(ir_plt, term) and erlang_module?(term)

  @doc """
  Returns true if the given term is an exception module, or false otherwise.
  """
  @spec exception?(any) :: boolean
  def exception?(term) do
    elixir_module?(term) && has_function?(term, :exception, 1) &&
      has_function?(term, :message, 1)
  end

  @doc """
  Returns true if module contains a public function with the given arity, otherwise false.

  A loaded module is asked directly. A module that is not loaded is answered from the export
  table of its BEAM on the code path, without loading it; a name with no BEAM has no functions.
  """
  @spec has_function?(module, atom, integer) :: boolean
  def has_function?(module, function, arity) do
    if :code.is_loaded(module) do
      function_exported?(module, function, arity)
    else
      case :code.which(module) do
        :non_existing -> false
        beam_path -> beam_exports_function?(beam_path, function, arity)
      end
    end
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
  Lists Elixir modules which are Hologram components and that belong to any of the OTP apps in the project.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/reflection/list_components_0/README.md
  """
  @spec list_components() :: list(module)
  def list_components do
    Enum.filter(list_elixir_modules(), &component?/1)
  end

  @doc """
  Lists the names that may be Elixir modules in the loaded OTP applications used by the project (except :hex),
  without checking any of them: the names come from each application's spec and, in dev and test, from the
  BEAM files in its ebin directory. Modules listed in @ignored_modules module attribute are left out.
  The project OTP application is included.
  """
  @spec list_candidate_modules() :: list(module)
  def list_candidate_modules do
    Application.ensure_loaded(otp_app())

    list_loaded_otp_apps()
    |> Kernel.--([:hex])
    |> list_candidate_modules()
  end

  @doc """
  Lists the names that may be Elixir modules in the given OTP apps, without checking any of them beyond
  the name: Erlang-named modules (no `Elixir.` prefix) and modules listed in @ignored_modules module
  attribute are left out.
  """
  @spec list_candidate_modules(list(atom)) :: list(module)
  def list_candidate_modules(apps) do
    apps
    |> Enum.reduce([], &include_app_elixir_modules/2)
    |> Enum.filter(&alias?/1)
    |> Kernel.--(@ignored_modules)
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
    |> list_candidate_modules()
    |> Enum.filter(&elixir_module?/1)
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
  Returns the application of every module listed by a loaded application, as a map. It is the
  lookup `Application.get_application/1` makes for one module at a time, which walks the module
  lists of every loaded application on each call, done once for all of them. A module listed by
  more than one application keeps the first one in `Application.loaded_applications/0` order.
  """
  @spec list_module_applications() :: %{module => atom}
  def list_module_applications do
    Enum.reduce(Application.loaded_applications(), %{}, fn {app, _description, _version}, acc ->
      app
      |> Application.spec(:modules)
      |> List.wrap()
      |> Enum.reduce(acc, &Map.put_new(&2, &1, app))
    end)
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
  A module exists when the VM holds it or has a BEAM for it on the code path; it is not loaded to find out.

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
    :code.is_loaded(term) != false or :code.which(term) != :non_existing
  end

  def module?(_term), do: false

  @doc """
  Returns the module info PLT dump file name.
  """
  @spec module_info_plt_dump_file_name() :: String.t()
  def module_info_plt_dump_file_name do
    @module_info_plt_dump_file_name
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
  Returns the absolute path of the project OTP application's source directory.

  In an umbrella this is the app's directory under the umbrella's apps path.
  Otherwise it is the active Mix project's directory (which Mix keeps as the
  current working directory).

  Requires a Mix project context (compilation or Mix tasks in any Mix env) -
  not callable inside a release, where Mix is unavailable.
  """
  @spec otp_app_dir() :: String.t()
  def otp_app_dir do
    case Mix.Project.apps_paths() do
      nil ->
        File.cwd!()

      apps_paths ->
        apps_paths
        |> Map.fetch!(otp_app())
        |> Path.expand()
    end
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
  @spec protocol_implementation(module) :: module | nil
  def protocol_implementation(module) do
    if has_function?(module, :__impl__, 1) do
      module.__impl__(:protocol)
    end
  end

  @doc """
  Returns true if the given module is a protocol implementation, or false otherwise.
  """
  @spec protocol_implementation?(module) :: boolean
  def protocol_implementation?(module) do
    has_function?(module, :__impl__, 1)
  end

  @doc """
  Returns the given module's source file path in the form stacktraces render:
  relative to the root of the code that compiled it. Project modules are
  relative to the project root, dep modules to their dep's root, and Elixir
  standard library modules to Elixir's own source root. When no source root
  is recognized, the file name alone is returned, so absolute build-machine
  paths are never exposed.
  """
  @spec relative_source_path(module) :: String.t()
  def relative_source_path(module) do
    relative_source_path(source_path(module), root_dir())
  end

  @doc """
  The path form of relative_source_path/1, for callers that have the source path and the project
  root already and need the relative path of many modules.
  """
  @spec relative_source_path(String.t(), String.t()) :: String.t()
  def relative_source_path(source_path, root_dir) do
    root_prefix = root_dir <> "/"
    deps_prefix = root_prefix <> "deps/"

    cond do
      String.starts_with?(source_path, deps_prefix) ->
        source_path
        |> String.replace_prefix(deps_prefix, "")
        |> String.split("/", parts: 2)
        |> List.last()

      String.starts_with?(source_path, root_prefix) ->
        String.replace_prefix(source_path, root_prefix, "")

      String.contains?(source_path, "/lib/elixir/") ->
        source_path
        |> String.split("/lib/elixir/", parts: 2)
        |> List.last()

      true ->
        Path.basename(source_path)
    end
  end

  @doc """
  Returns the absolute path of the workspace root - the top of the codebase
  checkout: the umbrella root in an umbrella project, the project root in a
  single-app project.

  Derived from `Mix.Project.deps_path/0`, so it assumes the deps dir sits
  directly under the workspace root (Mix's default in every layout). A custom
  external `:deps_path` or `MIX_DEPS_PATH` breaks this assumption and is not
  supported.

  Requires a Mix project context (compilation or Mix tasks in any Mix env) -
  not callable inside a release, where Mix is unavailable.
  """
  @spec root_dir() :: String.t()
  def root_dir do
    Path.dirname(Mix.Project.deps_path())
  end

  @doc """
  Returns the file path of the given module's source code.
  """
  @spec source_path(module()) :: String.t()
  def source_path(module) do
    # module_info(:compile) builds only the compile info, not the whole module info.
    to_string(module.module_info(:compile)[:source])
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

  # TODO: Remove when Hologram.Compiler.resolve_beam_source/2 goes (see the
  # removal note there), unless something else uses it by then - it exists to
  # keep the purged-consolidated-beam fallback off the single-app path.
  @doc """
  Returns true if the code runs in an umbrella project, or false otherwise.

  Detects the umbrella root through its apps path, a child app entered from the
  root through its parent project file, and a child app run directly through its
  in-umbrella deps. A child app that has no in-umbrella deps and is run directly
  is not detected.

  Requires a Mix project context (compilation or Mix tasks in any Mix env) -
  not callable inside a release, where Mix is unavailable.
  """
  @spec umbrella?() :: boolean
  def umbrella? do
    Mix.Project.apps_paths() != nil or
      Mix.Project.parent_umbrella_project_file() != nil or
      Enum.any?(Mix.Dep.cached(), & &1.opts[:in_umbrella])
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

  defp beam_mtime_and_size(beam_path) when is_list(beam_path) do
    %File.Stat{mtime: mtime, size: size} = File.stat!(beam_path, time: :posix)
    {mtime, size}
  end

  defp beam_mtime_and_size(_beam_binary), do: {nil, nil}

  # The export table in the beam is what the VM installs on load, so reading it
  # from the file answers the same question as function_exported?/3 would after
  # loading, without loading.
  # A beam that cannot be read (removed after :code.which/1 found it, or not a beam) exports
  # nothing, which is what Code.ensure_loaded/1 made of it before this read replaced it.
  defp beam_exports_function?(beam_path, function, arity) do
    case :beam_lib.chunks(beam_path, [:exports]) do
      {:ok, {_module, [{:exports, exports}]}} -> {function, arity} in exports
      {:error, :beam_lib, _reason} -> false
    end
  end

  defp compile_info_source(compile_info) do
    case Keyword.get(compile_info, :source) do
      nil -> nil
      source -> to_string(source)
    end
  end

  # TODO: Remove together with beam_source/1 (see the removal note there), which
  # is its only caller.
  defp consolidated_beam_removed?(beam_path) do
    if :string.find(beam_path, ~c"/consolidated/") == :nomatch do
      false
    else
      beam_path_str = to_string(beam_path)
      not File.exists?(beam_path_str, [:raw])
    end
  end

  # The function definitions from an Elixir debug info chunk, each {{name, arity}, kind, meta,
  # clauses} with clauses as {meta, args, guards, body} in expanded quoted form.
  # The chunk is bytes of a compiled BEAM on the code path, the same code the VM loads and runs,
  # so decoding its term is as trusted as loading the module.
  # sobelow_skip ["Misc.BinToTerm"]
  defp debug_info_definitions(dbgi_chunk) do
    case :erlang.binary_to_term(dbgi_chunk) do
      {:debug_info_v1, _backend, {:elixir_v1, %{definitions: definitions}, _specs}} -> definitions
      _other -> []
    end
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

  # TODO: Remove together with beam_source/1 (see the removal note there), which
  # is its only caller.
  # The value returned by the clause of the named function that takes exactly the given literal
  # arguments and has no guard, when that value is a literal; nil when there is no such clause or
  # the clause computes its value.
  defp literal_return(definitions, name, args) do
    with {_name_arity, _kind, _meta, clauses} <-
           List.keyfind(definitions, {name, length(args)}, 0),
         {_meta, _args, [], body} <- Enum.find(clauses, &match?({_meta, ^args, [], _body}, &1)),
         true <- Macro.quoted_literal?(body) do
      body
    else
      _no_literal -> nil
    end
  end

  defp object_code(module) do
    case :code.get_object_code(module) do
      {^module, binary, _beam_path} -> binary
      :error -> nil
    end
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
