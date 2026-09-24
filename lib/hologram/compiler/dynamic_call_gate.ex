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
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.DynamicCallSites
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  # What the gate is given besides the page's reach: what the runtime's own dynamic calls open
  # (see CallGraph.runtime_dynamic_calls/2), and the IR PLT the callers' code is read from, where a
  # module it does not hold yet is put once read.
  @type t :: %{ir_plt: PLT.t(), runtime: CallGraph.runtime_dynamic_calls()}

  @doc """
  Returns the reflection functions, as `{name, arity}` tuples, that the given gate opens for code
  that reaches the given vertices from the given entries (the functions called from outside the
  graph, with arguments the graph cannot see): those a dynamic call among the vertices makes on a
  module that is not its function's parameter, those a dynamic call makes on a parameter some caller
  can pass anything else than a module written in the code, and those the runtime opens. With no gate,
  every reflection function is open, which is what the compiler did before it had one.
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

    for {:dynamic_call, function, name, arity, kind} <- reached_vertices,
        open_site?(kind, function, context),
        into: gate.runtime.open do
      {name, arity}
    end
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

  defp module_ir(module, ir_plt) do
    case PLT.get(ir_plt, module) do
      {:ok, module_def} ->
        {:ok, module_def}

      :error ->
        if Reflection.elixir_module?(module) do
          module_def = IR.for_module(module)
          PLT.put(ir_plt, module, module_def)
          {:ok, module_def}
        else
          :error
        end
    end
  end

  defp open_argument?({:literal, _ir}, _caller, _context, _seen), do: false

  defp open_argument?({{:param, caller_index}, _ir}, caller, context, seen) do
    open_param?(caller, caller_index, context, seen)
  end

  defp open_argument?({:other, _ir}, _caller, _context, _seen), do: true

  defp open_caller?({module, _function, _arity} = caller, function, index, context, seen) do
    case clauses(caller, context.ir_plt) do
      nil ->
        true

      clauses ->
        calls = Enum.flat_map(clauses, &DynamicCallSites.call_args(&1, module, function))

        calls == [] or
          Enum.any?(calls, &open_argument?(Enum.at(&1, index), caller, context, seen))
    end
  end

  defp open_caller?(_module_vertex, _function, _index, _context, _seen), do: true

  # A parameter already being followed on this path is closed here: whether it opens is decided
  # where the path first reached it, by its other callers.
  defp open_param?(function, index, context, seen) do
    cond do
      MapSet.member?(seen, {function, index}) ->
        false

      MapSet.member?(context.entries, function) ->
        true

      true ->
        callers =
          for {caller, _function} <- Digraph.incoming_edges(context.graph, function),
              MapSet.member?(context.reached, caller) do
            caller
          end

        new_seen = MapSet.put(seen, {function, index})

        callers == [] or Enum.any?(callers, &open_caller?(&1, function, index, context, new_seen))
    end
  end

  defp open_site?(:open, _function, _context), do: true

  defp open_site?({:param, index}, function, context) do
    open_param?(function, index, context, MapSet.new())
  end
end
