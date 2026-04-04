# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
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

  alias String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12, as: StringCharsModule12

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
    result = add_edge(call_graph, :vertex_1, :vertex_2)
    assert result == call_graph

    graph = get_graph(call_graph)
    assert Digraph.edges(graph) == [{:vertex_1, :vertex_2}]
  end

  test "add_edges/2", %{empty_call_graph: call_graph} do
    edges = [{:a, :b}, {:c, :d}]
    result = add_edges(call_graph, edges)

    assert result == call_graph

    graph = get_graph(call_graph)
    assert Digraph.sorted_edges(graph) == edges
  end

  describe "add_non_discoverable_edges/1" do
    test "adds @erlang_mfa_edges to the call graph", %{empty_call_graph: call_graph} do
      add_non_discoverable_edges(call_graph)

      assert has_edge?(call_graph, {:binary, :match, 2}, {:binary, :match, 3})
    end

    test "adds @dynamic_dispatch_edges to the call graph", %{empty_call_graph: call_graph} do
      add_non_discoverable_edges(call_graph)

      assert has_edge?(call_graph, {Date, :new, 4}, {Calendar.ISO, :valid_date?, 3})
    end
  end

  test "add_vertex/2", %{empty_call_graph: call_graph} do
    result = add_vertex(call_graph, :vertex_3)
    assert result == call_graph

    graph = get_graph(call_graph)
    assert Digraph.vertices(graph) == [:vertex_3]
  end

  describe "build/3" do
    test "atom type ir, which is not an alias", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, which as an alias of a non-existing module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Aaa.Bbb}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Aaa.Bbb, :vertex_1]
      assert edges(call_graph) == [{:vertex_1, Aaa.Bbb}]
    end

    test "atom type ir, which is an alias of an existing non-templatable module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, :vertex_1]
      assert edges(call_graph) == [{:vertex_1, Module1}]
    end

    test "atom type ir, which is an alias of a page module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module2}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module2, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module2}]
    end

    test "atom type ir, which is an alias of a layout module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module3}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module3, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module3}]
    end

    test "atom type ir, which is an alias of a component module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module4}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module4, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module4}]
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

      result = build(call_graph, ir, Module1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               Module6,
               Module7,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module5},
               {{Module1, :my_fun, 2}, Module6},
               {{Module1, :my_fun, 2}, Module7}
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

      result = build(call_graph, ir, Module1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [{Module1, :my_fun, 2}]
      assert sorted_edges(call_graph) == []
    end

    test "list", %{empty_call_graph: call_graph} do
      list = [%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}]
      result = build(call_graph, list, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5}
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

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               Module6,
               Module7,
               {Module1, :my_fun_1, 4},
               {Module1, :my_fun_2, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module5},
               {{Module1, :my_fun_1, 4}, Module6},
               {{Module1, :my_fun_1, 4}, Module7},
               {{Module1, :my_fun_1, 4}, {Module1, :my_fun_2, 3}}
             ]
    end

    test "map", %{empty_call_graph: call_graph} do
      map = %{
        %IR.AtomType{value: Module1} => %IR.AtomType{value: Module5},
        %IR.AtomType{value: Module6} => %IR.AtomType{value: Module7}
      }

      result = build(call_graph, map, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, Module6, Module7, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5},
               {:vertex_1, Module6},
               {:vertex_1, Module7}
             ]
    end

    test "module definition ir, regular module", %{empty_call_graph: call_graph} do
      ir = %IR.ModuleDefinition{
        module: %IR.AtomType{value: Module1},
        body: %IR.Block{
          expressions: [
            %IR.AtomType{value: Module5},
            %IR.AtomType{value: Module6}
          ]
        }
      }

      result = build(call_graph, ir)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module1,
               Module5,
               Module6
             ]

      assert sorted_edges(call_graph) == [
               {Module1, Module5},
               {Module1, Module6}
             ]
    end

    test "module definition ir, page module adds page-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_2_ir = IR.for_module(Module2)
      result = build(call_graph, module_2_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module2, :__params__, 0})
      assert has_vertex?(call_graph, {Module2, :__route__, 0})

      assert has_edge?(call_graph, Module2, {Module2, :__params__, 0})
      assert has_edge?(call_graph, Module2, {Module2, :__route__, 0})
    end

    test "module definition ir, component module adds component-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_4_ir = IR.for_module(Module4)
      result = build(call_graph, module_4_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module4, :__props__, 0})
      assert has_vertex?(call_graph, {Module4, :action, 3})
      assert has_vertex?(call_graph, {Module4, :init, 2})
      assert has_vertex?(call_graph, {Module4, :template, 0})

      assert has_edge?(call_graph, Module4, {Module4, :__props__, 0})
      assert has_edge?(call_graph, Module4, {Module4, :action, 3})
      assert has_edge?(call_graph, Module4, {Module4, :init, 2})
      assert has_edge?(call_graph, Module4, {Module4, :template, 0})
    end

    test "module definition ir, struct module adds struct-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_25_ir = IR.for_module(Module25)
      result = build(call_graph, module_25_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module25, :__struct__, 0})
      assert has_vertex?(call_graph, {Module25, :__struct__, 1})

      assert has_edge?(call_graph, Module25, {Module25, :__struct__, 0})
      assert has_edge?(call_graph, Module25, {Module25, :__struct__, 1})
    end

    test "module definition ir, Ecto schema module adds Ecto schema-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_21_ir = IR.for_module(Module21)
      result = build(call_graph, module_21_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module21, :__changeset__, 0})
      assert has_vertex?(call_graph, {Module21, :__schema__, 1})
      assert has_vertex?(call_graph, {Module21, :__schema__, 2})

      assert has_edge?(call_graph, Module21, {Module21, :__changeset__, 0})
      assert has_edge?(call_graph, Module21, {Module21, :__schema__, 1})
      assert has_edge?(call_graph, Module21, {Module21, :__schema__, 2})
    end

    test "module definition ir, protocol module adds protocol-specific edges", %{
      empty_call_graph: call_graph
    } do
      string_chars_ir = IR.for_module(String.Chars)
      result = build(call_graph, string_chars_ir)

      assert result == call_graph

      from_vertex = {String.Chars, :to_string, 1}

      assert has_edge?(call_graph, from_vertex, {String.Chars.Atom, :__impl__, 1})
      assert has_edge?(call_graph, from_vertex, {String.Chars.Atom, :to_string, 1})

      assert has_edge?(
               call_graph,
               from_vertex,
               {StringCharsModule12, :__impl__, 1}
             )

      assert has_edge?(
               call_graph,
               from_vertex,
               {StringCharsModule12, :to_string, 1}
             )
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

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               Module7,
               Module8,
               {Module1, :my_fun_1, 4},
               {Module5, :my_fun_2, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module6},
               {{Module1, :my_fun_1, 4}, Module7},
               {{Module1, :my_fun_1, 4}, Module8},
               {{Module1, :my_fun_1, 4}, {Module5, :my_fun_2, 3}}
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

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               Module7,
               Module8,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module6},
               {{Module1, :my_fun_1, 4}, Module7},
               {{Module1, :my_fun_1, 4}, Module8}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
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

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {DateTime, :utc_now, 1},
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO},
               {{Module1, :my_fun_1, 4}, {DateTime, :utc_now, 1}}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
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

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               DateTime,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO},
               {{Module1, :my_fun_1, 4}, DateTime}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
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

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
    test "remote function call using Kernel.apply/3, neither module nor function field is an atom",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.Variable{name: :module},
          %IR.Variable{name: :my_fun},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO}
             ]
    end

    test "tuple", %{empty_call_graph: call_graph} do
      tuple = {%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}}
      result = build(call_graph, tuple, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5}
             ]
    end
  end

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
             {Module11, Module5},
             {Module11, Module6},
             {Module11, {Module11, :__params__, 0}},
             {Module11, {Module11, :__route__, 0}}
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
    assert {:vertex_2, :vertex_3} in result
    assert {:vertex_4, :vertex_5} in result
  end

  test "get_graph/1", %{empty_call_graph: call_graph} do
    assert %Digraph{} = get_graph(call_graph)
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

  describe "list_async_mfas/1" do
    test "returns empty set when Task.await/1 is not in the graph" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {MyModule, :helper, 1})
        |> list_async_mfas()

      assert result == MapSet.new()
    end

    test "returns MFAs that directly call Task.await/1" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {Task, :await, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{MyModule, :action, 3}, {Task, :await, 1}])
    end

    test "returns MFAs that transitively call Task.await/1" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {MyModule, :fetch_data, 1})
        |> add_edge({MyModule, :fetch_data, 1}, {Task, :await, 1})
        |> list_async_mfas()

      assert result ==
               MapSet.new([
                 {MyModule, :action, 3},
                 {MyModule, :fetch_data, 1},
                 {Task, :await, 1}
               ])
    end

    test "excludes MFAs that do not reach Task.await/1" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {Task, :await, 1})
        |> add_edge({OtherModule, :action, 3}, {OtherModule, :sync_helper, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{MyModule, :action, 3}, {Task, :await, 1}])
    end

    test "excludes module vertices (non-MFA)" do
      result =
        start()
        |> add_edge(MyModule, {MyModule, :action, 3})
        |> add_edge({MyModule, :action, 3}, {Task, :await, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{MyModule, :action, 3}, {Task, :await, 1}])
    end

    test "does not mark MFAs as async when they only reach Task.await/1 through a module vertex" do
      result =
        start()
        |> add_edge({MyModule, :my_fun, 1}, OtherModule)
        |> add_edge(OtherModule, {OtherModule, :fetch_data, 1})
        |> add_edge({OtherModule, :fetch_data, 1}, {Task, :await, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{OtherModule, :fetch_data, 1}, {Task, :await, 1}])
    end
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

    test "excludes Hex MFAs" do
      module_17_ir = IR.for_module(Module17)

      call_graph =
        start()
        |> build(module_17_ir)
        |> add_edge({Module17, :action, 3}, {Hex, :start, 2})
        |> add_edge({Module17, :action, 3}, {Hex, :version, 0})

      result = list_page_mfas(call_graph, Module17)

      assert {Module18, :my_fun_18, 2} in result

      refute {Hex, :start, 2} in result
      refute {Hex, :version, 0} in result
    end

    test "excludes Hex.* MFAs" do
      module_17_ir = IR.for_module(Module17)

      call_graph =
        start()
        |> build(module_17_ir)
        |> add_edge({Module17, :action, 3}, {Hex.API, :request, 4})
        |> add_edge({Module17, :action, 3}, {Hex.Registry.Server, :versions, 2})

      result = list_page_mfas(call_graph, Module17)

      assert {Module18, :my_fun_18, 2} in result

      refute {Hex.API, :request, 4} in result
      refute {Hex.Registry.Server, :versions, 2} in result
    end

    test "excludes Hex implementations for Inspect and String.Chars protocols" do
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

    test "excludes Hex MFAs", %{full_call_graph: call_graph} do
      call_graph_clone = CallGraph.clone(call_graph)

      call_graph_clone
      |> add_edge({Enum, :into, 2}, {Hex, :start, 2})
      |> add_edge({Enum, :into, 2}, {Hex, :version, 0})

      result = list_runtime_mfas(call_graph_clone)

      assert {Enum, :into, 2} in result

      refute {Hex, :start, 2} in result
      refute {Hex, :version, 0} in result
    end

    test "excludes Hex.* MFAs", %{full_call_graph: call_graph} do
      call_graph_clone = CallGraph.clone(call_graph)

      call_graph_clone
      |> add_edge({Enum, :into, 2}, {Hex.API, :request, 4})
      |> add_edge({Enum, :into, 2}, {Hex.Registry.Server, :versions, 2})

      result = list_runtime_mfas(call_graph_clone)

      assert {Enum, :into, 2} in result

      refute {Hex.API, :request, 4} in result
      refute {Hex.Registry.Server, :versions, 2} in result
    end

    test "excludes Hex implementations for Inspect and String.Chars protocols", %{
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

  test "manually_ported_elixir_mfas/0" do
    result = manually_ported_elixir_mfas()

    assert is_list(result)
    assert {Kernel, :inspect, 1} in result
    assert {String, :upcase, 1} in result
  end

  describe "maybe_load/2" do
    setup do
      dump_dir = Path.join([@tmp_dir, "tests", "compiler", "call_graph", "maybe_load_2"])
      clean_dir(dump_dir)

      [dump_path: Path.join(dump_dir, Reflection.call_graph_dump_file_name())]
    end

    test "dump file exists", %{dump_path: dump_path} do
      graph = Digraph.add_edge(Digraph.new(), :vertex_1, :vertex_2)

      data = SerializationUtils.serialize(graph)
      File.write!(dump_path, data)

      call_graph = start()

      assert maybe_load(call_graph, dump_path) == call_graph
      assert get_graph(call_graph) == graph
    end

    test "dump file doesn't exist", %{dump_path: dump_path} do
      call_graph = start()

      assert maybe_load(call_graph, dump_path) == call_graph
      assert get_graph(call_graph) == Digraph.new()
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
        edited_modules: []
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
        edited_modules: []
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
               {{:module_5, :fun_h, :arity_h}, :module_6}
             ]
    end

    test "adds protocol dispatch edges when an added module is a protocol implementation", %{
      empty_call_graph: call_graph
    } do
      impl_module = StringCharsModule12
      impl_ir = IR.for_module(impl_module)
      from_vertex = {String.Chars, :to_string, 1}

      # Simulate a previous build that had String.Chars but not Module12:
      # manually add the protocol function vertex without the dispatch edge to Module12.
      add_vertex(call_graph, from_vertex)

      refute has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      refute has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})

      # Now patch with Module12 (which has defimpl String.Chars) as an added module
      ir_plt = PLT.put(PLT.start(), impl_module, impl_ir)

      diff = %{
        added_modules: [impl_module],
        removed_modules: [],
        edited_modules: []
      }

      patch(call_graph, ir_plt, diff)

      assert has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      assert has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})
    end

    test "adds protocol dispatch edges when an edited module is a protocol implementation", %{
      empty_call_graph: call_graph
    } do
      impl_module = StringCharsModule12
      impl_ir = IR.for_module(impl_module)
      from_vertex = {String.Chars, :to_string, 1}

      # Simulate a previous build: the protocol function vertex exists and the
      # implementation module was already built (has its own internal edges).
      call_graph
      |> add_vertex(from_vertex)
      |> build(impl_ir)

      # The impl's internal edges exist, but there are no dispatch edges
      # from the protocol to the implementation.
      assert has_vertex?(call_graph, {impl_module, :to_string, 1})
      refute has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      refute has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})

      ir_plt = PLT.put(PLT.start(), impl_module, impl_ir)

      diff = %{
        added_modules: [],
        removed_modules: [],
        edited_modules: [impl_module]
      }

      patch(call_graph, ir_plt, diff)

      assert has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      assert has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})
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
        edited_modules: [Module9, Module10]
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
               {{Module10, :my_fun_3, 0}, {Module10, :my_fun_4, 0}},
               {{Module9, :my_fun_1, 0}, {Module9, :my_fun_2, 0}},
               {{:module_1, :fun_a, :arity_a}, {Module9, :my_fun_1, 0}},
               {{:module_1, :fun_d, :arity_d}, Module9},
               {{:module_2, :fun_b, :arity_b}, {Module9, :my_fun_2, 0}},
               {{:module_3, :fun_c, :arity_c}, Module9}
             ]
    end
  end

  test "put_graph", %{empty_call_graph: call_graph} do
    graph = Digraph.add_edge(Digraph.new(), :vertex_3, :vertex_4)

    assert put_graph(call_graph, graph) == call_graph
    assert get_graph(call_graph) == graph
  end

  describe "reachable_mfas/2" do
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
        Digraph.new()
        |> Digraph.add_edge(:vertex_1, {Module2, :f2, 2})
        |> Digraph.add_edge(:vertex_1, {Module3, :f3, 3})
        |> Digraph.add_edge({Module2, :f2, 2}, :vertex_4)
        |> Digraph.add_edge({Module2, :f2, 2}, {Module5, :f5, 5})
        |> Digraph.add_edge({Module3, :f3, 3}, :vertex_6)
        |> Digraph.add_edge({Module3, :f3, 3}, {Module7, :f7, 7})
        |> Digraph.add_edge(:vertex_4, {Module8, :f8, 8})
        |> Digraph.add_edge(:vertex_4, :vertex_9)
        |> Digraph.add_edge({Module5, :f5, 5}, :vertex_10)
        |> Digraph.add_edge({Module5, :f5, 5}, :vertex_11)
        |> Digraph.add_edge(:vertex_6, {Module11, :f12, 12})
        |> Digraph.add_edge(:vertex_6, :vertex_13)
        |> Digraph.add_edge({Module7, :f7, 7}, :vertex_14)
        |> Digraph.add_edge({Module7, :f7, 7}, {Module15, :f15, 15})
        |> Digraph.add_edge({Module7, :f7, 7}, {Collectable.Atom, :fca, 123})

      [graph: graph]
    end

    test "single MFA argument", %{graph: graph} do
      result = reachable_mfas(graph, [{Module3, :f3, 3}])

      assert Enum.sort(result) == [
               {Module11, :f12, 12},
               {Module15, :f15, 15},
               {Module3, :f3, 3},
               {Module7, :f7, 7}
             ]
    end

    test "multiple MFAs argument", %{graph: graph} do
      result = reachable_mfas(graph, [{Module5, :f5, 5}, {Module3, :f3, 3}])

      assert Enum.sort(result) == [
               {Module11, :f12, 12},
               {Module15, :f15, 15},
               {Module3, :f3, 3},
               {Module5, :f5, 5},
               {Module7, :f7, 7}
             ]
    end
  end

  test "remote_incoming_edges/2", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge({:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b})
    |> add_edge({:module_3, :fun_c, :arity_c}, {:module_2, :fun_d, :arity_d})
    |> add_edge({:module_4, :fun_e, :arity_e}, :module_2)
    |> add_edge({:module_5, :fun_f, :arity_f}, :module_2)
    |> add_edge({:module_6, :fun_g, :arity_g}, {:module_7, :fun_h, :arity_h})
    |> add_edge({:module_8, :fun_i, :arity_i}, :module_9)

    result =
      call_graph
      |> remote_incoming_edges(:module_2)
      |> Enum.sort()

    assert result == [
             {{:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b}},
             {{:module_3, :fun_c, :arity_c}, {:module_2, :fun_d, :arity_d}},
             {{:module_4, :fun_e, :arity_e}, :module_2},
             {{:module_5, :fun_f, :arity_f}, :module_2}
           ]
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
             {:vertex_2, :vertex_3},
             {:vertex_4, :vertex_5}
           ]
  end

  describe "sorted_reachable_mfas/2" do
    setup do
      # Simple graph to verify sorting behavior.
      # Reachability logic is tested in reachable_mfas/2 tests.
      graph =
        Digraph.new()
        |> Digraph.add_edge(:vertex_1, {Module7, :f7, 7})
        |> Digraph.add_edge(:vertex_1, {Module3, :f3, 3})
        |> Digraph.add_edge({Module3, :f3, 3}, {Module11, :f12, 12})

      [graph: graph]
    end

    test "returns same results as reachable_mfas/2 but sorted", %{graph: graph} do
      unsorted = reachable_mfas(graph, [:vertex_1])
      sorted = sorted_reachable_mfas(graph, [:vertex_1])

      assert sorted == Enum.sort(unsorted)
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
      assert Agent.get(pid, & &1) == Digraph.new()
    end

    test "graph param specified" do
      graph = Digraph.add_vertex(Digraph.new(), :my_vertex)

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

  # Consistency tests verifying that the Elixir stdlib IR patterns
  # assumed by the call graph still hold. If these fail after an
  # Elixir upgrade, the corresponding call graph code needs updating.
  describe "Elixir stdlib IR pattern assumptions" do
    defp find_fun_defs(ir_plt, module, name, arity) do
      %IR.ModuleDefinition{body: %IR.Block{expressions: expressions}} =
        PLT.get!(ir_plt, module)

      Enum.filter(expressions, &match?(%IR.FunctionDefinition{name: ^name, arity: ^arity}, &1))
    end

    # Dynamic dispatch assumption: Date.day_of_era/1 extracts calendar from the struct
    # and calls `calendar.day_of_era(year, month, day)`.
    #
    # Original source:
    #   def day_of_era(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.day_of_era(year, month, day)
    #   end
    test "Date.day_of_era/1 dynamically dispatches calendar.day_of_era/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :day_of_era, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :day_of_era,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.day_of_week/2 extracts calendar from the struct
    # and calls `calendar.day_of_week(year, month, day, starting_on)`.
    #
    # Original source:
    #   def day_of_week(%{calendar: calendar, year: year, month: month, day: day}, starting_on) do
    #     {day_of_week, _first, _last} = calendar.day_of_week(year, month, day, starting_on)
    #     day_of_week
    #   end
    test "Date.day_of_week/2 dynamically dispatches calendar.day_of_week/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :day_of_week, 2)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   },
                   _starting_on
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :day_of_week,
                         args: [_year_arg, _month_arg, _day_arg, _starting_on_arg]
                       }
                     },
                     _result
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.day_of_year/1 extracts calendar from the struct
    # and calls `calendar.day_of_year(year, month, day)`.
    #
    # Original source:
    #   def day_of_year(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.day_of_year(year, month, day)
    #   end
    test "Date.day_of_year/1 dynamically dispatches calendar.day_of_year/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :day_of_year, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :day_of_year,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.days_in_month/1 extracts calendar from the struct
    # and calls `calendar.days_in_month(year, month)`.
    #
    # Original source:
    #   def days_in_month(%{calendar: calendar, year: year, month: month}) do
    #     calendar.days_in_month(year, month)
    #   end
    test "Date.days_in_month/1 dynamically dispatches calendar.days_in_month/2",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :days_in_month, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :days_in_month,
                       args: [_year_arg, _month_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.leap_year?/1 extracts calendar from the struct
    # and calls `calendar.leap_year?(year)`.
    #
    # Original source:
    #   def leap_year?(%{calendar: calendar, year: year}) do
    #     calendar.leap_year?(year)
    #   end
    test "Date.leap_year?/1 dynamically dispatches calendar.leap_year?/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :leap_year?, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :leap_year?,
                       args: [_year_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.months_in_year/1 extracts calendar from the struct
    # and calls `calendar.months_in_year(year)`.
    #
    # Original source:
    #   def months_in_year(%{calendar: calendar, year: year}) do
    #     calendar.months_in_year(year)
    #   end
    test "Date.months_in_year/1 dynamically dispatches calendar.months_in_year/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :months_in_year, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :months_in_year,
                       args: [_year_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Default param assumption: Date.new/3 is the generated clause that fills in the
    # Calendar.ISO default and calls Date.new/4. The Calendar.ISO atom appears in the body
    # as data (not a dispatch target).
    #
    # Generated from: def new(year, month, day, calendar \\ Calendar.ISO)
    #
    # Expanded:
    #   def new(x0, x1, x2), do: new(x0, x1, x2, Calendar.ISO)
    test "Date.new/3 fills in Calendar.ISO default and calls Date.new/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :new, 3)

      assert fun_def == %IR.FunctionDefinition{
               name: :new,
               arity: 3,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x0, version: 0},
                   %IR.Variable{name: :x1, version: 1},
                   %IR.Variable{name: :x2, version: 2}
                 ],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.LocalFunctionCall{
                       function: :new,
                       args: [
                         %IR.Variable{name: :x0, version: 0},
                         %IR.Variable{name: :x1, version: 1},
                         %IR.Variable{name: :x2, version: 2},
                         %IR.AtomType{value: Calendar.ISO}
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Dynamic dispatch assumption: Date.new/4 has `calendar \\ Calendar.ISO` and calls
    # `calendar.valid_date?(year, month, day)` where calendar is a variable, not a literal
    # module atom. This call can't be discovered from static IR analysis, so we add a
    # manual edge in @dynamic_dispatch_edges.
    #
    # Original source:
    #   def new(year, month, day, calendar \\ Calendar.ISO) do
    #     if calendar.valid_date?(year, month, day) do
    #       {:ok, %Date{year: year, month: month, day: day, calendar: calendar}}
    #     else
    #       {:error, :invalid_date}
    #     end
    #   end
    test "Date.new/4 dynamically dispatches calendar.valid_date?/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :new, 4)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_year, _month, _day, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     %IR.Case{
                       condition: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :valid_date?,
                         args: [_year_arg, _month_arg, _day_arg]
                       }
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.quarter_of_year/1 extracts calendar from the struct
    # and calls `calendar.quarter_of_year(year, month, day)`.
    #
    # Original source:
    #   def quarter_of_year(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.quarter_of_year(year, month, day)
    #   end
    test "Date.quarter_of_year/1 dynamically dispatches calendar.quarter_of_year/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :quarter_of_year, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :quarter_of_year,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.shift/2 extracts calendar from the struct
    # and calls `calendar.shift_date(year, month, day, duration)`.
    # Date.shift/2 was added in Elixir 1.17.0.
    #
    # Original source:
    #   def shift(%{calendar: calendar} = date, duration) do
    #     %{year: year, month: month, day: day} = date
    #     {year, month, day} = calendar.shift_date(year, month, day, __duration__!(duration))
    #     %Date{calendar: calendar, year: year, month: month, day: day}
    #   end
    if Version.match?(System.version(), ">= 1.17.0") do
      test "Date.shift/2 dynamically dispatches calendar.shift_date/4",
           %{ir_plt: ir_plt} do
        assert [fun_def] = find_fun_defs(ir_plt, Date, :shift, 2)

        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   params: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                       }
                     },
                     _duration
                   ],
                   body: %IR.Block{
                     expressions: [
                       _destructure,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_date,
                           args: [_year, _month, _day, _duration_arg]
                         }
                       },
                       _result
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: Date.to_string/1 extracts calendar from the struct
    # and calls `calendar.date_to_string(year, month, day)`.
    #
    # Original source:
    #   def to_string(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.date_to_string(year, month, day)
    #   end
    test "Date.to_string/1 dynamically dispatches calendar.date_to_string/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :date_to_string,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.year_of_era/1 extracts calendar from the struct
    # and calls `calendar.year_of_era(year, month, day)`.
    #
    # Original source (Elixir >= 1.18):
    #   def year_of_era(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.year_of_era(year, month, day)
    #   end
    #
    # Original source (Elixir < 1.18):
    #   def year_of_era(%{calendar: calendar, year: year, month: month, day: day}) do
    #     if function_exported?(calendar, :year_of_era, 3) do
    #       calendar.year_of_era(year, month, day)
    #     else
    #       calendar.year_of_era(year)
    #     end
    #   end
    test "Date.year_of_era/1 dynamically dispatches calendar.year_of_era/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :year_of_era, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ]
               }
             } = fun_def

      if Version.match?(System.version(), ">= 1.18.0") do
        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :year_of_era,
                         args: [_year_arg, _month_arg, _day_arg]
                       }
                     ]
                   }
                 }
               } = fun_def
      else
        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   body: %IR.Block{
                     expressions: [
                       %IR.Case{
                         condition: %IR.RemoteFunctionCall{
                           function: :function_exported,
                           args: [
                             %IR.Variable{name: :calendar},
                             %IR.AtomType{value: :year_of_era},
                             %IR.IntegerType{value: 3}
                           ]
                         }
                       }
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: Inspect.Date.inspect/2 extracts calendar from the struct
    # and calls `calendar.date_to_string(year, month, day)`. Calendar.ISO dates with normal
    # years reach this clause in all Elixir versions:
    # - Elixir >= 1.18: guard `when calendar != Calendar.ISO or year in -9999..9999`
    # - Elixir 1.17: guard `when year in -9999..9999`
    # - Elixir < 1.17: no guard (single clause handles all dates)
    #
    # Original source (Elixir >= 1.18):
    #   def inspect(%{calendar: calendar, year: year, month: month, day: day}, _)
    #       when calendar != Calendar.ISO or year in -9999..9999 do
    #     "~D[" <> calendar.date_to_string(year, month, day) <> suffix(calendar) <> "]"
    #   end
    #
    # Original source (Elixir 1.17):
    #   def inspect(%{calendar: calendar, year: year, month: month, day: day}, _)
    #       when year in -9999..9999 do
    #     "~D[" <> calendar.date_to_string(year, month, day) <> suffix(calendar) <> "]"
    #   end
    #
    # Original source (Elixir < 1.17):
    #   def inspect(%{calendar: calendar, year: year, month: month, day: day}, _) do
    #     "~D[" <> calendar.date_to_string(year, month, day) <> suffix(calendar) <> "]"
    #   end
    test "Inspect.Date.inspect/2 dynamically dispatches calendar.date_to_string/3",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Inspect.Date, :inspect, 2)
      assert [first_clause | _rest] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   },
                   _opts
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.BitstringType{
                       segments: [
                         _prefix,
                         %IR.BitstringSegment{
                           value: %IR.RemoteFunctionCall{
                             module: %IR.Variable{name: :calendar},
                             function: :date_to_string,
                             args: [_year_arg, _month_arg, _day_arg]
                           }
                         },
                         _suffix,
                         _closing
                       ]
                     }
                   ]
                 }
               }
             } = first_clause

      cond do
        Version.match?(System.version(), ">= 1.18.0") ->
          assert [
                   %IR.RemoteFunctionCall{
                     function: :orelse,
                     args: [
                       %IR.RemoteFunctionCall{
                         function: :"/=",
                         args: [%IR.Variable{name: :calendar}, %IR.AtomType{value: Calendar.ISO}]
                       },
                       _year_range_check
                     ]
                   }
                 ] = first_clause.clause.guards

        Version.match?(System.version(), ">= 1.17.0") ->
          assert [
                   %IR.RemoteFunctionCall{
                     function: :andalso,
                     args: [
                       %IR.RemoteFunctionCall{
                         function: :is_integer,
                         args: [%IR.Variable{name: :year}]
                       },
                       _year_range_check
                     ]
                   }
                 ] = first_clause.clause.guards

        true ->
          assert [] = first_clause.clause.guards
      end
    end

    # Dynamic dispatch assumption: Inspect.Time.inspect/2 destructures calendar from the
    # struct in the body and calls `calendar.time_to_string(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def inspect(time, _) do
    #     %{hour: hour, minute: minute, second: second,
    #       microsecond: microsecond, calendar: calendar} = time
    #     "~T[" <> calendar.time_to_string(hour, minute, second, microsecond) <>
    #       suffix(calendar) <> "]"
    #   end
    test "Inspect.Time.inspect/2 dynamically dispatches calendar.time_to_string/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Inspect.Time, :inspect, 2)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :time}, _opts],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond},
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                         ]
                       }
                     },
                     %IR.BitstringType{
                       segments: [
                         _prefix,
                         %IR.BitstringSegment{
                           value: %IR.RemoteFunctionCall{
                             module: %IR.Variable{name: :calendar},
                             function: :time_to_string,
                             args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                           }
                         },
                         _suffix,
                         _closing
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.beginning_of_day/1 extracts calendar from
    # the struct and calls `calendar.iso_days_to_beginning_of_day(iso_days)`.
    #
    # Original source:
    #   def beginning_of_day(%{calendar: calendar, microsecond: {_, precision}} = naive_datetime) do
    #     naive_datetime
    #     |> to_iso_days()
    #     |> calendar.iso_days_to_beginning_of_day()
    #     |> from_iso_days(calendar, precision)
    #   end
    test "NaiveDateTime.beginning_of_day/1 dynamically dispatches calendar.iso_days_to_beginning_of_day/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :beginning_of_day, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MatchOperator{
                     left: %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                         {%IR.AtomType{value: :microsecond}, _microsecond}
                       ]
                     }
                   }
                 ]
               }
             } = fun_def

      # The pipe chain compiles to:
      # from_iso_days(calendar.iso_days_to_beginning_of_day(to_iso_days(ndt)), calendar, precision)
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [
                     %IR.LocalFunctionCall{
                       function: :from_iso_days,
                       args: [
                         %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :iso_days_to_beginning_of_day,
                           args: [_iso_days]
                         },
                         %IR.Variable{name: :calendar},
                         _precision
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.end_of_day/1 extracts calendar from
    # the struct and calls `calendar.iso_days_to_end_of_day(iso_days)`.
    #
    # Original source:
    #   def end_of_day(%{calendar: calendar, microsecond: {_, precision}} = naive_datetime) do
    #     end_of_day =
    #       naive_datetime
    #       |> to_iso_days()
    #       |> calendar.iso_days_to_end_of_day()
    #       |> from_iso_days(calendar, precision)
    #     ...
    #   end
    test "NaiveDateTime.end_of_day/1 dynamically dispatches calendar.iso_days_to_end_of_day/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :end_of_day, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MatchOperator{
                     left: %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                         {%IR.AtomType{value: :microsecond}, _microsecond}
                       ]
                     }
                   }
                 ]
               }
             } = fun_def

      # The pipe chain compiles to:
      # from_iso_days(calendar.iso_days_to_end_of_day(to_iso_days(ndt)), calendar, precision)
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.LocalFunctionCall{
                         function: :from_iso_days,
                         args: [
                           %IR.RemoteFunctionCall{
                             module: %IR.Variable{name: :calendar},
                             function: :iso_days_to_end_of_day,
                             args: [_iso_days]
                           },
                           %IR.Variable{name: :calendar},
                           _precision
                         ]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.from_iso_days/3 (private) receives calendar
    # as a parameter and calls `calendar.naive_datetime_from_iso_days(iso_days)`.
    #
    # Original source:
    #   defp from_iso_days(iso_days, calendar, precision) do
    #     {year, month, day, hour, minute, second, {microsecond, _}} =
    #       calendar.naive_datetime_from_iso_days(iso_days)
    #     ...
    #   end
    test "NaiveDateTime.from_iso_days/3 dynamically dispatches calendar.naive_datetime_from_iso_days/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :from_iso_days, 3)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_iso_days, %IR.Variable{name: :calendar}, _precision],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :naive_datetime_from_iso_days,
                         args: [_iso_days_arg]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.new/8 receives calendar as a parameter
    # (default Calendar.ISO) and calls both `calendar.valid_date?(year, month, day)` and
    # `calendar.valid_time?(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def new(year, month, day, hour, minute, second, microsecond, calendar) do
    #     cond do
    #       not calendar.valid_date?(year, month, day) -> {:error, :invalid_date}
    #       not calendar.valid_time?(hour, minute, second, microsecond) -> {:error, :invalid_time}
    #       true -> ...
    #     end
    #   end
    test "NaiveDateTime.new/8 dynamically dispatches calendar.valid_date?/3 and calendar.valid_time?/4",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, NaiveDateTime, :new, 8)
      assert [_clause_1, clause_2] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   _year,
                   _month,
                   _day,
                   _hour,
                   _minute,
                   _second,
                   _microsecond,
                   %IR.Variable{name: :calendar}
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.Cond{
                       clauses: [
                         %IR.CondClause{
                           condition: %IR.RemoteFunctionCall{
                             module: %IR.AtomType{value: :erlang},
                             function: :not,
                             args: [
                               %IR.RemoteFunctionCall{
                                 module: %IR.Variable{name: :calendar},
                                 function: :valid_date?,
                                 args: [_year_arg, _month_arg, _day_arg]
                               }
                             ]
                           }
                         },
                         %IR.CondClause{
                           condition: %IR.RemoteFunctionCall{
                             module: %IR.AtomType{value: :erlang},
                             function: :not,
                             args: [
                               %IR.RemoteFunctionCall{
                                 module: %IR.Variable{name: :calendar},
                                 function: :valid_time?,
                                 args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                               }
                             ]
                           }
                         },
                         _true_clause
                       ]
                     }
                   ]
                 }
               }
             } = clause_2
    end

    # Dynamic dispatch assumption: NaiveDateTime.shift/2 extracts calendar from the struct
    # and calls `calendar.shift_naive_datetime(year, month, day, hour, minute, second,
    # microsecond, duration)`. NaiveDateTime.shift/2 was added in Elixir 1.17.0.
    #
    # Original source:
    #   def shift(%{calendar: calendar} = naive_datetime, duration) do
    #     %{year: year, month: month, day: day, hour: hour, minute: minute,
    #       second: second, microsecond: microsecond} = naive_datetime
    #     {year, month, day, hour, minute, second, microsecond} =
    #       calendar.shift_naive_datetime(year, month, day, hour, minute, second,
    #         microsecond, __duration__!(duration))
    #     ...
    #   end
    if Version.match?(System.version(), ">= 1.17.0") do
      test "NaiveDateTime.shift/2 dynamically dispatches calendar.shift_naive_datetime/8",
           %{ir_plt: ir_plt} do
        assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :shift, 2)

        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   params: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                       }
                     },
                     _duration
                   ],
                   body: %IR.Block{
                     expressions: [
                       _destructure,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_naive_datetime,
                           args: [
                             _year,
                             _month,
                             _day,
                             _hour,
                             _minute,
                             _second,
                             _microsecond,
                             _duration_arg
                           ]
                         }
                       }
                       | _rest
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: String.Chars.Date.to_string/1 extracts calendar from
    # the struct and calls `calendar.date_to_string(year, month, day)`.
    #
    # Original source:
    #   def to_string(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.date_to_string(year, month, day)
    #   end
    test "String.Chars.Date.to_string/1 dynamically dispatches calendar.date_to_string/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, String.Chars.Date, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :date_to_string,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: String.Chars.Time.to_string/1 destructures calendar
    # from the struct in the body and calls
    # `calendar.time_to_string(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def to_string(time) do
    #     %{hour: hour, minute: minute, second: second,
    #       microsecond: microsecond, calendar: calendar} = time
    #     calendar.time_to_string(hour, minute, second, microsecond)
    #   end
    test "String.Chars.Time.to_string/1 dynamically dispatches calendar.time_to_string/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, String.Chars.Time, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :time}],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond},
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                         ]
                       }
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :time_to_string,
                       args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Time.convert/2 receives calendar as a parameter and
    # calls `calendar.time_from_day_fraction(day_fraction)`.
    #
    # Original source:
    #   def convert(%{microsecond: {_, precision}} = time, calendar) do
    #     {hour, minute, second, {microsecond, _}} =
    #       time
    #       |> to_day_fraction()
    #       |> calendar.time_from_day_fraction()
    #     ...
    #   end
    test "Time.convert/2 dynamically dispatches calendar.time_from_day_fraction/1",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Time, :convert, 2)
      assert [_clause_1, clause_2] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_time, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :time_from_day_fraction,
                         args: [_day_fraction]
                       }
                     },
                     _struct_assignment,
                     _ok_tuple
                   ]
                 }
               }
             } = clause_2
    end

    # Dynamic dispatch assumption: Time.from_seconds_after_midnight/3 receives calendar
    # as a parameter (default Calendar.ISO) and calls
    # `calendar.time_from_day_fraction({seconds_in_day, @seconds_per_day})`.
    #
    # Original source:
    #   def from_seconds_after_midnight(seconds, microsecond \\ {0, 0}, calendar \\ Calendar.ISO)
    #       when is_integer(seconds) do
    #     seconds_in_day = Integer.mod(seconds, @seconds_per_day)
    #     {hour, minute, second, {_, _}} =
    #       calendar.time_from_day_fraction({seconds_in_day, @seconds_per_day})
    #     ...
    #   end
    test "Time.from_seconds_after_midnight/3 dynamically dispatches calendar.time_from_day_fraction/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Time, :from_seconds_after_midnight, 3)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_seconds, _microsecond, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     _seconds_in_day,
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :time_from_day_fraction,
                         args: [_day_fraction]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Time.new/5 receives calendar as a parameter
    # (default Calendar.ISO) and calls `calendar.valid_time?(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def new(hour, minute, second, {microsecond, precision}, calendar)
    #       when is_integer(hour) and ... do
    #     case calendar.valid_time?(hour, minute, second, {microsecond, precision}) do
    #       ...
    #     end
    #   end
    test "Time.new/5 dynamically dispatches calendar.valid_time?/4",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Time, :new, 5)
      assert [_clause_1, clause_2] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_hour, _minute, _second, _microsecond, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     %IR.Case{
                       condition: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :valid_time?,
                         args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                       }
                     }
                   ]
                 }
               }
             } = clause_2
    end

    # Dynamic dispatch assumption: Time.shift/2 extracts calendar from the struct
    # and calls `calendar.shift_time(hour, minute, second, microsecond, duration)`.
    # Time.shift/2 was added in Elixir 1.17.0.
    #
    # Original source:
    #   def shift(%{calendar: calendar} = time, duration) do
    #     %{hour: hour, minute: minute, second: second, microsecond: microsecond} = time
    #     {hour, minute, second, microsecond} =
    #       calendar.shift_time(hour, minute, second, microsecond, __duration__!(duration))
    #     ...
    #   end
    if Version.match?(System.version(), ">= 1.17.0") do
      test "Time.shift/2 dynamically dispatches calendar.shift_time/5",
           %{ir_plt: ir_plt} do
        assert [fun_def] = find_fun_defs(ir_plt, Time, :shift, 2)

        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   params: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                       }
                     },
                     _duration
                   ],
                   body: %IR.Block{
                     expressions: [
                       _destructure,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_time,
                           args: [_hour, _minute, _second, _microsecond, _duration_arg]
                         }
                       }
                       | _rest
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: Time.to_day_fraction/1 (private) extracts calendar
    # from the struct and calls `calendar.time_to_day_fraction(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   defp to_day_fraction(%{hour: hour, minute: minute, second: second,
    #          microsecond: {_, _} = microsecond, calendar: calendar}) do
    #     calendar.time_to_day_fraction(hour, minute, second, microsecond)
    #   end
    test "Time.to_day_fraction/1 dynamically dispatches calendar.time_to_day_fraction/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Time, :to_day_fraction, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :hour}, _hour},
                       {%IR.AtomType{value: :minute}, _minute},
                       {%IR.AtomType{value: :second}, _second},
                       {%IR.AtomType{value: :microsecond}, _microsecond},
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :time_to_day_fraction,
                       args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Time.to_string/1 extracts calendar from the struct
    # and calls `calendar.time_to_string(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def to_string(%{hour: hour, minute: minute, second: second,
    #         microsecond: microsecond, calendar: calendar}) do
    #     calendar.time_to_string(hour, minute, second, microsecond)
    #   end
    test "Time.to_string/1 dynamically dispatches calendar.time_to_string/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Time, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :hour}, _hour},
                       {%IR.AtomType{value: :minute}, _minute},
                       {%IR.AtomType{value: :second}, _second},
                       {%IR.AtomType{value: :microsecond}, _microsecond},
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :time_to_string,
                       args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end
  end
end
