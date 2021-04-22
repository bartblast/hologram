defmodule Hologram.Transpiler.EliminatorTest do
  use ExUnit.Case, async: true

  alias Hologram.Transpiler.AST.{Function, Module}
  alias Hologram.Transpiler.Eliminator

  describe "eliminate_dead_code/1" do
    test "Hologram backend functions" do
      ast =
        %Module{
          name: [:Abc],
          imports: [],
          aliases: [],
          functions: [
            %Function{name: :render, arity: 1},
            %Function{name: :test, arity: 0},
            %Function{name: :render, arity: 0}
          ]
        }

      result = Eliminator.eliminate_dead_code(ast)

      expected =
        %Module{
          name: [:Abc],
          imports: [],
          aliases: [],
          functions: [
            %Function{name: :render, arity: 1},
            %Function{name: :test, arity: 0}
          ]
        }

      assert result == expected
    end
  end
end
