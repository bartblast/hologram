defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module10
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module11
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module13
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module14
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module15
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module16
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module17
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module18
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module19
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module2
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module20
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module21
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module22
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module24
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module25
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module27
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module28
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module3
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module30
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module31
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module32
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module33
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module35
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module36
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module37
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module4
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module5
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module6
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module7
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module8
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module9

  @tmp_dir Reflection.tmp_dir()

  setup_all do
    ir_plt = Compiler.build_ir_plt()
    full_call_graph = Compiler.build_call_graph(ir_plt)
    runtime_mfas = CallGraph.list_runtime_mfas(full_call_graph)

    [
      full_call_graph: full_call_graph,
      ir_plt: ir_plt,
      runtime_mfas: runtime_mfas
    ]
  end

  setup do
    [empty_call_graph: start()]
  end

  test "add_edge/3", %{empty_call_graph: call_graph} do
    assert add_edge(call_graph, :vertex_1, :vertex_2) == call_graph

    graph = get_graph(call_graph)

    assert Graph.edge(graph, :vertex_1, :vertex_2) == %Graph.Edge{
             v1: :vertex_1,
             v2: :vertex_2,
             weight: 1,
             label: nil
           }
  end

  test "add_edges/2", %{empty_call_graph: call_graph} do
    edges = [Graph.Edge.new(:a, :b), Graph.Edge.new(:c, :d)]

    assert add_edges(call_graph, edges) == call_graph
    assert edges(call_graph) == edges
  end

  test "add_vertex/2", %{empty_call_graph: call_graph} do
    assert add_vertex(call_graph, :vertex_3) == call_graph

    graph = get_graph(call_graph)
    assert Graph.has_vertex?(graph, :vertex_3)
  end

  describe "build/3" do
    test "atom type ir, which is not an alias", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      assert build(call_graph, ir, :vertex_1) == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, which as an alias of a non-existing module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Aaa.Bbb}
      assert build(call_graph, ir, :vertex_1) == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, which is an alias of an existing non-templatable module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      assert build(call_graph, ir, :vertex_1) == call_graph

      assert sorted_vertices(call_graph) == [Module1, :vertex_1]

      assert edges(call_graph) == [
               %Graph.Edge{
                 v1: :vertex_1,
                 v2: Module1,
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "atom type ir, which is an alias of a page module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module2}
      assert build(call_graph, ir, :vertex_1) == call_graph

      assert sorted_vertices(call_graph) == [
               Module2,
               :vertex_1,
               {Module2, :__params__, 0},
               {Module2, :__route__, 0}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: Module2,
                 v2: {Module2, :__params__, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module2,
                 v2: {Module2, :__route__, 0},
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

    test "atom type ir, which is an alias of a layout module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module3}
      assert build(call_graph, ir, :vertex_1) == call_graph

      assert sorted_vertices(call_graph) == [
               Module3,
               :vertex_1,
               {Module3, :__props__, 0},
               {Module3, :action, 3},
               {Module3, :init, 2},
               {Module3, :template, 0}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{v1: Module3, v2: {Module3, :__props__, 0}, weight: 1, label: nil},
               %Graph.Edge{v1: Module3, v2: {Module3, :action, 3}, weight: 1, label: nil},
               %Graph.Edge{v1: Module3, v2: {Module3, :init, 2}, weight: 1, label: nil},
               %Graph.Edge{v1: Module3, v2: {Module3, :template, 0}, weight: 1, label: nil},
               %Graph.Edge{v1: :vertex_1, v2: Module3, weight: 1, label: nil}
             ]
    end

    test "atom type ir, which is an alias of a component module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module4}
      assert build(call_graph, ir, :vertex_1) == call_graph

      assert sorted_vertices(call_graph) == [
               Module4,
               :vertex_1,
               {Module4, :__props__, 0},
               {Module4, :action, 3},
               {Module4, :init, 2},
               {Module4, :template, 0}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: Module4,
                 v2: {Module4, :__props__, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module4,
                 v2: {Module4, :action, 3},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module4,
                 v2: {Module4, :init, 2},
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

    test "function definition ir, with outbound vertices", %{empty_call_graph: call_graph} do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
          guards: [%IR.AtomType{value: Module5}],
          body: %IR.Block{
            expressions: [
              %IR.AtomType{value: Module6},
              %IR.AtomType{value: Module7}
            ]
          }
        }
      }

      assert build(call_graph, ir, Module1) == call_graph

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

    test "function definition ir, without outbound vertices", %{empty_call_graph: call_graph} do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.AtomType{value: :ok}
            ]
          }
        }
      }

      assert build(call_graph, ir, Module1) == call_graph

      assert sorted_vertices(call_graph) == [{Module1, :my_fun, 2}]

      assert sorted_edges(call_graph) == []
    end

    test "list", %{empty_call_graph: call_graph} do
      list = [%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}]
      assert build(call_graph, list, :vertex_1) == call_graph

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

    test "local function call ir", %{empty_call_graph: call_graph} do
      ir = %IR.LocalFunctionCall{
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module5},
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7}
        ]
      }

      assert build(call_graph, ir, {Module1, :my_fun_1, 4}) == call_graph

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

    test "map", %{empty_call_graph: call_graph} do
      map = %{
        %IR.AtomType{value: Module1} => %IR.AtomType{value: Module5},
        %IR.AtomType{value: Module6} => %IR.AtomType{value: Module7}
      }

      assert build(call_graph, map, :vertex_1) == call_graph

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

    # credo:disable-for-lines:48 Credo.Check.Design.DuplicatedCode
    test "module definition ir", %{empty_call_graph: call_graph} do
      ir = %IR.ModuleDefinition{
        module: %IR.AtomType{value: Module11},
        body: %IR.Block{
          expressions: [
            %IR.AtomType{value: Module5},
            %IR.AtomType{value: Module6}
          ]
        }
      }

      assert build(call_graph, ir) == call_graph

      assert sorted_vertices(call_graph) == [
               Module11,
               Module5,
               Module6,
               {Module11, :__params__, 0},
               {Module11, :__route__, 0}
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
                 v2: {Module11, :__params__, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: Module11,
                 v2: {Module11, :__route__, 0},
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "remote function call ir, module field as an atom", %{empty_call_graph: call_graph} do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Module5},
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7},
          %IR.AtomType{value: Module8}
        ]
      }

      assert build(call_graph, ir, {Module1, :my_fun_1, 4}) == call_graph

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

    test "remote function call ir, module field is a variable", %{empty_call_graph: call_graph} do
      ir = %IR.RemoteFunctionCall{
        module: %IR.Variable{name: :my_var},
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7},
          %IR.AtomType{value: Module8}
        ]
      }

      assert build(call_graph, ir, {Module1, :my_fun_1, 4}) == call_graph

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

    test "remote function call using Kernel.apply/3, module and function fields are both atoms",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.AtomType{value: DateTime},
          %IR.AtomType{value: :utc_now},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      assert build(call_graph, ir, {Module1, :my_fun_1, 4}) == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {DateTime, :utc_now, 1},
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Calendar.ISO,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: {DateTime, :utc_now, 1},
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "remote function call using Kernel.apply/3, module field is an atom, function field is not an atom",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.AtomType{value: DateTime},
          %IR.Variable{name: :my_fun},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      assert build(call_graph, ir, {Module1, :my_fun_1, 4}) == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               DateTime,
               {DateTime, :__struct__, 0},
               {DateTime, :__struct__, 1},
               {Module1, :my_fun_1, 4},
               {:erlang, :apply, 3}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: DateTime,
                 v2: {DateTime, :__struct__, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: DateTime,
                 v2: {DateTime, :__struct__, 1},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Calendar.ISO,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: DateTime,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: {:erlang, :apply, 3},
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "remote function call using Kernel.apply/3, module field is not an atom, function field is an atom",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.Variable{name: :module},
          %IR.AtomType{value: :utc_now},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      assert build(call_graph, ir, {Module1, :my_fun_1, 4}) == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {Module1, :my_fun_1, 4},
               {:erlang, :apply, 3}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: Calendar.ISO,
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module1, :my_fun_1, 4},
                 v2: {:erlang, :apply, 3},
                 weight: 1,
                 label: nil
               }
             ]
    end

    test "tuple", %{empty_call_graph: call_graph} do
      tuple = {%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}}
      assert build(call_graph, tuple, :vertex_1) == call_graph

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

    test "protocol (implementation edges are added)", %{empty_call_graph: call_graph} do
      ir = IR.for_module(String.Chars)
      build(call_graph, ir)

      from_vertex = {String.Chars, :to_string, 1}

      assert has_edge?(call_graph, from_vertex, {String.Chars.Atom, :__impl__, 1})

      assert has_edge?(call_graph, from_vertex, {String.Chars.Atom, :to_string, 1})

      assert has_edge?(
               call_graph,
               from_vertex,
               {String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12, :__impl__, 1}
             )

      assert has_edge?(
               call_graph,
               from_vertex,
               {String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12, :to_string, 1}
             )
    end

    # TODO: verify programatically that "use Ecto.Schema"
    # still adds __changeset__/0 (maybe in consistency tests)
    test "Ecto schema (__changeset__/0 edge is added)", %{empty_call_graph: call_graph} do
      ir = IR.for_module(Module21)
      build(call_graph, ir)

      assert has_edge?(call_graph, Module21, {Module21, :__changeset__, 0})
    end
  end

  # credo:disable-for-lines:50 Credo.Check.Design.DuplicatedCode
  test "build_for_module/3", %{empty_call_graph: call_graph} do
    ir = %IR.ModuleDefinition{
      module: %IR.AtomType{value: Module11},
      body: %IR.Block{
        expressions: [
          %IR.AtomType{value: Module5},
          %IR.AtomType{value: Module6}
        ]
      }
    }

    ir_plt = PLT.start(items: [{Module11, ir}])

    assert build_for_module(call_graph, ir_plt, Module11) == call_graph

    assert sorted_vertices(call_graph) == [
             Module11,
             Module5,
             Module6,
             {Module11, :__params__, 0},
             {Module11, :__route__, 0}
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
               v2: {Module11, :__params__, 0},
               weight: 1,
               label: nil
             },
             %Graph.Edge{
               v1: Module11,
               v2: {Module11, :__route__, 0},
               weight: 1,
               label: nil
             }
           ]
  end

  test "clone/1", %{full_call_graph: call_graph} do
    assert %CallGraph{} = call_graph_clone = clone(call_graph)

    refute call_graph_clone == call_graph
    assert get_graph(call_graph_clone) == get_graph(call_graph)
  end

  test "dump/2", %{empty_call_graph: call_graph} do
    dump_dir =
      Path.join([
        @tmp_dir,
        "tests",
        "compiler",
        "call_graph",
        "dump_2",
        "nested_a",
        "nested_b"
      ])

    clean_dir(dump_dir)

    dump_path = Path.join(dump_dir, Reflection.call_graph_dump_file_name())

    graph =
      call_graph
      |> add_edge(:vertex_1, :vertex_2)
      |> get_graph()

    assert dump(call_graph, dump_path) == call_graph

    deserialized_graph =
      dump_path
      |> File.read!()
      |> SerializationUtils.deserialize()

    assert deserialized_graph == graph
  end

  test "edges/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    result = edges(call_graph)

    assert Enum.count(result) == 2
    assert %Graph.Edge{v1: :vertex_2, v2: :vertex_3, weight: 1, label: nil} in result
    assert %Graph.Edge{v1: :vertex_4, v2: :vertex_5, weight: 1, label: nil} in result
  end

  test "get_graph/1", %{empty_call_graph: call_graph} do
    assert %Graph{} = get_graph(call_graph)
  end

  describe "has_edge?/3" do
    test "has the given edge", %{empty_call_graph: call_graph} do
      add_edge(call_graph, :vertex_1, :vertex_2)
      assert has_edge?(call_graph, :vertex_1, :vertex_2)
    end

    test "doesn't have the given edge", %{empty_call_graph: call_graph} do
      refute has_edge?(call_graph, :vertex_1, :vertex_2)
    end
  end

  describe "has_vertex?/2" do
    test "has the given vertex", %{empty_call_graph: call_graph} do
      add_vertex(call_graph, :vertex)
      assert has_vertex?(call_graph, :vertex)
    end

    test "doesn't have the given vertex", %{empty_call_graph: call_graph} do
      refute has_vertex?(call_graph, :vertex)
    end
  end

  test "inbound_remote_edges/2", %{empty_call_graph: call_graph} do
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

  test "list_page_entry_mfas/1" do
    assert list_page_entry_mfas(Module19) == [
             {Module19, :__layout_module__, 0},
             {Module19, :__layout_props__, 0},
             {Module19, :__params__, 0},
             {Module19, :__route__, 0},
             {Module19, :action, 3},
             {Module19, :template, 0},
             {Module20, :__props__, 0},
             {Module20, :action, 3},
             {Module20, :template, 0}
           ]
  end

  describe "list_page_mfas/2" do
    setup %{full_call_graph: full_call_graph, runtime_mfas: runtime_mfas} do
      page_module_22_mfas =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> list_page_mfas(Module22)

      [page_module_22_mfas: page_module_22_mfas]
    end

    test "includes action/3, template/0 and other MFAs that should be included" do
      module_14_ir = IR.for_module(Module14)
      module_15_ir = IR.for_module(Module15)
      module_16_ir = IR.for_module(Module16)

      result =
        start()
        |> build(module_14_ir)
        |> build(module_15_ir)
        |> build(module_16_ir)
        |> list_page_mfas(Module14)

      assert result == [
               {Enum, :reverse, 1},
               {Enum, :to_list, 1},
               {Module14, :__layout_module__, 0},
               {Module14, :__layout_props__, 0},
               {Module14, :__params__, 0},
               {Module14, :__route__, 0},
               {Module14, :action, 3},
               {Module14, :template, 0},
               {Module15, :__props__, 0},
               {Module15, :action, 3},
               {Module15, :init, 2},
               {Module15, :template, 0},
               {Module16, :my_fun_16a, 2},
               {Kernel, :inspect, 1},
               {:erlang, :hd, 1}
             ]
    end

    test "excludes Hex.Solver's implementations for Inspect and String.Chars protocols" do
      module_17_ir = IR.for_module(Module17)

      result =
        start()
        |> build(module_17_ir)
        |> list_page_mfas(Module17)

      assert {Module18, :my_fun_18, 2} in result

      assert {Inspect.Integer, :__impl__, 1} in result
      assert {Inspect.Integer, :inspect, 2} in result

      refute {Inspect.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {Inspect.Hex.Solver.PackageRange, :inspect, 2} in result

      assert {String.Chars.Integer, :__impl__, 1} in result
      assert {String.Chars.Integer, :to_string, 1} in result

      refute {String.Chars.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {String.Chars.Hex.Solver.PackageRange, :to_string, 1} in result
    end

    test "excludes Hex.Solver.* MFAs" do
      module_17_ir = IR.for_module(Module17)

      result =
        start()
        |> build(module_17_ir)
        |> list_page_mfas(Module17)

      refute {Hex.Solver.Assignment, :__struct__, 0} in result
      refute {Hex.Solver.Assignment, :__struct__, 1} in result
    end

    test "includes reflection MFAs reachable from server inits of components used by the page", %{
      page_module_22_mfas: result
    } do
      assert {Module24, :__changeset__, 0} in result
      assert {Module24, :__schema__, 1} in result
      assert {Module24, :__schema__, 2} in result

      assert {Module25, :__struct__, 0} in result
      assert {Module25, :__struct__, 1} in result

      assert {Module27, :__changeset__, 0} in result
      assert {Module27, :__schema__, 1} in result
      assert {Module27, :__schema__, 2} in result

      assert {Module28, :__struct__, 0} in result
      assert {Module28, :__struct__, 1} in result

      assert {Module30, :__changeset__, 0} in result
      assert {Module30, :__schema__, 1} in result
      assert {Module30, :__schema__, 2} in result

      assert {Module31, :__struct__, 0} in result
      assert {Module31, :__struct__, 1} in result

      assert {Module32, :__changeset__, 0} in result
      assert {Module32, :__schema__, 1} in result
      assert {Module32, :__schema__, 2} in result

      assert {Module33, :__struct__, 0} in result
      assert {Module33, :__struct__, 1} in result

      assert {Module35, :__changeset__, 0} in result
      assert {Module35, :__schema__, 1} in result
      assert {Module35, :__schema__, 2} in result

      assert {Module36, :__struct__, 0} in result
      assert {Module36, :__struct__, 1} in result

      assert {Module37, :__struct__, 0} in result
      assert {Module37, :__struct__, 1} in result
    end

    test "removes duplicate reflection MFAs reachable from server inits of components used by the page",
         %{page_module_22_mfas: result} do
      assert Enum.count(result, &(&1 == {Module32, :__changeset__, 0})) == 1
      assert Enum.count(result, &(&1 == {Module32, :__schema__, 1})) == 1
      assert Enum.count(result, &(&1 == {Module32, :__schema__, 2})) == 1

      assert Enum.count(result, &(&1 == {Module37, :__struct__, 0})) == 1
      assert Enum.count(result, &(&1 == {Module37, :__struct__, 1})) == 1
    end

    test "results are deduped", %{page_module_22_mfas: result} do
      assert result == Enum.uniq(result)
    end

    test "results are sorted", %{page_module_22_mfas: result} do
      assert result == Enum.sort(result)
    end
  end

  test "list_runtime_entry_mfas/0" do
    result = list_runtime_entry_mfas()

    assert {:erlang, :error, 1} in result
    assert {String.Chars, :to_string, 1} in result

    assert {Hologram.Router.Helpers, :page_path, 1} in result

    refute {:unicode, :characters_to_binary, 1} in result
    refute {Hologram.Router.Helpers, :asset_path, 1} in result
  end

  describe "list_runtime_mfas/1" do
    setup %{full_call_graph: call_graph} do
      [runtime_mfas: list_runtime_mfas(call_graph)]
    end

    test "includes MFAs that are reachable by Elixir functions used by the runtime", %{
      runtime_mfas: result
    } do
      assert {Enum, :into, 2} in result
      assert {Enum, :into_protocol, 2} in result
      assert {:lists, :foldl, 3} in result

      assert {Enum, :to_list, 1} in result
      assert {Enum, :reverse, 1} in result
      assert {:lists, :reverse, 1} in result
    end

    test "includes MFAs that are reachable by Erlang functions used by the runtime", %{
      runtime_mfas: result
    } do
      assert {:erlang, :==, 2} in result
      assert {:erlang, :error, 2} in result
    end

    test "excludes MFAs with non-existing modules", %{full_call_graph: call_graph} do
      call_graph_clone = CallGraph.clone(call_graph)

      call_graph_clone
      |> add_edge({Enum, :into, 2}, {Calendar.ISO, :dummy_function_1, 1})
      |> add_edge({Enum, :into, 2}, {NonExistingModuleFixture, :dummy_function_2, 2})
      |> add_edge({Enum, :into, 2}, {:maps, :dummy_function_3, 3})
      |> add_edge({Enum, :into, 2}, {:non_existing_module_fixture, :dummy_function_4, 4})

      result = list_runtime_mfas(call_graph_clone)

      assert {Calendar.ISO, :dummy_function_1, 1} in result
      refute {NonExistingModuleFixture, :dummy_function_2, 2} in result
      assert {:maps, :dummy_function_3, 3} in result
      refute {:non_existing_module_fixture, :dummy_function_4, 4} in result
    end

    test "excludes Hex.Solver's implementations for Inspect and String.Chars protocols", %{
      runtime_mfas: result
    } do
      assert {Inspect.Integer, :__impl__, 1} in result
      assert {Inspect.Integer, :inspect, 2} in result

      refute {Inspect.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {Inspect.Hex.Solver.PackageRange, :inspect, 2} in result

      assert {String.Chars.Integer, :__impl__, 1} in result
      assert {String.Chars.Integer, :to_string, 1} in result

      refute {String.Chars.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {String.Chars.Hex.Solver.PackageRange, :to_string, 1} in result
    end

    test "excludes Hex.Solver.* MFAs", %{runtime_mfas: result} do
      refute {Hex.Solver.Assignment, :__struct__, 0} in result
      refute {Hex.Solver.Assignment, :__struct__, 1} in result
    end

    test "results are deduped", %{runtime_mfas: result} do
      assert result == Enum.uniq(result)
    end

    test "results are sorted", %{runtime_mfas: result} do
      assert result == Enum.sort(result)
    end
  end

  test "load/2", %{empty_call_graph: call_graph} do
    add_edge(call_graph, :vertex_1, :vertex_2)

    dump_dir = Path.join([@tmp_dir, "tests", "compiler", "call_graph", "load_2"])
    clean_dir(dump_dir)

    dump_path = Path.join(dump_dir, Reflection.call_graph_dump_file_name())
    dump(call_graph, dump_path)

    call_graph_2 = start()

    assert load(call_graph_2, dump_path) == call_graph_2
    assert get_graph(call_graph_2) == get_graph(call_graph)
  end

  describe "maybe_load/2" do
    setup do
      dump_dir = Path.join([@tmp_dir, "tests", "compiler", "call_graph", "maybe_load_2"])
      clean_dir(dump_dir)

      [dump_path: Path.join(dump_dir, Reflection.call_graph_dump_file_name())]
    end

    test "dump file exists", %{dump_path: dump_path} do
      graph = Graph.add_edge(Graph.new(), :vertex_1, :vertex_2)

      data = SerializationUtils.serialize(graph)
      File.write!(dump_path, data)

      call_graph = start()

      assert maybe_load(call_graph, dump_path) == call_graph
      assert get_graph(call_graph) == graph
    end

    test "dump file doesn't exist", %{dump_path: dump_path} do
      call_graph = start()

      assert maybe_load(call_graph, dump_path) == call_graph
      assert get_graph(call_graph) == Graph.new()
    end
  end

  test "module_vertices/2", %{empty_call_graph: call_graph} do
    ir = IR.for_module(Module13)

    call_graph
    |> add_vertex({:module_1, :fun_a, 1})
    |> add_vertex({:module_3, :fun_b, 2})
    |> build(ir)
    |> add_vertex(:module_4)

    assert module_vertices(call_graph, Module13) == [
             {Module13, :fun_b, 2},
             {Module13, :fun_d, 4},
             {Module13, :fun_e, 2}
           ]
  end

  describe "patch/3" do
    test "adds modules", %{empty_call_graph: call_graph_1} do
      module_9_ir = IR.for_module(Module9)
      module_10_ir = IR.for_module(Module10)

      ir_plt =
        PLT.start()
        |> PLT.put(Module9, module_9_ir)
        |> PLT.put(Module10, module_10_ir)

      call_graph_2 =
        start()
        |> build(module_9_ir)
        |> build(module_10_ir)

      diff = %{
        added_modules: [Module10, Module9],
        removed_modules: [],
        updated_modules: []
      }

      patch(call_graph_1, ir_plt, diff)

      assert get_graph(call_graph_1) == get_graph(call_graph_2)
    end

    test "removes modules", %{empty_call_graph: call_graph} do
      call_graph
      |> add_edge({:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b})
      |> add_edge({:module_2, :fun_c, :arity_c}, {:module_3, :fun_d, :arity_d})
      |> add_edge({:module_1, :fun_e, :arity_e}, {:module_3, :fun_f, :arity_f})
      |> add_edge({:module_4, :fun_g, :arity_g}, :module_2)
      |> add_edge({:module_5, :fun_h, :arity_h}, :module_6)

      ir_plt = PLT.start()

      diff = %{
        added_modules: [],
        removed_modules: [:module_2, :module_3],
        updated_modules: []
      }

      patch(call_graph, ir_plt, diff)

      assert sorted_vertices(call_graph) == [
               :module_6,
               {:module_1, :fun_a, :arity_a},
               {:module_1, :fun_e, :arity_e},
               {:module_4, :fun_g, :arity_g},
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

    test "updates modules", %{empty_call_graph: call_graph} do
      module_9_ir = IR.for_module(Module9)
      module_10_ir = IR.for_module(Module10)

      ir_plt =
        PLT.start()
        |> PLT.put(Module9, module_9_ir)
        |> PLT.put(Module10, module_10_ir)

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

      assert sorted_vertices(call_graph) == [
               Module9,
               {Module10, :my_fun_3, 0},
               {Module10, :my_fun_4, 0},
               {Module9, :my_fun_1, 0},
               {Module9, :my_fun_2, 0},
               {:module_1, :fun_a, :arity_a},
               {:module_1, :fun_d, :arity_d},
               {:module_2, :fun_b, :arity_b},
               {:module_3, :fun_c, :arity_c},
               {:module_4, :fun_e, :arity_e},
               {:module_5, :fun_f, :arity_f}
             ]

      assert sorted_edges(call_graph) == [
               %Graph.Edge{
                 v1: {Module10, :my_fun_3, 0},
                 v2: {Module10, :my_fun_4, 0},
                 weight: 1,
                 label: nil
               },
               %Graph.Edge{
                 v1: {Module9, :my_fun_1, 0},
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
                 v1: {:module_2, :fun_b, :arity_b},
                 v2: {Module9, :my_fun_2, 0},
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

  test "put_graph", %{empty_call_graph: call_graph} do
    graph = Graph.add_edge(Graph.new(), :vertex_3, :vertex_4)

    assert put_graph(call_graph, graph) == call_graph
    assert get_graph(call_graph) == graph
  end

  describe "reachable/2" do
    setup do
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

      graph =
        Graph.new()
        |> Graph.add_edge(:vertex_1, :vertex_2)
        |> Graph.add_edge(:vertex_1, :vertex_3)
        |> Graph.add_edge(:vertex_2, :vertex_4)
        |> Graph.add_edge(:vertex_2, :vertex_5)
        |> Graph.add_edge(:vertex_3, :vertex_6)
        |> Graph.add_edge(:vertex_3, :vertex_7)
        |> Graph.add_edge(:vertex_4, :vertex_8)
        |> Graph.add_edge(:vertex_4, :vertex_9)
        |> Graph.add_edge(:vertex_5, :vertex_10)
        |> Graph.add_edge(:vertex_5, :vertex_11)
        |> Graph.add_edge(:vertex_6, :vertex_12)
        |> Graph.add_edge(:vertex_6, :vertex_13)
        |> Graph.add_edge(:vertex_7, :vertex_14)
        |> Graph.add_edge(:vertex_7, :vertex_15)

      [graph: graph]
    end

    test "single vertex argument", %{graph: graph} do
      assert reachable(graph, :vertex_3) == [
               :vertex_15,
               :vertex_14,
               :vertex_7,
               :vertex_13,
               :vertex_12,
               :vertex_6,
               :vertex_3
             ]
    end

    test "multiple vertices argument", %{graph: graph} do
      assert reachable(graph, [:vertex_3, :vertex_5]) == [
               :vertex_11,
               :vertex_10,
               :vertex_5,
               :vertex_15,
               :vertex_14,
               :vertex_7,
               :vertex_13,
               :vertex_12,
               :vertex_6,
               :vertex_3
             ]
    end

    test "vertex that is not in the call graph", %{graph: graph} do
      assert reachable(graph, :not_in_call_graph) == []
    end

    test "vertices that are not in the call graph", %{graph: graph} do
      assert reachable(graph, [:not_in_call_graph_1, :not_in_call_graph_2]) == []
    end
  end

  describe "remove_manually_ported_mfas/1" do
    setup %{full_call_graph: call_graph} do
      call_graph_clone =
        call_graph
        |> CallGraph.clone()
        |> remove_manually_ported_mfas()

      [call_graph: call_graph_clone]
    end

    test "excludes Elixir functions which are ported manually", %{call_graph: call_graph} do
      refute CallGraph.has_vertex?(call_graph, {Kernel, :inspect, 1})
    end

    test "includes functions which are not ported manually", %{call_graph: call_graph} do
      assert CallGraph.has_vertex?(call_graph, {Kernel, :hd, 1})
    end
  end

  test "remove_runtime_mfas!/2", %{ir_plt: ir_plt} do
    call_graph = Compiler.build_call_graph(ir_plt)
    runtime_mfas = list_runtime_mfas(call_graph)

    CallGraph.add_edge(call_graph, :my_vertex_1, :my_vertex_2)

    CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

    assert CallGraph.has_edge?(call_graph, :my_vertex_1, :my_vertex_2)

    Enum.each(runtime_mfas, fn mfa ->
      refute CallGraph.has_vertex?(call_graph, mfa)
    end)
  end

  test "remove_vertex/2", %{empty_call_graph: call_graph} do
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

  test "remove_vertices/2", %{empty_call_graph: call_graph} do
    call_graph
    |> add_vertex(:vertex_1)
    |> add_vertex(:vertex_2)
    |> add_vertex(:vertex_3)
    |> add_vertex(:vertex_4)
    |> add_edge(:vertex_1, :vertex_2)
    |> add_edge(:vertex_2, :vertex_3)
    |> add_edge(:vertex_3, :vertex_4)
    |> add_edge(:vertex_4, :vertex_1)
    |> remove_vertices([:vertex_2, :vertex_3])

    assert has_vertex?(call_graph, :vertex_1)
    refute has_vertex?(call_graph, :vertex_2)
    refute has_vertex?(call_graph, :vertex_3)
    assert has_vertex?(call_graph, :vertex_4)

    refute has_edge?(call_graph, :vertex_1, :vertex_2)
    refute has_edge?(call_graph, :vertex_2, :vertex_3)
    refute has_edge?(call_graph, :vertex_3, :vertex_4)
    assert has_edge?(call_graph, :vertex_4, :vertex_1)
  end

  test "sorted_edges/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    assert sorted_edges(call_graph) == [
             %Graph.Edge{v1: :vertex_2, v2: :vertex_3, weight: 1, label: nil},
             %Graph.Edge{v1: :vertex_4, v2: :vertex_5, weight: 1, label: nil}
           ]
  end

  describe "sorted_reachable_mfas/2" do
    setup do
      # 1
      # ├─ {Module2, :f2, 2}
      # │  ├─ 4
      # │  │  ├─ {Module8, :f8, 8}
      # │  │  ├─ 9
      # │  ├─ {Module5, :f5, 5}
      # │  │  ├─ 10
      # │  │  ├─ 11
      # ├─ {Module3, :f3, 3}
      # │  ├─ 6
      # │  │  ├─ {Module11, :f12, 12}
      # │  │  ├─ 13
      # │  ├─ {Module7, :f7, 7}
      # │  │  ├─ 14
      # │  │  ├─ {Module15, :f15, 15}
      # |  |  |- {Collectable.Atom, :fca, 123}

      graph =
        Graph.new()
        |> Graph.add_edge(:vertex_1, {Module2, :f2, 2})
        |> Graph.add_edge(:vertex_1, {Module3, :f3, 3})
        |> Graph.add_edge({Module2, :f2, 2}, :vertex_4)
        |> Graph.add_edge({Module2, :f2, 2}, {Module5, :f5, 5})
        |> Graph.add_edge({Module3, :f3, 3}, :vertex_6)
        |> Graph.add_edge({Module3, :f3, 3}, {Module7, :f7, 7})
        |> Graph.add_edge(:vertex_4, {Module8, :f8, 8})
        |> Graph.add_edge(:vertex_4, :vertex_9)
        |> Graph.add_edge({Module5, :f5, 5}, :vertex_10)
        |> Graph.add_edge({Module5, :f5, 5}, :vertex_11)
        |> Graph.add_edge(:vertex_6, {Module11, :f12, 12})
        |> Graph.add_edge(:vertex_6, :vertex_13)
        |> Graph.add_edge({Module7, :f7, 7}, :vertex_14)
        |> Graph.add_edge({Module7, :f7, 7}, {Module15, :f15, 15})
        |> Graph.add_edge({Module7, :f7, 7}, {Collectable.Atom, :fca, 123})

      [graph: graph]
    end

    test "single MFA argument", %{graph: graph} do
      assert sorted_reachable_mfas(graph, {Module3, :f3, 3}) == [
               {Module11, :f12, 12},
               {Module15, :f15, 15},
               {Module3, :f3, 3},
               {Module7, :f7, 7}
             ]
    end

    test "multiple MFAs argument", %{graph: graph} do
      assert sorted_reachable_mfas(graph, [{Module5, :f5, 5}, {Module3, :f3, 3}]) == [
               {Module11, :f12, 12},
               {Module15, :f15, 15},
               {Module3, :f3, 3},
               {Module5, :f5, 5},
               {Module7, :f7, 7}
             ]
    end
  end

  test "sorted_vertices/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    assert sorted_vertices(call_graph) == [:vertex_1, :vertex_2, :vertex_3, :vertex_4, :vertex_5]
  end

  describe "start/1" do
    test "default graph param" do
      assert %CallGraph{pid: pid} = start()
      assert is_pid(pid)
      assert Agent.get(pid, & &1) == Graph.new()
    end

    test "graph param specified" do
      graph = Graph.add_vertex(Graph.new(), :my_vertex)

      assert %CallGraph{pid: pid} = start(graph)
      assert is_pid(pid)
      assert Agent.get(pid, & &1) == graph
    end
  end

  test "stop/1" do
    %{pid: pid} = call_graph = start()

    assert stop(call_graph) == :ok
    refute Process.alive?(pid)
  end

  test "vertices/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    result = vertices(call_graph)

    assert Enum.count(result) == 5
    assert :vertex_1 in result
    assert :vertex_2 in result
    assert :vertex_3 in result
    assert :vertex_4 in result
    assert :vertex_5 in result
  end
end
