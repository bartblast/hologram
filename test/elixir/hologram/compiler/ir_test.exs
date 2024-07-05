defmodule Hologram.Compiler.IRTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.IR

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.IR.Module1

  defp my_fun(x, y), do: x + y

  test "for_code/1" do
    assert for_code("[1, :b]", %Context{}) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.AtomType{value: :b}
             ]
           }
  end

  describe "for_module/1" do
    @expected %IR.ModuleDefinition{
      module: %IR.AtomType{
        value: Module1
      },
      body: %IR.Block{
        expressions: [
          %IR.FunctionDefinition{
            name: :my_fun_1,
            arity: 2,
            visibility: :public,
            clause: %IR.FunctionClause{
              params: [
                %IR.Variable{name: :x},
                %IR.Variable{name: :y}
              ],
              guards: [],
              body: %IR.Block{
                expressions: [
                  %IR.RemoteFunctionCall{
                    module: %IR.AtomType{value: :erlang},
                    function: :+,
                    args: [
                      %IR.Variable{name: :x},
                      %IR.Variable{name: :y}
                    ]
                  }
                ]
              }
            }
          },
          %IR.FunctionDefinition{
            name: :my_fun_2,
            arity: 0,
            visibility: :public,
            clause: %IR.FunctionClause{
              params: [],
              guards: [],
              body: %IR.Block{
                expressions: [
                  %IR.AnonymousFunctionType{
                    arity: 2,
                    captured_function: :my_fun_1,
                    captured_module: Module1,
                    clauses: [
                      %IR.FunctionClause{
                        params: [
                          %IR.Variable{name: :"$1"},
                          %IR.Variable{name: :"$2"}
                        ],
                        guards: [],
                        body: %IR.Block{
                          expressions: [
                            %IR.LocalFunctionCall{
                              function: :my_fun_1,
                              args: [
                                %IR.Variable{name: :"$1"},
                                %IR.Variable{name: :"$2"}
                              ]
                            }
                          ]
                        }
                      }
                    ]
                  }
                ]
              }
            }
          }
        ]
      }
    }

    test "with BEAM path not specified" do
      assert for_module(Module1) == @expected
    end

    test "with BEAM path specified" do
      beam_path = :code.which(Module1)
      assert for_module(Module1, beam_path) == @expected
    end
  end

  describe "for_term/1" do
    test "can be represented in IR" do
      assert for_term(123) == {:ok, %IR.IntegerType{value: 123}}
    end

    test "can't be represented in IR" do
      expected_msg =
        if System.otp_release() >= "23" do
          "term contains an anonymous function that is not a named function capture"
        else
          "term contains an anonymous function that is not a remote function capture"
        end

      assert for_term(fn x -> x end) == {:error, expected_msg}
    end
  end

  describe "for_term!/1" do
    test "local function capture" do
      term = &my_fun/2

      if System.otp_release() >= "23" do
        assert for_term!(term) == %IR.AnonymousFunctionType{
                 arity: 2,
                 captured_function: :my_fun,
                 captured_module: Hologram.Compiler.IRTest,
                 clauses: [
                   %IR.FunctionClause{
                     params: [
                       %IR.Variable{name: :"$1"},
                       %IR.Variable{name: :"$2"}
                     ],
                     guards: [],
                     body: %IR.Block{
                       expressions: [
                         %IR.RemoteFunctionCall{
                           module: %IR.AtomType{
                             value: Hologram.Compiler.IRTest
                           },
                           function: :my_fun,
                           args: [
                             %IR.Variable{name: :"$1"},
                             %IR.Variable{name: :"$2"}
                           ]
                         }
                       ]
                     }
                   }
                 ]
               }
      else
        assert_error ArgumentError,
                     "term contains an anonymous function that is not a remote function capture",
                     fn ->
                       for_term!(term)
                     end
      end
    end

    test "remote function capture" do
      term = &DateTime.now/2

      # credo:disable-for-lines:26 Credo.Check.Design.DuplicatedCode
      assert for_term!(term) == %IR.AnonymousFunctionType{
               arity: 2,
               captured_function: :now,
               captured_module: DateTime,
               clauses: [
                 %IR.FunctionClause{
                   params: [
                     %IR.Variable{name: :"$1"},
                     %IR.Variable{name: :"$2"}
                   ],
                   guards: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.AtomType{value: DateTime},
                         function: :now,
                         args: [
                           %IR.Variable{name: :"$1"},
                           %IR.Variable{name: :"$2"}
                         ]
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "anonymous function (non-capture)" do
      term = fn x, y -> x + y end

      expected_msg =
        if System.otp_release() >= "23" do
          "term contains an anonymous function that is not a named function capture"
        else
          "term contains an anonymous function that is not a remote function capture"
        end

      assert_error ArgumentError, expected_msg, fn -> for_term!(term) end
    end

    test "anonymous function (capture)" do
      term = &(&1 + &2)

      assert_error ArgumentError,
                   "term contains an anonymous function that is not a named function capture",
                   fn ->
                     for_term!(term)
                   end
    end

    test "atom" do
      term = :abc
      assert for_term!(term) == %IR.AtomType{value: term}
    end

    test "bistring (binary)" do
      term = "abc"
      assert for_term!(term) == %IR.StringType{value: "abc"}
    end

    test "bistring (non-binary)" do
      term = <<1::1, 0::1>>

      assert for_term!(term) == %IR.BitstringType{
               segments: [
                 %IR.BitstringSegment{
                   value: %IR.IntegerType{value: 2},
                   modifiers: [
                     type: :integer,
                     size: %IR.IntegerType{value: 2}
                   ]
                 }
               ]
             }
    end

    test "float" do
      term = 1.23
      assert for_term!(term) == %IR.FloatType{value: term}
    end

    test "integer" do
      term = 123
      assert for_term!(term) == %IR.IntegerType{value: term}
    end

    test "list" do
      term = [123, :abc]

      assert for_term!(term) == %IR.ListType{
               data: [
                 %IR.IntegerType{value: 123},
                 %IR.AtomType{value: :abc}
               ]
             }
    end

    test "map" do
      term = %{123 => :abc, "xyz" => 9.87}

      assert for_term!(term) == %IR.MapType{
               data: [
                 {%IR.IntegerType{value: 123}, %IR.AtomType{value: :abc}},
                 {%IR.StringType{value: "xyz"}, %IR.FloatType{value: 9.87}}
               ]
             }
    end

    test "pid" do
      term = pid("0.11.222")
      assert for_term!(term) == %IR.PIDType{value: term}
    end

    test "port" do
      term = port("0.11")
      assert for_term!(term) == %IR.PortType{value: term}
    end

    test "reference" do
      term = make_ref()
      assert for_term!(term) == %IR.ReferenceType{value: term}
    end

    test "tuple" do
      term = {123, :abc}

      assert for_term!(term) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 123},
                 %IR.AtomType{value: :abc}
               ]
             }
    end
  end
end
