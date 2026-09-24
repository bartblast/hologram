defmodule Hologram.Compiler.ReflectionGateTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ReflectionGate

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.ReflectionGate.Module1

  @build {Module1, :build, 1}
  @site {:reflection_site, @build, :__struct__, 0, {:param, 0}}

  # The graph of Module1, its reach from the given entry function, and what the gate opens for it.
  defp open_from(function, arity, graph \\ module_1_graph()) do
    entry = {Module1, function, arity}
    reached_vertices = Digraph.reachable(graph, [entry])

    open_functions(graph, reached_vertices, [entry], gate())
  end

  defp gate(runtime_open \\ []) do
    %{ir_plt: PLT.start(), runtime: %{open: MapSet.new(runtime_open)}}
  end

  defp module_1_graph do
    CallGraph.start()
    |> CallGraph.build(IR.for_module(Module1))
    |> CallGraph.get_graph()
  end

  describe "open_functions/4" do
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
        {:reflection_site, {:module_1, :fun_a, 1}, :__changeset__, 0, :open},
        {:reflection_site, {:module_2, :fun_b, 2}, :__schema__, 2, :open},
        {:reflection_site, {:module_3, :fun_c, 0}, :__schema__, 2, :open}
      ]

      assert open_functions(Digraph.new(), reached_vertices, [], gate()) ==
               MapSet.new([{:__changeset__, 0}, {:__schema__, 2}])
    end

    test "other vertices open nothing" do
      reached_vertices = [:module_1, {:module_1, :__struct__, 0}, {:module_2, :__changeset__, 0}]

      assert open_functions(Digraph.new(), reached_vertices, [], gate()) == MapSet.new()
    end

    test "the runtime's open functions are added" do
      reached_vertices = [{:reflection_site, {:module_1, :fun_a, 1}, :__schema__, 1, :open}]

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
  end
end
