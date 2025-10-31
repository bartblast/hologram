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
  Aggregates information about Erlang functions used by Elixir stdlib.

  Returns comprehensive data including porting status and dependency information
  for each Erlang function used by Elixir standard library modules.

  ## Parameters

  - `erlang_js_dir` - Path to the directory containing manually ported Erlang functions
  - `opts` - Keyword list with optional keys:
    - `:in_progress` - List of MFA tuples currently being ported (defaults to [])
    - `:blocked` - List of MFA tuples that are blocked (defaults to [])
    
    Note: `:in_progress` takes precedence over `:blocked` when determining status.

  ## Returns

  A map where each key is an Erlang MFA tuple and the value is a map containing:
  - `:status` - One of `:todo`, `:in_progress`, `:blocked`, or `:done`
  - `:dependents` - List of Elixir MFA tuples that depend on it  
  - `:dependents_count` - Count of Elixir functions that depend on it

  ## Example

      iex> aggregate_erlang_funs_info("assets/js/erlang", in_progress: [{:erlang, :-, 2}], blocked: [{:erlang, :div, 2}])
      %{
        {:erlang, :+, 2} => %{
          status: :done,
          dependents: [{Kernel, :+, 2}, {Integer, :parse, 2}, ...],
          dependents_count: 15          
        },
        {:erlang, :-, 2} => %{
          status: :in_progress,
          dependents: [{Kernel, :-, 2}, ...],
          dependents_count: 10          
        },
        {:erlang, :div, 2} => %{
          status: :blocked,
          dependents: [{Integer, :floor_div, 2}, ...],          
          dependents_count: 5
        },
        ...
      }
  """
  @spec aggregate_erlang_funs_info(Path.t(), keyword()) :: %{
          mfa => %{
            status: :todo | :in_progress | :blocked | :done,
            dependents: [mfa],
            dependents_count: non_neg_integer()
          }
        }
  def aggregate_erlang_funs_info(erlang_js_dir, opts \\ []) do
    modules_map = elixir_stdlib_erlang_deps()

    ported_erlang_funs =
      erlang_js_dir
      |> list_ported_erlang_funs()
      |> MapSet.new()

    in_progress_mfas = Keyword.get(opts, :in_progress, [])
    blocked_mfas = Keyword.get(opts, :blocked, [])

    in_progress_set = MapSet.new(in_progress_mfas)
    blocked_set = MapSet.new(blocked_mfas)

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

    # Build the final result with status and dependency counts
    dependents_by_erlang_mfa
    |> Enum.map(fn {erlang_mfa, dependents} ->
      unique_dependents = Enum.uniq(dependents)

      status =
        cond do
          MapSet.member?(ported_erlang_funs, erlang_mfa) -> :done
          MapSet.member?(in_progress_set, erlang_mfa) -> :in_progress
          MapSet.member?(blocked_set, erlang_mfa) -> :blocked
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
