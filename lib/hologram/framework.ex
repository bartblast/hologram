defmodule Hologram.Framework do
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection

  @elixir_stdlib_module_groups [
    {"Core",
     [
       Kernel
       #  Kernel.SpecialForms
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
       JSON.Encoder,
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
  - `opts` - Keyword list with optional keys:
    - `:deferred_elixir` - List of Elixir MFA tuples that are deferred (defaults to [])
    - `:in_progress_erlang` - List of Erlang MFA tuples currently being ported (defaults to [])
    - `:deferred_erlang` - List of Erlang MFA tuples that are deferred (defaults to [])
  """
  @spec elixir_funs_info(Path.t(), keyword()) :: %{
          mfa => %{
            status: :done | :in_progress | :todo | :deferred,
            progress: non_neg_integer(),
            dependencies: [mfa],
            dependencies_count: non_neg_integer()
          }
        }
  def elixir_funs_info(erlang_js_dir, opts \\ []) do
    deferred_elixir = Keyword.get(opts, :deferred_elixir, [])
    in_progress_erlang = Keyword.get(opts, :in_progress_erlang, [])
    deferred_erlang = Keyword.get(opts, :deferred_erlang, [])

    deferred_elixir_set = MapSet.new(deferred_elixir)

    elixir_deps = elixir_stdlib_erlang_deps()

    erlang_funs_info =
      erlang_funs_info(erlang_js_dir,
        in_progress: in_progress_erlang,
        deferred: deferred_erlang
      )

    elixir_deps
    |> Enum.flat_map(fn {module, funs} ->
      Enum.map(funs, fn {{fun, arity}, erlang_deps} ->
        elixir_mfa = {module, fun, arity}

        status =
          calculate_elixir_fun_status(
            elixir_mfa,
            erlang_deps,
            erlang_funs_info,
            deferred_elixir_set
          )

        progress = calculate_elixir_fun_progress(erlang_deps, erlang_funs_info)

        {elixir_mfa,
         %{
           status: status,
           progress: progress,
           dependencies: erlang_deps,
           dependencies_count: length(erlang_deps)
         }}
      end)
    end)
    |> Enum.into(%{})
  end

  @doc """
  Aggregates information about Elixir standard library modules.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with optional keys:
    - `:deferred_elixir_modules` - List of Elixir modules that are deferred (defaults to [])
    - `:deferred_elixir_funs` - List of Elixir MFA tuples that are deferred (defaults to [])
    - `:in_progress_erlang_funs` - List of Erlang MFA tuples currently being worked on (defaults to [])
    - `:deferred_erlang_funs` - List of Erlang MFA tuples that are deferred (defaults to [])    
  """
  @spec elixir_modules_info(Path.t(), keyword()) :: %{
          module => %{
            group: String.t(),
            status: :done | :in_progress | :todo | :deferred,
            progress: non_neg_integer(),
            functions: [{atom, arity}],
            functions_count: non_neg_integer()
          }
        }
  def elixir_modules_info(erlang_js_dir, opts \\ []) do
    deferred_elixir_modules = Keyword.get(opts, :deferred_elixir_modules, [])
    deferred_elixir_funs = Keyword.get(opts, :deferred_elixir_funs, [])
    in_progress_erlang_funs = Keyword.get(opts, :in_progress_erlang_funs, [])
    deferred_erlang_funs = Keyword.get(opts, :deferred_erlang_funs, [])

    deferred_elixir_modules_set = MapSet.new(deferred_elixir_modules)

    elixir_funs_info =
      elixir_funs_info(erlang_js_dir,
        deferred_elixir: deferred_elixir_funs,
        in_progress_erlang: in_progress_erlang_funs,
        deferred_erlang: deferred_erlang_funs
      )

    # Build a map of module => group
    module_to_group =
      @elixir_stdlib_module_groups
      |> Enum.flat_map(fn {group, modules} ->
        Enum.map(modules, fn module -> {module, group} end)
      end)
      |> Enum.into(%{})

    @elixir_stdlib_module_groups
    |> Enum.flat_map(fn {_group, modules} -> modules end)
    |> Enum.map(fn module ->
      group = module_to_group[module]
      functions = module.__info__(:functions)
      functions_count = length(functions)

      fun_infos =
        Enum.map(functions, fn {fun, arity} ->
          elixir_funs_info[{module, fun, arity}]
        end)

      status = calculate_elixir_module_status(module, fun_infos, deferred_elixir_modules_set)
      progress = calculate_elixir_module_progress(fun_infos)

      {module,
       %{
         group: group,
         status: status,
         progress: progress,
         functions: functions,
         functions_count: functions_count
       }}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns overview statistics of Elixir functions porting status.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with optional keys:
    - `:deferred_elixir_modules` - List of Elixir modules that are deferred (defaults to [])
    - `:deferred_elixir_funs` - List of Elixir MFA tuples that are deferred (defaults to [])
    - `:in_progress_erlang_funs` - List of Erlang MFA tuples currently being ported (defaults to [])
    - `:deferred_erlang_funs` - List of Erlang MFA tuples that are deferred (defaults to [])
  """
  @spec elixir_overview_stats(Path.t(), keyword()) :: %{
          done_count: non_neg_integer(),
          in_progress_count: non_neg_integer(),
          todo_count: non_neg_integer(),
          deferred_count: non_neg_integer(),
          progress: non_neg_integer()
        }
  def elixir_overview_stats(erlang_js_dir, opts \\ []) do
    elixir_funs_info =
      elixir_funs_info(erlang_js_dir,
        deferred_elixir: Keyword.get(opts, :deferred_elixir_funs, []),
        in_progress_erlang: Keyword.get(opts, :in_progress_erlang_funs, []),
        deferred_erlang: Keyword.get(opts, :deferred_erlang_funs, [])
      )

    stats =
      Enum.reduce(
        elixir_funs_info,
        %{done_count: 0, in_progress_count: 0, deferred_count: 0, todo_count: 0},
        fn {_mfa, %{status: status}}, acc ->
          count_key = String.to_existing_atom("#{status}_count")
          Map.update!(acc, count_key, &(&1 + 1))
        end
      )

    non_deferred_funs =
      Enum.filter(elixir_funs_info, fn {_mfa, info} -> info.status != :deferred end)

    non_deferred_funs_count = length(non_deferred_funs)

    # Calculate progress as average of non-deferred function progresses      
    progress =
      if non_deferred_funs_count > 0 do
        total_progress =
          Enum.reduce(non_deferred_funs, 0, fn {_mfa, info}, acc ->
            acc + info.progress
          end)

        round(total_progress / non_deferred_funs_count)
      else
        0
      end

    Map.put(stats, :progress, progress)
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
      Compiler.build_call_graph()
      |> CallGraph.remove_manually_ported_mfas()
      |> CallGraph.get_graph()

    @elixir_stdlib_module_groups
    |> Enum.flat_map(fn {_group, modules} -> modules end)
    |> Enum.reduce(%{}, fn module, modules_acc ->
      module_map =
        Enum.reduce(module.__info__(:functions), %{}, fn {fun, arity}, funs_acc ->
          reachable_erlang_mfas = reachable_erlang_mfas(graph, {module, fun, arity})
          Map.put(funs_acc, {fun, arity}, reachable_erlang_mfas)
        end)

      Map.put(modules_acc, module, module_map)
    end)
  end

  @doc """
  Returns grouped Elixir standard library modules.

  The return value is a list of pairs `{group_name, modules}` where
  `group_name` is a string and `modules` is a list of Elixir module atoms.
  """
  @spec elixir_stdlib_module_groups() :: [{String.t(), [module]}]
  def elixir_stdlib_module_groups, do: @elixir_stdlib_module_groups

  @doc """
  Aggregates information about Erlang functions used by Elixir stdlib.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with optional keys:
    - `:in_progress` - List of MFA tuples currently being ported (defaults to [])
    - `:deferred` - List of MFA tuples that are deferred (defaults to [])
    
    Note: `:in_progress` takes precedence over `:deferred` when determining status.
  """
  @spec erlang_funs_info(Path.t(), keyword()) :: %{
          mfa => %{
            status: :done | :in_progress | :todo | :deferred,
            dependents: [mfa],
            dependents_count: non_neg_integer()
          }
        }
  def erlang_funs_info(erlang_js_dir, opts \\ []) do
    modules_map = elixir_stdlib_erlang_deps()

    ported_erlang_funs =
      erlang_js_dir
      |> list_ported_erlang_funs()
      |> MapSet.new()

    in_progress_mfas = Keyword.get(opts, :in_progress, [])
    deferred_mfas = Keyword.get(opts, :deferred, [])

    in_progress_set = MapSet.new(in_progress_mfas)
    deferred_set = MapSet.new(deferred_mfas)

    # Build a map of erlang_mfa => list of elixir mfas that depend on it
    dependents_by_erlang_mfa =
      modules_map
      |> Enum.flat_map(fn {module, funs} ->
        Enum.flat_map(funs, fn {{fun, arity}, erlang_mfas} ->
          Enum.map(erlang_mfas, fn erlang_mfa ->
            {erlang_mfa, {module, fun, arity}}
          end)
        end)
      end)
      |> Enum.reduce(%{}, fn {erlang_mfa, elixir_mfa}, acc ->
        Map.update(acc, erlang_mfa, [elixir_mfa], fn existing ->
          [elixir_mfa | existing]
        end)
      end)

    dependents_by_erlang_mfa
    |> Enum.map(fn {erlang_mfa, dependents} ->
      unique_dependents = Enum.uniq(dependents)

      status =
        cond do
          MapSet.member?(ported_erlang_funs, erlang_mfa) -> :done
          MapSet.member?(in_progress_set, erlang_mfa) -> :in_progress
          MapSet.member?(deferred_set, erlang_mfa) -> :deferred
          true -> :todo
        end

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
  - `opts` - Keyword list with optional keys:
    - `:in_progress` - List of Erlang MFA tuples currently being ported (defaults to [])
    - `:deferred` - List of Erlang MFA tuples that are deferred (defaults to [])
  """
  @spec erlang_overview_stats(Path.t(), keyword()) :: %{
          done_count: non_neg_integer(),
          in_progress_count: non_neg_integer(),
          todo_count: non_neg_integer(),
          deferred_count: non_neg_integer(),
          progress: non_neg_integer()
        }
  def erlang_overview_stats(erlang_js_dir, opts \\ []) do
    erlang_info = erlang_funs_info(erlang_js_dir, opts)

    stats =
      Enum.reduce(
        erlang_info,
        %{done_count: 0, in_progress_count: 0, deferred_count: 0, todo_count: 0},
        fn {_mfa, %{status: status}}, acc ->
          count_key = String.to_existing_atom("#{status}_count")
          Map.update!(acc, count_key, &(&1 + 1))
        end
      )

    # Deferred functions are excluded from the calculation
    total_relevant = stats.done_count + stats.todo_count + stats.in_progress_count

    progress =
      if total_relevant > 0 do
        round(stats.done_count * 100 / total_relevant)
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

  defp calculate_elixir_fun_progress([], _erlang_info), do: 100

  defp calculate_elixir_fun_progress(erlang_deps, erlang_info) do
    done_count = Enum.count(erlang_deps, &(erlang_info[&1].status == :done))
    round(done_count * 100 / length(erlang_deps))
  end

  defp calculate_elixir_fun_status(elixir_mfa, erlang_deps, erlang_info, deferred_elixir_set) do
    cond do
      Enum.all?(erlang_deps, &(erlang_info[&1].status == :done)) ->
        :done

      MapSet.member?(deferred_elixir_set, elixir_mfa) ->
        :deferred

      Enum.any?(erlang_deps, &(erlang_info[&1].status == :in_progress)) ->
        :in_progress

      true ->
        :todo
    end
  end

  defp calculate_elixir_module_progress([]), do: 0

  defp calculate_elixir_module_progress(fun_infos) do
    progress_sum = Enum.reduce(fun_infos, 0, fn info, acc -> acc + info.progress end)
    round(progress_sum / length(fun_infos))
  end

  defp calculate_elixir_module_status(module, fun_infos, deferred_modules_set) do
    cond do
      # All functions are done
      Enum.all?(fun_infos, fn info -> info.status == :done end) ->
        :done

      # Module is explicitly deferred
      MapSet.member?(deferred_modules_set, module) ->
        :deferred

      # Any function is in progress
      Enum.any?(fun_infos, fn info -> info.status == :in_progress end) ->
        :in_progress

      # Otherwise, it's todo
      true ->
        :todo
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

  defp reachable_erlang_mfas(graph, mfa) do
    graph
    |> CallGraph.reachable_mfas([mfa])
    |> Enum.filter(fn {module, _fun, _arity} -> Reflection.erlang_module?(module) end)
  end
end
