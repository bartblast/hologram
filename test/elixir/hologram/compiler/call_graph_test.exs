defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph
  alias Hologram.Compiler.CallGraph

  @name :"cg_#{__MODULE__}"
  @opts name: @name

  setup do
    [call_graph: start(@opts)]
  end

  test "add_edge/3", %{call_graph: call_graph} do
    :ok = CallGraph.add_edge(call_graph, :vertex_1, :vertex_2)
    graph = CallGraph.graph(call_graph)

    assert Graph.edge(graph, :vertex_1, :vertex_2) == %Graph.Edge{
             v1: :vertex_1,
             v2: :vertex_2,
             weight: 1,
             label: nil
           }
  end

  test "graph/1", %{call_graph: call_graph} do
    assert %Graph{} = CallGraph.graph(call_graph)
  end

  describe "has_edge?/3" do
    test "doesn't have the given edge", %{call_graph: call_graph} do
      refute CallGraph.has_edge?(call_graph, :vertex_1, :vertex_2)
    end

    test "has the given edge", %{call_graph: call_graph} do
      CallGraph.add_edge(call_graph, :vertex_1, :vertex_2)
      assert CallGraph.has_edge?(call_graph, :vertex_1, :vertex_2)
    end
  end

  describe "start/1" do
    test "%CallGraph{} struct is returned" do
      name = :"#{@name}_start_test"
      assert %CallGraph{name: ^name} = start(name: name)
    end

    test "process name is registered" do
      name = :"#{@name}_start_test"
      %CallGraph{pid: pid} = start(name: name)

      assert Process.whereis(name) == pid
    end
  end
end
