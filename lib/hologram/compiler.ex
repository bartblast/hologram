defmodule Hologram.Compiler do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PathUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.StringUtils
  alias Hologram.Commons.SystemUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.QueryChains
  alias Hologram.Compiler.QueryExtractor
  alias Hologram.DB.Codec
  alias Hologram.DB.IndexPlan
  alias Hologram.Entity
  alias Hologram.Entity.Derived
  alias Hologram.Entity.Model
  alias Hologram.Entity.Validator
  alias Hologram.Job
  alias Hologram.Policy
  alias Hologram.Policy.Edges
  alias Hologram.Query.Shape
  alias Hologram.Query.Stage
  alias Hologram.Query.Window
  alias Hologram.Reflection
  alias Hologram.Runtime.Serializer
  alias Hologram.Sync.Fill
  alias Hologram.Sync.Frame

  # The declaration options a write is judged against, which is why they are the ones baked into
  # the client's model. What is missing from the list is missing on purpose: :values already
  # travels as the entry's enum values, :default as its defaults, and :server_only as the names a
  # client is told it may not have.
  @baked_constraint_opts [
    :format,
    :in,
    :length,
    :max,
    :max_length,
    :min,
    :min_length,
    :optional,
    :unique
  ]

  # The MFAs whose presence in a page's client code makes the page a permission checker - one
  # that reads grant rows in the browser. The grant verbs join can?/3 because each asks the gate
  # locally before it writes, and the role checks because they read the grant rows themselves.
  #
  # What being a checker buys a page: the grant type and the types its rules read among the page's
  # own types, filled first (first-render completeness), and, build-wide, that they sync at all.
  @permission_mfas [
    {Hologram.Auth, :can?, 3},
    {Hologram.Auth, :grant_role, 3},
    {Hologram.Auth, :has_role?, 2},
    {Hologram.Auth, :has_role?, 3},
    {Hologram.Auth, :revoke_role, 3}
  ]

  # The functions that run only on the server: the SQL surface, which reads the database through
  # the driver and hands back names for SQL text. A page whose client code reaches one would have
  # its server call tree transpiled into the bundle, down to the driver. The defaulted arities are
  # functions of their own, each a vertex a page can reach.
  @server_only_mfas [
    {Hologram.DB, :join_table_name, 2},
    {Hologram.DB, :schema_name, 0},
    {Hologram.DB, :sql, 1},
    {Hologram.DB, :sql, 2},
    {Hologram.DB, :sql, 3},
    {Hologram.DB, :sql!, 1},
    {Hologram.DB, :sql!, 2},
    {Hologram.DB, :sql!, 3},
    {Hologram.DB, :table_name, 1}
  ]

  # The calls an app spells an entity operation at, each with the position of the argument the
  # operation is read from.
  @operation_asks %{{Hologram.Auth, :can?, 3} => 1}

  # The modules the runtime entry file always imports, by class and file under the js dir.
  @runtime_imports [
    {"Bitstring", "bitstring.mjs"},
    {"ERTS", "erts.mjs"},
    {"Hologram", "hologram.mjs"},
    {"HologramBoxedError", "errors/boxed_error.mjs"},
    {"HologramInterpreterError", "errors/interpreter_error.mjs"},
    {"Interpreter", "interpreter.mjs"},
    {"MemoryStorage", "memory_storage.mjs"},
    {"PerformanceTimer", "performance_timer.mjs"},
    {"Type", "type.mjs"},
    {"Utils", "utils.mjs"}
  ]

  # The hand-written runtime modules a build ships only when it needs them, each with its file under
  # the js dir, its class, the handle the runtime reads it through and the Elixir modules whose
  # manually ported functions it defines. The handle is a public static of Hologram, null when the
  # module is not shipped, which the runtime calls through `?.`. The bundler only follows imports,
  # so a module no other runtime module imports is left out of a bundle whose entry file does not
  # import it either.
  @optional_runtime_subsystems [
    data_layer: %{
      class: "DataLayer",
      file: "data_layer.mjs",
      handle: "dataLayer",
      ported_modules: [
        Hologram.Auth,
        Hologram.DB,
        Hologram.Entity,
        Hologram.Job,
        Hologram.Query.Stage
      ]
    }
  ]

  @typedoc """
  The definition of every derived field of a build, keyed by entity type and field name, and the
  modules a walk followed calls into resolving them - besides the entity types, the modules whose
  edits can change a definition (see `resolve_derived_definitions/2`).
  """
  @type derived_definitions :: %{
          definitions: %{{module, atom} => Derived.definition()},
          read_modules: [module]
        }

  @typedoc """
  What the data layer keeps of a page's reach between compiles: whether the page's client code
  reaches a permission check (see `pages_checking_permissions/1`), the atoms its client code spells
  (see `build_kept_page_reach/4`), the modules it reaches, the struct types it names included,
  whether one of the components among them reads the session user from the context, and the
  queries its client code writes in one piece (see `Hologram.Compiler.QueryChains`).
  """
  @type kept_page_reach :: %{
          atoms: MapSet.t(atom),
          checks_permissions?: boolean,
          modules: MapSet.t(module),
          query_chains: [QueryChains.t()],
          reads_session_user?: boolean
        }

  @typedoc """
  What a page's client code reaches (see `list_reach_by_page/2`): the MFAs reachable from it, and
  the struct types it names, which carry no MFA of their own in the list.
  """
  @type page_reach :: %{mfas: [mfa], types: [module]}

  @typedoc """
  What the client's data layer is compiled with (see `build_sync_constants/2`).
  """
  @type sync_constants :: %{
          entity_types: MapSet.t(module),
          model_hash: String.t() | nil,
          page_types: %{module => list(module)},
          policy_hash: String.t() | nil,
          role_modules: list(module),
          synced_types: list(module),
          user_entity: module | nil
        }

  @type js_input_fingerprint ::
          {:digest, integer} | {:stat, non_neg_integer, non_neg_integer} | :fresh | :missing

  @typedoc """
  The literal refs a template declares, laid out the way the template renders them: in sequence,
  as alternatives only one of which renders (the clauses of the case an `{%if}` expands to, in
  clause order, so an `{%else}` comes first), or repeated (the body of a `{%for}`), with the
  components it renders in their places. A ref is its name and the number of parts after it,
  so `$ref="search"` is `{:ref, :search, 0}` and `$ref={:message, message.id}` is
  `{:ref, :message, 1}`.
  """
  @type template_refs ::
          {:seq, [template_refs]}
          | {:alt, [template_refs]}
          | {:loop, template_refs}
          | {:ref, atom, non_neg_integer}
          | {:component, module}

  # A chunk whose rendered definitions are smaller than this many bytes is folded into another
  # chunk (see fold_small_chunks/2), because shipping it as a file of its own costs more than it
  # holds. The measured part: a bundled chunk with no function is 403 bytes, and the response
  # headers of a static script are about 185 bytes, so a file costs about 590 bytes on the wire
  # before its first function. Rendered definitions minify to about 0.69 of their size (measured on
  # the chunks under 2 KB of Hologram's own test build), which makes 590 bytes on the wire about 850
  # rendered ones. The policy part: a request is counted as costing those bytes and nothing else.
  @chunk_fold_bound 850

  # The longest command line, in characters, that esbuild is started with for a group of chunks (see
  # bundle/2). The measured part: on Windows esbuild's launcher is a .cmd file, which is run
  # through cmd.exe (see Hologram.Commons.SystemUtils.cmd_cross_platform/3), and cmd.exe takes a
  # command line of 8191 characters at most. The launcher is what esbuild is started through there
  # when the binary of its platform package is not found (see esbuild_bin_path/1). The policy part:
  # the bound is applied on every OS, and whichever of the two is started, so that the chunks are
  # bundled the same way everywhere.
  @max_chunks_command_length 8_191

  @doc """
  Aggregates JS imports from all Elixir modules referenced by the given MFAs,
  skipping the modules whose bindings another bundle already registers. The module info PLT says which
  modules declare imports; with nil, every module is asked.
  Returns a map with:
  - `:imports` — unique imports with generated `$1`, `$2`, ... aliases for JS import statements
  - `:bindings` — per-module map of user alias to generated alias for `__bindings__` on module proxies
  """
  @spec aggregate_js_imports(list(mfa), PLT.t(), PLT.t() | nil, MapSet.t(module)) :: %{
          imports: list(%{from: String.t(), export: String.t(), alias: String.t()}),
          bindings: %{module => %{String.t() => String.t()}}
        }
  def aggregate_js_imports(mfas, ir_plt, module_info_plt, excluded_modules \\ MapSet.new()) do
    modules_with_imports =
      mfas
      |> list_js_import_modules(ir_plt, module_info_plt)
      |> Enum.reject(&MapSet.member?(excluded_modules, &1))

    unique_imports =
      modules_with_imports
      |> Enum.flat_map(fn module ->
        Enum.map(module.__js_imports__(), fn %{from: from, export: export} ->
          {from, export}
        end)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    alias_map =
      unique_imports
      |> Enum.with_index(1)
      |> Map.new(fn {{from, export}, index} -> {{from, export}, "$#{index}"} end)

    imports =
      Enum.map(unique_imports, fn {from, export} ->
        %{from: from, export: export, alias: alias_map[{from, export}]}
      end)

    bindings =
      Map.new(modules_with_imports, fn module ->
        module_bindings =
          Map.new(module.__js_imports__(), fn %{as: as, from: from, export: export} ->
            {as, alias_map[{from, export}]}
          end)

        {module, module_bindings}
      end)

    %{imports: imports, bindings: bindings}
  end

  @doc """
  Whether the application versions `build_app_versions/1` computes can differ from the ones an earlier
  compile computed, given that compile's module digests diff and the project's OTP application.

  They change in two ways. A module of an application appears in or disappears from the call graph,
  which takes an added or a removed module. Or an application's version changes, which for a
  dependency comes with its modules being recompiled, so they show up as edited. An edit to the
  project's own modules does neither, which is what an ordinary save is, so the kept versions stand.

  A module of no application, or of a sibling application in an umbrella, counts as not the
  project's: recomputing then is safe, and cheap next to being wrong.
  """
  @spec app_versions_changed?(map, atom) :: boolean
  def app_versions_changed?(module_digests_diff, otp_app) do
    module_digests_diff.added_modules != [] or module_digests_diff.removed_modules != [] or
      Enum.any?(
        module_digests_diff.edited_modules,
        &(Application.get_application(&1) != otp_app)
      )
  end

  @doc """
  Returns the version of each OTP application the given call graph reaches, keyed by application
  name and sorted by it.

  A stacktrace frame names the application its module belongs to and that application's version,
  the way the server renders one, and this is where the client reads the version from.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_app_versions_1/README.md
  """
  @spec build_app_versions(CallGraph.t()) :: keyword(String.t())
  def build_app_versions(call_graph) do
    call_graph
    |> CallGraph.vertices()
    |> Enum.map(&CallGraph.vertex_module/1)
    |> Enum.uniq()
    |> Enum.map(&Application.get_application/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(fn app -> {app, Application.spec(app, :vsn)} end)
    |> Enum.reject(fn {_app, vsn} -> is_nil(vsn) end)
    |> Enum.map(fn {app, vsn} -> {app, to_string(vsn)} end)
    |> Enum.sort()
  end

  @doc """
  Returns what every bundle depends on besides the modules it carries, apart from Hologram's own
  modules (see `build_bundle_inputs/2`): the client stack traces setting (bundles built with it on
  register module metadata and app versions), the mtime and size of each of Hologram's JavaScript
  sources under the `:js_dir` opt (esbuild copies them into every bundle) and the digest of
  `package.json` in the `:assets_dir` opt (which pins esbuild).

  The JavaScript sources are compared by mtime and size rather than by content: they belong to a
  dependency, which changes with an upgrade or a fetch, never within a second of a compile.
  """
  @spec build_bundle_inputs(T.opts()) :: %{
          client_stacktraces?: boolean,
          js_sources: [{String.t(), integer, non_neg_integer}],
          package_json_digest: binary
        }
  def build_bundle_inputs(opts) do
    %{
      client_stacktraces?: Hologram.client_stacktraces?(),
      js_sources: list_js_sources(opts[:js_dir]),
      package_json_digest: get_package_json_digest(opts[:assets_dir])
    }
  end

  @doc """
  Returns what every bundle depends on besides the modules it carries: the inputs that need no
  module (see `build_bundle_inputs/1`) and the digests of Hologram's own modules, the ones compiled
  from its lib dir, from the given module info PLT (the encoder and the transformer decide what a
  module encodes to). Two compiles whose inputs are equal make the same bundle from the same
  modules; the compile task rebuilds every bundle when the inputs differ from the ones its kept
  bundles were built with (see `Hologram.Compiler.Cache.forget_bundles/0`).
  """
  @spec build_bundle_inputs(PLT.t(), T.opts()) :: %{
          client_stacktraces?: boolean,
          hologram_modules: [{module, integer}],
          js_sources: [{String.t(), integer, non_neg_integer}],
          package_json_digest: binary
        }
  def build_bundle_inputs(module_info_plt, opts) do
    opts
    |> build_bundle_inputs()
    |> Map.put(:hologram_modules, list_hologram_module_digests(module_info_plt))
  end

  @doc """
  Returns every place the build spells an entity operation at, sorted by the calling function:
  each call of `Hologram.Auth.can?/3` found in the IR of the functions the call graph names as
  its callers, with the line of the call and the operation it names - a literal atom, a literal
  `{name, role}` tuple of atoms, a literal `{:update, field}` or `{:update, fields}` tuple, or
  `{:dynamic}` when the operation is computed and the build cannot read it - a tuple rather than an
  atom, so a name an allow line carries, `:dynamic` included, is never mistaken for it.

  Takes the UNSPLIT call graph - `can?/3` is hand-ported, so the runtime graph no longer holds the
  vertices whose callers this reads. The IR of a caller whose module the call graph's module info
  PLT holds is built into the IR PLT when it is missing (the compile task builds IR as it is read,
  see `build_missing_ir!/2`); a caller the IR PLT does not hold after that is skipped, as
  `validate_prop_usages/2` skips one.

  ## Options

    * `:modules` - the modules whose callers are read, for a compile that validated the rest
      already; every caller is read without it (default: none).
  """
  @spec operation_asks(CallGraph.t(), PLT.t(), T.opts()) ::
          list(%{mfa: mfa, line: integer | nil, operation: Entity.operation() | {:dynamic}})
  def operation_asks(call_graph, ir_plt, opts \\ []) do
    callers =
      @operation_asks
      |> Map.keys()
      |> Enum.map(fn {module, _function, _arity} -> module end)
      |> Enum.uniq()
      |> Enum.flat_map(&CallGraph.remote_incoming_edges(call_graph, &1))
      |> Enum.filter(fn {_from, to} -> Map.has_key?(@operation_asks, to) end)
      |> Enum.map(fn {from, _to} -> from end)
      |> Enum.filter(&match?({_module, _function, _arity}, &1))
      |> Enum.uniq()
      |> Enum.sort()
      |> scope_callers(opts[:modules])

    build_caller_ir!(callers, CallGraph.module_info_plt(call_graph), ir_plt)

    Enum.flat_map(callers, &caller_operation_asks(&1, ir_plt))
  end

  @doc """
  Returns the optional runtime subsystems: the hand-written runtime modules a build ships only when
  it needs them, by key, each with its file under the js dir, its class, the name of the
  `Hologram` static the runtime reads it through and the Elixir modules whose manually ported
  functions it defines.
  """
  @spec optional_runtime_subsystems() ::
          keyword(%{
            class: String.t(),
            file: String.t(),
            handle: String.t(),
            ported_modules: [module]
          })
  def optional_runtime_subsystems, do: @optional_runtime_subsystems

  @doc """
  Returns the pages that can check permissions on the CLIENT - the ones whose bundled code
  reaches one of `permission_mfas/0`: a permission check, which reads the rules and the server's
  verdicts, and the grant rows when the model has a grant store, a role check, which reads grant
  rows, or a grant verb, which asks the same gate locally before it writes - from what each page's
  client code reaches, as `list_reach_by_page/2` lists it.

  Takes the pages' reach on the call graph BEFORE manually ported MFAs are removed: every one of
  those MFAs is ported, so the graph the bundles are derived from no longer holds the vertex to ask
  about. Reachability is read through the same page walk the bundles use, so what syncs the grant
  rows is what actually ships - a `can?` reached only from command handlers, which run on the
  server, does not.

  Whether the app has a grant store at all is not asked here: a data model with no user entity
  type has none - the framework's grant entity joins the data model only with one - and what syncs
  the grant rows checks that where it reads this list (see `build_sync_constants/2`).
  """
  @spec pages_checking_permissions([{module, page_reach}]) :: list(module)
  def pages_checking_permissions(reach_by_page) do
    for {page_module, %{mfas: mfas}} <- reach_by_page,
        Enum.any?(mfas, &(&1 in @permission_mfas)) do
      page_module
    end
  end

  @doc """
  Returns true when some page checks permissions on the client, or false otherwise - from what the
  data layer keeps of each page's reach (see `build_kept_page_reach/4`).

  What it gates is build-wide: the related rows a checking query embeds beside the rows it returns
  (see `Hologram.Query.Window.embed/2`), the types sync sends for the rules to read, and the
  server's verdicts its rows carry. The rules and roles ship with every build that has a data model (see
  `build_sync_constants/2`).

  Whether the data model has a grant store is not asked: one with no user entity type has none,
  but its pages still check rules that name no role - an app with no logins calls `can?/3` for
  the anonymous session, and the browser answers it from the server's verdicts like any other. What
  needs the grant store, the grant type's rows, checks for it on its own (see
  `build_sync_constants/2`).
  """
  @spec permission_checking?(%{module => kept_page_reach}) :: boolean
  def permission_checking?(reach_by_page) do
    Enum.any?(reach_by_page, fn {_page_module, reach} -> reach.checks_permissions? end)
  end

  @doc false
  @spec permission_mfas() :: list(mfa)
  # Read by the test that pins every permission MFA as a manually ported one: a page reaching one
  # of these in client code would otherwise have the verb's server call tree transpiled into its
  # bundle, down to a NIF. The two lists live in two modules for two reasons, and this is the
  # invariant that ties them.
  def permission_mfas, do: @permission_mfas

  @doc false
  @spec server_only_mfas() :: list(mfa)
  # None of these may be manually ported: a ported function leaves the graph the reach is listed
  # on, so the check could never see a page reaching it.
  def server_only_mfas, do: @server_only_mfas

  @doc """
  Refuses a page whose client code reaches a function that runs only on the server, or returns :ok.

  Takes each page's reach as the compile task lists it. Command handlers and the initialization a
  page or component runs on the server are not part of a page's reach, so a call made there
  passes. A function that runs only on the server reached from client code would have its server
  call tree transpiled into the page's bundle, down to the database driver, and fail in the
  browser when the code runs - the build fails instead, naming the page and the function. The
  pages are judged in module order, so the same build always names the same page.

  Raises Hologram.CompileError.
  """
  @spec validate_server_only_mfas!([{module, page_reach}]) :: :ok
  def validate_server_only_mfas!(reach_by_page) do
    reach_by_page
    |> Enum.sort_by(fn {page_module, _reach} -> page_module end)
    |> Enum.each(fn {page_module, %{mfas: mfas}} ->
      case Enum.find(mfas, &(&1 in @server_only_mfas)) do
        nil -> :ok
        mfa -> raise Hologram.CompileError, message: server_only_mfa_message(page_module, mfa)
      end
    end)
  end

  @doc """
  Builds the call graph of all modules in the project.
  """
  @spec build_call_graph :: CallGraph.t()
  def build_call_graph do
    build_call_graph(build_ir_plt())
  end

  @doc """
  Builds the call graph of all modules in the given IR PLT, reading its module facts from a module info
  PLT built on the spot. That PLT stays up for as long as the call graph is used (it is linked to the
  calling process, like every PLT); the compile task builds its own instead and passes it to
  `build_call_graph/2`.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_call_graph_1/README.md
  """
  @spec build_call_graph(PLT.t()) :: CallGraph.t()
  def build_call_graph(ir_plt) do
    build_call_graph(ir_plt, build_module_info_plt!(PLT.start(), nil))
  end

  @doc """
  Builds the call graph of all modules in the given IR PLT with the given module info PLT as its module facts.
  """
  @spec build_call_graph(PLT.t(), PLT.t()) :: CallGraph.t()
  def build_call_graph(ir_plt, module_info_plt) do
    call_graph = CallGraph.start(module_info_plt: module_info_plt)

    ir_plt
    |> PLT.get_all()
    |> TaskUtils.map_concurrently(fn {_module, ir} -> CallGraph.build(call_graph, ir) end)

    CallGraph.add_non_discoverable_edges(call_graph)
  end

  @doc """
  Builds JavaScript code for a chunk: a script holding the given MFAs, which are the code a set of
  struct types shares, of their struct functions and their protocol implementations (see
  `group_mfas_by_signature/1`).

  The script does not define its functions when it runs: it leaves them, with its own digest, for
  the runtime to define, and announces itself with a `hologram:scriptLoaded` event (see
  `assets/js/script_registry.mjs`). A chunk can run before the runtime does, and neither needs to
  know the other's name: the digest is read from the file name of the script element running it
  (see `Hologram.Router.Helpers.chunk_bundle_path/1`), since a file cannot hold the hash of its
  own content.

  It carries no timing code, unlike the page and runtime scripts: a document can load many chunks,
  and the bundler would put a copy of the timer in each.

  Takes the options `build_page_js/5` takes.
  """
  @spec build_chunk_js([mfa], PLT.t(), PLT.t(), MapSet.t(mfa), T.opts()) :: String.t()
  def build_chunk_js(mfas, ir_plt, encode_plt, async_mfas, opts) do
    %{defs: defs, import_statements: import_statements} =
      render_script_parts(mfas, ir_plt, encode_plt, async_mfas, opts)

    """
    "use strict";#{import_statements}

    #{render_script_announcement(defs)}\
    """
  end

  @doc """
  Grows the call graph until it holds the code of every chunk (see `CallGraph.build_chunk_reach/4`),
  building the IR of each module the walk asks for into the IR PLT first, and returns what that
  walk returns: the chunks' entry vertices by type, the client protocols and the modules built.
  The walk asks only for modules the graph's module info PLT holds, so each has a beam to build
  IR from.
  """
  @spec build_chunk_reach!(CallGraph.t(), PLT.t(), [module], [module]) :: %{
          built_modules: [module],
          client_protocols: MapSet.t(module),
          entries_by_type: %{module => [CallGraph.vertex()]}
        }
  def build_chunk_reach!(call_graph, ir_plt, pages, components) do
    CallGraph.build_chunk_reach(
      call_graph,
      pages,
      components,
      &build_graph_modules!(call_graph, ir_plt, &1)
    )
  end

  @doc """
  Builds the chunk registry PLT, which says which chunks to load, and returns it with the path of
  its dump in the `:build_dir` opt:

    * `{:type, type}` - the digests of the chunks a struct type needs, sorted: every chunk whose
      signature holds the type. A type no chunk's signature holds has no entry.

    * `{:page, page}` - the digests of the chunks a page preloads, sorted: the ones its own types
      need and the ones the given runtime types need. A page that preloads none has an empty list.

  A chunk's digest names its file (see `Hologram.Router.Helpers.chunk_bundle_path/1`).

  Takes the chunks' bundle infos by signature (see `bundle/4`), each page's types (see
  `CallGraph.list_page_chunk_types/4`) and the struct types the runtime's code names (see
  `CallGraph.runtime_analysis/1`).
  """
  @spec build_chunk_registry_plt(
          %{MapSet.t(module) => map},
          %{module => [module]},
          Enumerable.t(module),
          T.opts()
        ) :: {PLT.t(), T.file_path()}
  def build_chunk_registry_plt(
        bundle_infos_by_signature,
        chunk_types_by_page,
        runtime_types,
        opts
      ) do
    digests_by_type =
      bundle_infos_by_signature
      |> Enum.flat_map(fn {signature, bundle_info} ->
        Enum.map(signature, &{&1, bundle_info.digest})
      end)
      |> Enum.sort()
      |> Enum.group_by(fn {type, _digest} -> type end, fn {_type, digest} -> digest end)

    type_items = Enum.map(digests_by_type, fn {type, digests} -> {{:type, type}, digests} end)

    page_items =
      Enum.map(chunk_types_by_page, fn {page, types} ->
        digests =
          types
          |> Enum.concat(runtime_types)
          |> Enum.flat_map(&Map.get(digests_by_type, &1, []))
          |> Enum.uniq()
          |> Enum.sort()

        {{:page, page}, digests}
      end)

    chunk_registry_plt = PLT.start(items: type_items ++ page_items, supervisor: opts[:supervisor])

    chunk_registry_plt_dump_path =
      Path.join([opts[:build_dir], Reflection.chunk_registry_plt_dump_file_name()])

    {chunk_registry_plt, chunk_registry_plt_dump_path}
  end

  @doc """
  Returns the access needs of the statements the server runs that the build knows of (see
  `Hologram.DB.IndexPlan.needs/3`), given the shapes of the queries the code writes (see
  `list_query_shapes/1`):

    * each synced type's fill, policied,
    * each entity type bare, as `DB.read/1` reads it, raw and policied,
    * each query chain the code writes, raw - recorded wherever it is written, a derived field's
      body included, so a chain only the browser reads can add an index no statement uses, which
      costs writes where missing one would cost a scan. A shape the stages refuse when replayed,
      or one on a type the mapping doesn't hold, gives nothing.

  Policied is under the read rules of a signed-in session and of an anonymous one. The read rules
  give the needs a policied read of any shape shares, so a query the code writes - raw, policied
  as `DB.read/1` reads it, or as a derived field's render reads it - needs no more than its raw
  needs and its type's bare ones. A query built at run time, which records no shape, has its
  type's bare needs.
  """
  @spec build_index_needs(list(module), list(Shape.t()), %{module => %{atom => any}}) ::
          list(IndexPlan.need())
  def build_index_needs(synced_types, query_shapes, mapping) do
    fill_terms = Enum.map(synced_types, &Fill.term(&1, synced_types))

    bare_terms =
      mapping
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map(&Stage.normalize/1)

    server_terms =
      for shape <- query_shapes,
          {:ok, term} <- [Shape.replay(shape)],
          Map.has_key?(mapping, term.entity),
          do: term

    raw_needs = Enum.flat_map(bare_terms ++ server_terms, &IndexPlan.needs(&1, mapping))
    policied_needs = Enum.flat_map(fill_terms ++ bare_terms, &policied_needs(&1, mapping))

    Enum.uniq(raw_needs ++ policied_needs)
  end

  @doc """
  Builds the index needs PLT, whose one item is the access needs the build derived (see
  `build_index_needs/3`), and returns it with the path to dump it at.
  """
  @spec build_index_needs_plt(list(IndexPlan.need()), T.opts()) :: {PLT.t(), T.file_path()}
  def build_index_needs_plt(index_needs, opts) do
    plt = PLT.start(items: [needs: index_needs], supervisor: opts[:supervisor])
    dump_path = Path.join([opts[:build_dir], Reflection.index_needs_plt_dump_file_name()])

    {plt, dump_path}
  end

  @doc """
  Builds IR persistent lookup table (PLT) of all modules in the project.
  Pass `modules:` to build IR for exactly those modules instead of listing them; the compile task passes the
  module info PLT's keys.
  Pass `plt:` to fill an existing PLT instead of starting one; the compile task passes the PLT it keeps between
  compiles.
  A module with a consolidated beam on the code path is read from it, whatever beam the VM loaded the
  module from.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_ir_plt_0/README.md
  """
  @spec build_ir_plt(T.opts()) :: PLT.t()
  # credo:disable-for-lines:27 Credo.Check.Refactor.Nesting
  # The above Credo check is disabled because the function is optimised this way
  def build_ir_plt(opts \\ []) do
    ir_plt = opts[:plt] || PLT.start(opts)

    modules = opts[:modules] || Reflection.list_elixir_modules()

    # Processing modules in chunks of 2 improves performance by ~7%
    # (determined experimentally)
    chunk_size = 2

    consolidated_beams = Reflection.list_consolidated_beams()

    # TODO: Remove this flag and the argument it feeds to resolve_beam_source/3
    # when resolve_beam_source/2 goes (see the removal note there).
    umbrella? = Reflection.umbrella?()

    modules
    |> Enum.chunk_every(chunk_size)
    |> TaskUtils.map_concurrently(fn module_chunk ->
      Enum.each(module_chunk, fn module ->
        beam_source = resolve_beam_source(module, consolidated_beams, umbrella?)

        if beam_source do
          ir = IR.for_module(module, beam_source)
          PLT.put(ir_plt, module, ir)
        end
      end)
    end)

    ir_plt
  end

  @doc """
  Folds what each page's client code reaches, as `list_reach_by_page/2` lists it, into what the data
  layer keeps of it (see `kept_page_reach`), keyed by page module. A page reads the session user when
  one of the components among the reached modules, told by the given module info PLT, or the page
  itself declares a prop taking it from the context (`from_context: {Hologram, :user}`).
  The pages checking permissions are given as `pages_checking_permissions/1` lists them, from the
  pages' reach on the call graph BEFORE manually ported MFAs are removed.

  The atoms are every atom literal in the IR of the functions a page's client code reaches, read
  from the given IR PLT, which the modules it lacks are built into first. They name what the page's
  code reads of the data model without a walk of it: a relationship it includes or a path goes
  through, a derived field it reads, a field a template reads off a row (see
  `build_sync_constants/2`). Every function is read but Elixir's and Hologram's, which never name
  the app's model, and the generated functions of entity types and Ecto schemas
  (`__relationships__/0`, `__schema__/1` and the like), which name every relationship and field
  their module declares. Kept whole, not narrowed to the names the model declares now: a model
  change derives again without listing the pages again. A function many pages reach is read once.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_kept_page_reach_4/README.md
  """
  @spec build_kept_page_reach([{module, page_reach}], [module], PLT.t(), PLT.t()) :: %{
          module => kept_page_reach
        }
  def build_kept_page_reach(reach_by_page, permission_checking_pages, module_info_plt, ir_plt) do
    checking_pages = MapSet.new(permission_checking_pages)
    read_by_mfa = read_by_mfa(reach_by_page, module_info_plt, ir_plt)

    Map.new(reach_by_page, fn {page_module, reach} ->
      modules = list_reached_modules(reach)

      components =
        modules
        |> reached_components(module_info_plt)
        |> Enum.concat([page_module])

      reads = Enum.map(reach.mfas, &Map.get(read_by_mfa, &1, %{atoms: MapSet.new(), chains: []}))

      atoms = Enum.reduce(reads, MapSet.new(), &MapSet.union(&2, &1.atoms))

      query_chains =
        reads
        |> Enum.flat_map(& &1.chains)
        |> Enum.uniq()

      kept_reach = %{
        atoms: atoms,
        checks_permissions?: MapSet.member?(checking_pages, page_module),
        modules: MapSet.new(modules),
        query_chains: query_chains,
        reads_session_user?: Enum.any?(components, &reads_session_user?/1)
      }

      {page_module, kept_reach}
    end)
  end

  @doc """
  Raises Hologram.CompileError when a query a page's client code writes in one piece is one no
  browser may run (see `Hologram.Compiler.QueryChains.validate!/2`), from what the data layer keeps
  of each page's reach (see `build_kept_page_reach/4`). Every page's queries are checked, kept ones
  included, since what a query may ask for moves with the data model; a query many pages reach is
  checked once.
  """
  @spec validate_query_chains!(%{module => kept_page_reach}, PLT.t() | nil) :: :ok
  def validate_query_chains!(reach_by_page, module_info_plt) do
    reach_by_page
    |> Enum.flat_map(fn {_page_module, reach} -> reach.query_chains end)
    |> Enum.uniq()
    |> Enum.sort_by(fn chain -> chain.mfa end)
    |> Enum.each(&QueryChains.validate!(&1, module_info_plt))
  end

  @doc """
  Builds the IR of the given modules that the IR PLT does not hold yet, and returns the PLT. The compile task
  calls it for the modules it is about to read, once the call graph says which they are. When the PLT holds
  every given module, it returns the PLT without reading the code path.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_missing_ir!_2/README.md
  """
  @spec build_missing_ir!(PLT.t(), [module]) :: PLT.t()
  def build_missing_ir!(ir_plt, modules) do
    # Asked before building: build_ir_plt/1 scans the code path for consolidated beams first, which
    # costs more than reading a module's IR from the PLT.
    case Enum.reject(modules, &PLT.member?(ir_plt, &1)) do
      [] -> ir_plt
      missing_modules -> build_ir_plt(plt: ir_plt, modules: missing_modules)
    end
  end

  @doc """
  Builds a persistent lookup table (PLT) holding, for every Elixir module in the project, the info the compiler
  needs before building IR: see `Hologram.Reflection.beam_info/1` for the entry shape.

  Each module's BEAM is read once. A module whose entry in `old_plt` has the same mtime and size as its BEAM
  now, and whose BEAM was last written at least a second before `dumped_at` (the mtime of the dump `old_plt`
  was loaded from, in posix seconds), reuses that entry without reading the BEAM. Pass nil as `dumped_at` to
  read every BEAM. A module with a consolidated beam on the code path is read from it, whatever beam the VM
  loaded the module from.
  """
  @spec build_module_info_plt!(PLT.t(), non_neg_integer | nil, T.opts()) :: PLT.t()
  def build_module_info_plt!(old_plt, dumped_at, opts \\ []) do
    new_plt = PLT.start(opts)
    consolidated_beams = Reflection.list_consolidated_beams()

    # TODO: Remove this flag and the argument it feeds to
    # rebuild_module_info_plt_entry!/6 when resolve_beam_source/2 goes (see
    # the removal note there).
    umbrella? = Reflection.umbrella?()

    TaskUtils.map_concurrently(
      Reflection.list_candidate_modules(),
      &rebuild_module_info_plt_entry!(
        &1,
        old_plt,
        dumped_at,
        new_plt,
        consolidated_beams,
        umbrella?
      )
    )

    new_plt
  end

  @doc """
  Returns the stack trace metadata of every module the given module info PLT holds a source path
  for: its application and its source file relative to the root of the code that compiled it, the
  form `Hologram.Compiler.Encoder.encode_module_metadata_registration/2` renders. Computed once
  per compile, so the bundles look each module up instead of asking the VM about it per bundle.
  """
  @spec build_module_metadata(PLT.t()) :: %{module => %{app: atom | nil, file: String.t()}}
  def build_module_metadata(module_info_plt) do
    apps = Reflection.list_module_applications()
    root_dir = Reflection.root_dir()

    for {module, %{source_path: source_path}} when is_binary(source_path) <-
          PLT.get_all(module_info_plt),
        into: %{} do
      {module, %{app: apps[module], file: Reflection.relative_source_path(source_path, root_dir)}}
    end
  end

  @doc """
  Builds page digest PLT, where the keys represent page modules,
  and the values are the digests of their JavaScript bundles (esbuild's content hashes).
  """
  @spec build_page_digest_plt(list(map), T.opts()) :: {PLT.t(), T.file_path()}
  def build_page_digest_plt(bundle_info, opts) do
    page_digest_plt_items =
      for %{bundle_name: "page", entry_name: page_module, digest: digest} <- bundle_info,
          do: {page_module, digest}

    page_digest_plt = PLT.start(items: page_digest_plt_items, supervisor: opts[:supervisor])

    page_digest_plt_dump_path =
      Path.join([opts[:build_dir], Reflection.page_digest_plt_dump_file_name()])

    {page_digest_plt, page_digest_plt_dump_path}
  end

  @doc """
  Builds the page types PLT, where the keys are page modules and the values are the synced types a
  session on each page fills first (see the `:page_types` of `build_sync_constants/2`), and returns
  it with the path to dump it at.
  """
  @spec build_page_types_plt(%{module => list(module)}, T.opts()) :: {PLT.t(), T.file_path()}
  def build_page_types_plt(page_types, opts) do
    plt = PLT.start(items: Map.to_list(page_types), supervisor: opts[:supervisor])
    dump_path = Path.join([opts[:build_dir], Reflection.page_types_plt_dump_file_name()])

    {plt, dump_path}
  end

  @doc """
  Builds the queries PLT, whose items are what a running app reads of the data layer - the derived
  fields' definitions, the entity types sync sends rows of, and whether a page checks permissions
  on the client - and returns it with the path to dump it at.
  """
  @spec build_queries_plt(%{atom => any}, T.opts()) :: {PLT.t(), T.file_path()}
  def build_queries_plt(queries, opts) do
    plt = PLT.start(items: Map.to_list(queries), supervisor: opts[:supervisor])
    dump_path = Path.join([opts[:build_dir], Reflection.queries_plt_dump_file_name()])

    {plt, dump_path}
  end

  @doc """
  Builds JavaScript code for the given Hologram page.

  The page's reachable MFAs are given (see `CallGraph.list_page_mfas/5`), so that a caller building
  many pages can encode their functions first with `encode_reachable_functions/5` and render every
  page from the encode PLT.

  The script announces itself the way a chunk does (see `build_chunk_js/5`): it leaves its
  function definitions, with its own digest, for the runtime to define. Its digest is in its file
  name too (see `Hologram.Router.Helpers.page_bundle_path/2`).

  ## Options

    * `:js_dir` - the directory of Hologram's JavaScript sources, which the page script imports
      from (required).
    * `:module_info_plt` - the module info PLT the bundled modules are classified from; without it
      each module is asked, which reads the BEAM of a module that is not loaded (default: none).
    * `:module_metadata` - the stack trace metadata of modules, as `build_module_metadata/1` returns
      it; the modules it does not hold are read from the loaded modules (default: none).
    * `:ref_names` - the page module and the literal refs it renders with its layout, as names with
      their numbers of parts, as `check_template_refs/2` returns them, which the script puts in
      the runtime's element ref registry (default: none).
    * `:runtime_js_binding_modules` - modules whose JS imports are skipped when the imports are
      aggregated, because the runtime script, which every page loads, already registers their
      bindings (default: none).

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_page_js_5/README.md
  """
  @spec build_page_js([mfa], PLT.t(), PLT.t(), MapSet.t(mfa), T.opts()) :: String.t()
  def build_page_js(mfas, ir_plt, encode_plt, async_mfas, opts) do
    js_dir = Keyword.fetch!(opts, :js_dir)

    %{defs: defs, import_statements: import_statements} =
      render_script_parts(mfas, ir_plt, encode_plt, async_mfas, opts)

    """
    "use strict";

    import PerformanceTimer from "#{js_dir}/performance_timer.mjs";#{import_statements}

    const startTime = performance.now();

    #{render_script_announcement(defs <> render_page_ref_names(opts[:ref_names]))}

    console.debug("Hologram: page script executed in", PerformanceTimer.diff(startTime));\
    """
  end

  @doc """
  Grows the call graph until it holds every module the pages, the runtime and the broadcast callers
  reach (see `CallGraph.build_reach/3`), building the IR of each module the walk asks for into the IR
  PLT first, and returns the modules built. The walk asks only for modules the graph's module info
  PLT holds, so each has a beam to build IR from.
  """
  @spec build_reach!(CallGraph.t(), PLT.t(), map) :: [module]
  def build_reach!(call_graph, ir_plt, graph_diff) do
    CallGraph.build_reach(call_graph, graph_diff, &build_graph_modules!(call_graph, ir_plt, &1))
  end

  @doc """
  Builds Hologram runtime JavaScript source code. The given statement sets the client's data layer
  constants (see `build_sync_constants_js/1`); it is taken rendered, since the compile task keeps
  it with the runtime bundle it built.

  The script starts the runtime once it has run. It waits for no page script: the runtime mounts
  the page when the scripts the page needs have announced themselves (see
  `assets/js/script_registry.mjs`).

  ## Options

    * `:js_dir` - the directory of Hologram's JavaScript sources, which the runtime script imports
      from (required).
    * `:module_info_plt` - the module info PLT the bundled modules are classified from; without it
      each module is asked, which reads the BEAM of a module that is not loaded (default: none).
    * `:module_metadata` - the stack trace metadata of modules, as `build_module_metadata/1` returns
      it; the modules it does not hold are read from the loaded modules (default: none).
    * `:subsystems` - the keys of the optional runtime subsystems the build ships (see
      `optional_runtime_subsystems/0`), each rendered as an import, a handle the runtime reads it
      through and the clause heads of the functions it ports (required). Raises `ArgumentError` for
      a key that is not an optional runtime subsystem.
  """
  @spec build_runtime_js(
          list(mfa),
          PLT.t(),
          PLT.t(),
          MapSet.t(mfa),
          keyword(String.t()),
          String.t(),
          T.opts()
        ) :: String.t()
  def build_runtime_js(
        runtime_mfas,
        ir_plt,
        encode_plt,
        async_mfas,
        app_versions,
        sync_constants_js,
        opts
      ) do
    js_dir = Keyword.fetch!(opts, :js_dir)

    subsystems =
      opts
      |> Keyword.fetch!(:subsystems)
      |> Enum.map(&fetch_optional_runtime_subsystem!/1)

    runtime_import_statements =
      subsystems
      |> Enum.map(&{&1.class, &1.file})
      |> Enum.concat(@runtime_imports)
      |> Enum.sort()
      |> Enum.map_join("\n", fn {class, file} ->
        ~s/import #{class} from "#{js_dir}\/#{file}";/
      end)

    %{imports: imports, bindings: bindings} =
      aggregate_js_imports(runtime_mfas, ir_plt, opts[:module_info_plt])

    import_statements =
      imports
      |> render_js_import_statements()
      |> render_block()

    # A module bundled into the runtime script registers its JS bindings here, because
    # remove_runtime_mfas!/2 takes its MFAs out of every page graph, so no page bundle
    # can register them.
    js_bindings_registration_call =
      bindings
      |> render_js_bindings_registration_call()
      |> render_block()

    erlang_function_defs =
      runtime_mfas
      |> render_erlang_function_defs(ir_plt, Path.join(js_dir, "erlang"))
      |> render_block()

    elixir_function_defs =
      runtime_mfas
      |> render_elixir_function_defs(ir_plt, encode_plt, async_mfas, opts[:module_info_plt])
      |> render_block()

    module_metadata_registration =
      runtime_mfas
      |> render_module_metadata_registration(ir_plt, opts[:module_metadata])
      |> render_block()

    manually_ported_clause_heads =
      ir_plt
      |> render_manually_ported_clause_heads(subsystems)
      |> render_block()

    subsystem_handles =
      subsystems
      |> Enum.map_join("\n", &"Hologram.#{&1.handle} = #{&1.class};")
      |> render_block()

    """
    "use strict";

    #{runtime_import_statements}#{import_statements}

    const startTime = PerformanceTimer.start();

    globalThis.Hologram.config = #{client_config()};

    #{sync_constants_js}

    ERTS.appVersions = #{render_app_versions(app_versions)};#{module_metadata_registration}#{js_bindings_registration_call}#{erlang_function_defs}#{elixir_function_defs}#{manually_ported_clause_heads}#{subsystem_handles}

    Hologram.run();

    console.debug("Hologram: runtime script executed in", PerformanceTimer.diff(startTime));\
    """
  end

  @doc """
  Bundles multiple entry files at once, and returns what `bundle/4` returns for each, in the given
  order. An entry is given as `{entry_name, entry_file_path, bundle_name}`, the entry name `nil` for
  a bundle name with a single entry.

  An entry of the `"chunk"` bundle name is bundled with other chunks in one esbuild process (see
  `bundle_chunks/2`), every other entry in a process of its own (see `bundle/4`). An app has a
  chunk per struct type or more, most of them a few hundred bytes, and starting esbuild takes
  longer than bundling such a file. A page is the opposite case: bundling it is the work, and one
  process for all the pages would hold every output and source map in memory at once. The chunks
  are split into as few groups as the command line allows, at most 8191 characters each, which is
  the limit of Windows' `cmd.exe`.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/bundle_2/README.md
  """
  @spec bundle(list({module | String.t() | nil, T.file_path(), String.t()}), T.opts()) ::
          list(map)
  def bundle(entry_files_info, opts) do
    {chunk_entries_info, other_entries_info} =
      Enum.split_with(entry_files_info, fn {_entry_name, _entry_file_path, bundle_name} ->
        bundle_name == "chunk"
      end)

    chunk_jobs =
      chunk_entries_info
      |> Enum.map(fn {entry_name, entry_file_path, _bundle_name} ->
        {entry_name, entry_file_path}
      end)
      |> group_chunk_entries(opts)
      |> Enum.map(&{:chunks, &1})

    entry_jobs = Enum.map(other_entries_info, &{:entry, &1})

    bundle_info_by_entry =
      entry_jobs
      |> Enum.concat(chunk_jobs)
      |> TaskUtils.map_concurrently(fn
        {:chunks, entries} ->
          bundle_chunks(entries, opts)

        {:entry, {entry_name, entry_file_path, bundle_name}} ->
          [bundle(entry_name, entry_file_path, bundle_name, opts)]
      end)
      |> Enum.concat()
      |> Map.new(&{{&1.bundle_name, &1.entry_name}, &1})

    Enum.map(entry_files_info, fn {entry_name, _entry_file_path, bundle_name} ->
      Map.fetch!(bundle_info_by_entry, {bundle_name, entry_name})
    end)
  end

  @doc """
  Bundles the given entry file with esbuild, which names the output `<bundle_name>-<hash>.js` and
  its source map `<bundle_name>-<hash>.js.map` by the content hash. An entry name that is a module
  goes between the bundle name and the hash, written without its `Elixir.` prefix: the page
  bundles share a bundle name, and the name says which page a file is for. An entry name that is a
  string names the build only, its output dir under the `:tmp_dir` opt, which keeps the entries of
  a shared bundle name apart while they are bundled at once: the chunks' files are named by the
  bundle name and the hash alone, since no two chunks have the same content. The returned digest is
  the hash. Next to the bundle goes its gzip copy, `<bundle_name>-<hash>.js.gz` (see
  `gzip_path/1`).

  A bundle bigger than the `:max_bundle_size` config value fails the build, unless its bundle name
  is `"chunk"`: a chunk is downloaded only once a struct of one of its types is on the client, and
  an app has chunks for types it never sends there.

  The returned `js_inputs` are the files esbuild read for the bundle besides the entry file,
  Hologram's own sources under the `:js_dir` opt and the packages under the `:node_modules_path`
  opt, with their fingerprints (see `fingerprint_js_inputs/2`), taken against the time esbuild
  started: a bundle inlines them, and a kept bundle whose files moved must be built again.
  """
  @spec bundle(module | String.t() | nil, T.file_path(), String.t(), T.opts()) :: map
  def bundle(entry_name, entry_file_path, bundle_name, opts) do
    # esbuild names the bundle and its source map by their content hash and writes the source map
    # comment to match, so the source map is never read back and neither file is rewritten. Each
    # bundle gets its own output dir: the name is only known once esbuild has run, so the dir is
    # listed for it, and it is recreated so that a bundle left there by a run that failed the size
    # check is not listed too.
    output_name = bundle_output_name(bundle_name, entry_name)
    output_dir_name = bundle_output_dir_name(bundle_name, entry_name)
    output_dir = Path.join(opts[:tmp_dir], "#{output_dir_name}.output")
    FileUtils.recreate_dir(output_dir)
    metafile_path = Path.join(output_dir, "meta.json")

    started_at =
      run_esbuild!(
        ["#{output_name}=#{entry_file_path}"],
        output_dir,
        "entry file: #{entry_file_path}",
        opts
      )

    [bundle_file_name] =
      output_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".js"))

    output_bundle_path = Path.join(output_dir, bundle_file_name)

    maybe_ensure_bundle_within_size_limit!(bundle_name, output_name, output_bundle_path)

    {static_bundle_path, static_source_map_path} =
      move_bundle_to_static_dir(output_dir, bundle_file_name, opts)

    # Read once and removed, so that the output dir is left empty, as the bundle, its gzip copy and
    # its source map leave it.
    js_inputs =
      metafile_path
      |> read_esbuild_metafile()
      |> Map.fetch!("inputs")
      |> Map.keys()
      |> list_bundle_js_inputs(started_at, opts)

    File.rm!(metafile_path)

    %{
      bundle_name: bundle_name,
      digest: bundle_digest(bundle_file_name, output_name),
      entry_name: entry_name,
      js_inputs: js_inputs,
      static_bundle_path: static_bundle_path,
      static_source_map_path: static_source_map_path
    }
  end

  @doc """
  Bundles the given chunk entry files, each given as `{entry_name, entry_file_path}`, in one esbuild
  process, and returns what `bundle/4` returns for each, in the given order. Each entry gets a
  bundle of its own, named `chunk-<hash>.js` by its content hash like any chunk's (see `bundle/4`):
  the process is shared, the output is not. The files are written to one output dir under the
  `:tmp_dir` opt, named by the first entry's name, which keeps the groups bundled at once apart.

  The entry files must differ in their file names: esbuild reports which output it built from which
  entry file, and names the entry file by its real path, which is not the given one when a dir on
  the way is a symbolic link (a dependency's priv dir in the build dir can be one).
  """
  @spec bundle_chunks(list({String.t(), T.file_path()}), T.opts()) :: list(map)
  def bundle_chunks(entries, opts)

  def bundle_chunks([], _opts), do: []

  def bundle_chunks([{first_entry_name, _entry_file_path} | _rest] = entries, opts) do
    # Recreated for the reason bundle/4 recreates its output dir.
    output_dir = chunks_output_dir(first_entry_name, opts)
    FileUtils.recreate_dir(output_dir)
    metafile_path = Path.join(output_dir, "meta.json")

    started_at =
      run_esbuild!(chunk_entry_args(entries), output_dir, "the chunk entry files", opts)

    %{"inputs" => inputs, "outputs" => outputs} = read_esbuild_metafile(metafile_path)

    # Each bundle with the files esbuild read for it, by the file name of the entry it was built
    # from. A source map is among the outputs too, with no entry point.
    outputs_by_entry_file_name =
      for {output_path, %{"entryPoint" => entry_point}} <- outputs, into: %{} do
        input_paths = collect_esbuild_input_paths([entry_point], inputs, [])

        {Path.basename(entry_point), {Path.basename(output_path), input_paths}}
      end

    File.rm!(metafile_path)

    Enum.map(entries, fn {entry_name, entry_file_path} ->
      {bundle_file_name, input_paths} =
        Map.fetch!(outputs_by_entry_file_name, Path.basename(entry_file_path))

      {static_bundle_path, static_source_map_path} =
        move_bundle_to_static_dir(output_dir, bundle_file_name, opts)

      %{
        bundle_name: "chunk",
        digest: bundle_digest(bundle_file_name, "chunk"),
        entry_name: entry_name,
        js_inputs: list_bundle_js_inputs(input_paths, started_at, opts),
        static_bundle_path: static_bundle_path,
        static_source_map_path: static_source_map_path
      }
    end)
  end

  @doc """
  Checks the literal refs the given templates declare, as `list_template_refs/1` summarizes them,
  and raises `Hologram.CompileError` for the first mistake it finds. An atom ref names one
  element, so one that renders twice, inside a `{%for}` or in a component that renders itself is a
  mistake, and so is a ref name used with different numbers of parts. Every template is checked
  with what it renders, and each page also with its layout, since the two render together.

  Only one branch of an `{%if}` and `{%else}` renders, so refs in two branches don't clash. A
  component the summaries don't hold, like a dependency's component or one without IR, adds
  nothing. A component only a dynamic tag renders is never a usage, so it adds nothing either.

  Returns, for each page, the literal refs it renders with its layout, as names with their numbers
  of parts, sorted.

  ## Examples

      iex> check_template_refs(%{MyPage => {:ref, :search, 0}, MyLayout => {:seq, []}}, %{MyPage => MyLayout})
      %{MyPage => [{:search, 0}]}
  """
  @spec check_template_refs(%{module => template_refs}, %{module => module}) ::
          %{module => [{atom, non_neg_integer}]}
  def check_template_refs(summaries, layouts) do
    context = %{cycles: list_ref_cycles(summaries), summaries: summaries}

    {refs_by_module, _memo} =
      summaries
      |> Map.keys()
      |> Enum.sort()
      |> Enum.map_reduce(%{}, fn module, memo ->
        {refs, memo} = root_template_refs(module, layouts, context, memo)
        {{module, refs}, memo}
      end)

    Enum.each(refs_by_module, fn {module, refs} ->
      validate_root_refs(refs, root_label(module, layouts))
    end)

    refs_by_module
    |> Enum.filter(fn {module, _refs} -> Map.has_key?(layouts, module) end)
    |> Map.new(fn {page_module, refs} ->
      names =
        refs
        |> Enum.map(&{&1.name, &1.part_count})
        |> Enum.uniq()
        |> Enum.sort()

      {page_module, names}
    end)
  end

  @doc """
  Returns the digest of a chunk's signature (see `group_mfas_by_signature/1`): the first 8 hex
  digits of the MD5 of its type names, sorted. It names the chunk while it is built, its entry
  file and its output dir, and not the file that is served (see `bundle/4`). The same signature
  gives the same digest in every compile.
  """
  @spec chunk_signature_digest(MapSet.t(module)) :: String.t()
  # sobelow_skip ["Crypto.WeakHash"]
  def chunk_signature_digest(signature) do
    type_names =
      signature
      |> Enum.sort()
      |> Enum.map_join(",", &Atom.to_string/1)

    :md5
    |> :crypto.hash(type_names)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end

  @doc """
  Returns the client config the runtime bundle sets as `globalThis.Hologram.config`: whether the
  error overlay is on, whether live reload is (it runs in dev only, and in test, so that the feature
  tests can drive it, as the SSE stream's live reload subscription does), and whether client stack
  traces are. `liveReload` lets the client load a page afresh when it holds that page's code in an
  older version (see live_reload.mjs). The runtime bundle carries it as written here, so the
  compile task keeps a runtime bundle only while this is what it was built with.
  """
  @spec client_config() :: String.t()
  def client_config do
    live_reload? = Hologram.env() in [:dev, :test]

    "{errorOverlay: #{Hologram.client_error_overlay?()}, liveReload: #{live_reload?}, " <>
      "stacktraces: #{Hologram.client_stacktraces?()}}"
  end

  @doc """
  Creates the chunk bundle entry files, one per signature of the given folded chunks (see
  `fold_chunks/5`), and returns each signature with its digest (see `chunk_signature_digest/1`) and
  its entry file's path, sorted by digest. The functions of all the chunks are encoded into the
  encode PLT first, with one IR read per module (`encode_reachable_functions/5`), and then each
  chunk is rendered from that cache. Takes the options `create_page_entry_files/6` takes, with the
  modules whose JS bindings the runtime script registers as the `runtime_js_binding_modules:` opt.
  """
  @spec create_chunk_entry_files(
          %{MapSet.t(module) => [mfa]},
          PLT.t(),
          PLT.t(),
          MapSet.t(mfa),
          T.opts()
        ) :: list({MapSet.t(module), String.t(), T.file_path()})
  def create_chunk_entry_files(mfas_by_signature, ir_plt, encode_plt, async_mfas, opts) do
    script_opts = chunk_script_opts(opts)

    mfas_by_signature
    |> Enum.flat_map(fn {_signature, mfas} -> mfas end)
    |> encode_reachable_functions(ir_plt, encode_plt, async_mfas, opts[:module_info_plt])

    mfas_by_signature
    |> Enum.map(fn {signature, mfas} -> {signature, chunk_signature_digest(signature), mfas} end)
    |> Enum.sort_by(fn {_signature, signature_digest, _mfas} -> signature_digest end)
    |> TaskUtils.map_concurrently(fn {signature, signature_digest, mfas} ->
      entry_file_path =
        mfas
        |> build_chunk_js(ir_plt, encode_plt, async_mfas, script_opts)
        |> create_entry_file("chunk-" <> signature_digest, opts[:tmp_dir])

      {signature, signature_digest, entry_file_path}
    end)
  end

  @doc """
  Creates the page bundle entry files, given each page's reachable MFAs (see `list_mfas_by_page/5`).
  The functions of all the given pages are encoded into the encode PLT first, with one IR read per
  module (`encode_reachable_functions/5`), and then each page is rendered from that cache, so a
  module's IR is read once for all the pages of one call. The compile task calls it once per batch;
  a function already in the encode PLT, encoded for an earlier batch or an earlier compile, is not
  encoded again. The module info PLT is taken from the `module_info_plt:` opt, and each page's
  literal refs from the `ref_names_by_page:` opt, as `check_template_refs/2` returns them.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/create_page_entry_files_6/README.md
  """
  @spec create_page_entry_files(
          list({module, list(mfa)}),
          PLT.t(),
          PLT.t(),
          MapSet.t(mfa),
          MapSet.t(module),
          T.opts()
        ) :: list({module, T.file_path()})
  def create_page_entry_files(
        mfas_by_page,
        ir_plt,
        encode_plt,
        async_mfas,
        runtime_js_binding_modules,
        opts
      ) do
    module_info_plt = opts[:module_info_plt]
    ref_names_by_page = Keyword.get(opts, :ref_names_by_page, %{})

    mfas_by_page
    |> Enum.flat_map(fn {_page_module, mfas} -> mfas end)
    |> encode_reachable_functions(ir_plt, encode_plt, async_mfas, module_info_plt)

    TaskUtils.map_concurrently(mfas_by_page, fn {page_module, mfas} ->
      entry_name = Reflection.module_name(page_module)

      entry_file_path =
        mfas
        |> build_page_js(ir_plt, encode_plt, async_mfas,
          js_dir: opts[:js_dir],
          module_info_plt: module_info_plt,
          module_metadata: opts[:module_metadata],
          ref_names: {page_module, Map.get(ref_names_by_page, page_module, [])},
          runtime_js_binding_modules: runtime_js_binding_modules
        )
        |> create_entry_file(entry_name, opts[:tmp_dir])

      {page_module, entry_file_path}
    end)
  end

  @doc """
  Creates runtime bundle entry file. Requires the `:subsystems` option: the keys of the optional
  runtime subsystems to render.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/create_runtime_entry_file_7/README.md
  """
  @spec create_runtime_entry_file(
          list(mfa),
          PLT.t(),
          PLT.t(),
          MapSet.t(mfa),
          keyword(String.t()),
          String.t(),
          T.opts()
        ) :: T.file_path()
  def create_runtime_entry_file(
        runtime_mfas,
        ir_plt,
        encode_plt,
        async_mfas,
        app_versions,
        sync_constants_js,
        opts
      ) do
    runtime_mfas
    |> build_runtime_js(ir_plt, encode_plt, async_mfas, app_versions, sync_constants_js,
      js_dir: opts[:js_dir],
      module_info_plt: opts[:module_info_plt],
      module_metadata: opts[:module_metadata],
      subsystems: Keyword.fetch!(opts, :subsystems)
    )
    |> create_entry_file("runtime", opts[:tmp_dir])
  end

  @doc """
  Deletes from the encode PLT the entries of the given modules' functions, and returns the PLT. A
  module's functions are encoded again from its IR once it was edited, and are gone with it once it
  was removed. Reads the keys only, never the values. Given no module, it reads nothing.
  """
  @spec delete_module_encodings(PLT.t(), [module]) :: PLT.t()
  def delete_module_encodings(encode_plt, []), do: encode_plt

  def delete_module_encodings(encode_plt, modules) do
    dropped_modules = MapSet.new(modules)

    encode_plt
    |> PLT.keys()
    |> Enum.filter(fn {module, _function, _arity} -> MapSet.member?(dropped_modules, module) end)
    |> Enum.each(&PLT.delete(encode_plt, &1))

    encode_plt
  end

  @doc """
  Deletes the IR of the given modules from the IR PLT and returns the PLT. The compile task calls it
  with the removed and edited modules of a compile: a removed module's IR is not read again, and an
  edited module's is built again from its new beam, with `build_missing_ir!/2`, by whatever reads it
  in this compile or a later one.
  """
  @spec delete_module_ir(PLT.t(), [module]) :: PLT.t()
  def delete_module_ir(ir_plt, modules) do
    TaskUtils.map_concurrently(modules, &PLT.delete(ir_plt, &1))
    ir_plt
  end

  @doc """
  Compares two module info PLTs by digest and returns the added, removed, and edited modules lists.
  An entry whose mtime or size moved but whose digest did not is not an edit.
  """
  @spec diff_module_info_plts(PLT.t(), PLT.t()) :: %{
          added_modules: list(module),
          removed_modules: list(module),
          edited_modules: list(module)
        }
  def diff_module_info_plts(old_plt, new_plt) do
    old_infos = PLT.get_all(old_plt)
    new_infos = PLT.get_all(new_plt)

    added_modules =
      for {module, _info} <- new_infos, not Map.has_key?(old_infos, module), do: module

    edited_modules =
      for {module, %{digest: digest}} <- new_infos,
          edited_module?(old_infos, module, digest),
          do: module

    removed_modules =
      for {module, _info} <- old_infos, not Map.has_key?(new_infos, module), do: module

    %{
      added_modules: added_modules,
      removed_modules: removed_modules,
      edited_modules: edited_modules
    }
  end

  @doc """
  Writes the module info PLT to the dump at the given path, with a new random token next to it that
  tells this dump from any other (see `module_info_dump_stamp/1`). The token is written first, so
  that a compile that dies between the two leaves a token no dump was written with.
  """
  @spec dump_module_info_plt(PLT.t(), T.file_path()) :: :ok
  def dump_module_info_plt(plt, dump_path) do
    token =
      12
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    dump_path
    |> Path.dirname()
    |> File.mkdir_p!()

    dump_path
    |> module_info_dump_token_path()
    |> FileUtils.write_atomically!(token)

    PLT.dump(plt, dump_path)

    :ok
  end

  @doc """
  Encodes into the encode PLT every function of the given MFAs that is not there yet, reading each
  module's IR once however many entry files reach it. Erlang modules are skipped, and so are
  protocol modules, whose dispatcher functions depend on the entry file and are encoded per entry
  file; the module info PLT says which modules are protocols without touching their code paths.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/encode_reachable_functions_5/README.md
  """
  @spec encode_reachable_functions([mfa], PLT.t(), PLT.t(), MapSet.t(mfa), PLT.t() | nil) :: :ok
  def encode_reachable_functions(mfas, ir_plt, encode_plt, async_mfas, module_info_plt) do
    mfas
    |> Enum.uniq()
    |> group_mfas_by_module()
    # Checked once per module, not per MFA: the lists of many pages repeat the same MFAs.
    |> Enum.filter(fn {module, _module_mfas} ->
      Reflection.elixir_module?(module, ir_plt) and
        not Reflection.protocol?(module, module_info_plt)
    end)
    |> TaskUtils.map_concurrently(fn {module, module_mfas} ->
      missing =
        module_mfas
        |> Enum.map(fn {_module, function, arity} -> {function, arity} end)
        |> Enum.reject(&function_encoded?(encode_plt, module, &1))

      if missing != [] do
        context = %Context{async_mfas: async_mfas, ir_plt: ir_plt, module: module}
        encode_missing_module_functions(missing, module, ir_plt, encode_plt, context)
      end
    end)

    :ok
  end

  @doc """
  Returns the path esbuild is started with for the given `node_modules` dir: the esbuild binary of
  the platform package npm installed, `@esbuild/win32-*/esbuild.exe`, when there is exactly one,
  else the launcher `.bin/esbuild`. On Windows the launcher is a script that starts Node to start
  the binary, which costs about 50 ms per start. On the other platforms the launcher is the binary
  itself: esbuild's installer puts it there.
  """
  @spec esbuild_bin_path(T.file_path()) :: T.file_path()
  def esbuild_bin_path(node_modules_path) do
    binary_paths =
      [node_modules_path, "@esbuild", "win32-*", "esbuild.exe"]
      |> Path.join()
      |> Path.wildcard()

    case binary_paths do
      [binary_path] -> binary_path
      _none_or_several -> Path.join([node_modules_path, ".bin", "esbuild"])
    end
  end

  @doc """
  Returns the fingerprint of each given file, keyed by its path: `{:digest, digest}` of the content
  for a file outside any `node_modules` dir (the app's own JavaScript, which the dev saves,
  sometimes within the second of a compile), `{:stat, mtime, size}` for a file under one (packages
  change on install, never within a second of a compile, and a bundle can read dozens of them),
  `:fresh` for a file whose mtime is not older than `started_at` in posix seconds (it may have been
  written after the reader that started then read it, so its record must never match; nil takes no
  file as fresh) and `:missing` for a file that is not there or cannot be read (one removed between
  its stat and its read included). A bundle records the fingerprints of the files esbuild read for
  it (see `bundle/4`), and the compile task compares them with the fingerprints now to find the
  bundles to rebuild.
  """
  @spec fingerprint_js_inputs([String.t()], non_neg_integer | nil) :: %{
          String.t() => js_input_fingerprint
        }
  def fingerprint_js_inputs(paths, started_at) do
    Map.new(paths, &{&1, fingerprint_js_input(&1, started_at)})
  end

  @doc """
  Returns the chunks to bundle, by signature, with the size of each chunk given:

    * `:chunks` - the given MFAs by signature (see `group_mfas_by_signature/1`) with the small
      chunks folded into others (see `fold_small_chunks/2`).

    * `:sizes` - the size of each given chunk, keyed by its MFAs: the size of its definitions as
      rendered, which holds the Erlang functions and the protocol dispatchers too, so the encode
      PLT alone cannot tell it.

  A size given under the `:sizes` opt, keyed the same way, is taken as it is: the kept size of a
  chunk whose functions are the ones it was sized with, and whose modules were not edited since.
  The other chunks are sized: the IR their functions need is built into the IR PLT, the functions
  are encoded into the encode PLT (`encode_reachable_functions/5`) and each chunk is rendered
  once. Takes the options `create_chunk_entry_files/5` takes, plus `:sizes`.
  """
  @spec fold_chunks(%{MapSet.t(module) => [mfa]}, PLT.t(), PLT.t(), MapSet.t(mfa), T.opts()) ::
          %{chunks: %{MapSet.t(module) => [mfa]}, sizes: %{[mfa] => non_neg_integer}}
  def fold_chunks(mfas_by_signature, ir_plt, encode_plt, async_mfas, opts) do
    module_info_plt = opts[:module_info_plt]
    script_opts = chunk_script_opts(opts)
    known_sizes = opts[:sizes] || %{}

    chunks_to_size =
      Enum.reject(mfas_by_signature, fn {_signature, mfas} -> is_map_key(known_sizes, mfas) end)

    mfas_to_size = Enum.flat_map(chunks_to_size, fn {_signature, mfas} -> mfas end)

    mfas_to_size
    |> list_ir_modules(module_info_plt)
    |> then(&build_missing_ir!(ir_plt, &1))

    encode_reachable_functions(mfas_to_size, ir_plt, encode_plt, async_mfas, module_info_plt)

    sizes =
      chunks_to_size
      |> TaskUtils.map_concurrently(fn {_signature, mfas} ->
        %{defs: defs} = render_script_parts(mfas, ir_plt, encode_plt, async_mfas, script_opts)
        {mfas, byte_size(defs)}
      end)
      |> Map.new()
      |> Map.merge(Map.take(known_sizes, Map.values(mfas_by_signature)))

    size_by_signature =
      Map.new(mfas_by_signature, fn {signature, mfas} -> {signature, sizes[mfas]} end)

    %{chunks: fold_small_chunks(mfas_by_signature, size_by_signature), sizes: sizes}
  end

  @doc """
  Folds each chunk that is smaller than what a separate file costs into another chunk, given the
  MFAs by signature (see `group_mfas_by_signature/1`) and each signature's size, the bytes of its
  definitions as rendered. A small chunk is merged into the chunk whose signature is its smallest
  strict superset, so that every type that needs its MFAs still loads them: those types save a
  request, and the other types of the superset load a few bytes they have no use for. A small
  chunk with no superset stays.

  The smallest chunks are folded first, and a chunk that grew to the bound by what was folded into
  it stays.

  ## Examples

      iex> fold_small_chunks(
      ...>   %{
      ...>     MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
      ...>     MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}]
      ...>   },
      ...>   %{MapSet.new([Date]) => 300, MapSet.new([Date, DateTime]) => 4_000}
      ...> )
      %{
        MapSet.new([Date, DateTime]) => [
          {Calendar.ISO, :date_to_string, 3},
          {String.Chars.Date, :to_string, 1}
        ]
      }
  """
  @spec fold_small_chunks(
          %{MapSet.t(module) => [mfa]},
          %{MapSet.t(module) => non_neg_integer}
        ) :: %{MapSet.t(module) => [mfa]}
  def fold_small_chunks(mfas_by_signature, size_by_signature) do
    {folded_mfas_by_signature, _sizes} =
      size_by_signature
      |> Enum.filter(fn {_signature, size} -> size < @chunk_fold_bound end)
      |> Enum.sort_by(fn {signature, size} -> {size, Enum.sort(signature)} end)
      |> Enum.reduce({mfas_by_signature, size_by_signature}, fn {signature, _size}, acc ->
        fold_small_chunk(signature, acc)
      end)

    folded_mfas_by_signature
  end

  @doc """
  Extracts JavaScript source code for the given ported Erlang function.

  Returns the JavaScript function code if it exists in the corresponding .mjs file,
  or nil if the file or function doesn't exist.

  ## Examples

      iex> get_erlang_function_js(:erlang, :+, 2, "/path/to/erlang")
      "(left, right) => { ... }"

      iex> get_erlang_function_js(:maps, :get, 2, "/path/to/erlang")
      "(key, map) => { ... }"

      iex> get_erlang_function_js(:erlang, :not_implemented, 2, "/path/to/erlang")
      nil
  """
  @spec get_erlang_function_js(module, atom, non_neg_integer, T.file_path()) :: String.t() | nil
  def get_erlang_function_js(module, function, arity, erlang_js_dir) do
    file_path =
      if module == :erlang do
        "#{erlang_js_dir}/erlang.mjs"
      else
        "#{erlang_js_dir}/#{module}.mjs"
      end

    if File.exists?(file_path) do
      extract_erlang_function_js(file_path, function, arity)
    else
      nil
    end
  end

  @doc """
  Groups the given MFAs by module.
  """
  @spec group_mfas_by_module(list(mfa)) :: %{module => mfa}
  def group_mfas_by_module(mfas) do
    Enum.group_by(mfas, fn {module, _function, _arity} -> module end)
  end

  @doc """
  Groups the MFAs of the given types' chunks (see `CallGraph.list_chunk_mfas_by_type/4`) by their
  signature: the set of types whose MFAs hold them. Each group is the MFAs of one chunk, sorted, so
  that an MFA several types need is in one chunk those types share, and in no other.

  ## Examples

      iex> group_mfas_by_signature(%{
      ...>   Date => [{Calendar.ISO, :date_to_string, 3}, {String.Chars.Date, :to_string, 1}],
      ...>   Time => [{Calendar.ISO, :time_to_string, 4}, {String.Chars.Time, :to_string, 1}],
      ...>   DateTime => [{Calendar.ISO, :date_to_string, 3}, {Calendar.ISO, :time_to_string, 4}]
      ...> })
      %{
        MapSet.new([Date]) => [{String.Chars.Date, :to_string, 1}],
        MapSet.new([Date, DateTime]) => [{Calendar.ISO, :date_to_string, 3}],
        MapSet.new([DateTime, Time]) => [{Calendar.ISO, :time_to_string, 4}],
        MapSet.new([Time]) => [{String.Chars.Time, :to_string, 1}]
      }
  """
  @spec group_mfas_by_signature(%{module => [mfa]}) :: %{MapSet.t(module) => [mfa]}
  def group_mfas_by_signature(mfas_by_type) do
    mfas_by_type
    |> Enum.flat_map(fn {type, mfas} -> Enum.map(mfas, &{&1, type}) end)
    |> Enum.group_by(fn {mfa, _type} -> mfa end, fn {_mfa, type} -> type end)
    |> Enum.group_by(fn {_mfa, types} -> MapSet.new(types) end, fn {mfa, _types} -> mfa end)
    |> Map.new(fn {signature, mfas} -> {signature, Enum.sort(mfas)} end)
  end

  @doc """
  Returns the path of the gzip copy of the bundle at the given path: the bundle's path with `.gz`
  appended.
  """
  @spec gzip_path(T.file_path()) :: T.file_path()
  def gzip_path(bundle_path) do
    bundle_path <> ".gz"
  end

  @doc """
  Installs JavaScript deps which are specified in package.json located in assets_dir, and records
  the package.json digest in the node_modules dir the install fills (see `maybe_install_js_deps/1`).
  Creates package-lock.json when there is none, and never rewrites an existing one.
  """
  @spec install_js_deps(T.file_path()) :: :ok
  # sobelow_skip ["CI.System"]
  def install_js_deps(assets_dir) do
    package_json_digest_path = package_json_digest_path(assets_dir)

    # Gone before npm runs, so that an install that fails leaves no record of a finished one, which
    # every build env would then trust.
    File.rm(package_json_digest_path)

    # Run from the project root, not from inside assets_dir, so version managers like
    # asdf/mise resolve the Node.js version from the consuming project's config rather
    # than any .tool-versions inside a git-checked-out dependency. npm still installs
    # into assets_dir via --prefix.
    opts = [into: IO.stream(:stdio, :line)]

    # npm installs from an existing lockfile without writing it back: for a path dependency the
    # assets dir is the developer's own checkout, and an npm other than the one that generated the
    # lockfile would write it differently.
    package_lock_json_path = Path.join(assets_dir, "package-lock.json")

    npm_args =
      if File.exists?(package_lock_json_path) do
        ["install", "--no-save", "--prefix", assets_dir]
      else
        ["install", "--prefix", assets_dir]
      end

    {_result, exit_status} = SystemUtils.cmd_cross_platform("npm", npm_args, opts)

    if exit_status != 0 do
      raise RuntimeError, message: "npm install command failed"
    end

    package_json_digest = get_package_json_digest(assets_dir)

    # npm creates no node_modules dir for a package.json with no deps.
    FileUtils.write_p!(package_json_digest_path, package_json_digest)
  end

  @doc """
  Whether a bundle's recorded inputs (see `bundle/4`) no longer match the files: any recorded file
  whose fingerprint differs from its fingerprint now in `js_fingerprints` (see
  `fingerprint_js_inputs/2`), or that `js_fingerprints` does not hold. Each bundle is compared on
  its own record: two bundles can hold different fingerprints of one file, when it was saved
  between the two builds, and only the one that read the old content is stale.
  """
  @spec js_inputs_changed?(%{String.t() => js_input_fingerprint}, %{
          String.t() => js_input_fingerprint
        }) :: boolean
  def js_inputs_changed?(js_inputs, js_fingerprints) do
    Enum.any?(js_inputs, fn {path, fingerprint} ->
      Map.get(js_fingerprints, path) != fingerprint
    end)
  end

  @doc """
  Returns every component usage found in the given IR, as `{component_module, props, has_spread?}`
  tuples, in the order they appear in the template.

  `props` holds one entry per prop written at the usage, without the framework's own `$`-prefixed
  entries, as `{name, {:ok, value}}` when the value is known without running anything, and
  `{name, :unknown}` otherwise. `has_spread?` says whether the usage carries a `...{expr}` spread,
  which makes its set of props impossible to know before the expression has a value.

  Dynamic tags (`<{@module} />`) are skipped - the component module itself is a runtime value there.

  ## Examples

      iex> list_component_usages(IR.for_module(MyApp.HomePage))
      [{MyApp.Card, [{"size", {:ok, :small}}, {"count", :unknown}], false}]
  """
  @spec list_component_usages(IR.t()) ::
          list({module, list({String.t(), {:ok, any} | :unknown}), boolean})
  def list_component_usages(ir) do
    ir
    |> collect_component_usages([])
    |> Enum.reverse()
  end

  @doc """
  Lists the component modules recorded in the given module info PLT, sorted by name.
  """
  @spec list_components(PLT.t()) :: list(module)
  def list_components(module_info_plt) do
    list_modules_where(module_info_plt, :component?)
  end

  @doc """
  Lists the modules whose IR the entry files rendered from the given MFAs read: the modules of those MFAs and
  of the manually ported MFAs (the runtime entry file renders their clause heads), each once. Only the modules
  the module info PLT holds are listed, since the IR PLT is built for those alone (an Erlang module has no IR).
  """
  @spec list_ir_modules([mfa], PLT.t()) :: [module]
  def list_ir_modules(mfas, module_info_plt) do
    [mfas, CallGraph.manually_ported_elixir_mfas()]
    |> Stream.concat()
    |> Stream.map(fn {module, _function, _arity} -> module end)
    |> Stream.uniq()
    |> Enum.filter(&PLT.member?(module_info_plt, &1))
  end

  @doc """
  Lists the Elixir modules referenced by the given MFAs that declare JS imports. The IR PLT tells
  the Elixir modules apart from the Erlang ones, and the module info PLT says which of them declare
  imports without touching their code paths; with nil, every module is asked.
  """
  @spec list_js_import_modules(list(mfa), PLT.t(), PLT.t() | nil) :: list(module)
  def list_js_import_modules(mfas, ir_plt, module_info_plt) do
    mfas
    |> filter_elixir_mfas(ir_plt)
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Enum.filter(&(Reflection.js_imports?(&1, module_info_plt) and &1.__js_imports__() != []))
  end

  @doc """
  Lists the modules whose IR and function encodings a compile keeps: the modules the runtime entry file
  reads (see `list_ir_modules/2`) and the modules each page reaches, each once. A page's modules are
  given as the `MapSet` of the modules of its reachable MFAs, as a page state keeps it, so they include
  the page itself: every page is kept, and a component no page reaches is not. Only the modules the
  module info PLT holds are listed, since the IR PLT is built for those alone.
  """
  @spec list_kept_modules([mfa], [{module, MapSet.t(module)}], PLT.t()) :: [module]
  def list_kept_modules(runtime_mfas, modules_by_page, module_info_plt) do
    page_reached_modules =
      modules_by_page
      |> Enum.reduce(MapSet.new(), fn {_page_module, modules}, acc ->
        MapSet.union(acc, modules)
      end)
      |> Enum.filter(&PLT.member?(module_info_plt, &1))

    runtime_mfas
    |> list_ir_modules(module_info_plt)
    |> Enum.concat(page_reached_modules)
    |> Enum.uniq()
  end

  @doc """
  Lists, for each page, the MFAs reachable from it (see `CallGraph.list_page_mfas/5`), sharing the call
  graph's graph with the page tasks (see `CallGraph.with_shared_graph/2`) and the server callback
  analyses they compute, for this call. The compile task lists its batches with `list_mfas_by_page/5`
  against a graph and analyses it shares for the whole compile; this is for a caller that lists once.
  With no page, the graph is not read: a graph still being rebuilt is not waited for. A caller
  with no graph to give (see the compile task's pages graph) passes nil with no page. The opts are
  passed on to `CallGraph.list_page_mfas/5` (the `:gate` opt says which reflection functions the
  pages can call).
  """
  @spec list_mfas_by_page([module], CallGraph.t() | nil, T.opts()) :: [{module, [mfa]}]
  def list_mfas_by_page(page_modules, call_graph, opts \\ [])

  def list_mfas_by_page([], _call_graph, _opts), do: []

  def list_mfas_by_page(page_modules, call_graph, opts) do
    module_info_plt = CallGraph.module_info_plt(call_graph)
    analyses = PLT.start()

    try do
      CallGraph.with_shared_graph(
        call_graph,
        &list_mfas_by_page(page_modules, &1, analyses, module_info_plt, opts)
      )
    after
      PLT.stop(analyses)
    end
  end

  @doc """
  Lists, for each page, what its client code reaches: the MFAs reachable from it (see
  `CallGraph.list_page_mfas/5`) and the struct types it names (see
  `CallGraph.list_page_chunk_types/4`), which the MFAs do not show, since a type's struct functions
  ship in its chunks rather than in the page's bundle. Both are listed one task per page, through
  the reader of a graph shared with the page tasks (see `CallGraph.with_shared_graph/2`) and the
  server callback analyses they compute, for this call. With no page, the graph is not read.

  What the data layer derives per page reads it: what the data layer keeps of the page's reach (see
  `build_kept_page_reach/4`) and whether the page checks permissions (see
  `pages_checking_permissions/1`).

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/list_reach_by_page_2/README.md
  """
  @spec list_reach_by_page([module], CallGraph.t()) :: [{module, page_reach}]
  def list_reach_by_page([], _call_graph), do: []

  def list_reach_by_page(page_modules, call_graph) do
    module_info_plt = CallGraph.module_info_plt(call_graph)
    analyses = PLT.start()

    try do
      CallGraph.with_shared_graph(call_graph, fn read_graph ->
        # The tasks get the reader, which captures only the shared graph's key (see
        # list_mfas_by_page/5).
        TaskUtils.map_concurrently(page_modules, fn page_module ->
          graph = read_graph.()

          reach = %{
            mfas: CallGraph.list_page_mfas(graph, page_module, analyses, module_info_plt),
            types: CallGraph.list_page_chunk_types(graph, page_module, analyses, module_info_plt)
          }

          {page_module, reach}
        end)
      end)
    after
      PLT.stop(analyses)
    end
  end

  @doc """
  Lists, for each page, the MFAs reachable from it (see `CallGraph.list_page_mfas/5`), one task per
  page, through the reader of a shared graph (see `CallGraph.with_shared_graph/2`) and the PLT of
  server callback analyses, which the pages fill as they go: a caller listing pages in rounds, as the
  compile task does with its batches, computes each templatable's analysis once for all of them. The
  opts are passed on to `CallGraph.list_page_mfas/5`.
  """
  @spec list_mfas_by_page([module], (-> Digraph.t()), PLT.t(), PLT.t() | nil, T.opts()) ::
          [{module, [mfa]}]
  def list_mfas_by_page(page_modules, read_graph, analyses, module_info_plt, opts \\ []) do
    # The tasks get the reader, which captures only the shared graph's key: a closure that
    # captured the graph itself would copy it into every task it starts. Listing a page's MFAs is
    # a cheap graph walk.
    TaskUtils.map_concurrently(page_modules, fn page_module ->
      mfas = CallGraph.list_page_mfas(read_graph.(), page_module, analyses, module_info_plt, opts)
      {page_module, mfas}
    end)
  end

  @doc """
  Lists, for each given page, the pages among the modules it reaches, itself excluded. A link or a
  path helper in a template is a call with the page module as an argument, which reaches the page's
  module vertex and through it `__params__/0` and `__route__/0` only, so the modules of a page's
  reachable MFAs, given as the `MapSet` a page state keeps, name exactly the pages it links to, one
  hop away. A page whose modules are not given, one no compile has built, links to no page.
  """
  @spec list_page_links([{module, MapSet.t(module)}], [module]) :: %{module => MapSet.t(module)}
  def list_page_links(modules_by_page, page_modules) do
    page_set = MapSet.new(page_modules)

    links =
      Map.new(modules_by_page, fn {page_module, modules} ->
        linked_pages =
          modules
          |> MapSet.intersection(page_set)
          |> MapSet.delete(page_module)

        {page_module, linked_pages}
      end)

    Map.new(page_modules, &{&1, Map.get(links, &1, MapSet.new())})
  end

  @doc """
  Lists the page modules recorded in the given module info PLT, sorted by name.
  """
  @spec list_pages(PLT.t()) :: list(module)
  def list_pages(module_info_plt) do
    list_modules_where(module_info_plt, :page?)
  end

  @doc """
  Returns the shapes of the queries the modules recorded in the given module info PLT write on an
  entity type (see `Hologram.Query.Shape`), by module. A module recording none is left out.
  """
  @spec list_query_shapes(PLT.t()) :: %{module => list(Shape.t())}
  def list_query_shapes(module_info_plt) do
    for {module, info} <- PLT.get_all(module_info_plt),
        shapes = Map.get(info, :query_shapes, []),
        shapes != [],
        into: %{},
        do: {module, shapes}
  end

  @doc """
  Returns the shapes of the queries the given modules write on an entity type, by module, read
  from the given module info PLT (see `list_query_shapes/1`). A module recording none, or one the
  PLT doesn't hold, is left out.
  """
  @spec list_query_shapes(PLT.t(), list(module)) :: %{module => list(Shape.t())}
  def list_query_shapes(module_info_plt, modules) do
    for module <- modules,
        {:ok, info} <- [PLT.get(module_info_plt, module)],
        shapes = Map.get(info, :query_shapes, []),
        shapes != [],
        into: %{},
        do: {module, shapes}
  end

  @doc """
  Lists the literal refs the template of the given module IR declares, and the components it
  renders, as `t:template_refs/0`. A ref whose name only an expression knows, like
  `$ref={@input_ref}`, is left out. So is a component a dynamic tag renders. A component's slot
  content follows it, since the template that writes the content declares its refs.

  ## Examples

      iex> list_template_refs(IR.for_module(MyComponent))
      {:seq, [{:ref, :search, 0}, {:loop, {:ref, :item, 1}}, {:component, MyApp.Card}]}
  """
  @spec list_template_refs(IR.t()) :: template_refs
  def list_template_refs(ir) do
    ir
    |> template_ir()
    |> collect_template_refs()
  end

  @doc """
  Lists the literal refs the template of each given module declares, as `list_template_refs/1`
  does, by module. A module missing from the IR PLT declares none, as `validate_prop_usages/2`
  finds it using no component: without a BEAM source it has no IR to walk.
  """
  @spec list_template_refs_by_module([module], PLT.t()) :: %{module => template_refs}
  def list_template_refs_by_module(modules, ir_plt) do
    Map.new(modules, fn module ->
      case PLT.get(ir_plt, module) do
        {:ok, ir} -> {module, list_template_refs(ir)}
        :error -> {module, {:seq, []}}
      end
    end)
  end

  @doc """
  Lists the templatables whose prop usages a compile validates: every one when no earlier validation
  is kept (`template_modules` nil), else the ones the module digests diff added or edited, and the
  ones whose template uses an added, edited or removed module, as `template_modules` (each
  templatable's used modules, from `validate_prop_usages/2`) records them. A usage's validity
  depends on its template and on the used component's props, which live in those modules' beams
  alone.
  """
  @spec list_templatables_to_validate([module], map, %{module => MapSet.t(module)} | nil) ::
          [module]
  def list_templatables_to_validate(templatable_modules, _module_digests_diff, nil) do
    templatable_modules
  end

  def list_templatables_to_validate(templatable_modules, module_digests_diff, template_modules) do
    changed_modules =
      MapSet.new(
        module_digests_diff.added_modules ++
          module_digests_diff.edited_modules ++ module_digests_diff.removed_modules
      )

    Enum.filter(templatable_modules, fn module ->
      MapSet.member?(changed_modules, module) or
        not MapSet.disjoint?(template_modules[module], changed_modules)
    end)
  end

  @doc """
  Installs JavaScript deps if package.json has changed or if the deps haven't been installed yet.
  The record of the last install is kept in the node_modules dir it filled, like the deps, so every
  build env reads the one record of the deps they share, and removing node_modules removes it too.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/maybe_install_js_deps_1/README.md
  """
  @spec maybe_install_js_deps(T.file_path()) :: :ok | nil
  def maybe_install_js_deps(assets_dir) do
    package_json_digest_path = package_json_digest_path(assets_dir)
    package_json_lock_path = Path.join(assets_dir, "package-lock.json")

    if !File.exists?(package_json_digest_path) or !File.exists?(package_json_lock_path) do
      install_js_deps(assets_dir)
    else
      old_package_json_digest = File.read!(package_json_digest_path)
      new_package_json_digest = get_package_json_digest(assets_dir)

      if new_package_json_digest != old_package_json_digest do
        install_js_deps(assets_dir)
      end
    end
  end

  @doc """
  Loads the module info PLT from its dump file in the build dir if the file exists, or creates an empty PLT.
  Returns the PLT, the dump path, and the dump file's mtime in posix seconds (nil when there is no dump),
  which `build_module_info_plt!/3` uses to decide which entries can be reused.
  """
  @spec maybe_load_module_info_plt(T.file_path(), T.opts()) ::
          {PLT.t(), String.t(), non_neg_integer | nil}
  def maybe_load_module_info_plt(build_dir, opts \\ []) do
    plt = PLT.start(opts)
    dump_path = Path.join(build_dir, Reflection.module_info_plt_dump_file_name())
    dumped_at = module_info_dumped_at(dump_path)

    PLT.maybe_load(plt, dump_path)

    {plt, dump_path, dumped_at}
  end

  @doc """
  Returns the mtime in posix seconds of the module info dump at the given path, which
  `build_module_info_plt!/3` takes as `dumped_at`, or nil when there is no dump.
  """
  @spec module_info_dumped_at(T.file_path()) :: non_neg_integer | nil
  def module_info_dumped_at(dump_path) do
    case File.stat(dump_path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      {:error, _reason} -> nil
    end
  end

  @doc """
  Returns what tells the module info dump at the given path from another one: its mtime in posix
  seconds and the token `dump_module_info_plt/2` wrote with it, or nil when there is no dump. Each
  dump gets a new random token, so another compile's dump written within the same second has
  another stamp. The token is nil when there is none, as in a build dir only an older Hologram
  wrote to. An older Hologram that rewrites the dump leaves the token there, and the mtime alone
  tells its dump apart then.
  """
  @spec module_info_dump_stamp(T.file_path()) :: {non_neg_integer, String.t() | nil} | nil
  def module_info_dump_stamp(dump_path) do
    case File.stat(dump_path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> {mtime, read_module_info_dump_token(dump_path)}
      {:error, _reason} -> nil
    end
  end

  @doc """
  Splits the given pages into the ones a compile must rebuild and the ones whose bundle it can reuse.

  A page is rebuilt when the pages PLT holds no state for it (a new page, or the first compile in a
  VM), when the modules of its kept MFAs meet `reaching_modules` (see
  `Hologram.Compiler.CallGraph.list_modules_reaching/2`: every way a page's bundle depends on a
  module is a path in the call graph from a vertex of the page, or of a component it renders, to that
  module), when the bundle its kept state describes, its gzip copy or its source map is no longer on
  disk, or when that bundle belongs to a static dir other than the given one. A page whose bundle's recorded inputs no longer
  match `js_fingerprints`, the fingerprints of the files now, is rebuilt as well (see
  `js_inputs_changed?/2`): no beam moves when a JavaScript file a bundle inlines is edited. A page
  in `pending_pages` is rebuilt too: an earlier compile set out to build it and did not, so its kept
  bundle may predate an edit.

  Returns `{pages_to_rebuild, kept_pages}`, where the kept pages carry their state, both in the order
  the pages were given.
  """
  @spec partition_affected_pages(
          [module],
          MapSet.t(module),
          %{String.t() => js_input_fingerprint},
          MapSet.t(module),
          PLT.t(),
          T.file_path()
        ) ::
          {[module], [{module, map}]}
  def partition_affected_pages(
        page_modules,
        reaching_modules,
        js_fingerprints,
        pending_pages,
        pages_plt,
        static_dir
      ) do
    {kept_pages, pages_to_rebuild} =
      page_modules
      |> Enum.map(fn page_module ->
        page_state =
          keepable_page_state(
            pages_plt,
            page_module,
            reaching_modules,
            js_fingerprints,
            pending_pages,
            static_dir
          )

        {page_module, page_state}
      end)
      |> Enum.split_with(fn {_page_module, page_state} -> page_state end)

    {Enum.map(pages_to_rebuild, fn {page_module, nil} -> page_module end), kept_pages}
  end

  @doc """
  Returns what the client's data layer is compiled with, derived from what the data layer keeps of
  each page's reach (see `build_kept_page_reach/4`). Nothing is walked here, beyond the rules every
  entity type declares, which the policy hash is taken over.

  `:entity_types` are the types a client can ever hold or mention - every entity type the pages'
  client code mentions, the ones it reaches from them by the names it spells (see `:synced_types`),
  and the user entity type when a page reads the session user from the context, which the client
  answers from its database. A client
  constructs and validates entities as well as reading them, and a type it constructs is one it
  has to be told the declarations of. A type neither named nor mentioned is left out, which is what
  keeps an app's other tables out of a file every page load serves.

  When the given module info PLT records a user entity type, the grant type joins the entity
  types: a client holds grant rows, and a row of a type the model does not name cannot be read back
  at all. No browser code names that type - `can?/3` reads it inside the framework - so it is
  added here rather than derived.

  Every entity type declaring a policy or a role joins them too, with every type those types' rules
  read through relationships and every type the derived fields holding rows and the inverses of all
  of these lead to, whether or not a page checks permissions. A check's argument is whatever a
  template passes - a constructed struct as often as a queried row, `can?(user, :create, %Task{})`
  being the ordinary spelling of a create check - so which types get checked is not derivable from
  the queries. Shipping every such type's rules and roles is what lets the client answer every
  check the way the server would - a role check validates and expands the role from the type's
  own declarations, rules or none. What is left out is exactly the types declaring neither and
  led to by none, which is what lets the client read an ABSENT entry as the server's own default
  deny. And every build ships them, rather than only one whose pages check, so that any tab of a
  browser can hand its rules to a tab built with other ones (see `render_rules/1`).

  `:role_modules` are the project's global role modules: a client asking whether a user holds a
  global role needs every one of them to refuse an unknown one and to expand the one asked about.

  `:user_entity` is the project's user entity type, which a client answers the session user's
  row from (see `Hologram.Template.Renderer`'s `{Hologram, :user}` context), or nil when the model
  designates none or the client doesn't hold the type. A user entity type declaring no rule is
  one nobody may read, so no row of it ever reaches a client, and the model leaves it out unless a
  page reaches it or reads the session user.

  `:model_hash` is the hash of the project's data model, of every entity type and global role the
  module info PLT records, whatever the pages reach. It is nil when the PLT records no entity type:
  the application declares no data model.

  `:policy_hash` is the hash of the rules of those same entity types (see `Hologram.Policy.hash/1`),
  nil with the model hash. A client greets with it, and a server running other rules sends it the
  ones it enforces.

  `:synced_types` are the entity types sync sends rows of, sorted by name: the types the pages'
  client code mentions, those it reaches from them by the names it spells (a relationship it
  includes or a path goes through, a derived field it reads), and the user type when a page reads
  the session user, as
  for `:entity_types` - kept syncing whichever of its rows the read rules let the user hold - and,
  when the build checks permissions on the client (see `permission_checking?/1`), the types every
  rule of those types reads through relationships, with the grant type when the model has one. Read
  rules count too, since the browser decides them in `can?`. They are followed one step: client code
  checks only rows of types it queries or mentions, and a rule's chains already follow its
  delegations. A chain's types stop before its first type no session may read (see
  `Hologram.Policy.readable_prefix/2`), since no client gets a row of it, nor any row reached
  through it. A type only server code names, like an audit log, is left out, rules or not, and
  never reaches a browser. A name the code only builds at run time names nothing here, and a
  derived query reading such a type is refused on its render (see
  `Hologram.Template.Renderer`). The server reads the list (see
  `Hologram.DB.QueryCache.synced_types/0`), and the client is told it, refusing a query that reads
  another type the same way (see `build_sync_constants_js/1`).

  `:page_types` are each page's share of those, sorted by name: the types its own client code
  reaches the same way, with the user type when it reads the session user, and the types its rules
  read and the grant type when it checks permissions on the client. A session fills them first, so
  the page the client opened is answered before the rest of the app's rows arrive (see
  `Hologram.Sync.PageTypes`).

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_sync_constants_2/README.md
  """
  @spec build_sync_constants(%{module => kept_page_reach}, PLT.t()) :: sync_constants
  def build_sync_constants(reach_by_page, module_info_plt) do
    # One listing, from the module info PLT, for the mentions, the checked set and the model hash.
    all_entity_types = Reflection.list_entities(module_info_plt)
    role_modules = Reflection.list_roles(module_info_plt)

    # A page mentions an entity type however it spells the mention: `%Task{}` compiles to a call
    # to `Task.__struct__/1`, `Task.new(...)` calls an MFA of `Task`, and `Entity.new(Task, ...)`
    # hands the module over as a value. All three reach the module itself, because the call graph
    # links every module it reaches to its own `__struct__/0` and `__struct__/1` whenever the
    # module has a struct (`CallGraph.maybe_add_struct_call_graph_edges/2`). Every entity type has
    # one, so every spelling lands among the struct types the page names (its MFAs leave the
    # struct functions out, which ship in the type's chunks), and telling a mention apart from a
    # call would answer nothing this does not. Each page's modules are asked about the entity types
    # rather than joined into one set: a page reaches far more modules than there are entity types.
    #
    # From the types a page mentions, the ones its code reaches through them by name: what a type
    # leads to by a relationship or a derived field whose name the page's code spells as an atom
    # (see build_kept_page_reach/4) - an include, a path, a quantifier's set, a derived field it
    # reads, a field a template reads off a row - again from those, until nothing new is named. Per
    # page, since a name means something only on the types that page reaches.
    #
    # A page reading the session user from the context reads its row though nothing names the
    # type, so the names are followed from it too.
    user_entity = Reflection.user_entity(module_info_plt)

    {reached_by_page, _named_by} =
      Enum.map_reduce(reach_by_page, %{}, fn {page_module, reach}, named_by ->
        start_types =
          all_entity_types
          |> Enum.filter(&MapSet.member?(reach.modules, &1))
          |> MapSet.new()
          |> put_page_user_type(user_entity, reach)

        {page_types, named_by} =
          named_entity_types(start_types, start_types, reach.atoms, named_by)

        {{page_module, page_types}, named_by}
      end)

    named_entity_types =
      Enum.reduce(reached_by_page, MapSet.new(), fn {_page_module, page_types}, types ->
        MapSet.union(types, page_types)
      end)

    # A page reading the session user from the context answers it from the browser's database on
    # every render, so the user type is reached like a type a query reads - kept syncing whichever
    # of its rows the read rules let the user hold - though nothing names it.
    reached_entity_types = put_session_user_type(named_entity_types, user_entity, reach_by_page)

    # Rules and roles are baked for every type declaring a rule or a role, reached or not, and for
    # the types those lead to - the set a server hands a client built with other rules (see
    # render_rules/1), so a tab of this build can hand a tab of another the same entries the server
    # would. Trimming them to the reached types would save at most about 0.5 KB gzipped on the
    # feature test app, and a type that reaches the client as data the compiler cannot see would be
    # denied there while the server allows it.
    entity_types =
      reached_entity_types
      |> MapSet.union(checked_entity_types(all_entity_types))
      |> put_grant_type(all_entity_types)
      |> rules_entity_types()

    # What each type's rules read, worked out once for the build and every checking page.
    rule_types =
      if permission_checking?(reach_by_page),
        do: Map.new(reached_entity_types, &{&1, rule_entity_types(&1)}),
        else: %{}

    page_types =
      Map.new(reached_by_page, fn {page_module, types} ->
        checks_permissions? = reach_by_page[page_module].checks_permissions?
        {page_module, synced_types(types, entity_types, checks_permissions?, rule_types)}
      end)

    %{
      entity_types: entity_types,
      model_hash: model_hash(all_entity_types, role_modules),
      page_types: page_types,
      policy_hash: policy_hash(all_entity_types),
      role_modules: role_modules,
      synced_types:
        synced_types(
          reached_entity_types,
          entity_types,
          permission_checking?(reach_by_page),
          rule_types
        ),
      user_entity: if(MapSet.member?(entity_types, user_entity), do: user_entity)
    }
  end

  @doc """
  Builds the JavaScript statement that sets the client's data layer constants,
  `globalThis.Hologram.sync`, from the given sync constants (see `build_sync_constants/2`): the
  global roles with the role modules carrying each, the model of the entity types the client holds,
  the hash of the project's data model, the hash of the rules it was rendered with, the sync
  protocol version, the entity types sync sends rows of - which a query the browser answers may
  only read - and the user entity type.

  What the runtime bundle was built against, said by the bundle itself. It has to be baked in
  rather than handed over at page render: the check these answer is whether a client's JAVASCRIPT
  is stale, and a value the current server puts in the page would always agree with the current
  server.

  `null` when the APPLICATION declares no entity type - the sync constants carry no model hash
  then (see `build_sync_constants/2`) - which is the fact `application.ex` gates the database
  children on and `Handshake.check/1` refuses sync by. The three answer alike on purpose: the
  bundle claims a data layer exactly when the server has one. Null rather than nothing, so a client reads one unambiguous value instead of
  probing for a missing global - and rather than `{}`, which is truthy, so every "does this
  bundle sync?" check would pass on a bundle that never syncs.

  This is NOT the same as the build's own `:entity_types` being empty, which says only that no
  page reaches a query, no type declares a rule or a role, and the model has no user entity type. Such an app HAS a database
  and will answer a greeting, so its bundle keeps saying so: the client greets, its session
  syncs no type, and its model is empty because nothing syncs yet - not because nothing
  can.

  The model is rendered from what the entity types declare when this is called, which is why the
  compile task keeps the statement with the runtime bundle it built, and builds the constants and
  the statement together: the rules the model renders are the ones the policy hash was taken over
  only while nothing between the two moved them.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_sync_constants_js_1/README.md
  """
  @spec build_sync_constants_js(sync_constants) :: String.t()
  def build_sync_constants_js(sync_constants) do
    if sync_constants.model_hash == nil do
      ~s/globalThis.Hologram.sync = null;/
    else
      model = render_entity_model(sync_constants.entity_types)

      expanded_roles = render_global_expanded_roles(sync_constants.role_modules)

      policy_hash = Jason.encode!(sync_constants.policy_hash)

      synced_types =
        sync_constants.synced_types
        |> Enum.map(&Codec.encode_enum_value/1)
        |> Jason.encode!()

      user_entity = render_user_entity(sync_constants.user_entity)

      ~s/globalThis.Hologram.sync = {expandedRoles: #{expanded_roles}, model: #{model}, modelHash: "#{sync_constants.model_hash}", policyHash: #{policy_hash}, protocolVersion: #{Frame.protocol_version()}, syncedTypes: #{synced_types}, userEntity: #{user_entity}};/
    end
  end

  @doc """
  Returns `{pages_to_rebuild, kept_pages}`: the pages this compile must rebuild, which it lists with
  their batches (see `list_mfas_by_page/5`), and the pages whose kept bundle it can reuse, each with
  its state.

  Options:

    * `:gate` - the dynamic call gate the pages are listed with (see
      `Hologram.Compiler.DynamicCallGate`); read only with `:relist_all?`, where the kept pages are
      listed again with it, as their kept MFA lists were. Defaults to none.
    * `:pages_plt` - the PLT of page states kept by `Hologram.Compiler.Cache`.
    * `:page_mfas_plt` - the PLT of page MFA lists kept by `Hologram.Compiler.Cache`; read only with
      `:relist_all?`. A kept page it has no list for is rebuilt then.
    * `:pending_pages` - the pages an earlier compile left unbuilt (see
      `Hologram.Compiler.Cache.put_pending_pages/1`); they are rebuilt whether or not the edit reaches
      them. Defaults to none.
    * `:reaching_modules` - the modules that reach the changed ones, from
      `Hologram.Compiler.CallGraph.list_modules_reaching/2`; see `partition_affected_pages/6` for
      what makes a page affected.
    * `:js_fingerprints` - the fingerprints now of the files the kept bundles read (see
      `fingerprint_js_inputs/2`); a kept page whose recorded inputs no longer match them is
      rebuilt. Defaults to none, which only a page that recorded no input matches.
    * `:static_dir` - the dir this compile writes its bundles to; a kept bundle must live there.
    * `:relist_all?` - when the runtime bundle's MFA set, or what its dynamic calls open (see
      `Hologram.Compiler.CallGraph.runtime_dynamic_calls/2`), changed. A kept page's MFAs can then
      have moved although nothing it reaches was edited: a function that joined the runtime's set
      leaves the page's bundle, and one that left it enters, and a reflection function the runtime
      opens or closes enters or leaves it. The otherwise kept pages are listed again and those whose
      list differs from the one their bundle was built from are rebuilt, and listed again with their
      batch: few pages move, and a page's list is taken when the page is built.
    * `:rebuild_all?` - when the JS import modules the runtime registers changed. Page bundles leave
      those imports out, which their MFA lists do not show, so every page is rebuilt.

  The call graph is read only with `:relist_all?`, so a caller that passes it false may pass nil.
  """
  @spec partition_pages_to_rebuild([module], CallGraph.t() | nil, T.opts()) ::
          {[module], [{module, map}]}
  def partition_pages_to_rebuild(page_modules, call_graph, opts) do
    {pages_to_rebuild, kept_pages} =
      if opts[:rebuild_all?] do
        {page_modules, []}
      else
        partition_affected_pages(
          page_modules,
          opts[:reaching_modules],
          Keyword.get(opts, :js_fingerprints, %{}),
          Keyword.get(opts, :pending_pages, MapSet.new()),
          opts[:pages_plt],
          opts[:static_dir]
        )
      end

    if opts[:relist_all?] do
      {moved_pages, still_kept_pages} =
        relist_kept_pages(kept_pages, call_graph, opts[:page_mfas_plt], opts[:gate])

      {pages_to_rebuild ++ moved_pages, still_kept_pages}
    else
      {pages_to_rebuild, kept_pages}
    end
  end

  @doc """
  Brings the module info PLT of the last finished compile in this VM in line with the beams now, in
  place, and returns what changed: the module digests diff (as `diff_module_info_plts/2` returns it,
  each list sorted), whether any entry changed at all (an entry whose mtime moved but whose digest
  did not is changed, but no edit), and the entries the call replaced or removed, by module, with
  `nil` for a module it added (see `restore_module_infos/2`).

  A module the compiler reported since the last compile (`compiled_modules`, see
  `Hologram.Compiler.Tracer.peek/1`) is read, whatever its entry says. Any other beam is checked
  against its entry's mtime and size, as in `build_module_info_plt!/3`, with `dumped_at` the mtime of
  the module info dump on disk when the last compile finished, and read when they moved or when the
  beam is not older than that dump by a second: another OS process compiling the project, or a new
  implementation rewriting a consolidated protocol, changes a beam with no compile in this VM. A
  module of `editable_modules` that is not among `editable_beams` now is looked up as
  `build_module_info_plt!/3` looks up every module, and loses its entry only when the VM has no beam
  for it: a deleted module is purged, while a consolidated protocol whose directory is off the code
  path for a moment (Phoenix's reloader takes it off while it recompiles) keeps its entry. Leaving
  the entries a scan into a new PLT would copy is what makes a compile that changed nothing cheap: a
  stat per beam, no read.
  """
  @spec patch_module_info_plt!(
          PLT.t(),
          non_neg_integer | nil,
          MapSet.t(module),
          list({module, charlist}),
          MapSet.t(module)
        ) :: {map, boolean, %{module => map | nil}}
  def patch_module_info_plt!(plt, dumped_at, editable_modules, editable_beams, compiled_modules) do
    beam_results =
      TaskUtils.map_concurrently(editable_beams, fn {module, beam_path} ->
        patch_module_info_plt_entry!(plt, module, beam_path, dumped_at, compiled_modules)
      end)

    listed_modules = MapSet.new(editable_beams, fn {module, _beam_path} -> module end)
    umbrella? = Reflection.umbrella?()

    vanished_results =
      editable_modules
      |> MapSet.difference(listed_modules)
      |> Enum.map(&patch_vanished_module_info!(plt, &1, dumped_at, umbrella?))

    results = beam_results ++ vanished_results

    diff = %{
      added_modules: list_results(results, :added),
      edited_modules: list_results(results, :edited),
      removed_modules: list_results(results, :removed)
    }

    previous_infos =
      for {_kind, module, old_info} <- results, into: %{} do
        {module, old_info}
      end

    {diff, previous_infos != %{}, previous_infos}
  end

  @doc """
  Returns the kept module metadata (see `build_module_metadata/1`) brought in line with the module
  digests diff: the entries of the removed and edited modules dropped, the entries of the added and
  edited modules built from the module info PLT, as `build_module_metadata/1` builds them. An entry
  depends on its module's beam alone, since the application tables it names do not move within a VM.
  """
  @spec patch_module_metadata(%{module => map}, map, PLT.t()) :: %{module => map}
  def patch_module_metadata(module_metadata, module_digests_diff, module_info_plt) do
    root_dir = Reflection.root_dir()

    rebuilt_entries =
      for module <- module_digests_diff.added_modules ++ module_digests_diff.edited_modules,
          {:ok, %{source_path: source_path}} when is_binary(source_path) <-
            [PLT.get(module_info_plt, module)],
          into: %{} do
        {module,
         %{
           app: module_application(module),
           file: Reflection.relative_source_path(source_path, root_dir)
         }}
      end

    module_metadata
    |> Map.drop(module_digests_diff.removed_modules ++ module_digests_diff.edited_modules)
    |> Map.merge(rebuilt_entries)
  end

  @doc """
  Deletes from the IR PLT the entries of modules not in the given list, and returns the modules it
  deleted. Reads the keys only, never the values: the table can hold gigabytes.
  """
  @spec prune_ir_plt(PLT.t(), [module]) :: [module]
  def prune_ir_plt(ir_plt, modules) do
    kept_modules = MapSet.new(modules)

    dropped_modules =
      ir_plt
      |> PLT.keys()
      |> Enum.reject(&MapSet.member?(kept_modules, &1))

    Enum.each(dropped_modules, &PLT.delete(ir_plt, &1))

    dropped_modules
  end

  @doc """
  Renders, as a JSON object keyed by label, the client's model entry of every entity type a build
  bakes whatever the pages reach, out of the given ones - those declaring a rule or a role, the
  types their rules read through relationships, and the grant store when the model has one - and of
  every type the derived fields and inverses of those entries lead to, each the way that build
  bakes it, but for the terms among its defaults and constraints, which are serialized (see
  `Hologram.Runtime.Serializer`) where the runtime script spells them as JavaScript.

  What a server sends a client whose bundle was built with other rules but the same model, so it
  answers permission checks the way the server does without reloading. A whole entry rather than
  its rules alone, because rules a deploy added can read a type the client's bundle never held, and
  a derived field it redefined can lead to one. A type left out of the checked ones declares no
  rule and no role, which is the server's own default deny.
  """
  @spec render_rules(list(module)) :: String.t()
  def render_rules(entity_types) do
    entity_types
    |> checked_entity_types()
    |> put_grant_type(entity_types)
    |> rules_entity_types()
    |> Enum.sort()
    |> Enum.map(fn entity_type ->
      entry =
        entity_type
        |> entity_model_members(&Serializer.serialize!/1)
        |> render_json_object()

      {Codec.encode_enum_value(entity_type), entry}
    end)
    |> render_json_object()
  end

  @doc """
  Resolves the definition of every derived field of the given entity types: natively when the
  field's function calls no query builder (see
  `Hologram.Entity.Derived.resolve/2`), and by walking its IR, from the given IR PLT, when it does
  (see `Hologram.Compiler.QueryExtractor.derived_definition/3`).

  Raises Hologram.CompileError, located at the field's declaration or where the walk stood, when a
  definition cannot be built.
  """
  @spec resolve_derived_definitions([module], PLT.t()) :: derived_definitions
  def resolve_derived_definitions(entity_types, ir_plt) do
    resolved =
      for entity_type <- Enum.sort(entity_types),
          {name, _type, _opts} <- entity_type.__derived__() do
        resolve_derived_definition(entity_type, name, ir_plt)
      end

    read_modules =
      resolved
      |> Enum.flat_map(fn {_key, _definition, field_read_modules} -> field_read_modules end)
      |> Enum.uniq()
      |> Enum.sort()

    %{
      definitions:
        Map.new(resolved, fn {key, definition, _read_modules} -> {key, definition} end),
      read_modules: read_modules
    }
  end

  @doc """
  Puts back the entries a `patch_module_info_plt!/5` call replaced or removed in the given module
  info PLT, and deletes the ones it added: the PLT is as it was before that call.
  """
  @spec restore_module_infos(PLT.t(), %{module => map | nil}) :: PLT.t()
  def restore_module_infos(module_info_plt, previous_infos) do
    Enum.each(previous_infos, fn
      {module, nil} -> PLT.delete(module_info_plt, module)
      {module, info} -> PLT.put(module_info_plt, module, info)
    end)

    module_info_plt
  end

  @doc """
  Whether the runtime bundle must be rebuilt because its inputs differ from the ones the kept runtime
  state was built from: its MFAs, the JS import modules it registers (which every page bundle leaves
  out) and the application versions it carries. True when there is no kept state.
  """
  @spec runtime_changed?(map | nil, [mfa], MapSet.t(module), keyword(String.t())) :: boolean
  def runtime_changed?(kept_runtime, runtime_mfas, js_binding_modules, app_versions)

  def runtime_changed?(nil, _runtime_mfas, _js_binding_modules, _app_versions), do: true

  def runtime_changed?(kept_runtime, runtime_mfas, js_binding_modules, app_versions) do
    kept_runtime.mfas != runtime_mfas or
      kept_runtime.js_binding_modules != js_binding_modules or
      kept_runtime.app_versions != app_versions
  end

  @doc """
  Keeps only those IR expressions that are function definitions of the given reachable MFAs of
  the module. For protocol modules, additionally drops the consolidated impl_for/1 and
  struct_impl_for/1 clauses that return implementations not among the given reachable modules.
  Which modules are protocols and implementations is answered from the given module info PLT
  (nil to ask the modules), so no module is loaded to prune a dispatcher.
  """
  @spec prune_module_def(IR.ModuleDefinition.t(), list(mfa), MapSet.t(module), PLT.t() | nil) ::
          IR.ModuleDefinition.t()
  def prune_module_def(module_def_ir, module_mfas, reachable_modules, module_info_plt) do
    module = module_def_ir.module.value
    module_mfas = MapSet.new(module_mfas)

    function_defs =
      module_def_ir.body.expressions
      |> Enum.filter(fn
        %IR.FunctionDefinition{name: function, arity: arity} ->
          MapSet.member?(module_mfas, {module, function, arity})

        _fallback ->
          false
      end)
      |> maybe_prune_protocol_dispatcher_function_defs(module, reachable_modules, module_info_plt)

    %IR.ModuleDefinition{
      module: module_def_ir.module,
      body: %IR.Block{expressions: function_defs}
    }
  end

  @doc """
  Refuses an entity operation the build asks about that is neither a framework operation nor a
  name some allow line carries, or returns :ok.

  Every literal ask `operation_asks/3` reads is judged against the build's whole vocabulary - the
  framework's operations and every name an allow line on any of the given entity types carries -
  because the entity argument's type is not known at the ask. A role tuple's role has to be one
  some entity type declares, and every field an `{:update, field}` or `{:update, fields}` tuple
  names a field some entity type's update sets (`Hologram.Policy.update_fields/1`). A computed
  operation passes here and is judged at run time, by `Hologram.Policy.validate_operation!/2` and
  its client twin, which know the type.

  Raises Hologram.CompileError naming the ask's function and line, the operation, and what the
  build does declare - so a typo or a renamed operation fails the build at the line that asks,
  rather than answering no forever as if the rules had been consulted.

  The opts go to `operation_asks/3`: with `:modules`, only the asks of those modules' callers are
  judged.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/validate_operations!_4/README.md
  """
  @spec validate_operations!(list(module), CallGraph.t(), PLT.t(), T.opts()) :: :ok
  def validate_operations!(entity_types, call_graph, ir_plt, opts \\ []) do
    # Seeded with the framework's own rather than left to the types to carry: every type's
    # operations include them, but an app with NO entity type contributes nothing at all, and the
    # framework's own asks (Diff.carried/2 asks :read) are in every build's call graph.
    vocabulary =
      entity_types
      |> Enum.flat_map(&Policy.operations/1)
      |> Enum.concat(Policy.framework_operations())
      |> Enum.uniq()
      |> Enum.sort()

    role_names =
      entity_types
      |> Enum.flat_map(&Keyword.keys(&1.__roles__()))
      |> Enum.uniq()
      |> Enum.sort()

    field_names =
      entity_types
      |> Enum.flat_map(&Policy.update_fields/1)
      |> MapSet.new()

    declared = %{field_names: field_names, role_names: role_names, vocabulary: vocabulary}

    call_graph
    |> operation_asks(ir_plt, opts)
    |> Enum.each(&validate_operation_ask!(&1, declared))
  end

  @doc """
  Whether the bundle the given bundle info describes can still be served from the given static dir:
  it was written there, and the bundle, its gzip copy and its source map are all on disk. The info
  names one static dir, so reusing it for another, like the one the bundles moved to from the app's
  static dir, would put a digest into that dir's page digest PLT whose file lives elsewhere.
  """
  @spec usable_bundle?(map, T.file_path()) :: boolean
  def usable_bundle?(bundle_info, static_dir) do
    bundle_path = bundle_info.static_bundle_path
    gzip_path = gzip_path(bundle_path)

    Path.dirname(bundle_path) == static_dir and
      File.exists?(bundle_path) and
      File.exists?(gzip_path) and
      File.exists?(bundle_info.static_source_map_path)
  end

  @doc """
  Raises a compilation error if any page module lacks a specified route or layout, or has a route that
  is not a string. The route and the layout come from the pages' entries in the given module info PLT;
  a page is asked only for what its entry does not hold (a route built at runtime, say).

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/validate_page_modules_2/README.md
  """
  @spec validate_page_modules(list(module), PLT.t()) :: :ok
  def validate_page_modules(page_modules, module_info_plt) do
    Enum.each(page_modules, fn page_module ->
      info = PLT.get!(module_info_plt, page_module)
      validate_page_route(page_module, info.route)
      validate_page_layout(page_module, info.layout_module)
    end)
  end

  @doc """
  Raises a compilation error if a template uses a component without one of its required props.

  Only usages the compiler can decide are checked. A usage carrying a `...{expr}` spread is skipped,
  since any prop could be in the spread, and so is a prop declared with `:from_context`, which is
  never written at the usage. Those cases, along with dynamic tags, are left to the renderers.

  Modules missing from the IR PLT are skipped - a module without a BEAM source has no IR to walk.

  Returns, for each given module, the modules its template uses as components, whether or not they
  are components: with its own template, all its result depends on (see
  `list_templatables_to_validate/3`). A skipped module uses none.
  """
  @spec validate_prop_usages(list(module), PLT.t()) :: %{module => MapSet.t(module)}
  def validate_prop_usages(modules, ir_plt) do
    Map.new(modules, fn module ->
      usages =
        case PLT.get(ir_plt, module) do
          {:ok, ir} -> validate_module_prop_usages(module, ir)
          :error -> []
        end

      used_modules =
        MapSet.new(usages, fn {component_module, _prop_entries, _has_spread?} ->
          component_module
        end)

      {module, used_modules}
    end)
  end

  defp ask_location(%{mfa: {module, function, arity}, line: nil}) do
    "#{inspect(module)}.#{function}/#{arity}"
  end

  defp ask_location(%{line: line} = ask) do
    "#{ask_location(%{ask | line: nil})} (line #{line})"
  end

  defp caller_operation_asks({module, function, arity} = mfa, ir_plt) do
    case PLT.get(ir_plt, module) do
      {:ok, %IR.ModuleDefinition{body: %IR.Block{expressions: expressions}}} ->
        expressions
        |> Enum.filter(&match?(%IR.FunctionDefinition{name: ^function, arity: ^arity}, &1))
        |> Enum.flat_map(&collect_operation_asks(&1.clause.body, mfa, []))
        |> Enum.reverse()

      _fallback ->
        []
    end
  end

  # A call of one of the asks records the operation it names and is walked into as well - the
  # args of one call can hold another. Everything else is walked the way collect_component_usages
  # walks: lists, maps (structs included), tuples, and nothing else.
  defp collect_operation_asks(
         %IR.RemoteFunctionCall{
           module: %IR.AtomType{value: module},
           function: function,
           args: args,
           line: line
         } = call,
         mfa,
         acc
       ) do
    case Map.fetch(@operation_asks, {module, function, length(args)}) do
      {:ok, position} ->
        operation =
          args
          |> Enum.at(position)
          |> literal_operation()

        collect_operation_asks(args, mfa, [%{line: line, mfa: mfa, operation: operation} | acc])

      :error ->
        collect_operation_asks(Map.from_struct(call), mfa, acc)
    end
  end

  defp collect_operation_asks(list, mfa, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_operation_asks(&1, mfa, &2))
  end

  defp collect_operation_asks(map, mfa, acc) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.reduce(acc, fn {key, value}, key_acc ->
      collect_operation_asks(value, mfa, collect_operation_asks(key, mfa, key_acc))
    end)
  end

  defp collect_operation_asks(tuple, mfa, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(acc, &collect_operation_asks(&1, mfa, &2))
  end

  defp collect_operation_asks(_ir, _mfa, acc), do: acc

  # What each MFA the given pages reach writes, keyed by MFA: the atom literals it spells and the
  # query chains it writes (see Hologram.Compiler.QueryChains) - for every function but Elixir's and
  # Hologram's (see build_kept_page_reach/4), each read once however many pages reach it. The IR of
  # their modules is built into the PLT first, in one go. Module aliases are left out of the atoms:
  # they name modules, which the pages' reach already lists, and no relationship or derived field.
  defp read_by_mfa(reach_by_page, module_info_plt, ir_plt) do
    elixir_lib_dir = elixir_lib_dir()

    mfas_by_module =
      reach_by_page
      |> Enum.flat_map(fn {_page_module, reach} -> reach.mfas end)
      |> Enum.uniq()
      |> Enum.group_by(fn {module, _function, _arity} -> module end)
      |> Enum.filter(fn {module, _mfas} ->
        PLT.member?(module_info_plt, module) and app_module?(module, elixir_lib_dir)
      end)

    build_missing_ir!(ir_plt, Enum.map(mfas_by_module, fn {module, _mfas} -> module end))

    mfas_by_module
    |> Enum.flat_map(fn {module, module_mfas} ->
      funs = module_funs(ir_plt, module)

      # An entity type's and an Ecto schema's generated functions name every relationship, field
      # and derived field they declare. A component's or a page's hold what the app wrote, its prop
      # and state defaults among them, so they are read like the rest of its code.
      declares_model? =
        Reflection.entity?(module, module_info_plt) or
          Reflection.ecto_schema?(module, module_info_plt)

      module_mfas
      |> Enum.reject(fn {_module, function, _arity} ->
        declares_model? and generated?(function)
      end)
      |> Enum.map(fn {_module, function, arity} = mfa ->
        {_visibility, clauses} = Map.get(funs, {function, arity}, {:public, []})

        atoms =
          clauses
          |> collect_atoms(MapSet.new())
          |> MapSet.reject(&Reflection.alias?/1)

        {mfa, %{atoms: atoms, chains: QueryChains.collect(clauses, mfa)}}
      end)
    end)
    |> Map.new()
  end

  # The functions of the given module the IR PLT holds, by name and arity, or none for a module it
  # doesn't hold.
  defp module_funs(ir_plt, module) do
    case PLT.get(ir_plt, module) do
      {:ok, ir} ->
        ir
        |> IR.aggregate_module_funs()
        |> Map.new()

      :error ->
        %{}
    end
  end

  # Every atom literal in the given IR - lists, maps (structs included) and tuples walked, as
  # collect_operation_asks walks them.
  defp collect_atoms(%IR.AtomType{value: value}, acc), do: MapSet.put(acc, value)

  defp collect_atoms(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_atoms/2)

  defp collect_atoms(map, acc) when is_map(map) do
    map
    |> Map.values()
    |> collect_atoms(acc)
  end

  defp collect_atoms(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> collect_atoms(acc)
  end

  defp collect_atoms(_ir, acc), do: acc

  # The IR of the callers the module info PLT holds, built into the IR PLT when it lacks it. A graph
  # without a module info PLT (a test's) has nothing to build from, and the IR PLT is read as it is.
  defp build_caller_ir!(_callers, nil, _ir_plt), do: :ok

  defp build_caller_ir!(callers, module_info_plt, ir_plt) do
    callers
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Enum.filter(&PLT.member?(module_info_plt, &1))
    |> then(&build_missing_ir!(ir_plt, &1))
  end

  # The type of each row a chain of relationships from a row of the given type passes through, its
  # end included.
  defp chain_types(entity_type, chain) do
    for length <- 1..length(chain)//1,
        do: Entity.path_target(entity_type, Enum.take(chain, length))
  end

  # The types the rows an edge names are of: a related row's, a set's rows, and for pairs both the
  # type storing them and the rows they put into the set, the type the chain leads to - and every
  # row the chain passes through, which a client follows it through.
  defp edge_entity_types(checked_type, {:set_edges, chain, entity_type, _relationship_names}) do
    [entity_type | chain_types(checked_type, chain)]
  end

  defp edge_entity_types(checked_type, {kind, chain, entity_type, _names})
       when kind in [:relationship_attributes, :relationship_grants, :set_attributes],
       do: [entity_type | chain_types(checked_type, chain)]

  defp edge_entity_types(_checked_type, _edge), do: []

  # The type of the rows of the set a quantifier's source leads to, from the row it is read on - the
  # row the quantifier is about, the nearest of the given types, or the row that many out.
  defp quantified_type({:outer, levels, hops}, types) do
    types
    |> Enum.at(levels)
    |> Derived.path_target(hops)
  end

  defp quantified_type(hops, [entity_type | _types_above]),
    do: Derived.path_target(entity_type, hops)

  # Whether the given role reference, as {:to, reference}, or delegation, as {:via, via}, of a rule
  # is one the client can't decide, which it answers as unknown, leaving the rule to the server's
  # verdict on the operation.
  defp deciding_item?(item, {entity_type, operation}) do
    Policy.deciding_quantifier?(entity_type, operation, item)
  end

  # The needs of the given term under the read rules of a signed-in session and of an anonymous one.
  defp policied_needs(term, mapping) do
    rules =
      term.entity
      |> Policy.build()
      |> Map.get(:read, [])

    Enum.flat_map([false, true], fn anonymous? ->
      IndexPlan.needs(term, mapping, %{anonymous?: anonymous?, rules: rules})
    end)
  end

  defp resolve_derived_definition(entity_type, name, ir_plt) do
    if name in entity_type.__derived_builder_calls__() do
      {definition, read_modules} = QueryExtractor.derived_definition(entity_type, name, ir_plt)

      {{entity_type, name}, definition, read_modules}
    else
      {{entity_type, name}, Derived.resolve(entity_type, name), []}
    end
  end

  # The callers among the given modules, or every caller when no modules are given.
  defp scope_callers(callers, nil), do: callers

  defp scope_callers(callers, modules) do
    module_set = MapSet.new(modules)
    Enum.filter(callers, fn {module, _function, _arity} -> MapSet.member?(module_set, module) end)
  end

  # A literal atom, a literal {name, role} tuple of atoms, or a literal {:update, fields} tuple
  # whose list holds only atoms is read; anything else is computed. A list is read only under
  # :update - can? refuses one naming roles whatever it holds, so a role list is left to it.
  defp literal_operation(%IR.AtomType{value: operation}), do: operation

  defp literal_operation(%IR.TupleType{
         data: [%IR.AtomType{value: name}, %IR.AtomType{value: role_name}]
       }),
       do: {name, role_name}

  defp literal_operation(%IR.TupleType{
         data: [%IR.AtomType{value: :update}, %IR.ListType{data: field_irs}]
       }) do
    if Enum.all?(field_irs, &match?(%IR.AtomType{}, &1)) do
      {:update, Enum.map(field_irs, & &1.value)}
    else
      {:dynamic}
    end
  end

  defp literal_operation(_ir), do: {:dynamic}

  # One branch of a block renders, so an atom ref counts as often as the branch that renders it the
  # most times. The other branches' refs still name refs the page can render, so they stay for the
  # part-count check and the names, uncounted. A tie goes to the branch whose occurrences come first
  # in term order, which doesn't depend on the order the clauses were written in.
  defp alternative_ref_occurrences(branches) do
    # Names the block, so two refs can be told to be in separate blocks rather than one, and in
    # which of its branches each one is.
    block = System.unique_integer()

    occurrences =
      branches
      |> Enum.with_index()
      |> Enum.flat_map(fn {branch, index} -> Enum.map(branch, &{index, &1}) end)

    counted_branch_by_name =
      occurrences
      |> Enum.filter(fn {_index, occurrence} -> counted_atom_ref?(occurrence) end)
      |> Enum.group_by(fn {_index, occurrence} -> occurrence.name end)
      |> Map.new(fn {name, named} ->
        {index, _paths} =
          named
          |> Enum.group_by(fn {index, _occurrence} -> index end, fn {_index, occurrence} ->
            occurrence.path
          end)
          |> Enum.min_by(fn {_index, paths} -> {-length(paths), paths} end)

        {name, index}
      end)

    Enum.map(occurrences, fn {index, occurrence} ->
      counted? =
        occurrence.counted? and
          (occurrence.part_count > 0 or counted_branch_by_name[occurrence.name] == index)

      %{occurrence | blocks: [{block, index} | occurrence.blocks], counted?: counted?}
    end)
  end

  # Branches only one of which renders, in clause order. A branch that declares nothing adds nothing
  # to what the others do, so it is dropped, but a block with one branch left stays a block: two
  # blocks that may both render are told apart from refs that always render together.
  defp alternative_refs(branches) do
    case Enum.reject(branches, &(&1 == {:seq, []})) do
      [] -> {:seq, []}
      branches -> {:alt, branches}
    end
  end

  defp atom_ref_advice(name) do
    "an atom ref names one element, so give each element a ref of its own, " <>
      "like {#{inspect(name)}, item.id} for the items of a loop"
  end

  # Builds the IR of the given modules into the IR PLT, then the modules into the call graph.
  defp build_graph_modules!(call_graph, ir_plt, modules) do
    build_missing_ir!(ir_plt, modules)
    TaskUtils.map_concurrently(modules, &CallGraph.build_for_module(call_graph, ir_plt, &1))
  end

  # The digest of a bundle: the content hash esbuild put behind the given name in its file name.
  defp bundle_digest(bundle_file_name, output_name) do
    bundle_file_name
    |> Path.basename(".js")
    |> String.replace_prefix("#{output_name}-", "")
  end

  # The name of a bundle's output dir in the tmp dir, one per entry.
  defp bundle_output_dir_name(bundle_name, entry_name) when is_binary(entry_name) do
    "#{bundle_name}-#{entry_name}"
  end

  defp bundle_output_dir_name(bundle_name, entry_name) do
    bundle_output_name(bundle_name, entry_name)
  end

  # The name esbuild puts in front of the hash in a bundle's file name. An entry name, a module,
  # tells apart the entries bundled under one bundle name (the pages), so it goes into the file
  # name, without its Elixir prefix like the entry file name; a bundle name with a single entry (the
  # runtime) has none.
  defp bundle_output_name(bundle_name, entry_name)
       when is_nil(entry_name) or is_binary(entry_name) do
    bundle_name
  end

  defp bundle_output_name(bundle_name, entry_name) do
    "#{bundle_name}-#{Reflection.module_name(entry_name)}"
  end

  # The entry point arguments esbuild is given for the given chunk entries: every chunk's bundle is
  # named by the bundle name and its content hash alone (see bundle/4).
  defp chunk_entry_args(entries) do
    Enum.map(entries, fn {_entry_name, entry_file_path} -> "chunk=#{entry_file_path}" end)
  end

  # The options a chunk's script is rendered with, from the options the chunk functions take.
  defp chunk_script_opts(opts) do
    [
      js_dir: opts[:js_dir],
      module_info_plt: opts[:module_info_plt],
      module_metadata: opts[:module_metadata],
      runtime_js_binding_modules: opts[:runtime_js_binding_modules] || MapSet.new()
    ]
  end

  # The length of the command line esbuild is started with for the given chunk entries (see
  # bundle_chunks/2), counted generously: each argument with a space and the quotes Windows can put
  # around it, and the `cmd /c` the launcher is run through there.
  defp chunks_command_length([{first_entry_name, _entry_file_path} | _rest] = entries, opts) do
    output_dir = chunks_output_dir(first_entry_name, opts)

    args =
      entries
      |> chunk_entry_args()
      |> esbuild_args(output_dir)

    ["cmd", "/c", opts[:esbuild_bin_path] | args]
    |> Enum.map(&(String.length(&1) + 3))
    |> Enum.sum()
  end

  # The output dir of the chunks bundled in one esbuild process, named by the first one's entry name.
  defp chunks_output_dir(first_entry_name, opts) do
    Path.join(opts[:tmp_dir], "#{bundle_output_dir_name("chunk", first_entry_name)}.output")
  end

  # The files esbuild read for the bundle of an entry point, as the given inputs of its metafile
  # name them: the given files and what they import, directly or through the files they import.
  # What the metafile lists under an output is not that: it leaves out a file none of whose bytes
  # are in the output, such as one that only gave a constant esbuild wrote in place. An import
  # esbuild did not read (an external one) is no input and is passed over.
  defp collect_esbuild_input_paths([], _inputs, acc), do: acc

  defp collect_esbuild_input_paths([path | rest], inputs, acc) do
    if path in acc or not is_map_key(inputs, path) do
      collect_esbuild_input_paths(rest, inputs, acc)
    else
      imported_paths = Enum.map(inputs[path]["imports"], & &1["path"])

      collect_esbuild_input_paths(imported_paths ++ rest, inputs, [path | acc])
    end
  end

  # A component node is a 4-element tuple whose first element is the :component atom and whose
  # second is the component module, already resolved by the time the template AST becomes IR. A
  # dynamic tag carries :dynamic_tag instead and never matches, which is what leaves it out.
  # Props and children are walked as well - props hold expressions, children hold nested usages.
  defp collect_component_usages(
         %IR.TupleType{
           data: [
             %IR.AtomType{value: :component},
             %IR.AtomType{value: component_module},
             %IR.ListType{data: props},
             %IR.ListType{data: children}
           ]
         },
         acc
       ) do
    usage = {component_module, prop_entries(props), has_spread?(props)}

    collect_component_usages(children, collect_component_usages(props, [usage | acc]))
  end

  defp collect_component_usages(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_component_usages/2)
  end

  # Structs are maps too, so this walks every IR node's fields without naming any of them.
  defp collect_component_usages(map, acc) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.reduce(acc, fn {key, value}, key_acc ->
      collect_component_usages(value, collect_component_usages(key, key_acc))
    end)
  end

  defp collect_component_usages(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(acc, &collect_component_usages/2)
  end

  defp collect_component_usages(_ir, acc), do: acc

  # A node of the template's DOM: an element or dynamic tag, whose $ref comes before the refs of its
  # children, or a component, which renders its own template's refs before its slot content.
  defp collect_template_refs(%IR.TupleType{
         data: [
           %IR.AtomType{value: node_type},
           _name,
           %IR.ListType{data: attrs},
           children
         ]
       })
       when node_type in [:element, :dynamic_tag] do
    sequence_refs([literal_ref(attrs), collect_template_refs(children)])
  end

  defp collect_template_refs(%IR.TupleType{
         data: [
           %IR.AtomType{value: :component},
           %IR.AtomType{value: module},
           %IR.ListType{},
           children
         ]
       }) do
    sequence_refs([{:component, module}, collect_template_refs(children)])
  end

  # {%if} and {%else} expand to a case, and only one of its clauses renders.
  defp collect_template_refs(%IR.Case{clauses: clauses}) do
    clauses
    |> Enum.map(&collect_template_refs(&1.body))
    |> alternative_refs()
  end

  defp collect_template_refs(%IR.Cond{clauses: clauses}) do
    clauses
    |> Enum.map(&collect_template_refs(&1.body))
    |> alternative_refs()
  end

  # A {%for} is a comprehension, whose body renders once per item.
  defp collect_template_refs(%IR.Comprehension{mapper: mapper}) do
    case collect_template_refs(mapper) do
      {:seq, []} -> {:seq, []}
      refs -> {:loop, refs}
    end
  end

  defp collect_template_refs(list) when is_list(list) do
    list
    |> Enum.map(&collect_template_refs/1)
    |> sequence_refs()
  end

  # Structs are maps too, so this walks every IR node's fields without naming any of them.
  defp collect_template_refs(map) when is_map(map) do
    map
    |> Map.values()
    |> collect_template_refs()
  end

  defp collect_template_refs(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> collect_template_refs()
  end

  defp collect_template_refs(_ir), do: {:seq, []}

  defp component_usage_error!(component_module, name, module) do
    raise Hologram.CompileError,
      message:
        "component #{Reflection.module_name(component_module)} is missing required prop " <>
          ~s/"#{name}" in #{Reflection.module_name(module)}'s template/
  end

  defp component_value_error!(component_module, {name, value, values}, module) do
    raise Hologram.CompileError,
      message:
        ~s/prop "#{name}" of component #{Reflection.module_name(component_module)} must be one of / <>
          "#{inspect(values)}, got: #{inspect(value)}, " <>
          "in #{Reflection.module_name(module)}'s template"
  end

  # A cover-compiled module (coverage runs) is loaded from instrumented code, but its beam still
  # lives on disk in the code path. Its path is returned rather than its binary, so the module is
  # read, stat-ed and digested as any other.
  defp cover_compiled_beam_path(module) do
    case :code.get_object_code(module) do
      {^module, _binary, beam_path} -> beam_path
      :error -> nil
    end
  end

  defp counted_atom_ref?(occurrence), do: occurrence.counted? and occurrence.part_count == 0

  defp create_entry_file(js, entry_name, tmp_dir) do
    entry_file_path = Path.join(tmp_dir, "#{entry_name}.entry.js")
    File.write!(entry_file_path, js)

    entry_file_path
  end

  # A dump written by an older Hologram can hold entries without the keys added since. Fetched
  # dependencies lose their build dir, dumps included, when Mix recompiles them, but a path
  # dependency or the project itself keeps it, so the entry is checked rather than trusted.
  defp current_module_info?(info) do
    Enum.all?(Reflection.beam_info_keys(), &Map.has_key?(info, &1))
  end

  defp digest_js_input(path) do
    case File.read(path) do
      {:ok, content} -> {:digest, :erlang.phash2(content)}
      {:error, _reason} -> :missing
    end
  end

  defp edited_module?(old_infos, module, digest) do
    match?(%{digest: old_digest} when old_digest != digest, old_infos[module])
  end

  # The module IR is read once here however many functions are missing. A later entry file that
  # needs a function this one did not reads it again, so a module is copied out of the IR PLT
  # once per entry file that finds one of its functions missing, not once per compile. A function
  # the module does not define is stored as nil.
  defp encode_missing_module_functions(fun_arities, module, ir_plt, encode_plt, context) do
    module_name = Reflection.module_name(module)

    # Read outside the rescue below, so a module absent from the IR PLT raises the KeyError it
    # always did rather than being reported as an encoding failure.
    funs =
      ir_plt
      |> PLT.get!(module)
      |> IR.aggregate_module_funs()
      |> Map.new()

    try do
      Enum.each(fun_arities, fn {function, arity} = key ->
        case funs do
          %{^key => {visibility, clauses}} ->
            js =
              Encoder.encode_elixir_function(
                module_name,
                function,
                arity,
                visibility,
                clauses,
                context
              )

            PLT.put(encode_plt, {module, function, arity}, js)

          # Remembered as defining nothing, so later entry files that reach it do not read the
          # module again.
          _no_definition ->
            PLT.put(encode_plt, {module, function, arity}, nil)
        end
      end)
    rescue
      error ->
        message =
          StringUtils.normalize_newlines("""
          can't encode #{module_name} module definition
          #{Exception.message(error)}\
          """)

        reraise RuntimeError, [message: message], __STACKTRACE__
    end
  end

  defp encode_module_function_defs(fun_arities, module, ir_plt, encode_plt, context) do
    missing = Enum.reject(fun_arities, &function_encoded?(encode_plt, module, &1))

    if missing != [] do
      encode_missing_module_functions(missing, module, ir_plt, encode_plt, context)
    end

    Enum.flat_map(fun_arities, fn {function, arity} ->
      case PLT.get(encode_plt, {module, function, arity}) do
        # A reachable MFA with no definition in the module IR renders nothing, which is what
        # prune_module_def/4 does with it.
        {:ok, nil} ->
          []

        {:ok, js} ->
          [js]

        # Unreachable once the missing functions are encoded; kept so an entry without a value
        # renders nothing.
        :error ->
          []
      end
    end)
  end

  # The arguments esbuild is run with for the given entry points, each given as `<name>=<path>`: a
  # bundle and its source map per entry point, named `<name>-<hash>`, in the given output dir, and
  # a metafile there that lists what was read and written.
  defp esbuild_args(entry_args, output_dir) do
    entry_args ++
      [
        "--bundle",
        "--entry-names=[name]-[hash]",
        "--log-level=warning",
        "--metafile=#{Path.join(output_dir, "meta.json")}",
        "--minify",
        "--outdir=#{output_dir}",
        "--sourcemap",
        "--sources-content=true",
        "--target=es2021"
      ]
  end

  # The refs a component renders, each with the path of templates it is reached through, starting
  # with the component's own. Templates that render one another, or one that renders itself, are
  # evaluated together (see evaluate_cycle_refs/3).
  defp evaluate_component_refs(module, context, memo) do
    cond do
      Map.has_key?(memo, module) ->
        {memo[module], memo}

      not Map.has_key?(context.summaries, module) ->
        {[], memo}

      Map.has_key?(context.cycles, module) ->
        cycle_memo = evaluate_cycle_refs(context.cycles[module], context, memo)
        {cycle_memo[module], cycle_memo}

      true ->
        {occurrences, refs_memo} =
          evaluate_refs(context.summaries[module], module, context, [], memo)

        {occurrences, Map.put(refs_memo, module, occurrences)}
    end
  end

  # Once the recursion goes a level deep, each template of a cycle renders the others and itself
  # through them, so a ref that renders next to the usage that recurses repeats like a loop's. One in
  # a branch the usage isn't in, like a list's end marker, renders at one level only. A usage of a
  # template of the same cycle adds nothing on the spot: each template renders what all of them
  # declare, which takes one pass over the cycle whatever its shape.
  defp evaluate_cycle_refs(cycle, context, memo) do
    {own_refs, own_memo} =
      Enum.map_reduce(cycle.members, memo, fn member, acc_memo ->
        {occurrences, refs_memo} =
          evaluate_refs(context.summaries[member], member, context, cycle.members, acc_memo)

        {usages, refs} = Enum.split_with(occurrences, & &1.cycle_usage?)
        loop = {:recursion, member, context.cycles[member].through}

        {{member, Enum.map(refs, &put_recursion_loop(&1, usages, loop))}, refs_memo}
      end)

    Enum.reduce(own_refs, own_memo, fn {member, occurrences}, acc_memo ->
      others =
        for {other, other_occurrences} <- own_refs,
            other != member,
            occurrence <- other_occurrences do
          %{
            occurrence
            | path: Enum.drop(context.cycles[member].paths[other], -1) ++ occurrence.path
          }
        end

      Map.put(acc_memo, member, occurrences ++ others)
    end)
  end

  defp evaluate_ref_parts(parts, module, context, cycle, memo) do
    Enum.map_reduce(parts, memo, &evaluate_refs(&1, module, context, cycle, &2))
  end

  defp evaluate_refs({:ref, name, part_count}, module, _context, _cycle, memo) do
    occurrence = %{
      blocks: [],
      counted?: true,
      cycle_usage?: false,
      part_count: part_count,
      loop: nil,
      name: name,
      path: [module]
    }

    {[occurrence], memo}
  end

  # A usage of a template of the cycle being evaluated is kept as a marker, so the cycle's
  # evaluation can tell which refs render next to it.
  defp evaluate_refs({:component, component_module}, module, context, cycle, memo) do
    if component_module in cycle do
      usage = %{blocks: [], counted?: false, cycle_usage?: true, path: [module]}
      {[usage], memo}
    else
      {occurrences, component_memo} =
        evaluate_component_refs(component_module, context, memo)

      {Enum.map(occurrences, &%{&1 | path: [module | &1.path]}), component_memo}
    end
  end

  defp evaluate_refs({:seq, parts}, module, context, cycle, memo) do
    {results, parts_memo} = evaluate_ref_parts(parts, module, context, cycle, memo)
    {Enum.concat(results), parts_memo}
  end

  defp evaluate_refs({:alt, branches}, module, context, cycle, memo) do
    {results, branches_memo} = evaluate_ref_parts(branches, module, context, cycle, memo)
    {alternative_ref_occurrences(results), branches_memo}
  end

  defp evaluate_refs({:loop, body}, module, context, cycle, memo) do
    {occurrences, body_memo} = evaluate_refs(body, module, context, cycle, memo)
    {Enum.map(occurrences, &put_ref_loop(&1, {:for, module})), body_memo}
  end

  defp extract_erlang_function_js(file_path, function, arity) do
    key = "#{function}/#{arity}"
    start_marker = "// Start #{key}"
    end_marker = "// End #{key}"

    # Matches: start_marker, optional // comment lines, "key": <captured body>, end_marker
    regex =
      ~r/#{Regex.escape(start_marker)}\s+(?:\/\/[^\n]*\s+)*"#{Regex.escape(key)}":\s+(.+),\s+#{Regex.escape(end_marker)}/s

    file_contents = File.read!(file_path)

    case Regex.run(regex, file_contents) do
      [_full_capture, js] -> js
      nil -> nil
    end
  end

  defp fetch_optional_runtime_subsystem!(key) do
    case Keyword.fetch(@optional_runtime_subsystems, key) do
      {:ok, subsystem} ->
        subsystem

      :error ->
        raise ArgumentError, "unknown optional runtime subsystem: #{inspect(key)}"
    end
  end

  # The IR PLT answers for every module it holds, so a module the compiler knows never costs a
  # code path lookup here, however many MFAs of it the list has.
  defp filter_elixir_mfas(mfas, ir_plt) do
    Enum.filter(mfas, fn {module, _function, _arity} ->
      Reflection.elixir_module?(module, ir_plt)
    end)
  end

  defp filter_erlang_mfas(mfas, ir_plt) do
    Enum.filter(mfas, fn {module, _function, _arity} ->
      Reflection.erlang_module?(module, ir_plt)
    end)
  end

  defp fingerprint_js_input(path, started_at) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} when is_integer(started_at) and mtime >= started_at ->
        :fresh

      {:ok, %File.Stat{mtime: mtime, size: size}} ->
        if "node_modules" in Path.split(path) do
          {:stat, mtime, size}
        else
          digest_js_input(path)
        end

      {:error, _reason} ->
        :missing
    end
  end

  # Merges the chunk of the given signature into its target (see fold_target/2), when it is still
  # under the bound with what was folded into it and has one.
  defp fold_small_chunk(signature, {mfas_by_signature, size_by_signature} = acc) do
    size = Map.fetch!(size_by_signature, signature)
    target = fold_target(signature, Map.keys(mfas_by_signature))

    if size < @chunk_fold_bound and target do
      {mfas, remaining_mfas_by_signature} = Map.pop!(mfas_by_signature, signature)

      {
        Map.update!(remaining_mfas_by_signature, target, &Enum.sort(&1 ++ mfas)),
        size_by_signature
        |> Map.delete(signature)
        |> Map.update!(target, &(&1 + size))
      }
    else
      acc
    end
  end

  # The signature a small chunk is folded into: its strict superset with the fewest types, the
  # first by its sorted types among several. Nil when no signature is a strict superset.
  defp fold_target(signature, signatures) do
    signatures
    |> Enum.filter(&(&1 != signature and MapSet.subset?(signature, &1)))
    |> Enum.min_by(&{MapSet.size(&1), Enum.sort(&1)}, fn -> nil end)
  end

  defp function_encoded?(encode_plt, module, {function, arity}) do
    PLT.member?(encode_plt, {module, function, arity})
  end

  defp get_module_info(plt, module) do
    case PLT.get(plt, module) do
      {:ok, info} -> info
      :error -> nil
    end
  end

  defp get_package_json_digest(assets_dir) do
    assets_dir
    |> Path.join("package.json")
    |> File.read!()
    |> CryptographicUtils.digest(:sha256, :binary)
  end

  # Splits the given chunk entries into the groups that one esbuild process each bundles (see
  # bundle_chunks/2): as few as the bound of the command line allows (see
  # @max_chunks_command_length), in the given order. An entry too long for the bound alone is a
  # group of its own.
  defp group_chunk_entries(entries, opts) do
    Enum.chunk_while(
      entries,
      [],
      # The group being filled is kept in reverse.
      fn entry, reversed_group ->
        extended_group = Enum.reverse([entry | reversed_group])

        if reversed_group == [] or
             chunks_command_length(extended_group, opts) <= @max_chunks_command_length do
          {:cont, [entry | reversed_group]}
        else
          {:cont, Enum.reverse(reversed_group), [entry]}
        end
      end,
      fn
        [] -> {:cont, []}
        reversed_group -> {:cont, Enum.reverse(reversed_group), []}
      end
    )
  end

  defp has_spread?(props) do
    Enum.any?(props, &match?(%IR.TupleType{data: [%IR.AtomType{value: :spread}, _expr]}, &1))
  end

  # Only props whose value is known without running anything are judged. The comparison needs no
  # type guard: nothing casts a prop to its declared type, so a text value stays the string it was
  # written as, and the renderers compare it against values: exactly the same way.
  defp invalid_prop_values(component_module, prop_entries) do
    values_by_name =
      component_module.__props__()
      |> Enum.flat_map(fn {name, _type, opts} ->
        if opts[:values], do: [{to_string(name), opts[:values]}], else: []
      end)
      |> Map.new()

    Enum.flat_map(prop_entries, fn
      {name, {:ok, value}} ->
        values = values_by_name[name]

        if values && value not in values, do: [{name, value, values}], else: []

      {_name, :unknown} ->
        []
    end)
  end

  defp included_protocol_implementations(reachable_modules, protocol, module_info_plt) do
    reachable_modules
    |> Enum.filter(&(Reflection.protocol_implementation(&1, module_info_plt) == protocol))
    |> MapSet.new()
  end

  # Only a clause naming the protocol's implementation for a built-in type can be dropped, when
  # that implementation is not in the bundle. An implementation is named after its protocol and its
  # type, so the ones for the built-in types are known without asking any module.
  defp keep_protocol_dispatcher_function_def?(
         %IR.FunctionDefinition{name: function, arity: 1, clause: clause},
         built_in_impl_names,
         included_impls
       )
       when function in [:impl_for, :struct_impl_for] do
    case clause do
      %IR.FunctionClause{body: %IR.Block{expressions: [%IR.AtomType{value: value}]}} ->
        not MapSet.member?(built_in_impl_names, Atom.to_string(value)) or
          MapSet.member?(included_impls, value)

      _clause ->
        true
    end
  end

  defp keep_protocol_dispatcher_function_def?(
         _function_def,
         _built_in_impl_names,
         _included_impls
       ),
       do: true

  # nil when the page must be rebuilt, its kept state otherwise.
  defp keepable_page_state(
         pages_plt,
         page_module,
         reaching_modules,
         js_fingerprints,
         pending_pages,
         static_dir
       ) do
    with false <- MapSet.member?(pending_pages, page_module),
         {:ok, page_state} <- PLT.get(pages_plt, page_module),
         true <- MapSet.disjoint?(page_state.modules, reaching_modules),
         false <- js_inputs_changed?(page_state.bundle_info.js_inputs, js_fingerprints),
         true <- usable_bundle?(page_state.bundle_info, static_dir) do
      page_state
    else
      _fallback -> nil
    end
  end

  # The files esbuild read for a bundle, given as its metafile lists them relative to the working
  # dir, with their fingerprints taken against the time esbuild started (see fingerprint_js_inputs/2).
  # The entry file (under the tmp dir), Hologram's own sources (under the js dir) and the packages
  # they use are left out: the bundle inputs cover those for every bundle at once (see
  # build_bundle_inputs/2). esbuild resolves a package from the importing file's dir upwards, so
  # Hologram's sources take theirs from the node_modules next to the js dir; the node_modules path
  # opt names the same dir in an app, and is left out too.
  defp list_bundle_js_inputs(input_paths, started_at, opts) do
    cwd = File.cwd!()

    hologram_node_modules_dir =
      if opts[:js_dir] do
        opts[:js_dir]
        |> Path.dirname()
        |> Path.join("node_modules")
      end

    left_out_dirs =
      [opts[:tmp_dir], opts[:js_dir], hologram_node_modules_dir, opts[:node_modules_path]]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Path.expand/1)

    input_paths
    |> Enum.map(&Path.expand(&1, cwd))
    |> Enum.reject(fn path -> Enum.any?(left_out_dirs, &(Path.relative_to(path, &1) != path)) end)
    |> fingerprint_js_inputs(started_at)
  end

  # Hologram's own modules that the module info PLT holds, with their digests, sorted: the modules of
  # the :hologram app whose source is in Hologram's lib dir, the dir the Hologram module itself was
  # compiled from. Hologram's own tests compile their fixtures into the :hologram app too, and an
  # edit of a fixture is an edit of an app module, not of Hologram.
  defp list_hologram_module_digests(module_info_plt) do
    Application.ensure_loaded(:hologram)

    lib_dir =
      :compile
      |> Hologram.module_info()
      |> Keyword.fetch!(:source)
      |> to_string()
      |> Path.dirname()

    digests =
      for module <- Application.spec(:hologram, :modules),
          {:ok, %{digest: digest, source_path: source_path}} <- [PLT.get(module_info_plt, module)],
          is_binary(source_path),
          Path.relative_to(source_path, lib_dir) != source_path do
        {module, digest}
      end

    Enum.sort(digests)
  end

  # Every regular file under the given dir, as its path relative to the dir with its mtime and size,
  # sorted.
  defp list_js_sources(js_dir) do
    js_dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case File.stat!(path, time: :posix) do
        %File.Stat{type: :regular, mtime: mtime, size: size} ->
          [{Path.relative_to(path, js_dir), mtime, size}]

        _directory ->
          []
      end
    end)
    |> Enum.sort()
  end

  # Filtered in the table, so no info is copied out of it.
  defp list_modules_where(module_info_plt, flag) do
    module_info_plt
    |> PLT.keys(%{flag => true})
    |> Enum.sort()
  end

  # The templates that render one another, directly or through others, each with its cycle: the
  # cycle's templates, sorted, the shortest chain of templates it renders each of the others through,
  # and the templates it renders itself through. A template that renders itself is a cycle of one.
  defp list_ref_cycles(summaries) do
    graph = :digraph.new()

    try do
      Enum.each(summaries, fn {module, _refs} -> :digraph.add_vertex(graph, module) end)

      Enum.each(summaries, fn {module, refs} ->
        refs
        |> template_ref_components()
        |> Enum.filter(&Map.has_key?(summaries, &1))
        |> Enum.each(&:digraph.add_edge(graph, module, &1))
      end)

      graph
      |> :digraph_utils.cyclic_strong_components()
      |> Enum.flat_map(fn component ->
        members = Enum.sort(component)

        Enum.map(members, fn member ->
          paths =
            for other <- members, other != member, into: %{} do
              {other, :digraph.get_short_path(graph, member, other)}
            end

          through =
            graph
            |> :digraph.get_short_cycle(member)
            |> Enum.drop(1)
            |> Enum.drop(-1)

          {member, %{members: members, paths: paths, through: through}}
        end)
      end)
      |> Map.new()
    after
      :digraph.delete(graph)
    end
  end

  # The modules of the given kind among the results of patch_module_info_plt_entry!/5, sorted.
  defp list_results(results, kind) do
    results
    |> Enum.flat_map(fn
      {^kind, module, _old_info} -> [module]
      _other -> []
    end)
    |> Enum.sort()
  end

  defp maybe_ensure_bundle_within_size_limit!("chunk", _entry_name, _bundle_path), do: :ok

  defp maybe_ensure_bundle_within_size_limit!(_bundle_name, entry_name, bundle_path) do
    max_bundle_size = Application.get_env(:hologram, :max_bundle_size)

    if max_bundle_size do
      bundle_size = File.stat!(bundle_path).size

      if bundle_size > max_bundle_size do
        raise RuntimeError,
          message: """
          Generated JavaScript bundle '#{entry_name}' is #{bundle_size} bytes, which exceeds the configured maximum of #{max_bundle_size} bytes.

          This limit acts as an early warning system to surface abnormally large bundles before they reach your app (e.g., accidentally pulling in too many modules or dependencies).

          You can change this limit by setting the [:hologram, :max_bundle_size] config value (in bytes). For example:

              config :hologram, max_bundle_size: 2 * 1024 * 1024\
          """
      end
    end
  end

  # Consolidated protocol dispatchers list every loaded implementation. A clause for a struct
  # type always stays: the implementation for a struct type is in no runtime or page bundle, it is
  # loaded in a chunk once a struct of the type is on the client, and by then the dispatcher has to
  # name it, or dispatch would fall through to Any or raise Protocol.UndefinedError with the
  # implementation loaded. A clause for a built-in type stays only when its implementation ships
  # in the same bundle, so dispatch on a built-in type the bundle has no implementation for falls
  # through to the catch-all clause.
  defp maybe_prune_protocol_dispatcher_function_defs(
         function_defs,
         module,
         reachable_modules,
         module_info_plt
       ) do
    if Reflection.protocol?(module, module_info_plt) do
      # As names, not as modules: a protocol has no implementation for most built-in types, and
      # no atom is made for one that does not exist.
      built_in_impl_names =
        MapSet.new(
          CallGraph.built_in_protocol_types(),
          &"#{module}.#{Reflection.module_name(&1)}"
        )

      included_impls =
        included_protocol_implementations(reachable_modules, module, module_info_plt)

      Enum.filter(
        function_defs,
        &keep_protocol_dispatcher_function_def?(&1, built_in_impl_names, included_impls)
      )
    else
      function_defs
    end
  end

  # The modules a page reaches: those of its MFAs, and the struct types it names, each once.
  defp list_reached_modules(%{mfas: mfas, types: types}) do
    mfas
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.concat(types)
    |> Enum.uniq()
  end

  # The ref an element's $ref attribute names, when its name is a literal: an atom on its own, or
  # first in a tuple, with or without the braces that wrap the whole tuple (see expression_value/1
  # in Hologram.Template.Renderer). An identifier's atoms can't be nil, true or false.
  defp literal_ref(attrs) do
    Enum.find_value(attrs, fn
      %IR.TupleType{
        data: [
          %IR.StringType{value: "$ref"},
          %IR.ListType{
            data: [
              %IR.TupleType{data: [%IR.AtomType{value: :expression}, %IR.TupleType{data: parts}]}
            ]
          }
        ]
      } ->
        ref_from_parts(parts)

      _attr ->
        nil
    end)
  end

  # Any literal is resolved, composites included, as long as every part of it is one too - a single
  # expression anywhere inside makes the whole value unknowable until it runs. Pids, ports and
  # references can't be written in a template at all (they only come from calls, which aren't
  # literals), so the node types for them are not reachable here.
  defp literal_value(%IR.AtomType{value: value}), do: {:ok, value}
  defp literal_value(%IR.FloatType{value: value}), do: {:ok, value}
  defp literal_value(%IR.IntegerType{value: value}), do: {:ok, value}
  defp literal_value(%IR.StringType{value: value}), do: {:ok, value}

  defp literal_value(%IR.ListType{data: data}), do: literal_values(data)

  defp literal_value(%IR.TupleType{data: data}) do
    case literal_values(data) do
      {:ok, items} -> {:ok, List.to_tuple(items)}
      :unknown -> :unknown
    end
  end

  defp literal_value(%IR.MapType{data: data}) do
    {key_irs, value_irs} = Enum.unzip(data)

    with {:ok, keys} <- literal_values(key_irs),
         {:ok, values} <- literal_values(value_irs) do
      map =
        keys
        |> Enum.zip(values)
        |> Map.new()

      {:ok, map}
    end
  end

  defp literal_value(_ir), do: :unknown

  # One unresolvable part makes the whole composite unresolvable - a list holding an expression has
  # no value until that expression runs.
  defp literal_values(irs) do
    result =
      Enum.reduce_while(irs, {:ok, []}, fn ir, {:ok, acc} ->
        case literal_value(ir) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          :unknown -> {:halt, :unknown}
        end
      end)

    case result do
      {:ok, reversed_values} -> {:ok, Enum.reverse(reversed_values)}
      :unknown -> :unknown
    end
  end

  # A prop sourced from context is never written at the usage, so its absence there says nothing -
  # only the renderers can tell whether the context supplied it.
  defp missing_required_props(component_module, prop_names) do
    component_module.__props__()
    |> Enum.filter(fn {name, _type, opts} ->
      opts[:required] && !opts[:from_context] && to_string(name) not in prop_names
    end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  # The hash of the data model the given entity type and global role modules declare, or nil for
  # a project that declares no entity type and so has no data model.
  defp model_hash([], _role_modules), do: nil

  defp model_hash(entity_types, role_modules) do
    entity_types
    |> Model.from_modules(role_modules)
    |> Model.hash()
  end

  # The application Reflection.list_module_applications/0 names for the module: the first loaded
  # application, in the same order, whose modules list it.
  defp module_application(module) do
    Enum.find_value(Application.loaded_applications(), fn {app, _description, _version} ->
      if module in List.wrap(Application.spec(app, :modules)), do: app
    end)
  end

  # Moves the bundle with the given file name and its source map from the output dir esbuild wrote
  # them to into the static dir, and returns the paths of both there. The bundle's gzip copy is
  # written in the output dir and moved first, so that a served copy is never half written and a
  # served bundle always has one.
  defp move_bundle_to_static_dir(output_dir, bundle_file_name, opts) do
    output_bundle_path = Path.join(output_dir, bundle_file_name)
    output_gzip_path = gzip_path(output_bundle_path)
    static_bundle_path = Path.join(opts[:static_dir], bundle_file_name)
    static_source_map_path = static_bundle_path <> ".map"

    gzipped_bundle =
      output_bundle_path
      |> File.read!()
      |> :zlib.gzip()

    File.write!(output_gzip_path, gzipped_bundle)

    File.rename!(output_gzip_path, gzip_path(static_bundle_path))
    File.rename!(output_bundle_path, static_bundle_path)
    File.rename!(output_bundle_path <> ".map", static_source_map_path)

    {static_bundle_path, static_source_map_path}
  end

  # The file holding the token of the module info dump at the given path (see
  # dump_module_info_plt/2).
  defp module_info_dump_token_path(dump_path), do: dump_path <> ".token"

  # The record of the last JS deps install, in the node_modules dir it filled. npm leaves files it
  # doesn't know there alone, on a reinstall and on an install after package.json changed.
  defp package_json_digest_path(assets_dir) do
    Path.join([assets_dir, "node_modules", ".package_json_digest.bin"])
  end

  defp parts_text(0), do: "no parts"

  defp parts_text(1), do: "1 part"

  defp parts_text(part_count), do: "#{part_count} parts"

  # A compiled module is read. Any other beam is checked against its entry's mtime and size first:
  # another OS process can rewrite it, as a new implementation rewrites a consolidated protocol's,
  # with no compile this VM's tracer sees.
  defp patch_module_info_plt_entry!(plt, module, beam_path, dumped_at, compiled_modules) do
    old_info = get_module_info(plt, module)

    new_info =
      if MapSet.member?(compiled_modules, module) do
        Reflection.beam_info(beam_path)
      else
        reusable_module_info(module, beam_path, plt, dumped_at) || Reflection.beam_info(beam_path)
      end

    put_compared_module_info(plt, module, old_info, new_info)
  end

  # A module that left the listing without its beam being deleted, as the full scan would see it. A
  # path the VM still names for a module whose file is gone, or for one compiled in memory, has
  # nothing to read, so the module loses its entry, as a deleted one.
  defp patch_vanished_module_info!(plt, module, dumped_at, umbrella?) do
    beam_source = resolve_beam_source(module, umbrella?)
    old_info = get_module_info(plt, module)

    new_info =
      if beam_source && (is_binary(beam_source) or File.regular?(beam_source)) do
        reusable_module_info(module, beam_source, plt, dumped_at) ||
          Reflection.beam_info(beam_source)
      end

    put_compared_module_info(plt, module, old_info, new_info)
  end

  # The hash of the rules of the given entity types, or nil for a project that declares no entity
  # type, the way its model hash is.
  defp policy_hash([]), do: nil

  defp policy_hash(entity_types), do: Policy.hash(entity_types)

  # The grant store, when the given entity types of a data model hold it - which they do exactly
  # when it designates a user entity type.
  defp put_grant_type(entity_types, all_entity_types) do
    if RoleGrant in all_entity_types do
      MapSet.put(entity_types, RoleGrant)
    else
      entity_types
    end
  end

  # $-prefixed entries are the framework's own ($key, event bindings), never something the author
  # declared with prop/3, so they are not props as far as a usage is concerned.
  defp prop_entries(props) do
    props
    |> Enum.flat_map(fn
      %IR.TupleType{data: [%IR.StringType{value: name}, %IR.ListType{data: value_dom}]} ->
        [{name, static_prop_value(value_dom)}]

      _entry ->
        []
    end)
    |> Enum.reject(fn {name, _value} -> String.starts_with?(name, "$") end)
  end

  defp put_recursion_loop(ref, usages, loop) do
    if Enum.any?(usages, &render_together?(&1, ref)), do: put_ref_loop(ref, loop), else: ref
  end

  # The innermost loop around a ref is the one it repeats with, so an outer one leaves it alone.
  defp put_ref_loop(%{loop: nil} = occurrence, loop), do: %{occurrence | loop: loop}

  defp put_ref_loop(occurrence, _loop), do: occurrence

  defp ref_loop_text({:for, module}),
    do: "for each item of a {%for} in the template of #{inspect(module)}"

  defp ref_loop_text({:recursion, module, []}),
    do: "for each level of #{inspect(module)}, which renders itself"

  defp ref_loop_text({:recursion, module, through}) do
    "for each level of #{inspect(module)}, which renders itself through " <>
      Enum.map_join(through, " > ", &inspect/1)
  end

  # Where a ref renders from, as a message names it: the template that declares it, and the
  # templates it is rendered through from the root.
  defp ref_place(%{path: [module]}), do: "in the template of #{inspect(module)}"

  defp ref_place(%{path: path}) do
    {through, [module]} = Enum.split(path, -1)

    "in the template of #{inspect(module)} (rendered from #{Enum.map_join(through, " > ", &inspect/1)})"
  end

  # The call that puts the literal refs a page renders in the runtime's element ref registry, with
  # the names written as JSON, since a ref's name can be any atom. A page without refs puts none.
  defp render_page_ref_names(nil), do: ""

  defp render_page_ref_names({_page_module, []}), do: ""

  defp render_page_ref_names({page_module, names}) do
    names_json =
      names
      |> Enum.map(fn {name, part_count} -> [Atom.to_string(name), part_count] end)
      |> Jason.encode!()

    render_block(
      "ElementRefRegistry.putPageRefNames(#{Jason.encode!(Atom.to_string(page_module))}, #{names_json});"
    )
  end

  # Two occurrences render together unless a block they are both in renders each in another branch.
  defp render_together?(first, second) do
    first_branches = Map.new(first.blocks)

    Enum.all?(second.blocks, fn {block, branch} ->
      Map.get(first_branches, block, branch) == branch
    end)
  end

  defp root_label(module, layouts) do
    case layouts do
      %{^module => layout_module} ->
        "the page #{inspect(module)} with its layout #{inspect(layout_module)}"

      %{} ->
        "a render of #{inspect(module)}"
    end
  end

  # A page renders inside its layout, as the layout's slot content, so the layout's refs come first.
  defp root_template_refs(module, layouts, context, memo) do
    {layout_refs, layout_memo} =
      case layouts do
        %{^module => layout_module} -> evaluate_component_refs(layout_module, context, memo)
        %{} -> {[], memo}
      end

    {module_refs, module_memo} = evaluate_component_refs(module, context, layout_memo)

    {layout_refs ++ module_refs, module_memo}
  end

  # Two refs each inside a block of its own, past the blocks they share, can both render only when
  # separate blocks both take a branch that renders them. Blocks are listed outermost first, since
  # each one is added on the way out of it, so the blocks they share come first.
  defp separate_blocks?(first, second) do
    first_blocks = Enum.map(first.blocks, &elem(&1, 0))
    second_blocks = Enum.map(second.blocks, &elem(&1, 0))
    shared_count = shared_prefix_length(first_blocks, second_blocks)

    length(first_blocks) > shared_count and length(second_blocks) > shared_count
  end

  # Refs in the order they render, with nested sequences spliced in and the parts that declare
  # nothing left out.
  defp sequence_refs(parts) do
    spliced_parts =
      Enum.flat_map(parts, fn
        nil -> []
        {:seq, nested} -> nested
        refs -> [refs]
      end)

    case spliced_parts do
      [refs] -> refs
      spliced_parts -> {:seq, spliced_parts}
    end
  end

  # Mirrors evaluate_prop_value/1 in the renderer: a lone expression yields its term as it is, and
  # anything else is rendered to a string. So a value is known here only when the expression is a
  # literal, or when the value is text with nothing interpolated into it.

  defp shared_prefix_length([head | first_rest], [head | second_rest]) do
    1 + shared_prefix_length(first_rest, second_rest)
  end

  defp shared_prefix_length(_first, _second), do: 0

  defp static_prop_value([
         %IR.TupleType{data: [%IR.AtomType{value: :expression}, %IR.TupleType{data: [expr]}]}
       ]) do
    literal_value(expr)
  end

  defp static_prop_value([_first | _rest] = value_dom) do
    if Enum.all?(
         value_dom,
         &match?(%IR.TupleType{data: [%IR.AtomType{value: :text}, %IR.StringType{}]}, &1)
       ) do
      {:ok,
       Enum.map_join(value_dom, "", fn %IR.TupleType{data: [_tag, %IR.StringType{value: str}]} ->
         str
       end)}
    else
      :unknown
    end
  end

  defp static_prop_value(_value_dom), do: :unknown

  # The entity types sync sends rows of (see build_sync_constants/2), for the build or one page: the
  # reached ones, and where permissions are checked on the client, the types their rules read rows of through
  # relationships and the grant type. A chain's types stop before its first type no session may
  # read (see `Hologram.Policy.readable_prefix/2`): no client gets such a row, nor any row reached
  # through it. Kept to the types of the client's model: a row of a type the model does not name
  # cannot be read back. What that drops is a type declaring no rule, like one a read rule
  # delegates to, whose rows no one may read anyway, and the grant type when the model designates
  # no user entity type, which has no grant store.
  defp synced_types(reached_entity_types, model_entity_types, checks_permissions?, rule_types) do
    types =
      if checks_permissions? do
        reached_entity_types
        |> Enum.flat_map(&Map.fetch!(rule_types, &1))
        |> MapSet.new()
        |> MapSet.union(reached_entity_types)
        |> MapSet.put(RoleGrant)
      else
        reached_entity_types
      end

    types
    |> MapSet.intersection(model_entity_types)
    |> Enum.sort()
  end

  # The types the given type's rules read through relationships, each chain up to its first type no
  # session may read.
  defp rule_entity_types(entity_type) do
    entity_type
    |> Policy.related_chains()
    |> Enum.flat_map(&chain_types(entity_type, Policy.readable_prefix(entity_type, &1)))
  end

  # The types a permission check can ask about: those declaring a rule, and those
  # declaring a role, since a role check validates and expands the role from the type's own
  # declarations - and every type those rules read rows of through relationships. RoleGrant's
  # policy is framework-supplied rather than declared, so its empty __policies__ does not exclude
  # it - it joins by name beside this set.
  defp checked_entity_types(all_entity_types) do
    checked_types =
      all_entity_types
      |> Enum.filter(&(&1.__policies__() != [] or &1.__roles__() != []))
      |> MapSet.new()

    MapSet.union(checked_types, related_checked_entity_types(checked_types))
  end

  # The type of the rows the given derived field declaration holds, if it holds rows.
  defp derived_row_types({_name, [target], _opts}), do: [target]

  defp derived_row_types({_name, type, _opts}) do
    if Reflection.alias?(type), do: [type], else: []
  end

  # The types the derived fields holding rows and the inverses of the given entity type lead to.
  defp led_to_entity_types(entity_type) do
    derived_targets = Enum.flat_map(entity_type.__derived__(), &derived_row_types/1)

    inverse_targets =
      Enum.map(entity_type.__inverse_relationships__(), fn {name, _type, _opts} ->
        Entity.inverse_relationship(entity_type, name).target
      end)

    derived_targets ++ inverse_targets
  end

  # Read gives nil: not an Elixir module.
  # Puts the new entry in place of the old one and says what that was, with the module and the old
  # entry: an addition, an edit (another digest), a touch (the same digest, another mtime or size), a
  # removal (a beam that no longer reads as an Elixir module, or none), or nothing.
  defp put_compared_module_info(_plt, _module, nil, nil), do: :kept

  defp put_compared_module_info(plt, module, old_info, nil) do
    PLT.delete(plt, module)
    {:removed, module, old_info}
  end

  defp put_compared_module_info(_plt, _module, info, info), do: :kept

  defp put_compared_module_info(plt, module, old_info, new_info) do
    PLT.put(plt, module, new_info)

    cond do
      old_info == nil -> {:added, module, nil}
      old_info.digest != new_info.digest -> {:edited, module, old_info}
      true -> {:touched, module, old_info}
    end
  end

  defp put_module_info(new_plt, module, info) do
    if info, do: PLT.put(new_plt, module, info)
  end

  # Read unless reusable. A path the VM still names for a loaded module whose file another OS
  # process deleted has nothing to read, so the module gets no entry, as a deleted one. Checked only
  # when the entry is not reused, whose check of the beam found no file then.
  defp put_module_info_plt_entry!(new_plt, module, beam_source, old_plt, dumped_at) do
    info =
      cond do
        reused_info = reusable_module_info(module, beam_source, old_plt, dumped_at) ->
          reused_info

        is_binary(beam_source) or File.regular?(beam_source) ->
          Reflection.beam_info(beam_source)

        true ->
          nil
      end

    put_module_info(new_plt, module, info)
  end

  # What esbuild read (`"inputs"`) and wrote (`"outputs"`) in a run, from the metafile it left.
  defp read_esbuild_metafile(metafile_path) do
    metafile_path
    |> File.read!()
    |> JSON.decode!()
  end

  # nil when the dump has no token: an older Hologram wrote it.
  defp read_module_info_dump_token(dump_path) do
    case dump_path
         |> module_info_dump_token_path()
         |> File.read() do
      {:ok, token} -> token
      {:error, _reason} -> nil
    end
  end

  # The types a checked rule reads rows of through relationships - a path in a condition, the chain
  # of a delegation or of a grant reference, the set of a quantifier - whose model a client needs to
  # follow them, whether or not they declare a rule or a role of their own. The dependency edges
  # name every one, a set's rows by the chain its pairs are named with when the condition reads
  # nothing on them.
  defp related_checked_entity_types(checked_types) do
    checked_types
    |> Enum.to_list()
    |> Edges.derive()
    |> Enum.flat_map(fn {{checked_type, _operation}, edges} ->
      Enum.flat_map(edges, &edge_entity_types(checked_type, &1))
    end)
    |> MapSet.new()
  end

  # The given entity types with every type their derived fields holding rows and their inverses
  # lead to, and those types' own in turn: a client boxing a row of one reads the type's entry.
  defp rules_entity_types(entity_types) do
    led_to =
      entity_types
      |> Enum.flat_map(&led_to_entity_types/1)
      |> MapSet.new()

    if MapSet.subset?(led_to, entity_types) do
      entity_types
    else
      entity_types
      |> MapSet.union(led_to)
      |> rules_entity_types()
    end
  end

  # The kept pages whose MFAs moved, and the ones whose MFAs are unchanged, with their states. A
  # page's MFAs as its bundle was built from them are read from the page MFAs PLT. A page with no
  # list there counts as moved: its state was loaded from the compile state dump, which does not hold
  # the lists (see Hologram.Compiler.Cache.dump_compile_state/2).
  defp relist_kept_pages(kept_pages, call_graph, page_mfas_plt, gate) do
    mfas_by_kept_page =
      kept_pages
      |> Enum.map(fn {page_module, _page_state} -> page_module end)
      |> list_mfas_by_page(call_graph, gate: gate)
      |> Map.new()

    {changed_pages, unchanged_pages} =
      Enum.split_with(kept_pages, fn {page_module, _page_state} ->
        PLT.get(page_mfas_plt, page_module) != {:ok, mfas_by_kept_page[page_module]}
      end)

    moved_pages = Enum.map(changed_pages, fn {page_module, _page_state} -> page_module end)

    {moved_pages, unchanged_pages}
  end

  # TODO: Drop the umbrella? param and resolve the beam path with :code.which/1
  # when resolve_beam_source/2 goes (see the removal note there).
  defp rebuild_module_info_plt_entry!(
         module,
         old_plt,
         dumped_at,
         new_plt,
         consolidated_beams,
         umbrella?
       ) do
    # No beam: not a module of this project.
    if beam_source = resolve_beam_source(module, consolidated_beams, umbrella?) do
      put_module_info_plt_entry!(new_plt, module, beam_source, old_plt, dumped_at)
    end
  end

  # A literal part that can't be in an identifier makes the ref invalid when it renders, so it
  # names nothing the build could check.
  defp ref_from_parts([%IR.TupleType{data: [_name, _part | _rest] = parts}]) do
    ref_from_parts(parts)
  end

  defp ref_from_parts([%IR.AtomType{value: name} | parts])
       when name not in [nil, true, false] do
    if Enum.all?(parts, &ref_part?/1), do: {:ref, name, length(parts)}
  end

  defp ref_from_parts(_parts), do: nil

  defp ref_part?(%IR.AtomType{value: value}), do: value not in [nil, true, false]

  defp ref_part?(%IR.FloatType{}), do: false

  defp ref_part?(_part), do: true

  # Travels with the per-module metadata, which is emitted under the same
  # setting - a bundle built without client stacktraces names no application
  # and no version anywhere.
  defp render_app_versions(app_versions) do
    if Hologram.client_stacktraces?() do
      app_versions
      |> Enum.map_join(", ", fn {app, vsn} -> ~s/"#{app}": "#{vsn}"/ end)
      |> then(&"{#{&1}}")
    else
      "{}"
    end
  end

  defp render_block(str) do
    str = String.trim(str)

    if str != "" do
      "\n\n" <> str
    else
      ""
    end
  end

  # What the client judges a written value by, so that a browser answers what the server answers.
  # Only the attributes declaring at least one of these options are named, and each carries only
  # the options its declaration wrote.
  #
  # The inner keys are the option names as Elixir spells them (min_length, not minLength) rather
  # than in the camelCase of their neighbours, because they are also the words a violation is
  # reported in - one spelling, written by the build and read back in the answer.
  #
  # The terms among them - a bound, a pattern's options - are written by the given function: as
  # JavaScript for the runtime script, and serialized for a sync frame, which carries JSON.
  defp render_constraints(entity_type, encode_term) do
    max_bytes = Validator.unique_string_max_bytes(entity_type)

    entity_type.__attributes__()
    |> Enum.filter(fn {name, _type, opts} ->
      Map.has_key?(max_bytes, name) or
        Enum.any?(@baked_constraint_opts, &Keyword.has_key?(opts, &1))
    end)
    |> Enum.map(fn {name, _type, opts} ->
      {Atom.to_string(name),
       render_attribute_constraints(opts, Map.get(max_bytes, name), encode_term)}
    end)
    |> render_json_object()
  end

  # max_bytes is no declaration option: it is the bound the attribute's unique indexes put on a
  # string, which the server works out from the whole type - a key declared with unique shares
  # one index entry among its fields - so the client is handed the answer, not the rule.
  defp render_attribute_constraints(opts, max_bytes, encode_term) do
    declared =
      Enum.flat_map(@baked_constraint_opts, fn key ->
        case Keyword.fetch(opts, key) do
          {:ok, value} ->
            [{Atom.to_string(key), render_constraint_value(key, value, encode_term)}]

          :error ->
            []
        end
      end)

    derived = if max_bytes, do: [{"max_bytes", Integer.to_string(max_bytes)}], else: []

    render_json_object(declared ++ derived)
  end

  # A bound travels as the ENCODED TERM its literal becomes, for the reason a default does: a
  # violation names the bound the declaration wrote, and a float attribute takes both `max: 5` and
  # `max: 5.0`, which the wire spells alike.
  defp render_constraint_value(key, value, encode_term) when key in [:max, :min] do
    encode_term.(value)
  end

  # A pattern travels as its source and its options rather than as a compiled one: a compiled
  # pattern exists only inside the runtime that compiled it, and the encoded form of a Regex is a
  # struct wrapping a :re.import/1 CALL, which this line sits above in the runtime script. The
  # client compiles it once instead, which is what the import would have done anyway.
  #
  # The options travel as an ENCODED TERM rather than as their names, because not all of them are
  # names: ~r/x/s reads back as [:dotall, {:newline, :anycrlf}], and a tuple has no name to write.
  # Model.normalize_value/1 keeps the same list whole for the same reason.
  defp render_constraint_value(:format, value, encode_term) do
    opts =
      value
      |> Regex.opts()
      |> encode_term.()

    source =
      value
      |> Regex.source()
      |> Jason.encode!()

    render_json_object([{"opts", opts}, {"source", source}])
  end

  # A range travels as its three parts, the step included - `in: 0..100//5` admits 5 and refuses
  # 7, so a client told only the ends would answer differently from the server.
  defp render_constraint_value(:in, value, _encode_term) do
    render_json_object([
      {"first", Jason.encode!(value.first)},
      {"last", Jason.encode!(value.last)},
      {"step", Jason.encode!(value.step)}
    ])
  end

  defp render_constraint_value(_key, value, _encode_term), do: Jason.encode!(value)

  # A set's declared order, spelled the way a term spells one - each entry a name and a direction.
  defp render_declared_order(target, sort) do
    target
    |> Stage.sort(sort)
    |> Map.fetch!(:sort)
    |> Enum.map(fn {key, direction} -> [Atom.to_string(key), Atom.to_string(direction)] end)
  end

  # A default travels as the ENCODED TERM the declared literal becomes in transpiled code, rather
  # than as the way the wire spells the same value: the client applies it to a struct field, and a
  # struct field holds the literal the developer wrote. The two are not interchangeable - a float
  # attribute takes both `default: 5` and `default: 5.0`, which the wire spells alike and the term
  # encoder keeps apart, and a struct built on the client has to hold the one that was declared.
  #
  # Only the attributes declaring one are named - an attribute with no default has nothing to
  # apply, and the reader fills its field the way an absent value is filled anyway.
  defp render_defaults(entity_type, encode_term) do
    entity_type.__attributes__()
    |> Enum.filter(fn {_name, _type, opts} -> Keyword.has_key?(opts, :default) end)
    |> Enum.map(fn {name, _type, opts} ->
      default =
        opts
        |> Keyword.fetch!(:default)
        |> encode_term.()

      {Atom.to_string(name), default}
    end)
    |> render_json_object()
  end

  # A type's derived fields, each with what it holds - a value of its declared type, an enum's labels
  # in their declared order, or one row or a set of rows of an entity type - and its definition in
  # the shapes the query kernel reads: a filter's clauses, and a query as the term stage.mjs builds,
  # with the owning type and the chain its rows are read from. A value is spelled the way the wire
  # spells it, by the type of what it stands for.
  defp render_derived(entity_type) do
    entity_type.__derived__()
    |> Enum.map(fn {name, type, opts} ->
      definition = Derived.definition(entity_type, name)

      {Atom.to_string(name), render_derived_field(entity_type, definition, type, opts)}
    end)
    |> render_json_object()
  end

  defp render_derived_clause({:or, alternatives}, types) do
    alternatives_js =
      alternatives
      |> Enum.map_join(",", &render_derived_clauses(&1, types))
      |> then(&"[#{&1}]")

    render_json_object([{"or", alternatives_js}])
  end

  defp render_derived_clause({quantifier, {source, clauses}}, types)
       when quantifier in [:all, :any, :none] do
    related_type = quantified_type(source, types)

    quantifier_js =
      quantifier
      |> Atom.to_string()
      |> Jason.encode!()

    render_json_object([
      {"filter", render_derived_clauses(clauses, [related_type | types])},
      {"quantifier", quantifier_js},
      {"source", render_derived_name(source)}
    ])
  end

  defp render_derived_clause({name, operator, operand}, types) do
    operator_js =
      operator
      |> Atom.to_string()
      |> Jason.encode!()

    operand_js = render_derived_operand(operand, name_type(name, types))

    "[#{render_derived_name(name)},#{operator_js},#{operand_js}]"
  end

  defp render_derived_clauses(clauses, types) do
    clauses
    |> Enum.map_join(",", &render_derived_clause(&1, types))
    |> then(&"[#{&1}]")
  end

  defp render_derived_definition({:concat, operands}, entity_type, _type) do
    operands_js =
      operands
      |> Enum.map_join(",", &render_derived_definition(&1, entity_type, :string))
      |> then(&"[#{&1}]")

    render_json_object([{"concat", operands_js}])
  end

  defp render_derived_definition({:condition, clauses}, entity_type, _type) do
    render_json_object([{"condition", render_derived_clauses(clauses, [entity_type])}])
  end

  defp render_derived_definition({:if, clauses, then_value, else_value}, entity_type, type) do
    render_json_object([
      {"else", render_derived_definition(else_value, entity_type, type)},
      {"if", render_derived_clauses(clauses, [entity_type])},
      {"then", render_derived_definition(then_value, entity_type, type)}
    ])
  end

  defp render_derived_definition({:name, name}, _entity_type, _type) do
    render_json_object([{"name", render_derived_name(name)}])
  end

  defp render_derived_definition({:query, term}, entity_type, _type) do
    render_json_object([{"query", render_derived_term(term, [term.entity, entity_type])}])
  end

  defp render_derived_definition({:value, value}, _entity_type, type) do
    value_js =
      value
      |> Codec.encode_json(type)
      |> Jason.encode!()

    render_json_object([{"value", value_js}])
  end

  defp render_derived_field(entity_type, definition, [row_type], _opts) do
    render_json_object([
      {"definition", render_derived_definition(definition, entity_type, nil)},
      {"entity", render_entity_type_label(row_type)},
      {"kind", ~s("set")}
    ])
  end

  defp render_derived_field(entity_type, definition, type, opts) do
    if Reflection.alias?(type) do
      render_json_object([
        {"definition", render_derived_definition(definition, entity_type, nil)},
        {"entity", render_entity_type_label(type)},
        {"kind", ~s("one")}
      ])
    else
      values =
        if type == :enum do
          opts
          |> Keyword.fetch!(:values)
          |> Enum.map(&Codec.encode(&1, :enum))
        end

      render_json_object([
        {"definition", render_derived_definition(definition, entity_type, type)},
        {"kind", ~s("scalar")},
        {"type", Jason.encode!(type)},
        {"values", Jason.encode!(values)}
      ])
    end
  end

  defp render_derived_include(include) do
    include
    |> Enum.map(fn
      {name, nil} -> {Atom.to_string(name), "null"}
      {name, sub_term} -> {Atom.to_string(name), render_derived_term(sub_term, [sub_term.entity])}
    end)
    |> render_json_object()
  end

  # A name as the kernel spells it: an attribute's name, a path's or a chain's names in order, or a
  # name of a row above with how many quantifiers out it lies.
  defp render_derived_name({:outer, levels, name}) do
    render_json_object([
      {"name", render_derived_name(name)},
      {"outer", Integer.to_string(levels)}
    ])
  end

  defp render_derived_name(name), do: render_policy_name(name)

  defp render_derived_operand({:attribute, other}, _type) do
    render_json_object([{"attribute", render_derived_name(other)}])
  end

  defp render_derived_operand(values, type) when is_list(values) do
    values
    |> Enum.map_join(",", &render_derived_operand(&1, type))
    |> then(&"[#{&1}]")
  end

  defp render_derived_operand(value, type) do
    value
    |> Codec.encode_json(type)
    |> Jason.encode!()
  end

  # A term as stage.mjs builds one, with the owning type and the chain from its row when it is a
  # derived field's query.
  defp render_derived_term(term, types) do
    sort =
      Enum.map(term.sort, fn {key, direction} ->
        [Atom.to_string(key), Atom.to_string(direction)]
      end)

    source_members =
      case term.source do
        nil ->
          []

        {owner_type, chain} ->
          source_js =
            render_json_object([
              {"chain", render_policy_name(chain)},
              {"owner", render_entity_type_label(owner_type)}
            ])

          [{"source", source_js}]
      end

    cardinality_js =
      term.cardinality
      |> Atom.to_string()
      |> Jason.encode!()

    render_json_object([
      {"cardinality", cardinality_js},
      {"entity", render_entity_type_label(term.entity)},
      {"filter", render_derived_clauses(term.filter, types)},
      {"include", render_derived_include(term.include)},
      {"skip", Jason.encode!(term.skip)},
      {"sort", Jason.encode!(sort)},
      {"take", Jason.encode!(term.take)}
      | source_members
    ])
  end

  # What a client needs to read its own rows, and to build one: a value's type is not recoverable
  # from the value itself - a date, an enum and a uuid all arrive as strings - so reading one back
  # means knowing the attribute it belongs to, which is what this says. Building one means knowing
  # what the declaration fills in for an attribute nobody set, which is what the defaults say.
  #
  # It rides with the bundle rather than with the entity modules, for two reasons. A module says
  # this through functions nothing calls statically, so nothing keeps them: the caller names them
  # on a module it is handed, an edge no call graph can see. And a module travels in its PAGE's
  # bundle, while the database holds every type the app syncs - a row of a type the current page
  # never mentions still has to be read.
  #
  # Server-only attributes are named here, values and all: what the client holds of one is the
  # knowledge that it exists and is not for it, which is what lets a read of that field say so
  # rather than answer nil.
  #
  # An enum attribute's declared value list travels too, spelled the way the rows spell their
  # values: the order a list declares IS the type's order, and ordering by an enum attribute
  # sorts by a value's position in it - which the client can only follow if it is told the list.
  defp render_entity_model(entity_types) do
    entity_types
    |> Enum.map(&{Codec.encode_enum_value(&1), render_entity_model_entry(&1)})
    |> render_json_object()
  end

  defp render_entity_model_entry(entity_type) do
    entity_type
    |> entity_model_members(&Encoder.encode_term!/1)
    |> render_json_object()
  end

  # The members of the client's model entry of the given entity type, each rendered, by name, the
  # terms among the defaults and constraints written by the given function.
  defp entity_model_members(entity_type, encode_term) do
    attributes =
      entity_type.__attributes__()
      |> Enum.concat(entity_type.__system_attributes__())
      |> Enum.map(fn {name, type, _opts} -> {Atom.to_string(name), Jason.encode!(type)} end)
      |> render_json_object()

    server_only =
      entity_type
      |> Entity.server_only_attribute_names()
      |> Enum.sort()
      |> Jason.encode!()

    [
      {"attributes", attributes},
      {"constraints", render_constraints(entity_type, encode_term)},
      {"creatorRoles", render_creator_roles(entity_type)},
      {"defaults", render_defaults(entity_type, encode_term)},
      {"derived", render_derived(entity_type)},
      {"enumValues", render_enum_values(entity_type)},
      {"expandedRoles", render_expanded_roles(entity_type)},
      {"frameworkAttributes", render_framework_attributes(entity_type)},
      {"inverses", render_inverses(entity_type)},
      {"operations", render_operations(entity_type)},
      {"policy", render_policy(entity_type)},
      {"relationships", render_relationships(entity_type)},
      {"roles", render_roles(entity_type)},
      {"serverOnly", server_only},
      {"verdicts", render_verdicts(entity_type)}
    ]
  end

  # A type with no enum attributes carries an empty object rather than nothing at all - the reader
  # fetches the field without asking whether it is there.
  defp render_enum_values(entity_type) do
    entity_type.__attributes__()
    |> Enum.filter(fn {_name, type, _opts} -> type == :enum end)
    |> Enum.map(fn {name, _type, opts} ->
      values =
        opts
        |> Keyword.fetch!(:values)
        |> Enum.map(&Codec.encode(&1, :enum))
        |> Jason.encode!()

      {Atom.to_string(name), values}
    end)
    |> render_json_object()
  end

  # What carries each of the type's roles - the role itself and every role whose extends chain
  # reaches it, which is the set a role check reads grant rows for. Expanded here rather than in
  # the browser, the way the baked rules are, so the two tiers expand from one definition.
  defp render_expanded_roles(entity_type) do
    entity_type.__roles__()
    |> Enum.map(fn {name, _opts} ->
      expanded =
        entity_type
        |> Entity.expand_role(name)
        |> Enum.map(&Atom.to_string/1)
        |> Jason.encode!()

      {Atom.to_string(name), expanded}
    end)
    |> render_json_object()
  end

  # The attributes of a job that the framework owns and nobody else writes - the ones construction
  # refuses by name, so that a client refuses them for the same reason and in the same words.
  #
  # They travel in the order the refusal walks rather than sorted, because a construction naming
  # two of them reports the FIRST, and a client reporting the other would answer a question the
  # server was never asked. Every other entity type carries an empty list, which is what makes
  # this a fact about the type rather than a rule the reader has to know jobs by.
  defp render_framework_attributes(entity_type) do
    names = if Reflection.job?(entity_type), do: Job.framework_attribute_names(), else: []

    names
    |> Enum.map(&Atom.to_string/1)
    |> Jason.encode!()
  end

  # The global roles the client can be asked about, each with the role modules carrying it,
  # spelled the way the grant store spells a role module. The keys are the defined global roles,
  # which is what a refusal of an unknown one lists.
  defp render_global_expanded_roles(role_modules) do
    role_modules
    |> Enum.map(fn role_module ->
      expanded =
        role_module
        |> Policy.expand_global_role(role_modules)
        |> Enum.map(&Codec.encode_enum_value/1)
        |> Jason.encode!()

      {Codec.encode_enum_value(role_module), expanded}
    end)
    |> render_json_object()
  end

  # The operations a type can be asked about, framework ones included - the client's copy of
  # Policy.operations/1, so validateOperation in assets/js/model.mjs refuses what
  # Policy.validate_operation!/2 refuses without a second hand-ported list.
  defp render_operations(entity_type) do
    entity_type
    |> Policy.operations()
    |> Enum.map(&Atom.to_string/1)
    |> Jason.encode!()
  end

  # Keys are written in sorted order rather than the order a map hands them over in - that one
  # follows the atom table, which follows what the build happened to load first, and the bundle
  # this text ends up in is addressed by its content.
  defp render_json_object(members) do
    members
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(",", fn {key, value} -> ~s/#{Jason.encode!(key)}:#{value}/ end)
    |> then(&"{#{&1}}")
  end

  # An inverse is spelled apart from the stored relationships, because nothing on its row stores
  # the reference: it reverses a relationship of the related type - read off the related rows'
  # reference field when that one is a to-one, a to-many's facts otherwise - in its declared order,
  # spelled the way a query term spells an order, so normalizing a term in the browser applies it
  # the way the server does.
  defp render_inverses(entity_type) do
    entity_type.__inverse_relationships__()
    |> Enum.map(fn {name, _type, _opts} ->
      inverse = Entity.inverse_relationship(entity_type, name)
      sort = render_declared_order(inverse.target, inverse.sort)

      type =
        inverse.target
        |> Codec.encode_enum_value()
        |> Jason.encode!()

      forward =
        inverse.forward
        |> Atom.to_string()
        |> Jason.encode!()

      entry =
        render_json_object([
          {"forward", forward},
          {"reference", Jason.encode!(inverse.reference?)},
          {"sort", Jason.encode!(sort)},
          {"toMany", Jason.encode!(inverse.to_many?)},
          {"type", type}
        ])

      {Atom.to_string(name), entry}
    end)
    |> render_json_object()
  end

  # A to-many is spelled apart from a to-one because they are read apart: a to-many is assembled
  # from the relationship facts, a to-one is followed through the reference field the row carries.
  #
  # Optionality rides with both, though only a to-one is judged by it: a row missing the reference
  # field of a required to-one is a row the write refuses, which is an answer the client owes as
  # much as the server does.
  defp render_relationships(entity_type) do
    entity_type.__relationships__()
    |> Enum.map(fn {name, type, opts} ->
      {Atom.to_string(name), render_relationship(type, opts)}
    end)
    |> render_json_object()
  end

  # A to-many carries the order its declaration names, the way an inverse set does.
  defp render_relationship([target], opts) do
    sort = render_declared_order(target, Keyword.get(opts, :sort, []))
    fields = render_relationship_fields(target, true, opts)

    render_json_object([{"sort", Jason.encode!(sort)} | fields])
  end

  defp render_relationship(target, opts) do
    target
    |> render_relationship_fields(false, opts)
    |> render_json_object()
  end

  defp render_relationship_fields(target, to_many?, opts) do
    type =
      target
      |> Codec.encode_enum_value()
      |> Jason.encode!()

    [
      {"optional", Jason.encode!(Keyword.get(opts, :optional) == true)},
      {"toMany", Jason.encode!(to_many?)},
      {"type", type}
    ]
  end

  # The rules a client evaluates permissions by, spelled the way the rows it evaluates them
  # against are spelled: a predicate value travels as the wire spells it, so a date compares with
  # a date rather than with the way Elixir happens to print one.
  #
  # It rides in the type's own model entry rather than in a map of its own: it is keyed by entity
  # type, the ingest and read paths already fetch the entry, and every type named here is one the
  # model names anyway.
  #
  # A per-role grant lifecycle operation and a field of an update are keyed the way the client
  # spells them when asking -
  # Policy.operation_key/1 here and operationKey in assets/js/elixir/hologram/auth.mjs are a
  # hand-ported pair, so the two must agree.
  defp render_policy(entity_type) do
    entity_type
    |> Policy.build()
    |> Enum.map(fn {operation, rules} ->
      {Policy.operation_key(operation), render_policy_rules(entity_type, operation, rules)}
    end)
    |> render_json_object()
  end

  # The server's verdicts a client answers an operation by when the rows it holds leave the answer
  # open, by operation key as the policy is: each one's verdict key, which the row's $verdicts holds
  # it under, and the types its rules read, whose unanswered writes by the client make it stale
  # (see Policy.verdict_operations/1 and Policy.operation_reads/2).
  defp render_verdicts(entity_type) do
    entity_type
    |> Policy.verdict_operations()
    |> Enum.map(fn {key, operation} ->
      reads_js =
        entity_type
        |> Policy.operation_reads(operation)
        |> Enum.map_join(",", &render_entity_type_label/1)
        |> then(&"[#{&1}]")

      entry_js = render_json_object([{"reads", reads_js}, {"verdict", Jason.encode!(key)}])

      {Policy.operation_key(operation), entry_js}
    end)
    |> render_json_object()
  end

  defp render_policy_rules(entity_type, operation, rules) do
    rules
    |> Enum.map_join(",", &render_policy_rule(entity_type, operation, &1))
    |> then(&"[#{&1}]")
  end

  defp render_policy_rule(entity_type, operation, rule) do
    verdict_context = {entity_type, operation}

    render_json_object([
      {"predicates", render_policy_predicates([entity_type], rule.predicates, verdict_context)},
      {"to", render_policy_references(entity_type, rule.to, verdict_context)},
      {"via", render_policy_delegation(rule.via, verdict_context)}
    ])
  end

  # Triples, the same shape the client's query filters take - name, operator, value - so one
  # reader spells both. The types are those of the rows the clauses are read on, nearest first: the
  # rule's own row alone outside any quantifier. The verdict context is the rule's type and
  # operation for the clauses standing in its predicates, and nil inside a quantifier.
  defp render_policy_predicates(types, predicates, verdict_context \\ nil) do
    predicates
    |> Enum.map_join(",", &render_policy_clause(types, &1, verdict_context))
    |> then(&"[#{&1}]")
  end

  # A disjunction is an object beside the triple arrays, holding its alternatives - the shape the
  # query kernel's filters take, so one reader tells the two apart by whether a clause is an array.
  defp render_policy_clause(types, {:or, alternatives}, verdict_context) do
    alternatives_js =
      alternatives
      |> Enum.map_join(",", &render_policy_predicates(types, &1, verdict_context))
      |> then(&"[#{&1}]")

    render_json_object([{"or", alternatives_js}])
  end

  # A quantifier is an object too, in the shape the kernel's filters take it: the set its source
  # leads to, read on the row it is about or on one above it, and the condition each of the set's
  # rows is matched with, read on that row with the rows above it. A deciding one renders the same:
  # the rows the client holds of its set decide what one row can and leave the rest unknown, and
  # over a derived set they decide nothing.
  defp render_policy_clause(types, {quantifier, {source, clauses}}, _verdict_context)
       when quantifier in [:all, :any, :none] do
    related_type = quantified_type(source, types)

    quantifier_js =
      quantifier
      |> Atom.to_string()
      |> Jason.encode!()

    members = [
      {"filter", render_policy_predicates([related_type | types], clauses)},
      {"quantifier", quantifier_js},
      {"source", render_derived_name(source)}
    ]

    render_json_object(members)
  end

  # A predicate standing in a rule's predicates that reads a server-only attribute, whose value no
  # client holds, is a marker the client answers as unknown - its compared value stays off the
  # bundle. Every other predicate is its triple: one reading a row of a type no client holds reads
  # it as unknown unless an empty reference on its path reads no row.
  #
  # A clause reading a server-only attribute is deciding for that alone, so only whether it stands
  # in a rule's predicates is left to ask - inside a quantifier, with no context, it stays a triple.
  defp render_policy_clause(types, {_name, _operator, _value} = clause, {entity_type, _operation}) do
    if Policy.reads_server_only?(entity_type, clause) do
      render_json_object([{"server", "true"}])
    else
      render_policy_triple(types, clause)
    end
  end

  defp render_policy_clause(types, {_name, _operator, _value} = clause, nil) do
    render_policy_triple(types, clause)
  end

  defp render_policy_triple(types, {name, operator, value}) do
    name_js = render_derived_name(name)

    operator_js =
      operator
      |> Atom.to_string()
      |> Jason.encode!()

    ~s/[#{name_js},#{operator_js},#{render_policy_value(types, name, value)}]/
  end

  # The acting user's own id, named rather than carried: the client binds it when it evaluates the
  # rule.
  defp render_policy_value(_types, _name, {:actor}) do
    render_json_object([{"actor", "true"}])
  end

  # Another attribute of the row, of the row a path leads to, or of a row above inside a
  # quantifier, named rather than carried: the client reads it at evaluation, the way the query
  # kernel reads an attribute operand.
  defp render_policy_value(_types, _name, {:attribute, other}) do
    render_json_object([{"attribute", render_derived_name(other)}])
  end

  defp render_policy_value(types, name, values) when is_list(values) do
    values
    |> Enum.map_join(",", &render_policy_value(types, name, &1))
    |> then(&"[#{&1}]")
  end

  # A value is spelled by the type of the attribute it is compared with, on the row that attribute
  # is read on.
  defp render_policy_value(types, name, value) do
    value
    |> Codec.encode_json(name_type(name, types))
    |> Jason.encode!()
  end

  # A grant reference names WHERE a role must be held: on the entity itself, on its whole type,
  # on a related entity, on the entity a grant row names, or nowhere at all (a global role). The
  # verdict context is the rule's type and operation.
  defp render_policy_references(_entity_type, nil, _verdict_context), do: "null"

  defp render_policy_references(entity_type, references, verdict_context) do
    references
    |> Enum.map_join(",", &render_policy_reference(entity_type, &1, verdict_context))
    |> then(&"[#{&1}]")
  end

  defp render_policy_reference(_entity_type, {:own, role_names}, _verdict_context) do
    render_policy_reference_entry("own", [render_policy_roles(role_names)])
  end

  defp render_policy_reference(_entity_type, {:global, role_modules}, _verdict_context) do
    render_policy_reference_entry("global", [render_policy_roles(role_modules)])
  end

  # The chain a role is held through, spelled the way a delegation spells its chain. A deciding one
  # - in a read rule, one reading a row of a type no client holds - carries a fifth element, true,
  # and the client answers it as unknown.
  defp render_policy_reference(
         entity_type,
         {:rel, relationship_names, role_names} = reference,
         verdict_context
       ) do
    target_type = Entity.path_target(entity_type, relationship_names)

    verdict_entries = if deciding_item?({:to, reference}, verdict_context), do: ["true"], else: []

    render_policy_reference_entry(
      "rel",
      [
        render_policy_name(relationship_names),
        render_entity_type_label(target_type),
        render_policy_roles(role_names)
      ] ++ verdict_entries
    )
  end

  defp render_policy_reference(_entity_type, {kind, target_type, role_names}, _verdict_context) do
    render_policy_reference_entry(Atom.to_string(kind), [
      render_entity_type_label(target_type),
      render_policy_roles(role_names)
    ])
  end

  defp render_policy_reference_entry(kind, members) do
    [Jason.encode!(kind) | members]
    |> Enum.join(",")
    |> then(&"[#{&1}]")
  end

  defp render_policy_roles(role_names) do
    role_names
    |> Enum.map_join(",", fn role_name ->
      role_name
      |> Codec.encode_enum_value()
      |> Jason.encode!()
    end)
    |> then(&"[#{&1}]")
  end

  # Operation first, as the server's tuple holds it - the array shape grant references bake as. A
  # deciding one - in a read rule, one whose chain passes a row of a type no client holds - carries
  # a third element, true, and the client answers it as unknown.
  defp render_policy_delegation(nil, _verdict_context), do: "null"

  defp render_policy_delegation({operation, relationship_names} = via, verdict_context) do
    operation_js =
      operation
      |> Policy.operation_key()
      |> Jason.encode!()

    verdict_js = if deciding_item?({:via, via}, verdict_context), do: ",true", else: ""

    "[#{operation_js},#{render_policy_name(relationship_names)}#{verdict_js}]"
  end

  # An attribute as its name, and a path or the chain of a delegation or a grant reference as the
  # array of its names - the spelling the query kernel reads a filter's path by.
  defp render_policy_name(path) when is_list(path) do
    path
    |> Enum.map(&Atom.to_string/1)
    |> Jason.encode!()
  end

  defp render_policy_name(name) do
    name
    |> Atom.to_string()
    |> Jason.encode!()
  end

  # The client writes a creator's grants itself when it creates a row, so it has to be told which
  # of the type's roles those are.
  defp render_creator_roles(entity_type) do
    entity_type.__roles__()
    |> Enum.filter(fn {_name, opts} -> Keyword.get(opts, :granted_to) == :creator end)
    |> Enum.map(fn {name, _opts} -> Atom.to_string(name) end)
    |> Enum.sort()
    |> Jason.encode!()
  end

  # The name a grant row spells this type by - what its entity_type column holds, which is the
  # type's own name. A reference carries it spelled out rather than as a lookup into the model, so
  # that it may name a type the client never syncs: a role held on an admin-only type can gate a
  # synced type's rules, and the model would have nothing to look up.
  defp render_entity_type_label(entity_type) do
    entity_type
    |> Codec.encode_enum_value()
    |> Jason.encode!()
  end

  # The names a grant on this type may carry, so the browser can refuse an undeclared role with
  # the server's own sentence before anything is sent.
  defp render_roles(entity_type) do
    entity_type.__roles__()
    |> Enum.map(fn {name, _opts} -> Atom.to_string(name) end)
    |> Enum.sort()
    |> Jason.encode!()
  end

  # The given entity types and every one they lead to by a name among the given atoms, to a
  # fixpoint (see build_sync_constants/2), with what each name was found to lead to so far. Each
  # round follows the names of the types the round before added only.
  defp named_entity_types(entity_types, added_types, atoms, named_by) do
    {named, named_by} =
      Enum.reduce(added_types, {MapSet.new(), named_by}, fn entity_type, {acc, named_by} ->
        {types, named_by} = named_by(entity_type, atoms, named_by)

        {MapSet.union(acc, types), named_by}
      end)

    new_types = MapSet.difference(named, entity_types)

    if MapSet.size(new_types) == 0 do
      {entity_types, named_by}
    else
      named_entity_types(MapSet.union(entity_types, new_types), new_types, atoms, named_by)
    end
  end

  # The types the given entity type leads to by a relationship, an inverse or a derived field whose
  # name is among the given atoms: what including the name reads, as a query reads it (see
  # Hologram.Query.Window.entity_types/1) - a relationship's rows, a derived field's and the ones its
  # definition is computed from. What a name leads to is worked out once and kept by type and name.
  defp named_by(entity_type, atoms, named_by) do
    derived_names = Enum.map(entity_type.__derived__(), fn {name, _type, _opts} -> name end)

    entity_type
    |> Entity.includable_names()
    |> Enum.concat(derived_names)
    |> Enum.uniq()
    |> Enum.filter(&MapSet.member?(atoms, &1))
    |> Enum.reduce({MapSet.new(), named_by}, fn name, {acc, named_by} ->
      named_by =
        Map.put_new_lazy(named_by, {entity_type, name}, fn ->
          entity_type
          |> Stage.include(name)
          |> Stage.normalize()
          |> Window.entity_types()
        end)

      {MapSet.union(acc, MapSet.new(Map.fetch!(named_by, {entity_type, name}))), named_by}
    end)
  end

  # Whether the given module's code is read - neither Elixir's, whose applications live under the
  # given directory, nor Hologram's, whose test fixtures stand in for an app's modules. Told by the
  # module's name and where its code is rather than by the application holding it, which need not
  # be loaded while the app compiles. Asked only of a module the module info PLT records, which is
  # an Elixir module: nothing here reads its BEAM file.
  defp app_module?(module, elixir_lib_dir) do
    name = Atom.to_string(module)

    cond do
      String.starts_with?(name, "Elixir.Hologram.Test.") -> true
      String.starts_with?(name, "Elixir.Hologram.") -> false
      true -> not loaded_from?(module, elixir_lib_dir)
    end
  end

  # The directory Elixir's own applications are installed under, elixir, eex, ex_unit, iex, logger
  # and mix side by side.
  defp elixir_lib_dir do
    :elixir
    |> :code.lib_dir()
    |> to_string()
    |> Path.dirname()
  end

  # A function the compiler generates into a module, named like __relationships__ or __schema__.
  defp generated?(function) do
    name = Atom.to_string(function)

    String.starts_with?(name, "__") and String.ends_with?(name, "__")
  end

  defp loaded_from?(module, dir) do
    case :code.which(module) do
      path when is_list(path) ->
        path
        |> to_string()
        |> String.starts_with?(dir)

      _cover_compiled_or_missing ->
        false
    end
  end

  # The type of what a clause's name reads, for spelling the values it is compared with: an
  # attribute's, a derived field's declared one, or an entity id for a reference field - the
  # fallback the query stages make. An outer name is read on the row that many levels out, a path on
  # the row the path leads to.
  defp name_type({:outer, levels, name}, types) do
    name_type(name, [Enum.at(types, levels)])
  end

  defp name_type(path, [entity_type | _types_above]) when is_list(path) do
    {relationship_names, [name]} = Enum.split(path, -1)

    name_type(name, [Entity.path_target(entity_type, relationship_names)])
  end

  defp name_type(name, [entity_type | _types_above]) do
    declaration =
      entity_type.__attributes__()
      |> Enum.concat(entity_type.__system_attributes__())
      |> Enum.concat(entity_type.__derived__())
      |> List.keyfind(name, 0)

    case declaration do
      {_name, type, _opts} when is_atom(type) -> type
      _other -> :uuid
    end
  end

  # The components among the given modules, as the module info PLT records them: a module it does
  # not hold (an Erlang module, a dependency's) is no component of the build.
  defp reached_components(modules, module_info_plt) do
    Enum.filter(modules, fn module ->
      match?({:ok, %{component?: true}}, PLT.get(module_info_plt, module))
    end)
  end

  # A page module defines no props, so it never reads anything from the context through one. What
  # this decides also puts the user type among the synced types (see `build_sync_constants/2`).
  defp reads_session_user?(module) do
    Reflection.has_function?(module, :__props__, 0) and
      Enum.any?(module.__props__(), fn {_name, _type, opts} ->
        opts[:from_context] == {Hologram, :user}
      end)
  end

  # Functions are listed by module, then function name, then arity. The module order is the
  # sort below; the order within a module comes from IR.aggregate_module_funs/1 on the protocol
  # path and from the sort in render_module_function_defs/7 on the cached one.
  defp render_elixir_function_defs(mfas, ir_plt, encode_plt, async_mfas, module_info_plt) do
    mfas_by_module =
      mfas
      |> filter_elixir_mfas(ir_plt)
      |> group_mfas_by_module()
      |> Enum.sort()

    reachable_modules = MapSet.new(mfas_by_module, fn {module, _module_mfas} -> module end)

    mfas_by_module
    |> TaskUtils.map_concurrently(fn {module, module_mfas} ->
      render_module_function_defs(
        module,
        module_mfas,
        reachable_modules,
        ir_plt,
        encode_plt,
        async_mfas,
        module_info_plt
      )
    end)
    |> Enum.join("\n\n")
  end

  # A manually ported function's clauses aren't encoded, so its raise sites have
  # no attempted clauses to report. Their heads are registered separately, from
  # the IR of the Elixir function the port stands in for. The heads of the ports
  # an optional subsystem defines are registered only when it ships, since
  # without it those ports are never defined.
  defp render_manually_ported_clause_heads(ir_plt, subsystems) do
    shipped_modules = Enum.flat_map(subsystems, & &1.ported_modules)

    optional_modules =
      Enum.flat_map(@optional_runtime_subsystems, fn {_key, subsystem} ->
        subsystem.ported_modules
      end)

    CallGraph.manually_ported_elixir_mfas()
    |> Enum.reject(fn {module, _function, _arity} ->
      module in optional_modules and module not in shipped_modules
    end)
    |> Enum.map(fn {module, function, _arity} -> {module, function} end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn {module, function} ->
      render_manually_ported_clause_heads(ir_plt, module, function)
    end)
    |> Enum.join("\n")
  end

  # A raise reports the arity the function was defined with, which a default
  # argument makes differ from the arity the port replaces - Task.await/1 is
  # ported, but its clause is await/2 - so every arity is registered.
  defp render_manually_ported_clause_heads(ir_plt, module, function) do
    module_name = Reflection.module_name(module)

    case PLT.get(ir_plt, module) do
      {:ok, module_def} ->
        module_def
        |> IR.aggregate_module_funs()
        |> Enum.filter(fn {{name, _arity}, _fun} -> name == function end)
        |> Enum.sort()
        |> Enum.map(fn {{name, arity}, {visibility, clauses}} ->
          Encoder.encode_elixir_function_clause_heads(
            module_name,
            name,
            arity,
            visibility,
            clauses,
            %Context{ir_plt: ir_plt, module: module}
          )
        end)

      :error ->
        []
    end
  end

  # A protocol's dispatcher functions are selected against the whole reachable set, in
  # maybe_prune_protocol_dispatcher_function_defs/4, so their JavaScript depends on the entry
  # file being built and cannot be keyed by MFA alone. Every other module's functions encode
  # the same wherever they are reached from, so each is encoded once per compile in the common
  # case, and never differently. The module info PLT answers whether a module is a protocol and
  # which protocol a module implements, so no module is asked, or loaded, once per entry file.
  defp render_module_function_defs(
         module,
         module_mfas,
         reachable_modules,
         ir_plt,
         encode_plt,
         async_mfas,
         module_info_plt
       ) do
    context = %Context{async_mfas: async_mfas, ir_plt: ir_plt, module: module}

    if Reflection.protocol?(module, module_info_plt) do
      ir_plt
      |> PLT.get!(module)
      |> prune_module_def(module_mfas, reachable_modules, module_info_plt)
      |> Encoder.encode_ir(context)
    else
      module_mfas
      |> Enum.map(fn {_module, function, arity} -> {function, arity} end)
      |> Enum.sort()
      |> encode_module_function_defs(module, ir_plt, encode_plt, context)
      |> Enum.join("\n\n")
    end
  end

  defp render_module_metadata_registration(mfas, ir_plt, module_metadata) do
    mfas
    |> filter_elixir_mfas(ir_plt)
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Encoder.encode_module_metadata_registration(module_metadata)
  end

  # The part of a page or chunk script that leaves the script's definitions for the runtime to
  # define, with the script's digest, and announces the script (see assets/js/script_registry.mjs).
  # The digest is read from the file name of the script element running the script: both kinds of
  # file end in a dash, the digest and `.js`.
  defp render_script_announcement(defs) do
    """
    globalThis.Hologram.pendingScripts ??= [];

    globalThis.Hologram.pendingScripts.push({
      digest: new URL(document.currentScript.src).pathname.match(/-([^-]+)\\.js$/)[1],
      define: (deps) => {
        const {
          Bitstring,
          ERTS,
          ElementRefRegistry,
          HologramBoxedError,
          HologramInterpreterError,
          Interpreter,
          MemoryStorage,
          Type,
          Utils,
        } = deps;#{defs}
      },
    });

    document.dispatchEvent(new CustomEvent("hologram:scriptLoaded"));\
    """
  end

  # What a script holding the given MFAs is made of besides its wrapper: the import statements of
  # the JavaScript its modules bind (none for the modules whose bindings the runtime script
  # registers, the `runtime_js_binding_modules:` opt), and the definitions, each a block of its
  # own: the modules' stack trace metadata, the JS bindings, the Erlang and the Elixir functions.
  defp render_script_parts(mfas, ir_plt, encode_plt, async_mfas, opts) do
    js_dir = Keyword.fetch!(opts, :js_dir)
    runtime_js_binding_modules = Keyword.get(opts, :runtime_js_binding_modules, MapSet.new())

    %{imports: imports, bindings: bindings} =
      aggregate_js_imports(mfas, ir_plt, opts[:module_info_plt], runtime_js_binding_modules)

    import_statements =
      imports
      |> render_js_import_statements()
      |> render_block()

    js_bindings_registration_call =
      bindings
      |> render_js_bindings_registration_call()
      |> render_block()

    erlang_function_defs =
      mfas
      |> render_erlang_function_defs(ir_plt, Path.join(js_dir, "erlang"))
      |> render_block()

    elixir_function_defs =
      mfas
      |> render_elixir_function_defs(ir_plt, encode_plt, async_mfas, opts[:module_info_plt])
      |> render_block()

    module_metadata_registration =
      mfas
      |> render_module_metadata_registration(ir_plt, opts[:module_metadata])
      |> render_block()

    %{
      defs:
        module_metadata_registration <>
          js_bindings_registration_call <> erlang_function_defs <> elixir_function_defs,
      import_statements: import_statements
    }
  end

  # Spelled as the model's keys are, the way a query term names its entity type.
  defp render_user_entity(nil), do: "null"

  defp render_user_entity(user_entity) do
    user_entity
    |> Codec.encode_enum_value()
    |> Jason.encode!()
  end

  defp render_erlang_function_defs(mfas, ir_plt, erlang_js_dir) do
    mfas
    |> filter_erlang_mfas(ir_plt)
    |> TaskUtils.map_concurrently(fn {module, function, arity} ->
      Encoder.encode_erlang_function(module, function, arity, erlang_js_dir)
    end)
    |> Enum.join("\n\n")
  end

  defp render_js_bindings_registration_call(bindings) when bindings == %{}, do: ""

  defp render_js_bindings_registration_call(bindings) do
    modules_arg =
      bindings
      |> Enum.sort()
      |> Enum.map_join(", ", fn {module, module_bindings} ->
        module_name = Reflection.module_name(module)

        entries =
          module_bindings
          |> Enum.sort()
          |> Enum.map_join(", ", fn {as, alias} -> ~s'"#{as}": #{alias}' end)

        ~s'"#{module_name}": {#{entries}}'
      end)

    ~s'Interpreter.registerJsBindings({#{modules_arg}});'
  end

  defp render_js_import_statements(imports) do
    Enum.map_join(imports, "\n", fn %{from: from, export: export, alias: alias} ->
      ~s'import { #{export} as #{alias} } from "#{from}";'
    end)
  end

  # A module with a consolidated beam on the code path is read from it, whatever the VM has loaded.
  # The compile Phoenix's reloader runs takes the consolidated directory off the code path and
  # purges its modules, a protocol the compiler calls in that window is loaded from its own beam
  # again and stays so, and :code.which/1 then names that beam: another digest, mtime and size
  # than the consolidated beam every other compile reads, so every page reaching the protocol
  # would be rebuilt. A cover-compiled module is read from the beam its object code names.
  defp resolve_beam_source(module, consolidated_beams, umbrella?) do
    consolidated_beams[module] || resolve_beam_source(module, umbrella?)
  end

  # In umbrella projects a module can stay loaded from a consolidated protocol
  # beam that Phoenix's code reloader has purged: the reloader compiles with
  # --purge-consolidation-path-if-stale, which deletes the umbrella root
  # consolidated dir while :code.which/1 keeps pointing into it. The beam source
  # is therefore resolved through Reflection.beam_source/1, which falls back to
  # the module's object code. Single-app projects never hit that state, so they
  # resolve through a plain :code.which/1 lookup with no per-module overhead.
  # Note that this is NOT fixed by the Phoenix > 1.8.9 code reloader rework
  # (phoenixframework/phoenix#6753) - the purge flag is still passed after it.
  # TODO: Remove the umbrella branch once upstream stops leaving loaded modules
  # pointing at purged consolidated beams. That means this function,
  # Reflection.beam_source/1 and Reflection.umbrella?/0 (if nothing else uses
  # them by then), plus unwinding the umbrella? flag threaded through
  # build_ir_plt/1, build_module_info_plt!/3 and
  # rebuild_module_info_plt_entry!/6 - resolve_beam_source/3 stays, with
  # :code.which/1 as its fallback.
  defp resolve_beam_source(module, true), do: Reflection.beam_source(module)

  defp resolve_beam_source(module, false) do
    case :code.which(module) do
      :non_existing -> nil
      :cover_compiled -> cover_compiled_beam_path(module)
      beam_path -> beam_path
    end
  end

  # The previous entry is trusted only when the beam file looks untouched (same mtime and size) and was
  # written at least a second before the previous dump: mtimes have whole-second resolution, so a beam
  # rewritten during the dump's own second could match on both and still differ. A beam that came as a
  # binary (see resolve_beam_source/2) has no file to stat and is always read, as is everything when
  # there is no previous dump.
  defp reusable_module_info(module, beam_path, old_plt, dumped_at)
       when is_list(beam_path) and is_integer(dumped_at) do
    with {:ok, %{mtime: mtime, size: size} = info} when is_integer(mtime) <-
           PLT.get(old_plt, module),
         {:ok, %File.Stat{mtime: ^mtime, size: ^size}} when mtime <= dumped_at - 1 <-
           File.stat(beam_path, time: :posix),
         true <- current_module_info?(info) do
      info
    else
      _fallback -> nil
    end
  end

  defp reusable_module_info(_module, _beam_source, _old_plt, _dumped_at), do: nil

  # Runs esbuild for the given entry points (see esbuild_args/2), and returns the time it was
  # started at, in seconds: a file whose mtime is not older than that may have been written after
  # esbuild read it (see list_bundle_js_inputs/3). Raises when esbuild fails, naming what it was
  # run for with the given subject.
  # sobelow_skip ["CI.System"]
  defp run_esbuild!(entry_args, output_dir, subject, opts) do
    # Both the workspace root's and the OTP app's assets/node_modules go on
    # NODE_PATH (identical in single-app projects, hence deduplicated).
    # Non-existent dirs are silently ignored by Node.
    workspace_and_otp_app_node_modules_paths =
      [Reflection.root_dir(), Reflection.otp_app_dir()]
      |> Enum.uniq()
      |> Enum.map(&Path.join([&1, "assets", "node_modules"]))

    node_path =
      Enum.join(
        [opts[:node_modules_path] | workspace_and_otp_app_node_modules_paths],
        PathUtils.env_path_separator()
      )

    esbuild_opts = [
      env: [{"NODE_PATH", node_path}],
      parallelism: true
    ]

    started_at = System.os_time(:second)

    {_exit_msg, exit_status} =
      SystemUtils.cmd_cross_platform(
        opts[:esbuild_bin_path],
        esbuild_args(entry_args, output_dir),
        esbuild_opts
      )

    if exit_status != 0 do
      raise RuntimeError,
        message:
          "esbuild bundler failed for #{subject} (probably there were JavaScript syntax errors)"
    end

    started_at
  end

  defp carried_names_description(vocabulary) do
    case vocabulary -- Policy.framework_operations() do
      [] ->
        "no allow line in this build carries a name"

      [name] ->
        "the name this build's allow lines carry is #{inspect(name)}"

      names ->
        "the names this build's allow lines carry are #{spoken_names(names)}"
    end
  end

  defp declared_roles_description([]), do: "no entity type declares a role"

  defp declared_roles_description(role_names) do
    "declared roles are: #{Enum.map_join(role_names, ", ", &inspect/1)}"
  end

  defp put_page_user_type(entity_types, user_entity, %{reads_session_user?: true})
       when user_entity != nil do
    MapSet.put(entity_types, user_entity)
  end

  defp put_page_user_type(entity_types, _user_entity, _reach), do: entity_types

  defp put_session_user_type(entity_types, nil, _reach_by_page), do: entity_types

  defp put_session_user_type(entity_types, user_entity, reach_by_page) do
    if Enum.any?(reach_by_page, fn {_page_module, reach} -> reach.reads_session_user? end) do
      MapSet.put(entity_types, user_entity)
    else
      entity_types
    end
  end

  defp server_only_mfa_message(page_module, {module, function, arity}) do
    "page #{inspect(page_module)} reaches #{inspect(module)}.#{function}/#{arity} in its client " <>
      "code - the SQL surface runs only on the server, so the browser could not answer it. Call " <>
      "it from a command or a job instead, and send the client what it needs through an action."
  end

  # ":a", ":a and :b", ":a, :b and :c" - the spoken form, for a message listing a few names
  defp spoken_names([name]), do: inspect(name)

  defp spoken_names(names) do
    {init, [last]} = Enum.split(names, -1)

    "#{Enum.map_join(init, ", ", &inspect/1)} and #{inspect(last)}"
  end

  defp validate_operation_ask!(%{operation: {:dynamic}}, _declared), do: :ok

  defp validate_operation_ask!(%{operation: operation} = ask, %{vocabulary: vocabulary})
       when is_atom(operation) do
    if operation in vocabulary do
      :ok
    else
      raise Hologram.CompileError,
        message:
          "unknown operation #{inspect(operation)} in #{ask_location(ask)} - it is neither a framework operation nor a name an allow line carries; #{carried_names_description(vocabulary)}"
    end
  end

  # The two names a role tuple may carry - Policy's own @role_operations, which a per-type check
  # there reads and this build-wide one mirrors.
  defp validate_operation_ask!(
         %{operation: {name, role_name} = operation} = ask,
         %{role_names: role_names}
       )
       when name in [:grant_role, :revoke_role] do
    if role_name in role_names do
      :ok
    else
      raise Hologram.CompileError,
        message:
          "unknown role #{inspect(role_name)} in #{inspect(operation)} in #{ask_location(ask)} - #{declared_roles_description(role_names)}"
    end
  end

  defp validate_operation_ask!(%{operation: {:update, []} = operation} = ask, _declared) do
    raise Hologram.CompileError,
      message:
        "unknown operation #{inspect(operation)} in #{ask_location(ask)} - {:update, fields} names at least one field"
  end

  defp validate_operation_ask!(
         %{operation: {:update, field_names} = operation} = ask,
         %{field_names: declared_field_names}
       )
       when is_atom(field_names) or is_list(field_names) do
    # Not List.wrap/1 or Enum.find/2: both take a field named nil for no field at all, while the
    # run-time check judges it like any other name.
    field_names = if is_list(field_names), do: field_names, else: [field_names]

    case Enum.reject(field_names, &MapSet.member?(declared_field_names, &1)) do
      [] ->
        :ok

      [field_name | _later_names] ->
        raise Hologram.CompileError,
          message:
            "unknown field #{inspect(field_name)} in #{inspect(operation)} in #{ask_location(ask)} - no entity type has a field an update sets by that name"
    end
  end

  defp validate_operation_ask!(%{operation: operation} = ask, _declared) do
    raise Hologram.CompileError,
      message:
        "unknown operation #{inspect(operation)} in #{ask_location(ask)} - the operation tuples are {:grant_role, role}, {:revoke_role, role}, {:update, field} and {:update, fields}"
  end

  defp template_ref_components({:component, module}), do: [module]

  defp template_ref_components({:ref, _name, _part_count}), do: []

  defp template_ref_components({:loop, body}), do: template_ref_components(body)

  defp template_ref_components({_kind, parts}),
    do: Enum.flat_map(parts, &template_ref_components/1)

  defp validate_atom_ref(name, occurrences, root_label) do
    # A loop in a branch that doesn't count still repeats the ref whenever that branch renders.
    case {Enum.find(occurrences, & &1.loop), Enum.filter(occurrences, & &1.counted?)} do
      {nil, [first, second | _rest]} ->
        hint =
          if separate_blocks?(first, second) do
            " - two {%if} blocks can both render, so elements that take turns go in the branches of one {%if} and {%else}"
          else
            ""
          end

        places =
          if ref_place(first) == ref_place(second) do
            "both #{ref_place(first)}"
          else
            "one #{ref_place(first)} and one #{ref_place(second)}"
          end

        raise Hologram.CompileError,
          message:
            "the ref #{inspect(name)} would name two elements in #{root_label}, #{places} - " <>
              "#{atom_ref_advice(name)}#{hint}"

      {nil, _occurrences} ->
        :ok

      {occurrence, _occurrences} ->
        raise Hologram.CompileError,
          message:
            "the ref #{inspect(name)}, #{ref_place(occurrence)}, would name an element " <>
              "#{ref_loop_text(occurrence.loop)} - #{atom_ref_advice(name)}"
    end
  end

  defp validate_module_prop_usages(module, ir) do
    usages =
      ir
      |> template_ir()
      |> list_component_usages()

    Enum.each(usages, &validate_prop_usage(&1, module))

    usages
  end

  # Only the template's own DOM is validated. A component node is an ordinary 4-tuple, so code
  # elsewhere in the module - a helper building DOM by hand, a fixture - can hold one without any
  # template rendering it, and validating those would fail a build over a component nobody uses.
  defp template_ir(%IR.ModuleDefinition{body: %IR.Block{expressions: expressions}}) do
    Enum.find(expressions, &match?(%IR.FunctionDefinition{name: :template, arity: 0}, &1))
  end

  defp template_ir(_ir), do: nil

  # A spread decides only whether a prop is present, so it blocks the required check and nothing
  # else. A value written at the usage is judged either way: being overridden by a later spread
  # doesn't make an invalid literal valid, it just makes it dead as well as wrong.
  defp validate_page_layout(page_module, nil) do
    if !Reflection.has_function?(page_module, :__layout_module__, 0) do
      module_name = Reflection.module_name(page_module)

      raise Hologram.CompileError,
        message:
          "page '#{module_name}' doesn't have a layout module specified (use the layout/1 macro to fix it)"
    end
  end

  defp validate_page_layout(_page_module, _layout_module), do: :ok

  # A route the module info PLT does not hold is either missing or built at runtime; only the second
  # can be asked from the page.
  defp validate_page_route(page_module, nil) do
    if !Reflection.has_function?(page_module, :__route__, 0) do
      module_name = Reflection.module_name(page_module)

      raise Hologram.CompileError,
        message:
          "page '#{module_name}' doesn't have a route specified (use the route/1 macro to fix it)"
    end

    validate_page_route_type(page_module, page_module.__route__())
  end

  defp validate_page_route(page_module, route), do: validate_page_route_type(page_module, route)

  defp validate_page_route_type(_page_module, route) when is_binary(route), do: :ok

  defp validate_page_route_type(page_module, route) do
    module_name = Reflection.module_name(page_module)

    raise Hologram.CompileError,
      message:
        "page '#{module_name}' has a route that is not a string: #{inspect(route)} (pass a string to the route/1 macro to fix it)"
  end

  defp validate_prop_usage({component_module, prop_entries, has_spread?}, module) do
    if Reflection.has_function?(component_module, :__props__, 0) do
      validate_required_props(component_module, prop_entries, has_spread?, module)

      # Matched rather than iterated: both error functions only raise, so a capture of one would be
      # an anonymous function with no local return. Reporting the first violation is what iterating
      # did anyway - the raise ended it.
      case invalid_prop_values(component_module, prop_entries) do
        [] -> :ok
        [violation | _rest] -> component_value_error!(component_module, violation, module)
      end
    end
  end

  defp validate_ref_part_counts(name, [first | _rest] = occurrences, root_label) do
    case Enum.find(occurrences, &(&1.part_count != first.part_count)) do
      nil ->
        :ok

      other ->
        raise Hologram.CompileError,
          message:
            "the ref #{inspect(name)} takes #{parts_text(first.part_count)} after its name #{ref_place(first)}, " <>
              "and #{parts_text(other.part_count)} #{ref_place(other)}, both in #{root_label} - " <>
              "a ref name takes the same number of parts everywhere it can render"
    end
  end

  # A spread could supply any prop, so nothing can be proven missing at a usage carrying one.
  defp validate_required_props(_component_module, _prop_entries, true, _module), do: :ok

  defp validate_required_props(component_module, prop_entries, false, module) do
    prop_names = Enum.map(prop_entries, fn {name, _value} -> name end)

    case missing_required_props(component_module, prop_names) do
      [] -> :ok
      [name | _rest] -> component_usage_error!(component_module, name, module)
    end
  end

  # The first mistake by name, so the message doesn't depend on the order the templates render in:
  # a name used with different numbers of parts, then an atom ref that a loop or a recursion
  # repeats, then one rendered twice.
  defp validate_root_refs(refs, root_label) do
    refs
    |> Enum.group_by(& &1.name)
    |> Enum.sort()
    |> Enum.each(fn {name, occurrences} ->
      validate_ref_part_counts(name, occurrences, root_label)
      validate_atom_ref(name, Enum.filter(occurrences, &(&1.part_count == 0)), root_label)
    end)
  end
end
