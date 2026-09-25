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
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.DynamicCallSites
  alias Hologram.Compiler.IR

  # What the gate is given besides the page's reach: what the runtime's own dynamic calls open (see
  # runtime_dynamic_calls/4), the IR PLT the callers' code is read from, where a module it does not
  # hold yet is put once read, and the data flow context that tells an argument certainly a map or a
  # struct (nil for none, and every such argument opens).
  @type t :: %{
          flow: DataFlow.t() | nil,
          ir_plt: PLT.t(),
          runtime: CallGraph.runtime_dynamic_calls()
        }

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
  can open (see runtime_dynamic_calls/4). With no gate, every reflection function is open, which is
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
      flow: gate.flow,
      graph: graph,
      ir_plt: gate.ir_plt,
      module_callers?: false,
      reached: MapSet.new(reached_vertices)
    }

    %{exposed: exposed, open: runtime_open, page_callers: page_callers} = gate.runtime

    open =
      for {:dynamic_call, function, name, arity, kind} <- reached_vertices,
          open_site?(kind, function, {name, arity}, context),
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

  With a data flow context, a caller passing an argument that is certainly a map or a struct keeps
  the call closed (see `Hologram.Compiler.DataFlow.definite_map?/4`).
  """
  @spec runtime_dynamic_calls(Digraph.t(), [mfa], PLT.t(), DataFlow.t() | nil) ::
          CallGraph.runtime_dynamic_calls()
  def runtime_dynamic_calls(graph, runtime_mfas, ir_plt, flow \\ nil) do
    runtime = MapSet.new(runtime_mfas)

    context = %{
      entries: MapSet.new(CallGraph.list_runtime_entry_mfas()),
      flow: flow,
      graph: graph,
      ir_plt: ir_plt,
      module_callers?: true,
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
        {function, reflection_function, :open}, acc ->
          if open_site?(:open, function, reflection_function, context) do
            %{acc | open: MapSet.put(acc.open, reflection_function)}
          else
            acc
          end

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
    with {:ok, module_def} <- Compiler.module_ir(ir_plt, module),
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

  # The calls of the function in the given clauses, each with the clause it is in.
  defp list_calls(clauses, module, function) do
    for clause <- clauses, args <- DynamicCallSites.call_args(clause, module, function) do
      {clause, args}
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

  # A call on a value that is not the function's parameter opens, unless the data flow tells that
  # every value the function's calls of the reflection function are made on is certainly a map or a
  # struct, which is never the module a reflection function is called on (Exception.message/1 calls
  # __struct__ on the exception it rescued). A call on a parameter asks the callers (see
  # resolve_param/4); an argument that is certainly a map closes it there (see resolve_argument/5).
  defp open_site?(:open, function, {name, arity}, %{flow: flow} = context) when flow != nil do
    case clauses(function, context.ir_plt) do
      nil ->
        true

      clauses ->
        sites =
          for clause <- clauses, expr <- DynamicCallSites.site_expressions(clause, name, arity) do
            {clause, expr}
          end

        sites == [] or
          not Enum.all?(sites, fn {clause, expr} ->
            DataFlow.definite_map?(expr, clause, function, flow)
          end)
    end
  end

  defp open_site?(:open, _function, _reflection_function, _context), do: true

  defp open_site?({:param, index}, function, _reflection_function, context) do
    function
    |> resolve_param(index, context, MapSet.new())
    |> elem(0)
    |> Kernel.==(:open)
  end

  # The runtime's reached set holds its MFAs only, so there a module vertex among the callers is
  # taken whether or not the runtime reaches it: the runtime calls a component's or an exception's
  # functions through it, with arguments the walk cannot see. One only a page reaches then opens the
  # call for every page, which ships more than the page needs but never less.
  defp reached_caller?(caller, %{module_callers?: true}) when is_atom(caller), do: true
  defp reached_caller?(caller, context), do: MapSet.member?(context.reached, caller)

  defp resolve_argument({:literal, _ir}, _caller, _clause, _context, visited),
    do: {:closed, visited}

  defp resolve_argument({{:param, caller_index}, _ir}, caller, _clause, context, visited) do
    resolve_param(caller, caller_index, context, visited)
  end

  # Any other argument opens, unless it is certainly a map or a struct, which is never a module.
  defp resolve_argument({:other, ir}, caller, clause, %{flow: flow}, visited) when flow != nil do
    if DataFlow.definite_map?(ir, clause, caller, flow) do
      {:closed, visited}
    else
      {:open, visited}
    end
  end

  defp resolve_argument({:other, _ir}, _caller, _clause, _context, visited), do: {:open, visited}

  defp resolve_caller({module, _function, _arity} = caller, function, index, context, visited) do
    with clauses when clauses != nil <- clauses(caller, context.ir_plt),
         [_call | _calls] = calls <- list_calls(clauses, module, function) do
      Enum.reduce_while(calls, {:closed, visited}, fn {clause, args}, {:closed, acc} ->
        args
        |> Enum.at(index)
        |> resolve_argument(caller, clause, context, acc)
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
              reached_caller?(caller, context) do
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
