defmodule Hologram.Compiler.DynamicCallGate do
  @moduledoc false

  # Decides, from the dynamic calls a page's client code reaches (see
  # Hologram.Compiler.DynamicCallSites), which reflection functions the page can call. A call on a
  # named module gives the call graph an edge to the function it calls, so a reflection function
  # the graph cannot see runs on the client only through a dynamic call: the page's own, or the
  # runtime's, which every page loads.
  #
  # A dynamic call on a module that is the calling function's parameter opens its reflection
  # function only when some caller can pass that parameter something other than a module written in
  # the code. The callers are followed up the reached functions: a caller passing an atom it names
  # keeps the call closed, one passing its own parameter is followed in turn, and one passing
  # anything else opens it. Anything the walk cannot see opens it too: a function the runtime's
  # JavaScript calls (an entry), one no reached function calls, a module vertex among the callers
  # (the runtime calls a component's functions), and a caller whose code shows no call of the
  # function (a capture, a protocol dispatch, a call the graph was given by hand).

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.DynamicCallSites
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  # What the gate is given besides the page's reach: what the runtime's own dynamic calls open (see
  # runtime_dynamic_calls/3), and the IR PLT the callers' code is read from, where a module it does
  # not hold yet is put once read.
  @type t :: %{ir_plt: PLT.t(), runtime: CallGraph.runtime_dynamic_calls()}

  # The literal empty `MapSet.new()` a resolution starts from reads as concrete and won't unify with
  # the opaque `MapSet.t()` the visited parameters are put into (see the same note in CallGraph).
  @dialyzer {:no_opaque, [{:resolve_param, 4}]}

  @doc """
  Returns the reflection functions, as `{name, arity}` tuples, that the given gate opens for code
  that reaches the given vertices from the given entries (the functions called from outside the
  graph, with arguments the graph cannot see): those a dynamic call among the vertices makes on a
  module that is not its function's parameter, those a dynamic call makes on a parameter some
  caller can pass anything else than a module written in the code, those the runtime opens, and
  those of a runtime function's closed dynamic call that a reached caller of the runtime function
  can open (see runtime_dynamic_calls/3). With no gate, every reflection function is open, which is
  what the compiler did before it had one.
  """
  @spec open_functions(Digraph.t(), Enumerable.t(CallGraph.vertex()), [mfa], t | nil) ::
          MapSet.t({atom, arity})
  def open_functions(graph, reached_vertices, entries, gate)

  def open_functions(_graph, _reached_vertices, _entries, nil) do
    MapSet.new(DynamicCallSites.reflection_functions())
  end

  def open_functions(graph, reached_vertices, entries, gate) do
    context = %{
      entries: MapSet.new(entries),
      graph: graph,
      ir_plt: gate.ir_plt,
      reached: MapSet.new(reached_vertices)
    }

    %{exposed: exposed, open: runtime_open, page_callers: page_callers} = gate.runtime

    open =
      for {:dynamic_call, function, name, arity, kind} <- reached_vertices,
          open_site?(kind, function, context),
          into: runtime_open do
        {name, arity}
      end

    for {{function, index}, functions} <- exposed,
        open_exposed?(function, index, page_callers, context),
        reflection_function <- functions,
        into: open do
      reflection_function
    end
  end

  @doc """
  Returns what the runtime's own dynamic calls open for every page, from the graph that still holds
  the runtime's MFAs, the MFAs and the IR PLT the callers' code is read from:

    * `:open` - the reflection functions, as `{name, arity}` tuples, that a runtime function's
      dynamic call opens, followed up the runtime's own functions from the runtime's entries.
    * `:exposed` - for a dynamic call on a parameter that the runtime's own callers keep closed,
      each `{function, index}` its closed chain went through, with the reflection functions the
      call would open: page code can call those functions too, with arguments of its own.
    * `:page_callers` - the callers of each exposed function that are not runtime MFAs, taken
      here because the pages graph has the runtime's MFAs and their edges taken out.
  """
  @spec runtime_dynamic_calls(Digraph.t(), [mfa], PLT.t()) :: CallGraph.runtime_dynamic_calls()
  def runtime_dynamic_calls(graph, runtime_mfas, ir_plt) do
    runtime = MapSet.new(runtime_mfas)

    context = %{
      entries: MapSet.new(CallGraph.list_runtime_entry_mfas()),
      graph: graph,
      ir_plt: ir_plt,
      reached: runtime
    }

    sites =
      for mfa <- runtime_mfas,
          {_mfa, {:dynamic_call, function, name, arity, kind}} <-
            Digraph.outgoing_edges(graph, mfa) do
        {function, {name, arity}, kind}
      end

    %{exposed: exposed, open: open} =
      Enum.reduce(sites, %{exposed: %{}, open: MapSet.new()}, fn
        {_function, reflection_function, :open}, acc ->
          %{acc | open: MapSet.put(acc.open, reflection_function)}

        {function, reflection_function, {:param, index}}, acc ->
          case resolve_param(function, index, context, MapSet.new()) do
            {:open, _visited} ->
              %{acc | open: MapSet.put(acc.open, reflection_function)}

            {:closed, visited} ->
              %{acc | exposed: expose(acc.exposed, visited, reflection_function)}
          end
      end)

    page_callers =
      exposed
      |> Map.keys()
      |> Enum.map(fn {function, _index} -> function end)
      |> Enum.uniq()
      |> Map.new(&{&1, non_runtime_callers(graph, &1, runtime)})

    %{exposed: exposed, open: open, page_callers: page_callers}
  end

  # The clauses of the given function, read from its module's IR, or nil when the module has no IR
  # (an Erlang module) or does not define the function.
  defp clauses({module, function, arity}, ir_plt) do
    with {:ok, module_def} <- module_ir(module, ir_plt),
         {_key, {_visibility, clauses}} <-
           module_def
           |> IR.aggregate_module_funs()
           |> List.keyfind({function, arity}, 0) do
      clauses
    else
      _no_clauses -> nil
    end
  end

  defp expose(exposed, visited, reflection_function) do
    Enum.reduce(visited, exposed, fn param, acc ->
      Map.update(
        acc,
        param,
        MapSet.new([reflection_function]),
        &MapSet.put(&1, reflection_function)
      )
    end)
  end

  # Stops a reduction over callers or calls at the first one that opens.
  defp halt_when_open({:open, _visited} = open), do: {:halt, open}
  defp halt_when_open(closed), do: {:cont, closed}

  # Builds a module's IR the way the compile task does (see Hologram.Compiler.build_ir_plt/1), so that
  # in an umbrella a module still loaded from a consolidated beam the code reloader deleted is read
  # from its object code, and a module with no beam is left out.
  defp module_ir(module, ir_plt) do
    with :error <- PLT.get(ir_plt, module) do
      if Reflection.elixir_module?(module) do
        Compiler.build_missing_ir!(ir_plt, [module])
      end

      PLT.get(ir_plt, module)
    end
  end

  defp non_runtime_callers(graph, function, runtime) do
    for {caller, _function} <- Digraph.incoming_edges(graph, function),
        not MapSet.member?(runtime, caller) do
      caller
    end
    |> Enum.sort()
  end

  # A runtime function's closed dynamic call opens for a page when one of the page's reached
  # functions calls the runtime function with an argument that opens it. The runtime's own callers
  # were followed already, so a page that reaches no such caller leaves it closed.
  defp open_exposed?(function, index, page_callers, context) do
    page_callers
    |> Map.fetch!(function)
    |> Enum.filter(&MapSet.member?(context.reached, &1))
    |> resolve_callers(function, index, context, MapSet.new())
    |> elem(0)
    |> Kernel.==(:open)
  end

  # TODO: #938. Ask the value analysis whether the expression the call is made on is definitely a
  # map or a struct: such a value is never the module a reflection function is called on, so the
  # call would stay closed. The cases that keep __struct__/0 open on every page today are
  # Kernel.struct/3 calling itself on the result of validate_struct!/3 (every clause returns a map
  # or raises), Exception.message/1 calling __struct__ on its rescued exception, and, in a
  # dependency of a big app, Localize.LanguageTag.try_minimal_form/2 passing Kernel.struct/2 a value
  # taken from `{:ok, maximized} <- add_likely_subtags(tag)`, whose every clause returns
  # `{:ok, <a map>}` or `{:error, _}`. The same applies to an `:other` argument in
  # resolve_argument/4.
  defp open_site?(:open, _function, _context), do: true

  defp open_site?({:param, index}, function, context) do
    function
    |> resolve_param(index, context, MapSet.new())
    |> elem(0)
    |> Kernel.==(:open)
  end

  defp resolve_argument({:literal, _ir}, _caller, _context, visited), do: {:closed, visited}

  defp resolve_argument({{:param, caller_index}, _ir}, caller, context, visited) do
    resolve_param(caller, caller_index, context, visited)
  end

  # TODO: #938. See open_site?/3: an argument that is definitely a map or a struct would close.
  defp resolve_argument({:other, _ir}, _caller, _context, visited), do: {:open, visited}

  defp resolve_caller({module, _function, _arity} = caller, function, index, context, visited) do
    with clauses when clauses != nil <- clauses(caller, context.ir_plt),
         [_call | _calls] = calls <-
           Enum.flat_map(clauses, &DynamicCallSites.call_args(&1, module, function)) do
      Enum.reduce_while(calls, {:closed, visited}, fn args, {:closed, acc} ->
        args
        |> Enum.at(index)
        |> resolve_argument(caller, context, acc)
        |> halt_when_open()
      end)
    else
      _no_call -> {:open, visited}
    end
  end

  defp resolve_caller(_module_vertex, _function, _index, _context, visited), do: {:open, visited}

  defp resolve_callers(callers, function, index, context, visited) do
    Enum.reduce_while(callers, {:closed, visited}, fn caller, {:closed, acc} ->
      caller
      |> resolve_caller(function, index, context, acc)
      |> halt_when_open()
    end)
  end

  # Whether a parameter can hold anything else than a module written in the code, with the
  # parameters visited so far: a visited parameter is closed here, since the first result that
  # opens ends the resolution, so one visited before either closed or is being followed further up
  # this chain, where its other callers decide.
  defp resolve_param(function, index, context, visited) do
    cond do
      MapSet.member?(visited, {function, index}) ->
        {:closed, visited}

      MapSet.member?(context.entries, function) ->
        {:open, visited}

      true ->
        new_visited = MapSet.put(visited, {function, index})

        callers =
          for {caller, _function} <- Digraph.incoming_edges(context.graph, function),
              MapSet.member?(context.reached, caller) do
            caller
          end

        if callers == [] do
          {:open, new_visited}
        else
          resolve_callers(callers, function, index, context, new_visited)
        end
    end
  end
end
