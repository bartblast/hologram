defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph

  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module2
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module3
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module4
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module5
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module6
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module7
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module8

  @call_graph_name_1 :"cg_#{__MODULE__}_1"
  @call_graph_name_2 :"cg_#{__MODULE__}_2"
  @opts name: @call_graph_name_1

  setup do
    wait_for_process_cleanup(@call_graph_name_1)
    wait_for_process_cleanup(@call_graph_name_2)

    [call_graph: start(@opts)]
  end

  test "add_edge/3", %{call_graph: call_graph} do
    :ok = add_edge(call_graph, :vertex_1, :vertex_2)
    graph = graph(call_graph)

    assert Graph.edge(graph, :vertex_1, :vertex_2) == %Graph.Edge{
             v1: :vertex_1,
             v2: :vertex_2,
             weight: 1,
             label: nil
           }
  end

  test "add_vertex/2", %{call_graph: call_graph} do
    :ok = add_vertex(call_graph, :vertex_3)
    graph = graph(call_graph)

    assert Graph.has_vertex?(graph, :vertex_3)
  end

  describe "build/3" do
    test "atom type ir, which is not a module alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      build(call_graph, ir, :vertex_1)

      refute has_edge?(call_graph, :vertex_1, :abc)
    end

    test "atom type ir, which is a module alias of a non-templatable module", %{
      call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      build(call_graph, ir, :vertex_1)

      assert has_edge?(call_graph, :vertex_1, Module1)

      refute has_edge?(call_graph, Module1, {Module1, :__hologram_layout_module__, 0})
      refute has_edge?(call_graph, Module1, {Module1, :__hologram_route__, 0})
      refute has_edge?(call_graph, Module1, {Module1, :action, 3})
      refute has_edge?(call_graph, Module1, {Module1, :init, 1})
      refute has_edge?(call_graph, Module1, {Module1, :template, 0})
    end

    test "atom type ir, which is a page module alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Module2}
      build(call_graph, ir, :vertex_1)

      assert has_edge?(call_graph, :vertex_1, Module2)

      assert has_edge?(call_graph, Module2, {Module2, :__hologram_layout_module__, 0})
      assert has_edge?(call_graph, Module2, {Module2, :__hologram_route__, 0})

      refute has_edge?(call_graph, Module2, {Module2, :action, 3})
      refute has_edge?(call_graph, Module2, {Module2, :init, 1})
      refute has_edge?(call_graph, Module2, {Module2, :template, 0})
    end

    test "atom type ir, which is a layout module alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Module3}
      build(call_graph, ir, :vertex_1)

      assert has_edge?(call_graph, :vertex_1, Module3)

      refute has_edge?(call_graph, Module3, {Module3, :__hologram_layout_module__, 0})
      refute has_edge?(call_graph, Module3, {Module3, :__hologram_route__, 0})

      refute has_edge?(call_graph, Module3, {Module3, :action, 3})
      refute has_edge?(call_graph, Module3, {Module3, :init, 1})
      refute has_edge?(call_graph, Module3, {Module3, :template, 0})
    end

    test "atom type ir, which is a component module alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Module4}
      build(call_graph, ir, :vertex_1)

      assert has_edge?(call_graph, :vertex_1, Module4)

      assert has_edge?(call_graph, Module4, {Module4, :action, 3})
      assert has_edge?(call_graph, Module4, {Module4, :init, 1})
      assert has_edge?(call_graph, Module4, {Module4, :template, 0})

      refute has_edge?(call_graph, Module4, {Module4, :__hologram_layout_module__, 0})
      refute has_edge?(call_graph, Module4, {Module4, :__hologram_route__, 0})
    end

    test "function definition ir", %{call_graph: call_graph} do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
          guard: %IR.AtomType{value: Module5},
          body: %IR.Block{
            expressions: [
              %IR.AtomType{value: Module6},
              %IR.AtomType{value: Module7}
            ]
          }
        }
      }

      build(call_graph, ir, Module1)

      assert has_vertex?(call_graph, {Module1, :my_fun, 2})

      assert has_edge?(call_graph, {Module1, :my_fun, 2}, Module5)
      assert has_edge?(call_graph, {Module1, :my_fun, 2}, Module6)
      assert has_edge?(call_graph, {Module1, :my_fun, 2}, Module7)
    end

    test "list", %{call_graph: call_graph} do
      list = [%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}]
      build(call_graph, list, :vertex_1)

      assert has_edge?(call_graph, :vertex_1, Module1)
      assert has_edge?(call_graph, :vertex_1, Module5)
    end

    test "local function call ir", %{call_graph: call_graph} do
      ir = %IR.LocalFunctionCall{
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module5},
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7}
        ]
      }

      build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, {Module1, :my_fun_2, 3})
      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, Module5)
      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, Module6)
      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, Module7)
    end

    test "map", %{call_graph: call_graph} do
      map = %{
        %IR.AtomType{value: Module1} => %IR.AtomType{value: Module5},
        %IR.AtomType{value: Module6} => %IR.AtomType{value: Module7}
      }

      build(call_graph, map, :vertex_1)

      assert has_edge?(call_graph, :vertex_1, Module1)
      assert has_edge?(call_graph, :vertex_1, Module5)
      assert has_edge?(call_graph, :vertex_1, Module6)
      assert has_edge?(call_graph, :vertex_1, Module7)
    end

    test "module definition ir", %{call_graph: call_graph} do
      ir = %IR.ModuleDefinition{
        module: Module1,
        body: %IR.Block{
          expressions: [
            %IR.AtomType{value: Module5},
            %IR.AtomType{value: Module6}
          ]
        }
      }

      build(call_graph, ir)

      assert has_edge?(call_graph, Module1, Module5)
      assert has_edge?(call_graph, Module1, Module6)
    end

    test "remote function call ir", %{call_graph: call_graph} do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Module5},
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7},
          %IR.AtomType{value: Module8}
        ]
      }

      build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, {Module5, :my_fun_2, 3})
      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, Module6)
      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, Module7)
      assert has_edge?(call_graph, {Module1, :my_fun_1, 4}, Module8)
    end

    test "tuple", %{call_graph: call_graph} do
      tuple = {%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}}
      build(call_graph, tuple, :vertex_1)

      assert has_edge?(call_graph, :vertex_1, Module1)
      assert has_edge?(call_graph, :vertex_1, Module5)
    end
  end

  describe "clone/1" do
    test "returns CallGraph struct with name from opts", %{call_graph: call_graph} do
      assert %CallGraph{name: @call_graph_name_2} = clone(call_graph, name: @call_graph_name_2)
    end

    test "clones the call graph", %{call_graph: call_graph} do
      add_vertex(call_graph, :vertex_1)

      call_graph_clone = clone(call_graph, name: @call_graph_name_2)
      add_vertex(call_graph_clone, :vertex_2)

      assert has_vertex?(call_graph, :vertex_1)
      refute has_vertex?(call_graph, :vertex_2)

      assert has_vertex?(call_graph_clone, :vertex_1)
      assert has_vertex?(call_graph_clone, :vertex_2)
    end
  end

  test "graph/1", %{call_graph: call_graph} do
    assert %Graph{} = graph(call_graph)
  end

  describe "has_edge?/3" do
    test "doesn't have the given edge", %{call_graph: call_graph} do
      refute has_edge?(call_graph, :vertex_1, :vertex_2)
    end

    test "has the given edge", %{call_graph: call_graph} do
      add_edge(call_graph, :vertex_1, :vertex_2)
      assert has_edge?(call_graph, :vertex_1, :vertex_2)
    end
  end

  describe "has_vertex?/2" do
    test "doesn't have the given vertex", %{call_graph: call_graph} do
      refute has_vertex?(call_graph, :vertex)
    end

    test "has the given vertex", %{call_graph: call_graph} do
      add_vertex(call_graph, :vertex)
      assert has_vertex?(call_graph, :vertex)
    end
  end

  test "inbound_remote_edges/2", %{call_graph: call_graph} do
    add_edge(call_graph, {:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b})
    add_edge(call_graph, {:module_3, :fun_c, :arity_c}, {:module_2, :fun_d, :arity_d})
    add_edge(call_graph, {:module_4, :fun_e, :arity_e}, :module_2)
    add_edge(call_graph, {:module_5, :fun_f, :arity_f}, :module_2)

    add_edge(call_graph, {:module_6, :fun_g, :arity_g}, {:module_7, :fun_h, :arity_h})
    add_edge(call_graph, {:module_8, :fun_i, :arity_i}, :module_9)

    assert inbound_remote_edges(call_graph, :module_2) == [
             %Graph.Edge{
               v1: {:module_4, :fun_e, :arity_e},
               v2: :module_2,
               weight: 1,
               label: nil
             },
             %Graph.Edge{
               v1: {:module_1, :fun_a, :arity_a},
               v2: {:module_2, :fun_b, :arity_b},
               weight: 1,
               label: nil
             },
             %Graph.Edge{
               v1: {:module_5, :fun_f, :arity_f},
               v2: :module_2,
               weight: 1,
               label: nil
             },
             %Graph.Edge{
               v1: {:module_3, :fun_c, :arity_c},
               v2: {:module_2, :fun_d, :arity_d},
               weight: 1,
               label: nil
             }
           ]
  end

  test "module_vertices/2", %{call_graph: call_graph} do
    add_vertex(call_graph, {:module_1, :fun_a, :arity_a})
    add_vertex(call_graph, {:module_2, :fun_b, :arity_b})
    add_vertex(call_graph, {:module_3, :fun_c, :arity_c})
    add_vertex(call_graph, {:module_2, :fun_d, :arity_d})
    add_vertex(call_graph, :module_4)
    add_vertex(call_graph, :module_2)

    assert module_vertices(call_graph, :module_2) == [
             :module_2,
             {:module_2, :fun_b, :arity_b},
             {:module_2, :fun_d, :arity_d}
           ]
  end

  test "reachable/2", %{call_graph: call_graph} do
    # 1
    # ├─ 2
    # │  ├─ 4
    # │  │  ├─ 8
    # │  │  ├─ 9
    # │  ├─ 5
    # │  │  ├─ 10
    # │  │  ├─ 11
    # ├─ 3
    # │  ├─ 6
    # │  │  ├─ 12
    # │  │  ├─ 13
    # │  ├─ 7
    # │  │  ├─ 14
    # │  │  ├─ 15

    add_edge(call_graph, :vertex_1, :vertex_2)
    add_edge(call_graph, :vertex_1, :vertex_3)

    add_edge(call_graph, :vertex_2, :vertex_4)
    add_edge(call_graph, :vertex_2, :vertex_5)

    add_edge(call_graph, :vertex_3, :vertex_6)
    add_edge(call_graph, :vertex_3, :vertex_7)

    add_edge(call_graph, :vertex_4, :vertex_8)
    add_edge(call_graph, :vertex_4, :vertex_9)

    add_edge(call_graph, :vertex_5, :vertex_10)
    add_edge(call_graph, :vertex_5, :vertex_11)

    add_edge(call_graph, :vertex_6, :vertex_12)
    add_edge(call_graph, :vertex_6, :vertex_13)

    add_edge(call_graph, :vertex_7, :vertex_14)
    add_edge(call_graph, :vertex_7, :vertex_15)

    assert reachable(call_graph, :vertex_3) == [
             :vertex_15,
             :vertex_14,
             :vertex_7,
             :vertex_13,
             :vertex_12,
             :vertex_6,
             :vertex_3
           ]
  end

  test "remove_vertex/2", %{call_graph: call_graph} do
    add_vertex(call_graph, :vertex_1)
    add_vertex(call_graph, :vertex_2)
    add_vertex(call_graph, :vertex_3)

    add_edge(call_graph, :vertex_1, :vertex_2)
    add_edge(call_graph, :vertex_2, :vertex_3)
    add_edge(call_graph, :vertex_3, :vertex_1)

    remove_vertex(call_graph, :vertex_2)

    assert has_vertex?(call_graph, :vertex_1)
    refute has_vertex?(call_graph, :vertex_2)
    assert has_vertex?(call_graph, :vertex_3)

    refute has_edge?(call_graph, :vertex_1, :vertex_2)
    refute has_edge?(call_graph, :vertex_2, :vertex_3)
    assert has_edge?(call_graph, :vertex_3, :vertex_1)
  end

  describe "start/1" do
    test "returns CallGraph struct with name from opts" do
      assert %CallGraph{name: @call_graph_name_2} = start(name: @call_graph_name_2)
    end

    test "process name is registered" do
      %CallGraph{pid: pid} = start(name: @call_graph_name_2)
      assert Process.whereis(@call_graph_name_2) == pid
    end
  end
end
