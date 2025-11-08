defmodule Hologram.Framework do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection

  @elixir_stdlib_module_groups [
    {"Core",
     [
       Kernel
     ]},
    {"Data Types",
     [
       Atom,
       Base,
       Bitwise,
       Date,
       DateTime,
       Duration,
       Exception,
       Float,
       Function,
       Integer,
       JSON,
       Module,
       NaiveDateTime,
       Record,
       Regex,
       String,
       Time,
       Tuple,
       URI,
       Version,
       Version.Requirement
     ]},
    {"Collections & Enumerables",
     [
       Access,
       Date.Range,
       Enum,
       Keyword,
       List,
       Map,
       MapSet,
       Range,
       Stream
     ]},
    {"IO & System",
     [
       File,
       File.Stat,
       File.Stream,
       IO,
       IO.ANSI,
       IO.Stream,
       OptionParser,
       Path,
       Port,
       StringIO,
       System
     ]},
    {"Calendar",
     [
       Calendar,
       Calendar.ISO,
       Calendar.TimeZoneDatabase,
       Calendar.UTCOnlyTimeZoneDatabase
     ]},
    {"Processes & Applications",
     [
       Agent,
       Application,
       Config,
       Config.Provider,
       Config.Reader,
       DynamicSupervisor,
       GenServer,
       Node,
       PartitionSupervisor,
       Process,
       Registry,
       Supervisor,
       Task,
       Task.Supervisor
     ]},
    {"Protocols",
     [
       Collectable,
       Enumerable,
       Inspect,
       Inspect.Algebra,
       Inspect.Opts,
       List.Chars,
       Protocol,
       String.Chars
     ]},
    {"Code & Macros",
     [
       Code,
       Code.Fragment,
       Kernel.ParallelCompiler,
       Macro,
       Macro.Env
     ]},
    {"Exceptions",
     [
       ArgumentError,
       ArithmeticError,
       BadArityError,
       BadBooleanError,
       BadFunctionError,
       BadMapError,
       CaseClauseError,
       Code.LoadError,
       CompileError,
       CondClauseError,
       Enum.EmptyError,
       Enum.OutOfBoundsError,
       ErlangError,
       File.CopyError,
       File.Error,
       File.LinkError,
       File.RenameError,
       FunctionClauseError,
       IO.StreamError,
       Inspect.Error,
       JSON.DecodeError,
       Kernel.TypespecError,
       KeyError,
       MatchError,
       MismatchedDelimiterError,
       MissingApplicationsError,
       OptionParser.ParseError,
       Protocol.UndefinedError,
       Regex.CompileError,
       RuntimeError,
       SyntaxError,
       System.EnvError,
       SystemLimitError,
       TokenMissingError,
       TryClauseError,
       URI.Error,
       UndefinedFunctionError,
       UnicodeConversionError,
       Version.InvalidRequirementError,
       Version.InvalidVersionError,
       WithClauseError
     ]}
  ]

  @doc """
  Aggregates information about Elixir standard library functions.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with required keys:
    - `:deferred_elixir_funs` - List of Elixir MFA tuples that are deferred
    - `:in_progress_erlang_funs` - List of Erlang MFA tuples currently being ported
    - `:deferred_erlang_funs` - List of Erlang MFA tuples that are deferred
  """
  @spec elixir_funs_info(Path.t(), keyword()) :: %{
          mfa => %{
            status: :done | :in_progress | :todo | :deferred,
            progress: non_neg_integer(),
            method: :auto | :manual,
            dependencies: [mfa],
            dependencies_count: non_neg_integer()
          }
        }
  def elixir_funs_info(erlang_js_dir, opts) do
    deferred_elixir_funs = Keyword.fetch!(opts, :deferred_elixir_funs)
    in_progress_erlang_funs = Keyword.fetch!(opts, :in_progress_erlang_funs)
    deferred_erlang_funs = Keyword.fetch!(opts, :deferred_erlang_funs)

    deferred_elixir_funs_set = MapSet.new(deferred_elixir_funs)

    elixir_deps = elixir_stdlib_erlang_deps()

    erlang_funs_info =
      erlang_funs_info(erlang_js_dir,
        in_progress_erlang_funs: in_progress_erlang_funs,
        deferred_erlang_funs: deferred_erlang_funs
      )

    for {module, funs} <- elixir_deps, {{fun, arity}, erlang_deps} <- funs, into: %{} do
      elixir_mfa = {module, fun, arity}

      status =
        calculate_elixir_fun_status(
          elixir_mfa,
          erlang_deps,
          erlang_funs_info,
          deferred_elixir_funs_set
        )

      progress = calculate_elixir_fun_progress(erlang_deps, erlang_funs_info)

      {elixir_mfa,
       %{
         status: status,
         progress: progress,
         method: elixir_fun_method(elixir_mfa),
         dependencies: erlang_deps,
         dependencies_count: length(erlang_deps)
       }}
    end
  end

  @doc """
  Aggregates information about Elixir standard library modules.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with required keys:
    - `:deferred_elixir_modules` - List of Elixir modules that are deferred
    - `:deferred_elixir_funs` - List of Elixir MFA tuples that are deferred
    - `:in_progress_erlang_funs` - List of Erlang MFA tuples currently being worked on
    - `:deferred_erlang_funs` - List of Erlang MFA tuples that are deferred   
  """
  @spec elixir_modules_info(Path.t(), keyword()) :: %{
          module => %{
            group: String.t(),
            status: :done | :in_progress | :todo | :deferred,
            progress: non_neg_integer(),
            functions: [{atom, arity}],
            all_fun_count: non_neg_integer(),
            done_fun_count: non_neg_integer(),
            in_progress_fun_count: non_neg_integer(),
            todo_fun_count: non_neg_integer(),
            deferred_fun_count: non_neg_integer()
          }
        }
  # credo:disable-for-lines:46 Credo.Check.Refactor.ABCSize
  def elixir_modules_info(erlang_js_dir, opts) do
    deferred_elixir_modules = Keyword.fetch!(opts, :deferred_elixir_modules)
    deferred_elixir_funs = Keyword.fetch!(opts, :deferred_elixir_funs)
    in_progress_erlang_funs = Keyword.fetch!(opts, :in_progress_erlang_funs)
    deferred_erlang_funs = Keyword.fetch!(opts, :deferred_erlang_funs)

    deferred_elixir_modules_set = MapSet.new(deferred_elixir_modules)

    elixir_funs_info =
      elixir_funs_info(erlang_js_dir,
        deferred_elixir_funs: deferred_elixir_funs,
        in_progress_erlang_funs: in_progress_erlang_funs,
        deferred_erlang_funs: deferred_erlang_funs
      )

    elixir_stdlib_module_groups = elixir_stdlib_module_groups()

    module_to_group = map_module_to_group(elixir_stdlib_module_groups)

    for {_group, modules} <- elixir_stdlib_module_groups, module <- modules, into: %{} do
      group = module_to_group[module]
      functions = module.__info__(:functions)

      module_funs_info =
        for {fun, arity} <- functions do
          elixir_funs_info[{module, fun, arity}]
        end

      status =
        calculate_elixir_module_status(module, module_funs_info, deferred_elixir_modules_set)

      progress = calculate_elixir_module_progress(module_funs_info)
      fun_counts = aggregate_counts_by_status(module_funs_info, "fun", & &1.status)

      {module,
       %{
         group: group,
         status: status,
         progress: progress,
         functions: functions,
         all_fun_count: length(functions),
         done_fun_count: fun_counts.done_fun_count,
         in_progress_fun_count: fun_counts.in_progress_fun_count,
         todo_fun_count: fun_counts.todo_fun_count,
         deferred_fun_count: fun_counts.deferred_fun_count
       }}
    end
  end

  @doc """
  Returns overview statistics of Elixir functions porting status.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with required keys:
    - `:deferred_elixir_modules` - List of Elixir modules that are deferred
    - `:deferred_elixir_funs` - List of Elixir MFA tuples that are deferred
    - `:in_progress_erlang_funs` - List of Erlang MFA tuples currently being ported
    - `:deferred_erlang_funs` - List of Erlang MFA tuples that are deferred
  """
  @spec elixir_overview_stats(Path.t(), keyword()) :: %{
          done_fun_count: non_neg_integer(),
          in_progress_fun_count: non_neg_integer(),
          todo_fun_count: non_neg_integer(),
          deferred_fun_count: non_neg_integer(),
          done_module_count: non_neg_integer(),
          in_progress_module_count: non_neg_integer(),
          todo_module_count: non_neg_integer(),
          deferred_module_count: non_neg_integer(),
          progress: non_neg_integer()
        }
  def elixir_overview_stats(erlang_js_dir, opts) do
    elixir_funs_info = elixir_funs_info(erlang_js_dir, opts)
    status_fetcher = fn {_elixir_mfa, %{status: status}} -> status end
    fun_stats = aggregate_counts_by_status(elixir_funs_info, "fun", status_fetcher)

    elixir_modules_info = elixir_modules_info(erlang_js_dir, opts)
    status_fetcher = fn {_module, %{status: status}} -> status end
    module_stats = aggregate_counts_by_status(elixir_modules_info, "module", status_fetcher)

    progress = calculate_elixir_overall_progress(elixir_funs_info)

    fun_stats
    |> Map.merge(module_stats)
    |> Map.put(:progress, progress)
  end

  @doc """
  Returns Erlang dependencies for Elixir standard library modules.

  Analyzes the call graph of selected Elixir standard library modules and identifies
  which Erlang functions they depend on. Manually ported functions are excluded.

  ## Return Structure

  Returns a two-level nested map:
  - **Level 1**: Module (atom) -> functions in that module  
  - **Level 2**: Function key `{name, arity}` -> list of reachable Erlang MFAs

  ## Example

      iex> deps = elixir_stdlib_erlang_deps()
      iex> deps[Kernel][{:hd, 1}]
      [{:erlang, :hd, 1}]
  """
  @spec elixir_stdlib_erlang_deps() :: %{module => %{{fun, arity} => [mfa]}}
  def elixir_stdlib_erlang_deps do
    graph =
      stdlib_ir_plt()
      |> Compiler.build_call_graph()
      |> CallGraph.remove_manually_ported_mfas()
      |> CallGraph.get_graph()

    # Now query the graph for each documented stdlib function
    elixir_stdlib_module_groups()
    |> Enum.flat_map(fn {_group, modules} -> modules end)
    |> Enum.reduce(%{}, fn module, modules_acc ->
      module_map =
        for {fun, arity} <- module.__info__(:functions), into: %{} do
          reachable_erlang_mfas = reachable_erlang_mfas(graph, {module, fun, arity})
          {{fun, arity}, reachable_erlang_mfas}
        end

      Map.put(modules_acc, module, module_map)
    end)
  end

  @doc """
  Returns grouped Elixir standard library modules.

  The return value is a list of pairs `{group_name, modules}` where
  `group_name` is a string and `modules` is a list of Elixir module atoms.

  Modules that are not available in the current Elixir version are automatically filtered out.
  """
  @spec elixir_stdlib_module_groups() :: [{String.t(), [module]}]
  def elixir_stdlib_module_groups do
    Enum.map(@elixir_stdlib_module_groups, fn {group_name, modules} ->
      available_modules = Enum.filter(modules, &Code.ensure_loaded?/1)
      {group_name, available_modules}
    end)
  end

  @doc """
  Aggregates information about Erlang functions used by Elixir stdlib.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with required keys:
    - `:in_progress_erlang_funs` - List of MFA tuples currently being ported
    - `:deferred_erlang_funs` - List of MFA tuples that are deferred
    
    Note: `:in_progress` takes precedence over `:deferred` when determining status.
  """
  @spec erlang_funs_info(Path.t(), keyword()) :: %{
          mfa => %{
            status: :done | :in_progress | :todo | :deferred,
            dependents: [mfa],
            dependents_count: non_neg_integer()
          }
        }
  def erlang_funs_info(erlang_js_dir, opts) do
    modules_map = elixir_stdlib_erlang_deps()

    done_erlang_funs_set =
      erlang_js_dir
      |> list_ported_erlang_funs()
      |> MapSet.new()

    in_progress_erlang_funs_set =
      opts
      |> Keyword.fetch!(:in_progress_erlang_funs)
      |> MapSet.new()

    deferred_erlang_funs_set =
      opts
      |> Keyword.fetch!(:deferred_erlang_funs)
      |> MapSet.new()

    modules_map
    |> dependents_by_erlang_mfa()
    |> Enum.map(fn {erlang_mfa, dependents} ->
      unique_dependents = Enum.uniq(dependents)

      status =
        calculate_erlang_fun_status(
          erlang_mfa,
          done_erlang_funs_set,
          in_progress_erlang_funs_set,
          deferred_erlang_funs_set
        )

      {erlang_mfa,
       %{
         status: status,
         dependents: unique_dependents,
         dependents_count: length(unique_dependents)
       }}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns overview statistics of Erlang functions porting status.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with required keys:
    - `:in_progress_erlang_funs` - List of Erlang MFA tuples currently being ported
    - `:deferred_erlang_funs` - List of Erlang MFA tuples that are deferred
  """
  @spec erlang_overview_stats(Path.t(), keyword()) :: %{
          done_count: non_neg_integer(),
          in_progress_count: non_neg_integer(),
          todo_count: non_neg_integer(),
          deferred_count: non_neg_integer(),
          progress: non_neg_integer()
        }
  def erlang_overview_stats(erlang_js_dir, opts) do
    erlang_funs_info = erlang_funs_info(erlang_js_dir, opts)

    status_fetcher = fn {_mfa, %{status: status}} -> status end
    stats = aggregate_counts_by_status(erlang_funs_info, "fun", status_fetcher)

    # Deferred functions are excluded from the calculation
    total_relevant_fun_count =
      stats.done_fun_count + stats.todo_fun_count + stats.in_progress_fun_count

    progress =
      if total_relevant_fun_count > 0 do
        round(stats.done_fun_count * 100 / total_relevant_fun_count)
      else
        0
      end

    Map.put(stats, :progress, progress)
  end

  @doc """
  Lists all manually ported Erlang functions.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions JavaScript files in the Hologram library

  ## Returns

  A list of MFAs (module, function, arity tuples).

  ## Example

      iex> list_ported_erlang_funs("assets/js/erlang")
      [{:erlang, :*, 2}, {:lists, :flatten, 1}, {:maps, :get, 2}, ...]
  """
  @spec list_ported_erlang_funs(Path.t()) :: [mfa]
  def list_ported_erlang_funs(erlang_js_dir) do
    erlang_js_dir
    |> File.ls!()
    |> Enum.flat_map(fn file ->
      module = extract_module_name(file)
      path = Path.join(erlang_js_dir, file)

      path
      |> File.read!()
      |> extract_function_signatures()
      |> Enum.map(fn {fun, arity} -> {module, fun, arity} end)
    end)
  end

  defp aggregate_counts_by_status(items_info, item_type, status_fetcher) do
    Enum.reduce(
      items_info,
      %{
        "done_#{item_type}_count": 0,
        "in_progress_#{item_type}_count": 0,
        "todo_#{item_type}_count": 0,
        "deferred_#{item_type}_count": 0
      },
      fn item_info, acc ->
        status = status_fetcher.(item_info)
        count_key = String.to_existing_atom("#{status}_#{item_type}_count")
        Map.update!(acc, count_key, &(&1 + 1))
      end
    )
  end

  defp calculate_elixir_fun_progress([], _erlang_funs_info), do: 100

  defp calculate_elixir_fun_progress(erlang_deps, erlang_funs_info) do
    done_dep_count = Enum.count(erlang_deps, &(erlang_funs_info[&1].status == :done))
    round(done_dep_count * 100 / length(erlang_deps))
  end

  defp calculate_elixir_fun_status(
         elixir_mfa,
         erlang_deps,
         erlang_funs_info,
         deferred_elixir_funs_set
       ) do
    cond do
      Enum.all?(erlang_deps, &(erlang_funs_info[&1].status == :done)) ->
        :done

      MapSet.member?(deferred_elixir_funs_set, elixir_mfa) ->
        :deferred

      Enum.any?(erlang_deps, &(erlang_funs_info[&1].status in [:done, :in_progress])) ->
        :in_progress

      true ->
        :todo
    end
  end

  defp calculate_elixir_module_progress(elixir_funs_info)

  defp calculate_elixir_module_progress([]), do: 100

  defp calculate_elixir_module_progress(elixir_funs_info) do
    progress_sum = Enum.reduce(elixir_funs_info, 0, &(&2 + &1.progress))
    round(progress_sum / length(elixir_funs_info))
  end

  defp calculate_elixir_module_status(module, elixir_funs_info, deferred_elixir_modules_set) do
    cond do
      Enum.all?(elixir_funs_info, &(&1.status == :done)) ->
        :done

      MapSet.member?(deferred_elixir_modules_set, module) ->
        :deferred

      Enum.any?(elixir_funs_info, &(&1.status in [:done, :in_progress])) ->
        :in_progress

      true ->
        :todo
    end
  end

  # Calculate progress as average of non-deferred function progresses
  defp calculate_elixir_overall_progress(elixir_funs_info) do
    non_deferred_funs =
      Enum.filter(elixir_funs_info, fn {_elixir_mfa, info} -> info.status != :deferred end)

    non_deferred_fun_count = length(non_deferred_funs)

    if non_deferred_fun_count > 0 do
      total_progress =
        Enum.reduce(elixir_funs_info, 0, fn {_elixir_mfa, info}, acc ->
          acc + info.progress
        end)

      round(total_progress / non_deferred_fun_count)
    else
      0
    end
  end

  defp calculate_erlang_fun_status(
         erlang_mfa,
         done_erlang_funs_set,
         in_progress_erlang_funs_set,
         deferred_erlang_funs_set
       ) do
    cond do
      MapSet.member?(done_erlang_funs_set, erlang_mfa) -> :done
      MapSet.member?(in_progress_erlang_funs_set, erlang_mfa) -> :in_progress
      MapSet.member?(deferred_erlang_funs_set, erlang_mfa) -> :deferred
      true -> :todo
    end
  end

  # Build a map of erlang_mfa => list of elixir mfas that depend on it
  defp dependents_by_erlang_mfa(modules_map) do
    for {module, funs} <- modules_map,
        {{fun, arity}, erlang_mfas} <- funs,
        erlang_mfa <- erlang_mfas,
        reduce: %{} do
      acc ->
        Map.update(acc, erlang_mfa, [{module, fun, arity}], fn existing ->
          [{module, fun, arity} | existing]
        end)
    end
  end

  defp elixir_fun_method(elixir_mfa) do
    if elixir_mfa in CallGraph.manually_ported_elixir_mfas() do
      :manual
    else
      :auto
    end
  end

  defp extract_function_signatures(content) do
    ~r/\/\/ Start (.+?)\/(\d+)/
    |> Regex.scan(content)
    |> Enum.map(fn [_full, fun, arity] ->
      {String.to_existing_atom(fun), String.to_integer(arity)}
    end)
  end

  defp extract_module_name(filename) do
    filename
    |> Path.basename(".mjs")
    |> String.to_existing_atom()
  end

  # Build a map of module => group
  defp map_module_to_group(module_groups) do
    module_groups
    |> Enum.flat_map(fn {group, modules} ->
      Enum.map(modules, fn module -> {module, group} end)
    end)
    |> Enum.into(%{})
  end

  defp reachable_erlang_mfas(graph, source_mfa) do
    graph
    |> CallGraph.reachable_mfas([source_mfa])
    |> Enum.filter(fn {module, _fun, _arity} -> Reflection.erlang_module?(module) end)
  end

  defp stdlib_ir_plt do
    # Build IR PLT for all modules, then filter to only :elixir OTP app modules
    # This includes both documented stdlib modules AND internal implementation modules
    # that are part of the Elixir stdlib (e.g., String.Break, Enum.EmptyError)
    ir_plt = Compiler.build_ir_plt()

    stdlib_ir_items =
      ir_plt
      |> PLT.get_all()
      |> Enum.filter(fn {module, _ir} ->
        case :application.get_application(module) do
          {:ok, :elixir} -> true
          _other -> false
        end
      end)

    # Build call graph only from :elixir app modules
    # This ensures we only include edges within stdlib (including internal modules)
    # and to Erlang modules, without edges from non-stdlib modules
    PLT.start(items: stdlib_ir_items)
  end
end
