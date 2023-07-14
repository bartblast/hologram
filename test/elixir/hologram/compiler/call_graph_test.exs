defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR

  @call_graph_name_1 :"cg_#{__MODULE__}_1"
  @call_graph_name_2 :"cg_#{__MODULE__}_2"
  @opts name: @call_graph_name_1

  setup do
    wait_for_process_cleanup(@call_graph_name_1)
    wait_for_process_cleanup(@call_graph_name_2)

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

  test "add_vertex/2", %{call_graph: call_graph} do
    :ok = CallGraph.add_vertex(call_graph, :vertex_3)
    graph = CallGraph.graph(call_graph)

    assert Graph.has_vertex?(graph, :vertex_3)
  end

  describe "build/3" do
    test "atom, which is not an alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      build(call_graph, ir, :vertex_1)

      refute CallGraph.has_edge?(call_graph, :vertex_1, :abc)
    end

    test "atom, which is an alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Aaa.Bbb}
      build(call_graph, ir, :vertex_1)

      assert CallGraph.has_edge?(call_graph, :vertex_1, Aaa.Bbb)
    end
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
      assert %CallGraph{} = start(name: @call_graph_name_2)
    end

    test "uses name from opts" do
      assert %CallGraph{name: @call_graph_name_2} = start(name: @call_graph_name_2)
    end

    test "process name is registered" do
      %CallGraph{pid: pid} = start(name: @call_graph_name_2)
      assert Process.whereis(@call_graph_name_2) == pid
    end
  end
end
