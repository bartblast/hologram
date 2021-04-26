defmodule Hologram.CompilerTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler
  alias Hologram.Transpiler.AST.{Alias, Function, IntegerType, Module}

  test "module without directives" do
    result = Compiler.compile([:TestModule6])

    expected =
      %{
        [:TestModule6] => %Module{
          aliases: [],
          functions: [
            %Function{
              arity: 0,
              bindings: [],
              body: [%IntegerType{value: 6}],
              name: :test_6,
              params: []
            }
          ],
          imports: [],
          name: [:TestModule6]
        }
      }

    assert result == expected
  end

  test "module with a directive" do
    result = Compiler.compile([:TestModule7])

    expected =
      %{
        [:TestModule6] => %Module{
          aliases: [],
          functions: [
            %Function{
              arity: 0,
              bindings: [],
              body: [%IntegerType{value: 6}],
              name: :test_6,
              params: []
            }
          ],
          imports: [],
          name: [:TestModule6]
        },
        [:TestModule7] => %Module{
          aliases: [%Alias{as: nil, module: [:TestModule6]}],
          functions: [],
          imports: [],
          name: [:TestModule7]
        }
      }

    assert result == expected
  end

  test "nested directives" do
    result = Compiler.compile([:TestModule10])

    expected =
      %{
        [:TestModule10] => %Module{
          aliases: [%Alias{as: nil, module: [:TestModule7]}],
          functions: [],
          imports: [],
          name: [:TestModule10]
        },
        [:TestModule6] => %Module{
          aliases: [],
          functions: [
            %Function{
              arity: 0,
              bindings: [],
              body: [%IntegerType{value: 6}],
              name: :test_6,
              params: []
            }
          ],
          imports: [],
          name: [:TestModule6]
        },
        [:TestModule7] => %Module{
          aliases: [%Alias{as: nil, module: [:TestModule6]}],
          functions: [],
          imports: [],
          name: [:TestModule7]
        }
      }

    assert result == expected
  end

  test "circular dependency" do
    result = Compiler.compile([:TestModule8])

    expected =
      %{
        [:TestModule8] => %Module{
          aliases: [%Alias{as: nil, module: [:TestModule9]}],
          functions: [],
          imports: [],
          name: [:TestModule8]
        },
        [:TestModule9] => %Module{
          aliases: [%Alias{as: nil, module: [:TestModule8]}],
          functions: [],
          imports: [],
          name: [:TestModule9]
        }
      }

    assert result == expected
  end
end
