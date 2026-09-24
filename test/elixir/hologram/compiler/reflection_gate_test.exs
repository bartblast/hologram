defmodule Hologram.Compiler.ReflectionGateTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.ReflectionGate

  alias Hologram.Compiler.Digraph

  describe "open_functions/3" do
    setup do
      [gate: %{runtime: %{open: MapSet.new()}}, graph: Digraph.new()]
    end

    test "no gate opens every reflection function", %{graph: graph} do
      assert open_functions(graph, [], nil) ==
               MapSet.new([
                 {:__changeset__, 0},
                 {:__schema__, 1},
                 {:__schema__, 2},
                 {:__struct__, 0},
                 {:__struct__, 1}
               ])
    end

    test "nothing reached and nothing open in the runtime", %{gate: gate, graph: graph} do
      assert open_functions(graph, [], gate) == MapSet.new()
    end

    test "reached reflection sites open the functions they call", %{gate: gate, graph: graph} do
      reached_vertices =
        MapSet.new([
          {:module_1, :fun_a, 1},
          {:reflection_site, {:module_1, :fun_a, 1}, :__changeset__, 0, {:param, 0}},
          {:reflection_site, {:module_2, :fun_b, 2}, :__schema__, 2, :open},
          {:reflection_site, {:module_3, :fun_c, 0}, :__schema__, 2, :open}
        ])

      assert open_functions(graph, reached_vertices, gate) ==
               MapSet.new([{:__changeset__, 0}, {:__schema__, 2}])
    end

    test "other vertices open nothing", %{gate: gate, graph: graph} do
      reached_vertices = [:module_1, {:module_1, :__struct__, 0}, {:module_2, :__changeset__, 0}]

      assert open_functions(graph, reached_vertices, gate) == MapSet.new()
    end

    test "the runtime's open functions are added", %{graph: graph} do
      gate = %{runtime: %{open: MapSet.new([{:__struct__, 0}])}}
      reached_vertices = [{:reflection_site, {:module_1, :fun_a, 1}, :__schema__, 1, :open}]

      assert open_functions(graph, reached_vertices, gate) ==
               MapSet.new([{:__schema__, 1}, {:__struct__, 0}])
    end
  end
end
