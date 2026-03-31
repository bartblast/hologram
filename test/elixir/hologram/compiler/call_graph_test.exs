defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.CallGraph.Context
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
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module2
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
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module38
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module39
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module4
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module41Error
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module42
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module43
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module44
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module45
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module46
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module47
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module5
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module6
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module7
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module8
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module9
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Struct1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Struct2

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

  test "add_vertex/2", %{empty_call_graph: call_graph} do
    result = add_vertex(call_graph, :vertex_3)
    assert result == call_graph

    graph = get_graph(call_graph)
    assert Digraph.vertices(graph) == [:vertex_3]
  end

  describe "build/3" do
    test "atom type ir, which is not an alias", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, which as an alias of a non-existing module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Aaa.Bbb}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Aaa.Bbb, :vertex_1]
      assert edges(call_graph) == [{:vertex_1, Aaa.Bbb}]
    end

    test "atom type ir, which is an alias of an existing non-templatable module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, :vertex_1]
      assert edges(call_graph) == [{:vertex_1, Module1}]
    end

    test "atom type ir, which is an alias of a page module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module2}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module2, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module2}]
    end

    test "atom type ir, which is an alias of a layout module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module3}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module3, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module3}]
    end

    test "atom type ir, which is an alias of a component module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module4}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module4, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module4}]
    end

    test "atom type ir, alias in guard context does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1, guard?: true})

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, alias in pattern context does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1, pattern?: true})

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type ir, alias with suppress_edges_to_module_vertices? modifier does not create edge",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.AtomType{value: Module1}

      modifiers = %Context.Modifiers{suppress_edges_to_module_vertices?: true}
      result = build(call_graph, ir, %Context{from_vertex: :vertex_1, modifiers: modifiers})

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "clause ir, module alias in match does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.Clause{
        match: %IR.AtomType{value: Module5},
        guards: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module6}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module6}
             ]
    end

    test "clause ir, module alias in body creates edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.Clause{
        match: %IR.Variable{name: :x},
        guards: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module5}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module5}
             ]
    end

    test "clause ir, module alias in guards does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.Clause{
        match: %IR.Variable{name: :x},
        guards: [%IR.AtomType{value: Module5}],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module6}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module6}
             ]
    end

    test "function clause ir, module alias in body creates edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}],
          guards: [],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module5}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module1,
               Module5,
               {Module1, :my_fun, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :my_fun, 1}},
               {{Module1, :my_fun, 1}, Module5}
             ]
    end

    test "function clause ir, module alias in guards does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}],
          guards: [%IR.AtomType{value: Module5}],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module6}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module1,
               Module6,
               {Module1, :my_fun, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :my_fun, 1}},
               {{Module1, :my_fun, 1}, Module6}
             ]
    end

    test "function clause ir, module alias in params does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.AtomType{value: Module5}, %IR.Variable{name: :y}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.AtomType{value: Module6}
            ]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module1,
               Module6,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :my_fun, 2}},
               {{Module1, :my_fun, 2}, Module6}
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

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module1,
               Module6,
               Module7,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :my_fun, 2}},
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

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, {Module1, :my_fun, 2}]
      assert sorted_edges(call_graph) == [{Module1, {Module1, :my_fun, 2}}]
    end

    test "function definition ir, __impl__/1 suppresses module vertex edges from body", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :__impl__,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.AtomType{value: :for}],
          guards: [],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module5}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, {Module1, :__impl__, 1}]
      assert sorted_edges(call_graph) == [{Module1, {Module1, :__impl__, 1}}]
    end

    test "function definition ir, __protocol__/1 suppresses module vertex edges from body", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :__protocol__,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.AtomType{value: :functions}],
          guards: [],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module5}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, {Module1, :__protocol__, 1}]
      assert sorted_edges(call_graph) == [{Module1, {Module1, :__protocol__, 1}}]
    end

    test "function definition ir, __struct__/0 suppresses module vertex edges from body", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :__struct__,
        arity: 0,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.MapType{
                data: [
                  {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module5}},
                  {%IR.AtomType{value: :field_1}, %IR.AtomType{value: Module6}}
                ]
              }
            ]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      # Module5 and Module6 should NOT appear as module vertices.
      # {Module5, :__struct__, 0/1} are MFA edges from the __struct__ key-in-map special case.
      assert sorted_vertices(call_graph) == [
               Module1,
               {Module1, :__struct__, 0},
               {Module5, :__struct__, 0},
               {Module5, :__struct__, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :__struct__, 0}},
               {{Module1, :__struct__, 0}, {Module5, :__struct__, 0}},
               {{Module1, :__struct__, 0}, {Module5, :__struct__, 1}}
             ]
    end

    test "function definition ir, __struct__/1 suppresses module vertex edges from body", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :__struct__,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :kv}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.RemoteFunctionCall{
                module: %IR.AtomType{value: Enum},
                function: :reduce,
                args: [
                  %IR.Variable{name: :kv},
                  %IR.TupleType{
                    data: [
                      %IR.MapType{
                        data: [
                          {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module5}},
                          {%IR.AtomType{value: :calendar}, %IR.AtomType{value: Module6}}
                        ]
                      },
                      %IR.ListType{data: []}
                    ]
                  },
                  %IR.AtomType{value: :some_fun}
                ]
              }
            ]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      # Module5 and Module6 should NOT appear as module vertices.
      # {Module5, :__struct__, 0/1} are MFA edges from the __struct__ key-in-map special case,
      # not module vertex edges - they don't cascade.
      assert sorted_vertices(call_graph) == [
               Module1,
               {Enum, :reduce, 3},
               {Module1, :__struct__, 1},
               {Module5, :__struct__, 0},
               {Module5, :__struct__, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :__struct__, 1}},
               {{Module1, :__struct__, 1}, {Enum, :reduce, 3}},
               {{Module1, :__struct__, 1}, {Module5, :__struct__, 0}},
               {{Module1, :__struct__, 1}, {Module5, :__struct__, 1}}
             ]
    end

    test "function definition ir, impl_for/1 suppresses module vertex edges from body", %{
      empty_call_graph: call_graph
    } do
      # credo:disable-for-next-line Credo.Check.Design.DuplicatedCode
      ir = %IR.FunctionDefinition{
        name: :impl_for,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [
            %IR.MapType{
              data: [
                {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x, version: -1}}
              ]
            }
          ],
          guards: [
            %IR.RemoteFunctionCall{
              module: %IR.AtomType{value: :erlang},
              function: :is_atom,
              args: [%IR.Variable{name: :x, version: -1}]
            }
          ],
          body: %IR.Block{
            expressions: [
              %IR.LocalFunctionCall{
                function: :struct_impl_for,
                args: [%IR.Variable{name: :x, version: -1}]
              }
            ]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      # Module atoms are suppressed; struct_impl_for/1 local call and :erlang.is_atom/1
      # guard call are discovered through body traversal (no explicit edges needed).
      assert sorted_vertices(call_graph) == [
               Module1,
               {Module1, :impl_for, 1},
               {Module1, :struct_impl_for, 1},
               {:erlang, :is_atom, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :impl_for, 1}},
               {{Module1, :impl_for, 1}, {Module1, :struct_impl_for, 1}},
               {{Module1, :impl_for, 1}, {:erlang, :is_atom, 1}}
             ]
    end

    test "function definition ir, impl_for!/1 suppresses module vertex edges from body", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :impl_for!,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :data, version: 0}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.Case{
                condition: %IR.LocalFunctionCall{
                  function: :impl_for,
                  args: [%IR.Variable{name: :data, version: 0}]
                },
                clauses: [
                  %IR.Clause{
                    match: %IR.Variable{name: :x, version: 1},
                    guards: [
                      %IR.RemoteFunctionCall{
                        module: %IR.AtomType{value: :erlang},
                        function: :"=:=",
                        args: [
                          %IR.Variable{name: :x, version: 1},
                          %IR.AtomType{value: nil}
                        ]
                      }
                    ],
                    body: %IR.Block{
                      expressions: [
                        %IR.RemoteFunctionCall{
                          module: %IR.AtomType{value: :erlang},
                          function: :error,
                          args: [
                            %IR.RemoteFunctionCall{
                              module: %IR.AtomType{value: Protocol.UndefinedError},
                              function: :exception,
                              args: [
                                %IR.ListType{
                                  data: [
                                    %IR.TupleType{
                                      data: [
                                        %IR.AtomType{value: :protocol},
                                        %IR.AtomType{value: Module5}
                                      ]
                                    }
                                  ]
                                }
                              ]
                            }
                          ]
                        }
                      ]
                    }
                  },
                  %IR.Clause{
                    match: %IR.Variable{name: :x, version: 2},
                    guards: [],
                    body: %IR.Block{
                      expressions: [%IR.Variable{name: :x, version: 2}]
                    }
                  }
                ]
              }
            ]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      # Module5 (protocol module atom in error message) is suppressed; impl_for/1 local
      # call, Protocol.UndefinedError.exception/1, and :erlang MFA edges are discovered
      # through body traversal.
      assert sorted_vertices(call_graph) == [
               Module1,
               {Module1, :impl_for, 1},
               {Module1, :impl_for!, 1},
               {Protocol.UndefinedError, :exception, 1},
               {:erlang, :"=:=", 2},
               {:erlang, :error, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :impl_for!, 1}},
               {{Module1, :impl_for!, 1}, {Module1, :impl_for, 1}},
               {{Module1, :impl_for!, 1}, {Protocol.UndefinedError, :exception, 1}},
               {{Module1, :impl_for!, 1}, {:erlang, :"=:=", 2}},
               {{Module1, :impl_for!, 1}, {:erlang, :error, 1}}
             ]
    end

    test "function definition ir, struct_impl_for/1 suppresses module vertex edges from body", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :struct_impl_for,
        arity: 1,
        visibility: :private,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :struct}],
          guards: [],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module5}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, {Module1, :struct_impl_for, 1}]
      assert sorted_edges(call_graph) == [{Module1, {Module1, :struct_impl_for, 1}}]
    end

    test "function definition ir, Enumerable impl count/1 suppresses module vertex edges from body",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.FunctionDefinition{
        name: :count,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.MatchPlaceholder{}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error},
                  %IR.AtomType{value: Enumerable.Function}
                ]
              }
            ]
          }
        }
      }

      result =
        build(call_graph, ir, %Context{
          from_vertex: Enumerable.Function,
          protocol_impl: Enumerable
        })

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Enumerable.Function,
               {Enumerable.Function, :count, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Enumerable.Function, {Enumerable.Function, :count, 1}}
             ]
    end

    test "function definition ir, Enumerable impl member?/2 suppresses module vertex edges from body",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.FunctionDefinition{
        name: :member?,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.MatchPlaceholder{}, %IR.MatchPlaceholder{}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error},
                  %IR.AtomType{value: Enumerable.Function}
                ]
              }
            ]
          }
        }
      }

      result =
        build(call_graph, ir, %Context{
          from_vertex: Enumerable.Function,
          protocol_impl: Enumerable
        })

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Enumerable.Function,
               {Enumerable.Function, :member?, 2}
             ]

      assert sorted_edges(call_graph) == [
               {Enumerable.Function, {Enumerable.Function, :member?, 2}}
             ]
    end

    test "function definition ir, Enumerable impl slice/1 suppresses module vertex edges from body",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.FunctionDefinition{
        name: :slice,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.MatchPlaceholder{}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error},
                  %IR.AtomType{value: Enumerable.Function}
                ]
              }
            ]
          }
        }
      }

      result =
        build(call_graph, ir, %Context{
          from_vertex: Enumerable.Function,
          protocol_impl: Enumerable
        })

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Enumerable.Function,
               {Enumerable.Function, :slice, 1}
             ]

      assert sorted_edges(call_graph) == [
               {Enumerable.Function, {Enumerable.Function, :slice, 1}}
             ]
    end

    test "function definition ir, non-Enumerable module count/1 traverses clause body normally",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.FunctionDefinition{
        name: :count,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :data}],
          guards: [],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module5}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, {Module1, :count, 1}]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :count, 1}},
               {{Module1, :count, 1}, Module5}
             ]
    end

    test "function definition ir, non-Enumerable module member?/2 traverses clause body normally",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.FunctionDefinition{
        name: :member?,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :data}, %IR.Variable{name: :value}],
          guards: [],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module5}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, {Module1, :member?, 2}]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :member?, 2}},
               {{Module1, :member?, 2}, Module5}
             ]
    end

    test "function definition ir, non-Enumerable module slice/1 traverses clause body normally",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.FunctionDefinition{
        name: :slice,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :data}],
          guards: [],
          body: %IR.Block{
            expressions: [%IR.AtomType{value: Module5}]
          }
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: Module1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, {Module1, :slice, 1}]

      assert sorted_edges(call_graph) == [
               {Module1, {Module1, :slice, 1}},
               {{Module1, :slice, 1}, Module5}
             ]
    end

    test "function definition ir, module atom as call argument makes module functions reachable",
         %{empty_call_graph: call_graph} do
      # Module5 has a function my_fun/1.
      # Module1.caller/0 passes Module5 as a call argument.
      # Module5.my_fun/1 should be reachable from Module1.caller/0
      # through: {Module1, :caller, 0} -> Module5 -> {Module5, :my_fun, 1}
      module_5_ir = %IR.ModuleDefinition{
        module: %IR.AtomType{value: Module5},
        body: %IR.Block{
          expressions: [
            %IR.FunctionDefinition{
              name: :my_fun,
              arity: 1,
              visibility: :public,
              clause: %IR.FunctionClause{
                params: [%IR.Variable{name: :x}],
                guards: [],
                body: %IR.Block{expressions: [%IR.AtomType{value: :ok}]}
              }
            }
          ]
        }
      }

      module_1_ir = %IR.ModuleDefinition{
        module: %IR.AtomType{value: Module1},
        body: %IR.Block{
          expressions: [
            %IR.FunctionDefinition{
              name: :caller,
              arity: 0,
              visibility: :public,
              clause: %IR.FunctionClause{
                params: [],
                guards: [],
                body: %IR.Block{
                  expressions: [
                    %IR.AtomType{value: Module5}
                  ]
                }
              }
            }
          ]
        }
      }

      call_graph
      |> build(module_5_ir, %Context{})
      |> build(module_1_ir, %Context{})

      graph = get_graph(call_graph)
      reachable = reachable_mfas(graph, [{Module1, :caller, 0}])

      assert {Module5, :my_fun, 1} in reachable
    end

    test "list", %{empty_call_graph: call_graph} do
      list = [%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}]
      result = build(call_graph, list, %Context{from_vertex: :vertex_1})

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

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun_1, 4}})

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

      result = build(call_graph, map, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, Module6, Module7, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5},
               {:vertex_1, Module6},
               {:vertex_1, Module7}
             ]
    end

    test "map type ir, __struct__ key value creates edges to __struct__ functions instead of module vertex",
         %{empty_call_graph: call_graph} do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module5}},
          {%IR.AtomType{value: :field_1}, %IR.AtomType{value: Module6}}
        ]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               {Module1, :my_fun, 1},
               {Module5, :__struct__, 0},
               {Module5, :__struct__, 1}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, Module6},
               {{Module1, :my_fun, 1}, {Module5, :__struct__, 0}},
               {{Module1, :my_fun, 1}, {Module5, :__struct__, 1}}
             ]
    end

    test "map type ir, __struct__ key value in pattern context does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module5}},
          {%IR.AtomType{value: :field_1}, %IR.AtomType{value: Module6}}
        ]
      }

      result =
        build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}, pattern?: true})

      assert result == call_graph

      assert sorted_vertices(call_graph) == []
      assert sorted_edges(call_graph) == []
    end

    test "map type ir, __struct__ key value in guard context does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module5}},
          {%IR.AtomType{value: :field_1}, %IR.AtomType{value: Module6}}
        ]
      }

      result =
        build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}, guard?: true})

      assert result == call_graph

      assert sorted_vertices(call_graph) == []
      assert sorted_edges(call_graph) == []
    end

    test "match operator ir, module alias on left side does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.MatchOperator{
        left: %IR.AtomType{value: Module5},
        right: %IR.AtomType{value: Module6}
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module6}
             ]
    end

    test "match operator ir, module alias on right side creates edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.AtomType{value: Module5}
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module5}
             ]
    end

    test "match operator ir, nested, module on innermost right creates edge", %{
      empty_call_graph: call_graph
    } do
      # x = y = Module5
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.MatchOperator{
          left: %IR.Variable{name: :y},
          right: %IR.AtomType{value: Module5}
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module5}
             ]
    end

    test "match operator ir, nested, module on inner left does not create edge",
         %{
           empty_call_graph: call_graph
         } do
      # x = Module5 = y
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.MatchOperator{
          left: %IR.AtomType{value: Module5},
          right: %IR.Variable{name: :y}
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "match operator ir, in pattern context, module on right does not create edge", %{
      empty_call_graph: call_graph
    } do
      # In a function param like: x = Module5
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.AtomType{value: Module5}
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}, pattern?: true})

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "match operator ir, in pattern context, module on left does not create edge", %{
      empty_call_graph: call_graph
    } do
      # In a function param like: Module5 = x
      ir = %IR.MatchOperator{
        left: %IR.AtomType{value: Module5},
        right: %IR.Variable{name: :x}
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}, pattern?: true})

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
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

      result = build(call_graph, ir, %Context{})

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

    test "module definition ir, page module has edges to its functions", %{
      empty_call_graph: call_graph
    } do
      module_2_ir = IR.for_module(Module2)
      result = build(call_graph, module_2_ir, %Context{})

      assert result == call_graph

      assert has_vertex?(call_graph, {Module2, :__params__, 0})
      assert has_vertex?(call_graph, {Module2, :__route__, 0})

      assert has_edge?(call_graph, Module2, {Module2, :__params__, 0})
      assert has_edge?(call_graph, Module2, {Module2, :__route__, 0})
    end

    test "module definition ir, component module has edges to its functions", %{
      empty_call_graph: call_graph
    } do
      module_38_ir = IR.for_module(Module38)
      result = build(call_graph, module_38_ir, %Context{})

      assert result == call_graph

      assert has_vertex?(call_graph, {Module38, :action, 3})
      assert has_vertex?(call_graph, {Module38, :init, 2})
      assert has_vertex?(call_graph, {Module38, :template, 0})

      assert has_edge?(call_graph, Module38, {Module38, :action, 3})
      assert has_edge?(call_graph, Module38, {Module38, :init, 2})
      assert has_edge?(call_graph, Module38, {Module38, :template, 0})
    end

    test "module definition ir, struct module adds struct-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_25_ir = IR.for_module(Module25)
      result = build(call_graph, module_25_ir, %Context{})

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
      result = build(call_graph, module_21_ir, %Context{})

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
      result = build(call_graph, string_chars_ir, %Context{})

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

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun_1, 4}})

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

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun_1, 4}})

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

    test "remote function call ir, :erlang.error/3 suppresses module vertex edges in third argument (error options)",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :error,
        args: [
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: Enum.EmptyError},
            function: :exception,
            args: [%IR.ListType{data: []}]
          },
          %IR.AtomType{value: :none},
          %IR.ListType{
            data: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error_info},
                  %IR.MapType{
                    data: [
                      {%IR.AtomType{value: :module}, %IR.AtomType{value: Exception}}
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Enum.EmptyError, :exception, 1},
               {Module1, :my_fun, 1},
               {:erlang, :error, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, {Enum.EmptyError, :exception, 1}},
               {{Module1, :my_fun, 1}, {:erlang, :error, 3}}
             ]
    end

    test "remote function call ir, IO.warn_once/3 skips first argument (deduplication key)", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: IO},
        function: :warn_once,
        args: [
          %IR.TupleType{
            data: [
              %IR.AtomType{value: Module5},
              %IR.AtomType{value: :some_key}
            ]
          },
          %IR.AnonymousFunctionType{
            arity: 0,
            captured_function: nil,
            captured_module: nil,
            clauses: [
              %IR.FunctionClause{
                params: [],
                guards: [],
                body: %IR.Block{
                  expressions: [%IR.StringType{value: "some warning"}]
                }
              }
            ]
          },
          %IR.IntegerType{value: 4}
        ]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun, 1},
               {IO, :warn_once, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, {IO, :warn_once, 3}}
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

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun_1, 4}})

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

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun_1, 4}})

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

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun_1, 4}})

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

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun_1, 4}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO}
             ]
    end

    test "remote function call ir, Kernel.inspect/1 suppresses module vertex edges in first argument",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Kernel},
        function: :inspect,
        args: [%IR.AtomType{value: Module5}]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      # Module5 atom is suppressed; only the MFA edge to Kernel.inspect/1 is created.
      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun, 1},
               {Kernel, :inspect, 1}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, {Kernel, :inspect, 1}}
             ]
    end

    test "remote function call ir, Kernel.inspect/2 traverses second argument (options) normally",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Kernel},
        function: :inspect,
        args: [
          %IR.AtomType{value: Module5},
          %IR.RemoteFunctionCall{
            module: %IR.AtomType{value: Module6},
            function: :opts,
            args: []
          }
        ]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      # Module5 atom is suppressed, but Module6.opts/0 MFA edge is created.
      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun, 1},
               {Module6, :opts, 0},
               {Kernel, :inspect, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, {Module6, :opts, 0}},
               {{Module1, :my_fun, 1}, {Kernel, :inspect, 2}}
             ]
    end

    test "remote function call ir, Kernel.struct!/2 with literal module creates targeted __struct__ edges",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Kernel},
        function: :struct!,
        args: [
          %IR.AtomType{value: Module5},
          %IR.Variable{name: :args}
        ]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun, 1},
               {Module5, :__struct__, 0},
               {Module5, :__struct__, 1},
               {Kernel, :struct!, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, {Module5, :__struct__, 0}},
               {{Module1, :my_fun, 1}, {Module5, :__struct__, 1}},
               {{Module1, :my_fun, 1}, {Kernel, :struct!, 2}}
             ]
    end

    test "remote function call ir, Kernel.struct!/2 with variable module traverses normally",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Kernel},
        function: :struct!,
        args: [
          %IR.Variable{name: :module},
          %IR.Variable{name: :args}
        ]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun, 1},
               {Kernel, :struct!, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, {Kernel, :struct!, 2}}
             ]
    end

    test "remote function call ir, Protocol.UndefinedError.exception/1 suppresses module vertex edges in :protocol key value",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Protocol.UndefinedError},
        function: :exception,
        args: [
          %IR.ListType{
            data: [
              %IR.TupleType{
                data: [%IR.AtomType{value: :protocol}, %IR.AtomType{value: Module5}]
              },
              %IR.TupleType{
                data: [%IR.AtomType{value: :value}, %IR.AtomType{value: :some_value}]
              }
            ]
          }
        ]
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 1}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun, 1},
               {Protocol.UndefinedError, :exception, 1}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 1}, {Protocol.UndefinedError, :exception, 1}}
             ]
    end

    test "try catch clause ir, module alias in body creates edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.TryCatchClause{
        kind: %IR.AtomType{value: :error},
        value: %IR.Variable{name: :e},
        guards: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module5}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module5}
             ]
    end

    test "try catch clause ir, module alias in guards does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.TryCatchClause{
        kind: %IR.AtomType{value: :error},
        value: %IR.Variable{name: :e},
        guards: [%IR.AtomType{value: Module5}],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module6}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module6}
             ]
    end

    test "try catch clause ir, module alias in value does not create edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.TryCatchClause{
        kind: %IR.AtomType{value: :error},
        value: %IR.AtomType{value: Module5},
        guards: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module6}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module6}
             ]
    end

    test "try rescue clause ir, module alias in modules does not create module vertex edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.TryRescueClause{
        variable: %IR.Variable{name: :e},
        modules: [%IR.AtomType{value: Module5}],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module6}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module6}
             ]
    end

    test "try rescue clause ir, module alias in body creates edge", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.TryRescueClause{
        variable: %IR.Variable{name: :e},
        modules: [],
        body: %IR.Block{
          expressions: [%IR.AtomType{value: Module5}]
        }
      }

      result = build(call_graph, ir, %Context{from_vertex: {Module1, :my_fun, 2}})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module5}
             ]
    end

    test "tuple", %{empty_call_graph: call_graph} do
      tuple = {%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}}
      result = build(call_graph, tuple, %Context{from_vertex: :vertex_1})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5}
             ]
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
             Module6
           ]

    assert sorted_edges(call_graph) == [
             {Module11, Module5},
             {Module11, Module6}
           ]
  end

  test "clone/1", %{full_call_graph: call_graph} do
    assert %CallGraph{} = call_graph_clone = clone(call_graph)

    refute call_graph_clone == call_graph
    assert get_graph(call_graph_clone) == get_graph(call_graph)
  end

  describe "compute_cascades/3" do
    # :module_1 (module vertex) - large cascade
    # ├─ {:module_5, :fun_5a, 1} -> :module_1
    # ├─ {:module_6, :fun_6a, 2} -> :module_1
    # │  :module_1 -> {:module_7, :fun_7a, 1}
    # │  :module_1 -> {:module_7, :fun_7b, 1}
    # │  :module_1 -> {:module_8, :fun_8a, 2}
    # │  :module_1 -> {:module_8, :fun_8b, 1}
    # │  :module_1 -> {:module_9, :fun_9a, 1}
    #
    # :module_2 (module vertex) - medium cascade
    # ├─ {:module_6, :fun_6b, 3} -> :module_2
    # │  :module_2 -> {:module_10, :fun_10a, 1}
    # │  :module_2 -> {:module_10, :fun_10b, 2}
    # │  :module_2 -> {:module_11, :fun_11a, 1}
    #
    # :module_3 (module vertex) - small cascade, multiple incoming edges
    # ├─ {:module_5, :fun_5b, 1} -> :module_3
    # ├─ {:module_6, :fun_6a, 2} -> :module_3
    # ├─ {:module_9, :fun_9a, 1} -> :module_3
    # │  :module_3 -> {:module_11, :fun_11b, 1}
    #
    # :module_4 (module vertex) - leaf, no downstream MFAs
    # ├─ {:module_8, :fun_8a, 2} -> :module_4

    setup do
      graph =
        Digraph.new()
        # Edges into :module_1
        |> Digraph.add_edge({:module_5, :fun_5a, 1}, :module_1)
        |> Digraph.add_edge({:module_6, :fun_6a, 2}, :module_1)
        # :module_1 downstream MFAs
        |> Digraph.add_edge(:module_1, {:module_7, :fun_7a, 1})
        |> Digraph.add_edge(:module_1, {:module_7, :fun_7b, 1})
        |> Digraph.add_edge(:module_1, {:module_8, :fun_8a, 2})
        |> Digraph.add_edge(:module_1, {:module_8, :fun_8b, 1})
        |> Digraph.add_edge(:module_1, {:module_9, :fun_9a, 1})
        # Edges into :module_2
        |> Digraph.add_edge({:module_6, :fun_6b, 3}, :module_2)
        # :module_2 downstream MFAs
        |> Digraph.add_edge(:module_2, {:module_10, :fun_10a, 1})
        |> Digraph.add_edge(:module_2, {:module_10, :fun_10b, 2})
        |> Digraph.add_edge(:module_2, {:module_11, :fun_11a, 1})
        # Edges into :module_3
        |> Digraph.add_edge({:module_5, :fun_5b, 1}, :module_3)
        |> Digraph.add_edge({:module_6, :fun_6a, 2}, :module_3)
        |> Digraph.add_edge({:module_9, :fun_9a, 1}, :module_3)
        # :module_3 downstream MFAs
        |> Digraph.add_edge(:module_3, {:module_11, :fun_11b, 1})
        # Edges into :module_4
        |> Digraph.add_edge({:module_8, :fun_8a, 2}, :module_4)

      reachable =
        MapSet.new([
          :module_1,
          :module_2,
          :module_3,
          :module_4,
          {:module_5, :fun_5a, 1},
          {:module_5, :fun_5b, 1},
          {:module_6, :fun_6a, 2},
          {:module_6, :fun_6b, 3},
          {:module_7, :fun_7a, 1},
          {:module_7, :fun_7b, 1},
          {:module_8, :fun_8a, 2},
          {:module_8, :fun_8b, 1},
          {:module_9, :fun_9a, 1},
          {:module_10, :fun_10a, 1},
          {:module_10, :fun_10b, 2},
          {:module_11, :fun_11a, 1},
          {:module_11, :fun_11b, 1}
        ])

      module_vertices = MapSet.new([:module_1, :module_2, :module_3, :module_4])

      [graph: graph, module_vertices: module_vertices, reachable: reachable]
    end

    test "returns cascades sorted by downstream MFA count descending", %{
      graph: graph,
      module_vertices: module_vertices,
      reachable: reachable
    } do
      result = compute_cascades(graph, module_vertices, reachable)

      assert result == [
               {{:module_5, :fun_5a, 1}, :module_1, 6},
               {{:module_6, :fun_6a, 2}, :module_1, 6},
               {{:module_6, :fun_6b, 3}, :module_2, 3},
               {{:module_5, :fun_5b, 1}, :module_3, 1},
               {{:module_6, :fun_6a, 2}, :module_3, 1},
               {{:module_9, :fun_9a, 1}, :module_3, 1},
               {{:module_8, :fun_8a, 2}, :module_4, 0}
             ]
    end

    test "filters out sources not in reachable set", %{
      graph: graph,
      module_vertices: module_vertices,
      reachable: reachable
    } do
      restricted_reachable =
        reachable
        |> MapSet.delete({:module_6, :fun_6a, 2})
        |> MapSet.delete({:module_9, :fun_9a, 1})

      result = compute_cascades(graph, module_vertices, restricted_reachable)

      sources = Enum.map(result, &elem(&1, 0))

      refute {:module_6, :fun_6a, 2} in sources
      refute {:module_9, :fun_9a, 1} in sources
      assert {:module_5, :fun_5a, 1} in sources
    end

    test "returns empty list when no module vertices", %{graph: graph, reachable: reachable} do
      assert compute_cascades(graph, MapSet.new(), reachable) == []
    end
  end

  describe "compute_sinks/3" do
    # Graph:
    # {Module1, :fun_1a, 0} -> {:erlang, :hd, 1}       (sink A)
    # {Module1, :fun_1a, 0} -> {Module2, :fun_2a, 1}
    # {Module2, :fun_2a, 1} -> {:erlang, :hd, 1}       (sink A)
    # {Module3, :fun_3a, 0} -> {:erlang, :tl, 1}       (sink B)
    # {Module3, :fun_3a, 0} -> {:erlang, :hd, 1}       (sink A)

    setup do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module1, :fun_1a, 0}, {:erlang, :hd, 1})
        |> Digraph.add_edge({Module1, :fun_1a, 0}, {Module2, :fun_2a, 1})
        |> Digraph.add_edge({Module2, :fun_2a, 1}, {:erlang, :hd, 1})
        |> Digraph.add_edge({Module3, :fun_3a, 0}, {:erlang, :tl, 1})
        |> Digraph.add_edge({Module3, :fun_3a, 0}, {:erlang, :hd, 1})

      reachable =
        MapSet.new([
          {Module1, :fun_1a, 0},
          {Module2, :fun_2a, 1},
          {Module3, :fun_3a, 0},
          {:erlang, :hd, 1},
          {:erlang, :tl, 1}
        ])

      erlang_mfas = [{:erlang, :hd, 1}, {:erlang, :tl, 1}]

      [graph: graph, erlang_mfas: erlang_mfas, reachable: reachable]
    end

    test "returns sinks sorted by reaching count descending", %{
      graph: graph,
      erlang_mfas: erlang_mfas,
      reachable: reachable
    } do
      result = CallGraph.compute_sinks(graph, erlang_mfas, reachable)

      assert result == [
               {{:erlang, :hd, 1}, 4},
               {{:erlang, :tl, 1}, 2}
             ]
    end

    test "only counts MFAs in the reachable set", %{
      graph: graph,
      erlang_mfas: erlang_mfas,
      reachable: reachable
    } do
      restricted_reachable = MapSet.delete(reachable, {Module1, :fun_1a, 0})
      result = CallGraph.compute_sinks(graph, erlang_mfas, restricted_reachable)

      assert result == [
               {{:erlang, :hd, 1}, 3},
               {{:erlang, :tl, 1}, 2}
             ]
    end

    test "returns empty list when no erlang MFAs given", %{graph: graph, reachable: reachable} do
      assert CallGraph.compute_sinks(graph, [], reachable) == []
    end
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
        |> build(module_14_ir, %Context{})
        |> build(module_15_ir, %Context{})
        |> build(module_16_ir, %Context{})
        |> remove_server_only_mfas!()
        |> list_page_mfas(Module14)

      assert result == [
               {Enum, :reverse, 1},
               {Enum, :to_list, 1},
               {Module14, :__is_hologram_page__, 0},
               {Module14, :__layout_module__, 0},
               {Module14, :__layout_props__, 0},
               {Module14, :__params__, 0},
               {Module14, :__route__, 0},
               {Module14, :action, 3},
               {Module14, :template, 0},
               {Module15, :__is_hologram_component__, 0},
               {Module15, :__props__, 0},
               {Module15, :template, 0},
               {Module16, :my_fun_16a, 2},
               {Kernel, :inspect, 1},
               {:erlang, :hd, 1}
             ]
    end

    test "excludes server-only and other-page MFAs" do
      module_42_ir = IR.for_module(Module42)
      module_43_ir = IR.for_module(Module43)
      module_44_ir = IR.for_module(Module44)

      result =
        start()
        |> build(module_42_ir, %Context{})
        |> build(module_43_ir, %Context{})
        |> build(module_44_ir, %Context{})
        |> remove_server_only_mfas!()
        |> list_page_mfas(Module42)

      # Server-only MFA is excluded
      refute {Module42, :command, 3} in result

      # Other page's MFA is excluded
      refute {Module44, :action, 3} in result
    end

    test "excludes Hex MFAs" do
      module_17_ir = IR.for_module(Module17)

      call_graph =
        start()
        |> build(module_17_ir, %Context{})
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
        |> build(module_17_ir, %Context{})
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
        |> build(module_17_ir, %Context{})
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
    |> build(ir, %Context{})
    |> add_vertex(:module_4)

    assert module_vertices(call_graph, Module13) == [
             Module13,
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
        |> build(module_9_ir, %Context{})
        |> build(module_10_ir, %Context{})

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
      |> build(impl_ir, %Context{})

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
               Module10,
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
               {Module10, {Module10, :my_fun_3, 0}},
               {Module10, {Module10, :my_fun_4, 0}},
               {Module9, {Module9, :my_fun_1, 0}},
               {Module9, {Module9, :my_fun_2, 0}},
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

  describe "remove_other_pages_mfas/2" do
    test "removes other page functions except __params__/0 and __route__/0", %{
      empty_call_graph: empty_call_graph
    } do
      module_14_ir = IR.for_module(Module14)
      module_17_ir = IR.for_module(Module17)

      graph =
        empty_call_graph
        |> build(module_14_ir, %Context{})
        |> build(module_17_ir, %Context{})
        |> get_graph()
        |> remove_other_pages_mfas(Module14)

      vertices = Digraph.vertices(graph)

      assert {Module14, :action, 3} in vertices
      assert {Module14, :template, 0} in vertices

      assert {Module17, :__params__, 0} in vertices
      assert {Module17, :__route__, 0} in vertices

      refute {Module17, :action, 3} in vertices
      refute {Module17, :template, 0} in vertices
    end
  end

  describe "remove_other_pages_mfas!/2" do
    test "mutates the call graph", %{empty_call_graph: empty_call_graph} do
      module_14_ir = IR.for_module(Module14)
      module_17_ir = IR.for_module(Module17)

      result =
        empty_call_graph
        |> build(module_14_ir, %Context{})
        |> build(module_17_ir, %Context{})
        |> remove_other_pages_mfas!(Module14)

      assert has_vertex?(result, {Module14, :action, 3})
      refute has_vertex?(result, {Module17, :action, 3})
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

  describe "remove_server_only_mfas!/1" do
    test "removes command/3 for templatable modules", %{empty_call_graph: empty_call_graph} do
      module_42_ir = IR.for_module(Module42)
      module_43_ir = IR.for_module(Module43)

      result =
        empty_call_graph
        |> build(module_42_ir, %Context{})
        |> build(module_43_ir, %Context{})
        |> remove_server_only_mfas!()

      refute has_vertex?(result, {Module42, :command, 3})
      refute has_vertex?(result, {Module43, :command, 3})
    end

    test "removes init/3 for templatable modules", %{empty_call_graph: empty_call_graph} do
      module_44_ir = IR.for_module(Module44)
      module_45_ir = IR.for_module(Module45)

      result =
        empty_call_graph
        |> build(module_44_ir, %Context{})
        |> build(module_45_ir, %Context{})
        |> remove_server_only_mfas!()

      refute has_vertex?(result, {Module44, :init, 3})
      refute has_vertex?(result, {Module45, :init, 3})
    end

    test "keeps command/3 for non-templatable modules", %{empty_call_graph: empty_call_graph} do
      module_42_ir = IR.for_module(Module42)
      module_43_ir = IR.for_module(Module43)

      result =
        empty_call_graph
        |> build(module_42_ir, %Context{})
        |> build(module_43_ir, %Context{})
        |> add_edge({Module42, :action, 3}, {Module16, :command, 3})
        |> remove_server_only_mfas!()

      assert has_vertex?(result, {Module16, :command, 3})
    end

    test "keeps init/3 for non-templatable modules", %{empty_call_graph: empty_call_graph} do
      module_46_ir = IR.for_module(Module46)
      module_47_ir = IR.for_module(Module47)

      result =
        empty_call_graph
        |> build(module_46_ir, %Context{})
        |> build(module_47_ir, %Context{})
        |> remove_server_only_mfas!()

      assert has_vertex?(result, {Module46, :init, 3})
    end

    test "removes server-only Erlang MFA sinks and their transitive callers", %{
      empty_call_graph: call_graph
    } do
      sink = {:file, :make_symlink, 2}

      result =
        call_graph
        |> add_edge({Module14, :fun_14a, 3}, {Module16, :fun_16a, 1})
        |> add_edge({Module16, :fun_16a, 1}, sink)
        |> remove_server_only_mfas!()

      refute has_vertex?(result, sink)
      refute has_vertex?(result, {Module16, :fun_16a, 1})
      refute has_vertex?(result, {Module14, :fun_14a, 3})
    end

    test "keeps vertices that don't call any sink even if their only caller was removed", %{
      empty_call_graph: call_graph
    } do
      sink = {:file, :make_symlink, 2}

      result =
        call_graph
        |> add_edge({Module14, :fun_14a, 3}, {Module16, :fun_16a, 1})
        |> add_edge({Module16, :fun_16a, 1}, sink)
        |> add_edge({Module14, :fun_14a, 3}, {Module16, :fun_16b, 0})
        |> remove_server_only_mfas!()

      assert has_vertex?(result, {Module16, :fun_16b, 0})
    end

    test "stops at protocol dispatch boundary without removing the protocol function or its callers",
         %{
           empty_call_graph: call_graph
         } do
      sink = {:file, :make_symlink, 2}

      result =
        call_graph
        |> add_edge({Module14, :fun_14a, 3}, {Enumerable, :reduce, 3})
        |> add_edge({Enumerable, :reduce, 3}, {Enumerable.MyStruct, :reduce, 3})
        |> add_edge({Enumerable, :reduce, 3}, {Enumerable.OtherStruct, :reduce, 3})
        |> add_edge({Enumerable.MyStruct, :reduce, 3}, sink)
        |> remove_server_only_mfas!()

      refute has_vertex?(result, sink)
      refute has_vertex?(result, {Enumerable.MyStruct, :reduce, 3})

      assert has_vertex?(result, {Enumerable, :reduce, 3})
      assert has_vertex?(result, {Module14, :fun_14a, 3})
      assert has_vertex?(result, {Enumerable.OtherStruct, :reduce, 3})
    end

    test "keeps all vertices when no server-only MFAs are present", %{
      empty_call_graph: call_graph
    } do
      result =
        call_graph
        |> add_edge({Module14, :fun_14a, 3}, {Module16, :fun_16a, 1})
        |> remove_server_only_mfas!()

      assert has_vertex?(result, {Module14, :fun_14a, 3})
      assert has_vertex?(result, {Module16, :fun_16a, 1})
    end
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

  # Consistency tests verifying that Elixir stdlib IR patterns assumed by call graph
  # build/3 special cases still hold. If these fail after an Elixir upgrade,
  # the corresponding special cases in CallGraph.build/3 need updating.
  describe "Elixir stdlib IR pattern assumptions" do
    defp find_fun_defs(ir_plt, module, name, arity) do
      %IR.ModuleDefinition{body: %IR.Block{expressions: expressions}} =
        PLT.get!(ir_plt, module)

      Enum.filter(expressions, &match?(%IR.FunctionDefinition{name: ^name, arity: ^arity}, &1))
    end

    # Original source:
    #   defimpl Protocol1, for: Integer do
    #     def my_fun(_data), do: :ok
    #   end
    #
    # Expanded (Elixir >= 1.16):
    #   def __impl__(:for), do: Integer
    #   def __impl__(:protocol), do: Protocol1
    #
    # Expanded (Elixir < 1.16):
    #   def __impl__(:for), do: Integer
    #   def __impl__(:protocol), do: Protocol1
    #   def __impl__(:target), do: Protocol1.Integer
    test "__impl__/1 clauses have 'for' and 'protocol' module atoms in body",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1.Integer, :__impl__, 1)

      {for_clause, protocol_clause} =
        if Version.match?(System.version(), ">= 1.16.0") do
          assert [for_clause, protocol_clause] = fun_defs
          {for_clause, protocol_clause}
        else
          assert [target_clause, for_clause, protocol_clause] = fun_defs

          assert target_clause == %IR.FunctionDefinition{
                   name: :__impl__,
                   arity: 1,
                   visibility: :public,
                   clause: %IR.FunctionClause{
                     params: [%IR.AtomType{value: :target}],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.AtomType{value: Protocol1.Integer}]
                     }
                   }
                 }

          {for_clause, protocol_clause}
        end

      assert for_clause == %IR.FunctionDefinition{
               name: :__impl__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :for}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: Integer}]
                 }
               }
             }

      assert protocol_clause == %IR.FunctionDefinition{
               name: :__impl__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :protocol}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: Protocol1}]
                 }
               }
             }
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (after consolidation):
    #   def __protocol__(:module), do: Protocol1
    #   def __protocol__(:functions), do: [my_fun: 1]
    #   def __protocol__(:consolidated?), do: true
    #   def __protocol__(:impls), do: {:consolidated, [Struct1, Integer]}
    test "__protocol__/1 clauses have module atoms in body (protocol module and implementations)",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1, :__protocol__, 1)

      assert [module_clause, functions_clause, consolidated_clause, impls_clause] = fun_defs

      assert module_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :module}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: Protocol1}]
                 }
               }
             }

      assert functions_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :functions}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.ListType{
                       data: [
                         %IR.TupleType{
                           data: [
                             %IR.AtomType{value: :my_fun},
                             %IR.IntegerType{value: 1}
                           ]
                         }
                       ]
                     }
                   ]
                 }
               }
             }

      assert consolidated_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :consolidated?}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: true}]
                 }
               }
             }

      assert impls_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :impls}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :consolidated},
                         %IR.ListType{
                           data: [
                             %IR.AtomType{value: Struct1},
                             %IR.AtomType{value: Integer}
                           ]
                         }
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source:
    #   defmodule Struct1 do
    #     defstruct [:field_1]
    #   end
    #
    # Expanded:
    #   def __struct__(), do: %{__struct__: Struct1, field_1: nil}
    test "__struct__/0 body has a map with __struct__ key containing the module atom",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Struct1, :__struct__, 0)

      assert clause == %IR.FunctionDefinition{
               name: :__struct__,
               arity: 0,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Struct1}},
                         {%IR.AtomType{value: :field_1}, %IR.AtomType{value: nil}}
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source (Struct2):
    #   defstruct field_1: nil, field_2: Module1
    #
    # Generated __struct__/0:
    #   def __struct__(), do: %{__struct__: Struct2, field_1: nil, field_2: Module1}
    test "__struct__/0 body map values include module atoms when given as field defaults",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Struct2, :__struct__, 0)

      assert clause == %IR.FunctionDefinition{
               name: :__struct__,
               arity: 0,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Struct2}},
                         {%IR.AtomType{value: :field_1}, %IR.AtomType{value: nil}},
                         {%IR.AtomType{value: :field_2}, %IR.AtomType{value: Module1}}
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source (Struct2):
    #   defstruct field_1: nil, field_2: Module1
    #
    # Generated __struct__/1:
    #   def __struct__(kv) do
    #     Enum.reduce(kv,
    #       %{__struct__: Struct2, field_1: nil, field_2: Module1},
    #       fn {key, val}, map -> Map.merge(map, %{key => val}) end)
    #   end
    test "__struct__/1 body has Enum.reduce/3 with default struct map containing module atoms",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Struct2, :__struct__, 1)

      assert clause == %IR.FunctionDefinition{
               name: :__struct__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :kv, version: 0}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: Enum},
                       function: :reduce,
                       args: [
                         %IR.Variable{name: :kv, version: 0},
                         %IR.MapType{
                           data: [
                             {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Struct2}},
                             {%IR.AtomType{value: :field_1}, %IR.AtomType{value: nil}},
                             {%IR.AtomType{value: :field_2}, %IR.AtomType{value: Module1}}
                           ]
                         },
                         %IR.AnonymousFunctionType{
                           arity: 2,
                           captured_function: nil,
                           captured_module: nil,
                           clauses: [
                             %IR.FunctionClause{
                               params: [
                                 %IR.TupleType{
                                   data: [
                                     %IR.Variable{name: :key, version: 1},
                                     %IR.Variable{name: :val, version: 2}
                                   ]
                                 },
                                 %IR.Variable{name: :map, version: 3}
                               ],
                               guards: [],
                               body: %IR.Block{
                                 expressions: [
                                   %IR.RemoteFunctionCall{
                                     module: %IR.AtomType{value: Map},
                                     function: :merge,
                                     args: [
                                       %IR.Variable{name: :map, version: 3},
                                       %IR.MapType{
                                         data: [
                                           {%IR.Variable{name: :key, version: 1},
                                            %IR.Variable{name: :val, version: 2}}
                                         ]
                                       }
                                     ]
                                   }
                                 ]
                               }
                             }
                           ]
                         }
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source (Module41Error):
    #   defexception message: "test error"
    #
    # Generated exception/1 (Elixir >= 1.18):
    #   def exception(msg) when is_binary(msg), do: exception(message: msg)
    #   def exception(args) when is_list(args), do: Kernel.struct!(Module41Error, args)
    #
    # Generated exception/1 (Elixir < 1.18):
    #   def exception(msg) when is_binary(msg), do: exception(message: msg)
    #   def exception(args) when is_list(args) do
    #     struct = __struct__()
    #     {valid, invalid} = Enum.split_with(args, fn {k, _} -> :maps.is_key(k, struct) end)
    #     case invalid do
    #       [] -> :ok
    #       _ -> IO.warn("the following fields are unknown when raising " <>
    #              inspect(Module41Error) <> ": " <> inspect(invalid) <> ". " <>
    #              "Please make sure to only give known fields when raising " <>
    #              "or redefine " <> inspect(Module41Error) <> ".exception/1 to " <>
    #              "discard unknown fields. Future Elixir versions will raise on " <>
    #              "unknown fields given to raise/2")
    #     end
    #     Kernel.struct!(struct, valid)
    #   end
    test "defexception exception/1 calls Kernel.struct!/2 with literal module atom",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Module41Error, :exception, 1)

      if Version.match?(System.version(), ">= 1.18.0") do
        assert [msg_clause, args_clause] = fun_defs

        # credo:disable-for-next-line Credo.Check.Design.DuplicatedCode
        assert msg_clause == %IR.FunctionDefinition{
                 name: :exception,
                 arity: 1,
                 visibility: :public,
                 clause: %IR.FunctionClause{
                   params: [%IR.Variable{name: :msg, version: 0}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_binary,
                       args: [%IR.Variable{name: :msg, version: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :exception,
                         args: [
                           %IR.ListType{
                             data: [
                               %IR.TupleType{
                                 data: [
                                   %IR.AtomType{value: :message},
                                   %IR.Variable{name: :msg, version: 0}
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     ]
                   }
                 }
               }

        assert args_clause == %IR.FunctionDefinition{
                 name: :exception,
                 arity: 1,
                 visibility: :public,
                 clause: %IR.FunctionClause{
                   params: [%IR.Variable{name: :args, version: 0}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_list,
                       args: [%IR.Variable{name: :args, version: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Kernel},
                         function: :struct!,
                         args: [
                           %IR.AtomType{value: Module41Error},
                           %IR.Variable{name: :args, version: 0}
                         ]
                       }
                     ]
                   }
                 }
               }
      else
        # Elixir < 1.18: Kernel.struct!/2 is called with a variable (not a literal module
        # atom) - so the Kernel.struct!/2 special case in CallGraph.build/3 won't fire
        # (safe - missed optimization only).
        assert [msg_clause, args_clause] = fun_defs

        # credo:disable-for-next-line Credo.Check.Design.DuplicatedCode
        assert msg_clause == %IR.FunctionDefinition{
                 name: :exception,
                 arity: 1,
                 visibility: :public,
                 clause: %IR.FunctionClause{
                   params: [%IR.Variable{name: :msg, version: 0}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_binary,
                       args: [%IR.Variable{name: :msg, version: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.LocalFunctionCall{
                         function: :exception,
                         args: [
                           %IR.ListType{
                             data: [
                               %IR.TupleType{
                                 data: [
                                   %IR.AtomType{value: :message},
                                   %IR.Variable{name: :msg, version: 0}
                                 ]
                               }
                             ]
                           }
                         ]
                       }
                     ]
                   }
                 }
               }

        assert args_clause == %IR.FunctionDefinition{
                 name: :exception,
                 arity: 1,
                 visibility: :public,
                 clause: %IR.FunctionClause{
                   params: [%IR.Variable{name: :args, version: 0}],
                   guards: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :is_list,
                       args: [%IR.Variable{name: :args, version: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.MatchOperator{
                         left: %IR.Variable{name: :struct, version: 1},
                         right: %IR.LocalFunctionCall{function: :__struct__, args: []}
                       },
                       %IR.MatchOperator{
                         left: %IR.TupleType{
                           data: [
                             %IR.Variable{name: :valid, version: 3},
                             %IR.Variable{name: :invalid, version: 4}
                           ]
                         },
                         right: %IR.RemoteFunctionCall{
                           module: %IR.AtomType{value: Enum},
                           function: :split_with,
                           args: [
                             %IR.Variable{name: :args, version: 0},
                             %IR.AnonymousFunctionType{
                               arity: 1,
                               captured_function: nil,
                               captured_module: nil,
                               clauses: [
                                 %IR.FunctionClause{
                                   params: [
                                     %IR.TupleType{
                                       data: [
                                         %IR.Variable{name: :k, version: 2},
                                         %IR.MatchPlaceholder{}
                                       ]
                                     }
                                   ],
                                   guards: [],
                                   body: %IR.Block{
                                     expressions: [
                                       %IR.RemoteFunctionCall{
                                         module: %IR.AtomType{value: :maps},
                                         function: :is_key,
                                         args: [
                                           %IR.Variable{name: :k, version: 2},
                                           %IR.Variable{name: :struct, version: 1}
                                         ]
                                       }
                                     ]
                                   }
                                 }
                               ]
                             }
                           ]
                         }
                       },
                       %IR.Case{
                         condition: %IR.Variable{name: :invalid, version: 4},
                         clauses: [
                           %IR.Clause{
                             match: %IR.ListType{data: []},
                             guards: [],
                             body: %IR.Block{
                               expressions: [%IR.AtomType{value: :ok}]
                             }
                           },
                           %IR.Clause{
                             match: %IR.MatchPlaceholder{},
                             guards: [],
                             body: %IR.Block{
                               expressions: [
                                 %IR.RemoteFunctionCall{
                                   module: %IR.AtomType{value: IO},
                                   function: :warn,
                                   args: [
                                     %IR.BitstringType{
                                       segments: [
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{
                                             value:
                                               "the following fields are unknown when raising "
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.RemoteFunctionCall{
                                             module: %IR.AtomType{value: Kernel},
                                             function: :inspect,
                                             args: [%IR.AtomType{value: Module41Error}]
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{value: ": "},
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.RemoteFunctionCall{
                                             module: %IR.AtomType{value: Kernel},
                                             function: :inspect,
                                             args: [
                                               %IR.Variable{name: :invalid, version: 4}
                                             ]
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{value: ". "},
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{
                                             value:
                                               "Please make sure to only give known fields when raising "
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{
                                             value: "or redefine "
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.RemoteFunctionCall{
                                             module: %IR.AtomType{value: Kernel},
                                             function: :inspect,
                                             args: [%IR.AtomType{value: Module41Error}]
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{
                                             value: ".exception/1 to "
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{
                                             value:
                                               "discard unknown fields. Future Elixir versions will raise on "
                                           },
                                           modifiers: [type: :binary]
                                         },
                                         %IR.BitstringSegment{
                                           value: %IR.StringType{
                                             value: "unknown fields given to raise/2"
                                           },
                                           modifiers: [type: :binary]
                                         }
                                       ]
                                     }
                                   ]
                                 }
                               ]
                             }
                           }
                         ]
                       },
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: Kernel},
                         function: :struct!,
                         args: [
                           %IR.Variable{name: :struct, version: 1},
                           %IR.Variable{name: :valid, version: 3}
                         ]
                       }
                     ]
                   }
                 }
               }
      end
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (after consolidation):
    #   def impl_for(%{__struct__: x}) when is_atom(x), do: struct_impl_for(x)
    #   def impl_for(x) when is_integer(x), do: Protocol1.Integer
    #   def impl_for(_), do: nil
    test "impl_for/1 clauses have module atoms in body and struct dispatch calls struct_impl_for/1",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1, :impl_for, 1)

      assert [struct_clause, integer_clause, catch_all_clause] = fun_defs

      # credo:disable-for-next-line Credo.Check.Design.DuplicatedCode
      assert struct_clause == %IR.FunctionDefinition{
               name: :impl_for,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x, version: -1}}
                     ]
                   }
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_atom,
                     args: [%IR.Variable{name: :x, version: -1}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.LocalFunctionCall{
                       function: :struct_impl_for,
                       args: [%IR.Variable{name: :x, version: -1}]
                     }
                   ]
                 }
               }
             }

      assert integer_clause == %IR.FunctionDefinition{
               name: :impl_for,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :x, version: -1}],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_integer,
                     args: [%IR.Variable{name: :x, version: -1}]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.AtomType{value: Protocol1.Integer}
                   ]
                 }
               }
             }

      assert catch_all_clause == %IR.FunctionDefinition{
               name: :impl_for,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.MatchPlaceholder{}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: nil}]
                 }
               }
             }
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (Elixir >= 1.18):
    #   def impl_for!(data) do
    #     case impl_for(data) do
    #       x when x == false or x == nil ->
    #         :erlang.error(Protocol.UndefinedError.exception(
    #           protocol: Protocol1, value: data, description: ""))
    #       x -> x
    #     end
    #   end
    #
    # Expanded (Elixir < 1.18):
    #   def impl_for!(data) do
    #     case impl_for(data) do
    #       x when x == false or x == nil ->
    #         :erlang.error(Protocol.UndefinedError.exception(
    #           protocol: Protocol1, value: data))
    #       x -> x
    #     end
    #   end
    test "impl_for!/1 body calls impl_for/1 and has protocol module atom in error path",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Protocol1, :impl_for!, 1)

      exception_keyword_data =
        if Version.match?(System.version(), ">= 1.18.0") do
          [
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :protocol},
                %IR.AtomType{value: Protocol1}
              ]
            },
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :value},
                %IR.Variable{name: :data, version: 0}
              ]
            },
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :description},
                %IR.StringType{value: ""}
              ]
            }
          ]
        else
          [
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :protocol},
                %IR.AtomType{value: Protocol1}
              ]
            },
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :value},
                %IR.Variable{name: :data, version: 0}
              ]
            }
          ]
        end

      assert clause == %IR.FunctionDefinition{
               name: :impl_for!,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :data, version: 0}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.Case{
                       condition: %IR.LocalFunctionCall{
                         function: :impl_for,
                         args: [%IR.Variable{name: :data, version: 0}]
                       },
                       clauses: [
                         %IR.Clause{
                           match: %IR.Variable{name: :x, version: 1},
                           guards: [
                             %IR.RemoteFunctionCall{
                               module: %IR.AtomType{value: :erlang},
                               function: :orelse,
                               args: [
                                 %IR.RemoteFunctionCall{
                                   module: %IR.AtomType{value: :erlang},
                                   function: :"=:=",
                                   args: [
                                     %IR.Variable{name: :x, version: 1},
                                     %IR.AtomType{value: false}
                                   ]
                                 },
                                 %IR.RemoteFunctionCall{
                                   module: %IR.AtomType{value: :erlang},
                                   function: :"=:=",
                                   args: [
                                     %IR.Variable{name: :x, version: 1},
                                     %IR.AtomType{value: nil}
                                   ]
                                 }
                               ]
                             }
                           ],
                           body: %IR.Block{
                             expressions: [
                               %IR.RemoteFunctionCall{
                                 module: %IR.AtomType{value: :erlang},
                                 function: :error,
                                 args: [
                                   %IR.RemoteFunctionCall{
                                     module: %IR.AtomType{value: Protocol.UndefinedError},
                                     function: :exception,
                                     args: [
                                       %IR.ListType{data: exception_keyword_data}
                                     ]
                                   }
                                 ]
                               }
                             ]
                           }
                         },
                         %IR.Clause{
                           match: %IR.Variable{name: :x, version: 2},
                           guards: [],
                           body: %IR.Block{
                             expressions: [%IR.Variable{name: :x, version: 2}]
                           }
                         }
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source (Module39):
    #   raise ArgumentError
    #
    # Expanded:
    #   :erlang.error(ArgumentError.exception([]), :none,
    #     [error_info: %{module: Exception}])
    test "raise compiles to :erlang.error/3 with error_info: %{module: Exception}",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Module39, :my_fun, 0)

      %IR.FunctionDefinition{
        clause: %IR.FunctionClause{
          body: %IR.Block{
            expressions: [raise_expr]
          }
        }
      } = clause

      assert raise_expr == %IR.RemoteFunctionCall{
               module: %IR.AtomType{value: :erlang},
               function: :error,
               args: [
                 %IR.RemoteFunctionCall{
                   module: %IR.AtomType{value: ArgumentError},
                   function: :exception,
                   args: [%IR.ListType{data: []}]
                 },
                 %IR.AtomType{value: :none},
                 %IR.ListType{
                   data: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :error_info},
                         %IR.MapType{
                           data: [
                             {%IR.AtomType{value: :module}, %IR.AtomType{value: Exception}}
                           ]
                         }
                       ]
                     }
                   ]
                 }
               ]
             }
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (after consolidation, one clause per struct + catch-all):
    #   defp struct_impl_for(Struct1), do: Protocol1.Struct1
    #   defp struct_impl_for(_), do: nil
    test "struct_impl_for/1 clauses have struct and implementation module atoms",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1, :struct_impl_for, 1)

      assert [struct_1_clause, catch_all_clause] = fun_defs

      assert struct_1_clause == %IR.FunctionDefinition{
               name: :struct_impl_for,
               arity: 1,
               visibility: :private,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: Struct1}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.AtomType{value: Module.safe_concat(Protocol1, Struct1)}
                   ]
                 }
               }
             }

      assert catch_all_clause == %IR.FunctionDefinition{
               name: :struct_impl_for,
               arity: 1,
               visibility: :private,
               clause: %IR.FunctionClause{
                 params: [%IR.MatchPlaceholder{}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: nil}]
                 }
               }
             }
    end

    # Original source:
    #   defimpl Enumerable, for: Function do
    #     def count(_function), do: {:error, __MODULE__}
    #   end
    #
    # Expanded:
    #   def count(_function), do: {:error, Enumerable.Function}
    test "Enumerable impl count/1 body has {:error, __MODULE__} with implementation module atom",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Enumerable.Function, :count, 1)

      assert clause == %IR.FunctionDefinition{
               name: :count,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.MatchPlaceholder{}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :error},
                         %IR.AtomType{value: Enumerable.Function}
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source:
    #   defimpl Enumerable, for: Function do
    #     def member?(_function, _value), do: {:error, __MODULE__}
    #   end
    #
    # Expanded:
    #   def member?(_function, _value), do: {:error, Enumerable.Function}
    test "Enumerable impl member?/2 body has {:error, __MODULE__} with implementation module atom",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Enumerable.Function, :member?, 2)

      assert clause == %IR.FunctionDefinition{
               name: :member?,
               arity: 2,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.MatchPlaceholder{}, %IR.MatchPlaceholder{}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :error},
                         %IR.AtomType{value: Enumerable.Function}
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source:
    #   defimpl Enumerable, for: Function do
    #     def slice(_function), do: {:error, __MODULE__}
    #   end
    #
    # Expanded:
    #   def slice(_function), do: {:error, Enumerable.Function}
    test "Enumerable impl slice/1 body has {:error, __MODULE__} with implementation module atom",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Enumerable.Function, :slice, 1)

      assert clause == %IR.FunctionDefinition{
               name: :slice,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.MatchPlaceholder{}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :error},
                         %IR.AtomType{value: Enumerable.Function}
                       ]
                     }
                   ]
                 }
               }
             }
    end

    # Original source (System.warn/2):
    #
    # Elixir >= 1.17:
    #   defp warn(unit, replacement_unit) do
    #     IO.warn_once({System, unit}, fn ->
    #       "deprecated time unit: " <> inspect(unit) <>
    #         ". A time unit should be " <>
    #         ":second, :millisecond, :microsecond, :nanosecond, or a positive integer"
    #     end, _ = 4)
    #     replacement_unit
    #   end
    #
    # Elixir < 1.17:
    #   defp warn(unit, replacement_unit) do
    #     IO.warn_once({System, unit},
    #       "deprecated time unit: " <> inspect(unit) <>
    #         ". A time unit should be " <>
    #         ":second, :millisecond, :microsecond, :nanosecond, or a positive integer",
    #       _ = 4)
    #     replacement_unit
    #   end
    #
    # The first argument {System, unit} contains the System module atom as a
    # namespace identifier for the deduplication key, not as a dependency.
    test "IO.warn_once/3 first argument contains module atom as deduplication key",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, System, :warn, 2)

      message_bitstring = %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.StringType{value: "deprecated time unit: "},
            modifiers: [type: :binary]
          },
          %IR.BitstringSegment{
            value: %IR.RemoteFunctionCall{
              module: %IR.AtomType{value: Kernel},
              function: :inspect,
              args: [%IR.Variable{name: :unit, version: 0}]
            },
            modifiers: [type: :binary]
          },
          %IR.BitstringSegment{
            value: %IR.StringType{value: ". A time unit should be "},
            modifiers: [type: :binary]
          },
          %IR.BitstringSegment{
            value: %IR.StringType{
              value: ":second, :millisecond, :microsecond, :nanosecond, or a positive integer"
            },
            modifiers: [type: :binary]
          }
        ]
      }

      # Elixir >= 1.17 wraps the message in an anonymous function; < 1.17 passes it directly.
      message_arg =
        if Version.match?(System.version(), ">= 1.17.0") do
          %IR.AnonymousFunctionType{
            arity: 0,
            captured_function: nil,
            captured_module: nil,
            clauses: [
              %IR.FunctionClause{
                params: [],
                guards: [],
                body: %IR.Block{expressions: [message_bitstring]}
              }
            ]
          }
        else
          message_bitstring
        end

      assert clause == %IR.FunctionDefinition{
               name: :warn,
               arity: 2,
               visibility: :private,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :unit, version: 0},
                   %IR.Variable{name: :replacement_unit, version: 1}
                 ],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: IO},
                       function: :warn_once,
                       args: [
                         %IR.TupleType{
                           data: [
                             %IR.AtomType{value: System},
                             %IR.Variable{name: :unit, version: 0}
                           ]
                         },
                         message_arg,
                         %IR.MatchOperator{
                           left: %IR.MatchPlaceholder{},
                           right: %IR.IntegerType{value: 4}
                         }
                       ]
                     },
                     %IR.Variable{name: :replacement_unit, version: 1}
                   ]
                 }
               }
             }
    end

    # Protocol implementation fallback clauses that raise Protocol.UndefinedError contain
    # the protocol module atom in the exception keyword list. This pattern is not specific to
    # Enumerable - it appears in any protocol impl with a guarded clause and a fallback,
    # e.g. String.Chars.BitString.to_string/1, List.Chars.BitString.to_charlist/1.
    #
    # Original source (Enumerable.Function.reduce/3 as a concrete example):
    #   defimpl Enumerable, for: Function do
    #     def reduce(function, acc, fun) when is_function(function, 2), do: function.(acc, fun)
    #     def reduce(function, _acc, _fun) do
    #       raise Protocol.UndefinedError,
    #         protocol: Enumerable, value: function,
    #         description: "only anonymous functions of arity 2 are enumerable"
    #     end
    #   end
    #
    # Expanded:
    #   def reduce(function, acc, fun) when is_function(function, 2), do: function.(acc, fun)
    #   def reduce(function, _, _) do
    #     :erlang.error(Protocol.UndefinedError.exception(
    #       protocol: Enumerable, value: function,
    #       description: "only anonymous functions of arity 2 are enumerable"))
    #   end
    test "protocol implementation fallback clause has protocol module atom in Protocol.UndefinedError.exception/1 call",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Enumerable.Function, :reduce, 3)

      assert [guarded_clause, fallback_clause] = fun_defs

      assert guarded_clause == %IR.FunctionDefinition{
               name: :reduce,
               arity: 3,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :function, version: 0},
                   %IR.Variable{name: :acc, version: 1},
                   %IR.Variable{name: :fun, version: 2}
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_function,
                     args: [
                       %IR.Variable{name: :function, version: 0},
                       %IR.IntegerType{value: 2}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.AnonymousFunctionCall{
                       function: %IR.Variable{name: :function, version: 0},
                       args: [
                         %IR.Variable{name: :acc, version: 1},
                         %IR.Variable{name: :fun, version: 2}
                       ]
                     }
                   ]
                 }
               }
             }

      assert fallback_clause == %IR.FunctionDefinition{
               name: :reduce,
               arity: 3,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :function, version: 0},
                   %IR.MatchPlaceholder{},
                   %IR.MatchPlaceholder{}
                 ],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :error,
                       args: [
                         %IR.RemoteFunctionCall{
                           module: %IR.AtomType{value: Protocol.UndefinedError},
                           function: :exception,
                           args: [
                             %IR.ListType{
                               data: [
                                 %IR.TupleType{
                                   data: [
                                     %IR.AtomType{value: :protocol},
                                     %IR.AtomType{value: Enumerable}
                                   ]
                                 },
                                 %IR.TupleType{
                                   data: [
                                     %IR.AtomType{value: :value},
                                     %IR.Variable{name: :function, version: 0}
                                   ]
                                 },
                                 %IR.TupleType{
                                   data: [
                                     %IR.AtomType{value: :description},
                                     %IR.StringType{
                                       value: "only anonymous functions of arity 2 are enumerable"
                                     }
                                   ]
                                 }
                               ]
                             }
                           ]
                         }
                       ]
                     }
                   ]
                 }
               }
             }
    end
  end
end
