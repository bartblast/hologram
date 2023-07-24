defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module10
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module11
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module2
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module3
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module4
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module5
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module6
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module7
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module8
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module9

  @call_graph_dump_path Reflection.tmp_path() <> "/call_graph_#{__MODULE__}.bin"
  @call_graph_name_1 :"call_graph_#{__MODULE__}_1"
  @call_graph_name_2 :"call_graph_#{__MODULE__}_2"
  @ir_plt_name :"plt_{__MODULE__}"
  @opts name: @call_graph_name_1

  setup do
    wait_for_process_cleanup(@call_graph_name_1)
    wait_for_process_cleanup(@call_graph_name_2)

    File.rm_rf!(@call_graph_dump_path)

    [call_graph: start(@opts)]
  end

  test "add_edge/3", %{call_graph: call_graph} do
    assert ^call_graph = add_edge(call_graph, :vertex_1, :vertex_2)

    graph = get_graph(call_graph)

    assert Graph.edge(graph, :vertex_1, :vertex_2) == %Graph.Edge{
             v1: :vertex_1,
             v2: :vertex_2,
             weight: 1,
             label: nil
           }
  end

  test "add_edges/2", %{call_graph: call_graph} do
    edges = [Graph.Edge.new(:a, :b), Graph.Edge.new(:c, :d)]

    assert ^call_graph = add_edges(call_graph, edges)
    assert edges(call_graph) == edges
  end

  test "add_vertex/2", %{call_graph: call_graph} do
    assert ^call_graph = add_vertex(call_graph, :vertex_3)

    graph = get_graph(call_graph)
    assert Graph.has_vertex?(graph, :vertex_3)
  end

  describe "build/3" do
    test "atom type ir, which is not an alias", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      assert ^call_graph = build(call_graph, ir, :vertex_1)

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, which as an alias of a non-existing module", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Aaa.Bbb}
      assert ^call_graph = build(call_graph, ir, :vertex_1)

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, which is an alias of an existing non-templatable module", %{
      call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      assert ^call_graph = build(call_graph, ir, :vertex_1)

      assert sorted_vertices(call_graph) == [Module1, :vertex_1]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module1,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "atom type ir, which is an alias of a page module", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Module2}
      assert ^call_graph = build(call_graph, ir, :vertex_1)

      assert sorted_vertices(call_graph) == [
               Module2,
               :vertex_1,
               {Module2, :__hologram_route__, 0}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: Module2,
                 v2: {Module2, :__hologram_route__, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module2,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "atom type ir, which is an alias of a layout module", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Module3}
      assert ^call_graph = build(call_graph, ir, :vertex_1)

      assert sorted_vertices(call_graph) == [Module3, :vertex_1]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module3,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "atom type ir, which is an alias of a component module", %{call_graph: call_graph} do
      ir = %IR.AtomType{value: Module4}
      assert ^call_graph = build(call_graph, ir, :vertex_1)

      assert sorted_vertices(call_graph) == [
               Module4,
               :vertex_1,
               {Module4, :action, 3},
               {Module4, :init, 1},
               {Module4, :template, 0}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: Module4,
                 v2: {Module4, :action, 3},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module4,
                 v2: {Module4, :init, 1},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module4,
                 v2: {Module4, :template, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module4,
                 weight: 1,
                 label: nil
               }
             ]
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

      assert ^call_graph = build(call_graph, ir, Module1)

      assert sorted_vertices(call_graph) == [
               Module5,
               Module6,
               Module7,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module1, :my_fun, 2},
                 v2: Module5,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun, 2},
                 v2: Module6,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun, 2},
                 v2: Module7,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "list", %{call_graph: call_graph} do
      list = [%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}]
      assert ^call_graph = build(call_graph, list, :vertex_1)

      assert sorted_vertices(call_graph) == [Module1, Module5, :vertex_1]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module1,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module5,
                 weight: 1,
                 label: nil
               }
             ]
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

      assert ^call_graph = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert sorted_vertices(call_graph) == [
               Module5,
               Module6,
               Module7,
               {Module1, :my_fun_1, 4},
               {Module1, :my_fun_2, 3}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module5,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module6,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module7,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: {Module1, :my_fun_2, 3},
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "map", %{call_graph: call_graph} do
      map = %{
        %IR.AtomType{value: Module1} => %IR.AtomType{value: Module5},
        %IR.AtomType{value: Module6} => %IR.AtomType{value: Module7}
      }

      assert ^call_graph = build(call_graph, map, :vertex_1)

      assert sorted_vertices(call_graph) == [Module1, Module5, Module6, Module7, :vertex_1]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module1,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module5,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module6,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module7,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "module definition ir", %{call_graph: call_graph} do
      ir = %IR.ModuleDefinition{
        module: %IR.AtomType{value: Module11},
        body: %IR.Block{
          expressions: [
            %IR.AtomType{value: Module5},
            %IR.AtomType{value: Module6}
          ]
        }
      }

      assert ^call_graph = build(call_graph, ir)

      assert sorted_vertices(call_graph) == [
               Module11,
               Module5,
               Module6,
               {Module11, :__hologram_route__, 0}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: Module11,
                 v2: Module5,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module11,
                 v2: Module6,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module11,
                 v2: {Module11, :__hologram_route__, 0},
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "remote function call ir, module field as an atom", %{call_graph: call_graph} do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Module5},
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7},
          %IR.AtomType{value: Module8}
        ]
      }

      assert ^call_graph = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert sorted_vertices(call_graph) == [
               Module6,
               Module7,
               Module8,
               {Module1, :my_fun_1, 4},
               {Module5, :my_fun_2, 3}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module6,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module7,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module8,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: {Module5, :my_fun_2, 3},
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "remote function call ir, module field is a variable", %{call_graph: call_graph} do
      ir = %IR.RemoteFunctionCall{
        module: %IR.Variable{name: :my_var},
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7},
          %IR.AtomType{value: Module8}
        ]
      }

      assert ^call_graph = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert sorted_vertices(call_graph) == [
               Module6,
               Module7,
               Module8,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module6,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module7,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Module8,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "tuple", %{call_graph: call_graph} do
      tuple = {%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}}
      assert ^call_graph = build(call_graph, tuple, :vertex_1)

      assert sorted_vertices(call_graph) == [Module1, Module5, :vertex_1]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module1,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module5,
                 weight: 1,
                 label: nil
               }
             ]
    end
  end

  describe "clone/1" do
    test "returns CallGraph struct with name from opts", %{call_graph: call_graph} do
      assert %CallGraph{name: @call_graph_name_2} = clone(call_graph, name: @call_graph_name_2)
    end

    test "clones the call graph", %{call_graph: call_graph} do
      add_vertex(call_graph, :vertex_1)

      call_graph_clone =
        call_graph
        |> clone(name: @call_graph_name_2)
        |> add_vertex(:vertex_2)

      assert has_vertex?(call_graph, :vertex_1)
      refute has_vertex?(call_graph, :vertex_2)

      assert has_vertex?(call_graph_clone, :vertex_1)
      assert has_vertex?(call_graph_clone, :vertex_2)
    end
  end

  test "dump/1", %{call_graph: call_graph} do
    %{call_graph | dump_path: @call_graph_dump_path}
    |> add_vertex(:vertex_1)
    |> dump()

    graph =
      @call_graph_dump_path
      |> File.read!()
      |> SerializationUtils.deserialize()

    assert Graph.vertices(graph) == [:vertex_1]
  end

  test "edges/1", %{call_graph: call_graph} do
    call_graph
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)
    |> add_edge(:vertex_4, :vertex_5)

    assert edges(call_graph) == [
             %Graph.Edge{v1: :vertex_2, v2: :vertex_3, weight: 1, label: nil},
             %Graph.Edge{v1: :vertex_4, v2: :vertex_5, weight: 1, label: nil}
           ]
  end

  test "graph/1", %{call_graph: call_graph} do
    assert %Graph{} = get_graph(call_graph)
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
    call_graph
    |> add_edge({:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b})
    |> add_edge({:module_3, :fun_c, :arity_c}, {:module_2, :fun_d, :arity_d})
    |> add_edge({:module_4, :fun_e, :arity_e}, :module_2)
    |> add_edge({:module_5, :fun_f, :arity_f}, :module_2)
    |> add_edge({:module_6, :fun_g, :arity_g}, {:module_7, :fun_h, :arity_h})
    |> add_edge({:module_8, :fun_i, :arity_i}, :module_9)

    result =
      call_graph
      |> inbound_remote_edges(:module_2)
      |> Enum.sort()

    assert result == [
             %Graph.Edge{
               v1: {:module_1, :fun_a, :arity_a},
               v2: {:module_2, :fun_b, :arity_b},
               weight: 1,
               label: nil
             },
             %Graph.Edge{
               v1: {:module_3, :fun_c, :arity_c},
               v2: {:module_2, :fun_d, :arity_d},
               weight: 1,
               label: nil
             },
             %Graph.Edge{
               v1: {:module_4, :fun_e, :arity_e},
               v2: :module_2,
               weight: 1,
               label: nil
             },
             %Graph.Edge{
               v1: {:module_5, :fun_f, :arity_f},
               v2: :module_2,
               weight: 1,
               label: nil
             }
           ]
  end

  test "module_vertices/2", %{call_graph: call_graph} do
    call_graph
    |> add_vertex({:module_1, :fun_a, :arity_a})
    |> add_vertex({:module_2, :fun_b, :arity_b})
    |> add_vertex({:module_3, :fun_c, :arity_c})
    |> add_vertex({:module_2, :fun_d, :arity_d})
    |> add_vertex(:module_4)
    |> add_vertex(:module_2)

    assert module_vertices(call_graph, :module_2) == [
             :module_2,
             {:module_2, :fun_b, :arity_b},
             {:module_2, :fun_d, :arity_d}
           ]
  end

  describe "patch/3" do
    test "adds modules", %{call_graph: call_graph} do
      ir_plt = PLT.start(name: @ir_plt_name)

      module_9_ir = IR.for_module(Module9)
      PLT.put(ir_plt, Module9, module_9_ir)

      module_10_ir = IR.for_module(Module10)
      PLT.put(ir_plt, Module10, module_10_ir)

      call_graph_2 =
        [name: @call_graph_name_2]
        |> start()
        |> build(module_9_ir)
        |> build(module_10_ir)

      diff = %{
        added_modules: [Module10, Module9],
        removed_modules: [],
        updated_modules: []
      }

      patch(call_graph, ir_plt, diff)

      assert vertices(call_graph) == vertices(call_graph_2)
      assert edges(call_graph) == edges(call_graph_2)
    end

    test "removes modules", %{call_graph: call_graph} do
      call_graph
      |> add_edge({:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b})
      |> add_edge({:module_2, :fun_c, :arity_c}, {:module_3, :fun_d, :arity_d})
      |> add_edge({:module_1, :fun_e, :arity_e}, {:module_3, :fun_f, :arity_f})
      |> add_edge({:module_4, :fun_g, :arity_g}, :module_2)
      |> add_edge({:module_5, :fun_h, :arity_h}, :module_6)

      ir_plt = PLT.start(name: @ir_plt_name)

      diff = %{
        added_modules: [],
        removed_modules: [:module_2, :module_3],
        updated_modules: []
      }

      patch(call_graph, ir_plt, diff)

      assert vertices(call_graph) == [
               :module_6,
               {:module_1, :fun_a, :arity_a},
               {:module_4, :fun_g, :arity_g},
               {:module_1, :fun_e, :arity_e},
               {:module_5, :fun_h, :arity_h}
             ]

      assert edges(call_graph) == [
               %Graph.Edge{
                 v1: {:module_5, :fun_h, :arity_h},
                 v2: :module_6,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "updates modules", %{call_graph: call_graph} do
      ir_plt = PLT.start(name: @ir_plt_name)

      module_9_ir = IR.for_module(Module9)
      PLT.put(ir_plt, Module9, module_9_ir)

      module_10_ir = IR.for_module(Module10)
      PLT.put(ir_plt, Module10, module_10_ir)

      call_graph
      |> add_edge({:module_3, :fun_c, :arity_c}, Module9)
      |> add_edge({:module_1, :fun_a, :arity_a}, {Module9, :my_fun_1, 0})
      |> add_edge({:module_2, :fun_b, :arity_b}, {Module9, :my_fun_2, 0})
      |> add_edge({:module_1, :fun_d, :arity_d}, Module9)
      |> add_edge({Module9, :my_fun_3, 2}, {:module_4, :fun_e, :arity_e})
      |> add_edge({Module10, :my_fun_4, 2}, {:module_5, :fun_f, :arity_f})

      diff = %{
        added_modules: [],
        removed_modules: [],
        updated_modules: [Module9, Module10]
      }

      patch(call_graph, ir_plt, diff)

      assert vertices(call_graph) == [
               Module9,
               {Module9, :my_fun_1, 0},
               {:module_4, :fun_e, :arity_e},
               {:module_2, :fun_b, :arity_b},
               {:module_1, :fun_a, :arity_a},
               {Module9, :my_fun_2, 0},
               {:module_1, :fun_d, :arity_d},
               {Module10, :my_fun_3, 0},
               {:module_5, :fun_f, :arity_f},
               {Module10, :my_fun_4, 0},
               {:module_3, :fun_c, :arity_c}
             ]

      assert edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module9, :my_fun_1, 0},
                 v2: {Module9, :my_fun_2, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {:module_2, :fun_b, :arity_b},
                 v2: {Module9, :my_fun_2, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {:module_1, :fun_a, :arity_a},
                 v2: {Module9, :my_fun_1, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {:module_1, :fun_d, :arity_d},
                 v2: Module9,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module10, :my_fun_3, 0},
                 v2: {Module10, :my_fun_4, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {:module_3, :fun_c, :arity_c},
                 v2: Module9,
                 weight: 1,
                 label: nil
               }
             ]
    end
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

    call_graph
    |> add_edge(:vertex_1, :vertex_2)
    |> add_edge(:vertex_1, :vertex_3)
    |> add_edge(:vertex_2, :vertex_4)
    |> add_edge(:vertex_2, :vertex_5)
    |> add_edge(:vertex_3, :vertex_6)
    |> add_edge(:vertex_3, :vertex_7)
    |> add_edge(:vertex_4, :vertex_8)
    |> add_edge(:vertex_4, :vertex_9)
    |> add_edge(:vertex_5, :vertex_10)
    |> add_edge(:vertex_5, :vertex_11)
    |> add_edge(:vertex_6, :vertex_12)
    |> add_edge(:vertex_6, :vertex_13)
    |> add_edge(:vertex_7, :vertex_14)
    |> add_edge(:vertex_7, :vertex_15)

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
    call_graph
    |> add_vertex(:vertex_1)
    |> add_vertex(:vertex_2)
    |> add_vertex(:vertex_3)
    |> add_edge(:vertex_1, :vertex_2)
    |> add_edge(:vertex_2, :vertex_3)
    |> add_edge(:vertex_3, :vertex_1)
    |> remove_vertex(:vertex_2)

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

    test "graph is loaded from file when dump_path is given in opts and dump file exists", %{
      call_graph: call_graph
    } do
      %{call_graph | dump_path: @call_graph_dump_path}
      |> add_vertex(:vertex_2)
      |> dump()

      call_graph_2 = start(name: @call_graph_name_2, dump_path: @call_graph_dump_path)
      assert vertices(call_graph_2) == [:vertex_2]
    end

    test "graph is not loaded from file when dump_path is not given in opts" do
      call_graph = start(name: @call_graph_name_2)
      assert vertices(call_graph) == []
    end

    test "graph is not loaded from file when dump_path is given in opts but dump file doesn't exist" do
      call_graph = start(name: @call_graph_name_2, dump_path: @call_graph_dump_path)
      assert vertices(call_graph) == []
    end
  end

  test "vertices/1", %{call_graph: call_graph} do
    call_graph
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)
    |> add_edge(:vertex_4, :vertex_5)

    assert vertices(call_graph) == [:vertex_1, :vertex_2, :vertex_3, :vertex_4, :vertex_5]
  end
end
