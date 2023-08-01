defmodule Hologram.Compiler.IRTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.IR

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.IR.Module1

  test "for_code/1" do
    assert for_code("[1, :b]", %Context{}) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.AtomType{value: :b}
             ]
           }
  end

  test "for_module/1" do
    assert for_module(Module1) == %IR.ModuleDefinition{
             module: %IR.AtomType{
               value: Module1
             },
             body: %IR.Block{
               expressions: [
                 %IR.FunctionDefinition{
                   name: :my_fun,
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
                 }
               ]
             }
           }
  end
end
