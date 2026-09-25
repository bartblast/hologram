defmodule Hologram.Compiler.DynamicCallGateTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DynamicCallGate

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.DynamicCallGate.Module1

  @build {Module1, :build, 1}
  @site {:dynamic_call, @build, :__struct__, 0, {:param, 0}}

  # The graph of Module1, its reach from the given entry function, and what the given gate opens for
  # it.
  defp open_from(function, arity, graph \\ module_1_graph(), gate \\ gate()) do
    entry = {Module1, function, arity}
    reached_vertices = Digraph.reachable(graph, [entry])

    open_functions(graph, reached_vertices, [entry], gate)
  end

  # A gate with a data flow context, on the gate's IR PLT.
  defp gate_with_flow do
    %{ir_plt: ir_plt} = gate = gate()
    %{gate | flow: DataFlow.start(ir_plt, PLT.start())}
  end

  defp gate(runtime_open \\ []) do
    %{
      flow: nil,
      ir_plt: PLT.start(),
      runtime: %{exposed: %{}, open: MapSet.new(runtime_open), page_callers: %{}}
    }
  end

  defp module_1_graph do
    CallGraph.start()
    |> CallGraph.build(IR.for_module(Module1))
    |> CallGraph.get_graph()
  end

  # What the gate opens on a pages graph, which has the runtime's MFAs taken out, for code reached
  # from the given entry function, when Module1.build/1 is a runtime function whose dynamic call its
  # runtime callers keep closed and every other function of Module1 is page code.
  defp open_on_pages_from(function, arity) do
    full_graph = module_1_graph()
    graph = Digraph.remove_vertices(full_graph, [@build, @site])
    entry = {Module1, function, arity}

    page_callers =
      for {caller, _build} <- Digraph.incoming_edges(full_graph, @build), do: caller

    runtime = %{
      exposed: %{{@build, 0} => MapSet.new([{:__struct__, 0}])},
      open: MapSet.new(),
      page_callers: %{@build => page_callers}
    }

    open_functions(graph, Digraph.reachable(graph, [entry]), [entry], %{gate() | runtime: runtime})
  end

  describe "open_functions/4" do
    test "with a data flow context, a caller passing a map literal keeps a site on a parameter closed" do
      assert open_from(:with_map_literal, 0, module_1_graph(), gate_with_flow()) == MapSet.new()
    end

    test "with a data flow context, a caller passing a rescued exception keeps it closed" do
      assert open_from(:with_rescued, 1, module_1_graph(), gate_with_flow()) == MapSet.new()
    end

    test "with a data flow context, a caller passing a value from state still opens it" do
      assert open_from(:with_state_value_kept, 1, module_1_graph(), gate_with_flow()) ==
               MapSet.new([{:__struct__, 0}])
    end

    test "without a data flow context, a caller passing a map literal opens it" do
      assert open_from(:with_map_literal, 0) == MapSet.new([{:__struct__, 0}])
    end

    test "with a data flow context, a site on a struct the function built stays closed" do
      assert open_from(:struct_of_built, 0, module_1_graph(), gate_with_flow()) == MapSet.new()
    end

    test "with a data flow context, a site on a rescued exception stays closed" do
      assert open_from(:struct_of_rescued, 1, module_1_graph(), gate_with_flow()) == MapSet.new()
    end

    test "with a data flow context, a site on a value from state still opens" do
      assert open_from(:struct_of_state_value, 1, module_1_graph(), gate_with_flow()) ==
               MapSet.new([{:__struct__, 0}])
    end

    test "without a data flow context, a site on a struct the function built opens" do
      assert open_from(:struct_of_built, 0) == MapSet.new([{:__struct__, 0}])
    end

    test "no gate opens every reflection function" do
      assert open_functions(Digraph.new(), [], [], nil) ==
               MapSet.new([
                 {:__changeset__, 0},
                 {:__schema__, 1},
                 {:__schema__, 2},
                 {:__struct__, 0},
                 {:__struct__, 1}
               ])
    end

    test "nothing reached and nothing open in the runtime" do
      assert open_functions(Digraph.new(), [], [], gate()) == MapSet.new()
    end

    test "sites on modules that are not their function's parameter open the functions they call" do
      reached_vertices = [
        {:module_1, :fun_a, 1},
        {:dynamic_call, {:module_1, :fun_a, 1}, :__changeset__, 0, :open},
        {:dynamic_call, {:module_2, :fun_b, 2}, :__schema__, 2, :open},
        {:dynamic_call, {:module_3, :fun_c, 0}, :__schema__, 2, :open}
      ]

      assert open_functions(Digraph.new(), reached_vertices, [], gate()) ==
               MapSet.new([{:__changeset__, 0}, {:__schema__, 2}])
    end

    test "other vertices open nothing" do
      reached_vertices = [:module_1, {:module_1, :__struct__, 0}, {:module_2, :__changeset__, 0}]

      assert open_functions(Digraph.new(), reached_vertices, [], gate()) == MapSet.new()
    end

    test "the runtime's open functions are added" do
      reached_vertices = [{:dynamic_call, {:module_1, :fun_a, 1}, :__schema__, 1, :open}]

      assert open_functions(Digraph.new(), reached_vertices, [], gate([{:__struct__, 0}])) ==
               MapSet.new([{:__schema__, 1}, {:__struct__, 0}])
    end

    test "a caller passing a module written in the code keeps a site on a parameter closed" do
      assert open_from(:with_literal, 0) == MapSet.new()
    end

    test "a caller passing a value from state opens a site on a parameter" do
      assert open_from(:with_state_value, 1) == MapSet.new([{:__struct__, 0}])
    end

    test "a caller passing its own parameter is followed to its callers" do
      assert open_from(:forwarding_with_literal, 0) == MapSet.new()
      assert open_from(:forwarding_with_state_value, 1) == MapSet.new([{:__struct__, 0}])
    end

    test "a recursive chain is followed to an end" do
      assert open_from(:recursive_with_literal, 0) == MapSet.new()
    end

    test "a capture of the function opens a site on its parameter" do
      assert open_from(:capturing, 0) == MapSet.new([{:__struct__, 0}])
    end

    test "an entry opens a site on its parameter" do
      assert open_from(:build, 1) == MapSet.new([{:__struct__, 0}])
    end

    test "a function no reached function calls opens a site on its parameter" do
      assert open_functions(module_1_graph(), [@build, @site], [], gate()) ==
               MapSet.new([{:__struct__, 0}])
    end

    test "a module vertex among the callers opens a site on a parameter" do
      graph = Digraph.add_edge(module_1_graph(), Module1, @build)
      reached_vertices = [Module1, @build, @site]

      assert open_functions(graph, reached_vertices, [Module1], gate()) ==
               MapSet.new([{:__struct__, 0}])
    end

    test "a caller whose code shows no call of the function opens a site on a parameter" do
      graph = Digraph.add_edge(module_1_graph(), {Module1, :no_call, 0}, @build)

      assert open_from(:no_call, 0, graph) == MapSet.new([{:__struct__, 0}])
    end

    test "puts the IR of a module it reads into the gate's IR PLT" do
      %{ir_plt: ir_plt} = gate = gate()
      graph = module_1_graph()
      entry = {Module1, :with_literal, 0}

      open_functions(graph, Digraph.reachable(graph, [entry]), [entry], gate)

      assert PLT.member?(ir_plt, Module1)
    end

    test "a reached page caller passing a value from state opens an exposed runtime call" do
      assert open_on_pages_from(:with_state_value, 1) == MapSet.new([{:__struct__, 0}])
    end

    test "a reached page caller passing a written module keeps an exposed runtime call closed" do
      assert open_on_pages_from(:with_literal, 0) == MapSet.new()
    end

    test "a reached page caller passing its own parameter is followed to its page callers" do
      assert open_on_pages_from(:forwarding_with_literal, 0) == MapSet.new()

      assert open_on_pages_from(:forwarding_with_state_value, 1) ==
               MapSet.new([{:__struct__, 0}])
    end

    test "a page caller outside the reach leaves an exposed runtime call closed" do
      assert open_on_pages_from(:no_call, 0) == MapSet.new()
    end
  end

  describe "runtime_dynamic_calls/4" do
    test "with a data flow context, a runtime site on a struct the function built stays closed" do
      runtime_mfas = [{Module1, :struct_of_built, 0}]
      %{ir_plt: ir_plt, flow: flow} = gate_with_flow()

      refute {:__struct__, 0} in runtime_dynamic_calls(
               module_1_graph(),
               runtime_mfas,
               ir_plt,
               flow
             ).open

      assert {:__struct__, 0} in runtime_dynamic_calls(
               module_1_graph(),
               runtime_mfas,
               PLT.start()
             ).open
    end

    test "with a data flow context, a runtime caller passing a map keeps a call closed" do
      runtime_mfas = [{Module1, :build_or_keep, 1}, {Module1, :with_map_literal, 0}]
      %{ir_plt: ir_plt, flow: flow} = gate_with_flow()

      refute {:__struct__, 0} in runtime_dynamic_calls(
               module_1_graph(),
               runtime_mfas,
               ir_plt,
               flow
             ).open

      assert {:__struct__, 0} in runtime_dynamic_calls(
               module_1_graph(),
               runtime_mfas,
               PLT.start()
             ).open
    end

    test "a call the runtime's own callers keep closed is exposed, with its page callers" do
      result =
        runtime_dynamic_calls(
          module_1_graph(),
          [@build, {Module1, :with_literal, 0}],
          PLT.start()
        )

      assert result == %{
               exposed: %{{@build, 0} => MapSet.new([{:__struct__, 0}])},
               open: MapSet.new(),
               page_callers: %{
                 @build => [
                   {Module1, :capturing, 0},
                   {Module1, :forwarding, 1},
                   {Module1, :recursive, 2},
                   {Module1, :with_state_value, 1}
                 ]
               }
             }
    end

    test "a call a runtime caller opens is open" do
      result =
        runtime_dynamic_calls(
          module_1_graph(),
          [@build, {Module1, :with_state_value, 1}],
          PLT.start()
        )

      assert result.open == MapSet.new([{:__struct__, 0}])
      assert result.exposed == %{}
    end

    # The runtime's MFAs hold no module vertex, and the runtime calls a component's functions through
    # one, with arguments the walk cannot see.
    test "a module vertex among the callers opens a runtime call a runtime caller keeps closed" do
      graph = Digraph.add_edge(module_1_graph(), Module1, @build)

      result = runtime_dynamic_calls(graph, [@build, {Module1, :with_literal, 0}], PLT.start())

      assert result.open == MapSet.new([{:__struct__, 0}])
      assert result.exposed == %{}
    end

    test "every parameter a closed chain goes through is exposed" do
      runtime_mfas = [
        @build,
        {Module1, :forwarding, 1},
        {Module1, :forwarding_with_literal, 0}
      ]

      result = runtime_dynamic_calls(module_1_graph(), runtime_mfas, PLT.start())

      assert result.open == MapSet.new()

      assert result.exposed == %{
               {@build, 0} => MapSet.new([{:__struct__, 0}]),
               {{Module1, :forwarding, 1}, 0} => MapSet.new([{:__struct__, 0}])
             }
    end
  end
end
