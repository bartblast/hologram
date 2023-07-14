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
    test "atom type ir, which is not an alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      build(call_graph, ir, :vertex_1)

      refute CallGraph.has_edge?(call_graph, :vertex_1, :abc)
    end

    test "atom type ir, which is an alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Aaa}
      build(call_graph, ir, :vertex_1)

      assert CallGraph.has_edge?(call_graph, :vertex_1, Aaa)
    end

    test "function definition ir", %{call_graph: call_graph} do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
          guard: %IR.AtomType{value: Bbb},
          body: %IR.Block{
            expressions: [
              %IR.AtomType{value: Ccc},
              %IR.AtomType{value: Ddd}
            ]
          }
        }
      }

      build(call_graph, ir, Aaa)
      graph = graph(call_graph)

      assert Graph.has_vertex?(graph, {Aaa, :my_fun, 2})

      assert has_edge?(call_graph, {Aaa, :my_fun, 2}, Bbb)
      assert has_edge?(call_graph, {Aaa, :my_fun, 2}, Ccc)
      assert has_edge?(call_graph, {Aaa, :my_fun, 2}, Ddd)
    end

    test "list", %{call_graph: call_graph} do
      list = [%IR.AtomType{value: Aaa}, %IR.AtomType{value: Bbb}]
      build(call_graph, list, :vertex_1)

      assert CallGraph.has_edge?(call_graph, :vertex_1, Aaa)
      assert CallGraph.has_edge?(call_graph, :vertex_1, Bbb)
    end

    test "map", %{call_graph: call_graph} do
      map = %{
        %IR.AtomType{value: Aaa} => %IR.AtomType{value: Bbb},
        %IR.AtomType{value: Ccc} => %IR.AtomType{value: Ddd}
      }

      build(call_graph, map, :vertex_1)

      assert CallGraph.has_edge?(call_graph, :vertex_1, Aaa)
      assert CallGraph.has_edge?(call_graph, :vertex_1, Bbb)
      assert CallGraph.has_edge?(call_graph, :vertex_1, Ccc)
      assert CallGraph.has_edge?(call_graph, :vertex_1, Ddd)
    end

    test "module definition ir", %{call_graph: call_graph} do
      ir = %IR.ModuleDefinition{
        module: Aaa,
        body: %IR.Block{
          expressions: [
            %IR.AtomType{value: Bbb},
            %IR.AtomType{value: Ccc}
          ]
        }
      }

      build(call_graph, ir)

      assert CallGraph.has_edge?(call_graph, Aaa, Bbb)
      assert CallGraph.has_edge?(call_graph, Aaa, Ccc)
    end

    test "tuple", %{call_graph: call_graph} do
      tuple = {%IR.AtomType{value: Aaa}, %IR.AtomType{value: Bbb}}
      build(call_graph, tuple, :vertex_1)

      assert CallGraph.has_edge?(call_graph, :vertex_1, Aaa)
      assert CallGraph.has_edge?(call_graph, :vertex_1, Bbb)
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
