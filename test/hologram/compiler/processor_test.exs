defmodule Hologram.Compiler.ProcessorTest do
  use ExUnit.Case, async: true

  alias Hologram.Compiler.AST.{Alias, Function, IntegerType, Module}
  alias Hologram.Compiler.Processor

  test "module without directives" do
    result = Processor.compile([:TestModule6])

    expected =
      %{
        [:TestModule6] => %Module{
          aliases: [],
          attributes: [],
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
    result = Processor.compile([:TestModule7])

    expected =
      %{
        [:TestModule6] => %Module{
          aliases: [],
          attributes: [],
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
          aliases: [%Alias{as: [:TestModule6], module: [:TestModule6]}],
          attributes: [],
          functions: [],
          imports: [],
          name: [:TestModule7]
        }
      }

    assert result == expected
  end

  test "nested directives" do
    result = Processor.compile([:TestModule10])

    expected =
      %{
        [:TestModule10] => %Module{
          aliases: [%Alias{as: [:TestModule7], module: [:TestModule7]}],
          attributes: [],
          functions: [],
          imports: [],
          name: [:TestModule10]
        },
        [:TestModule6] => %Module{
          aliases: [],
          attributes: [],
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
          aliases: [%Alias{as: [:TestModule6], module: [:TestModule6]}],
          attributes: [],
          functions: [],
          imports: [],
          name: [:TestModule7]
        }
      }

    assert result == expected
  end

  test "circular dependency" do
    result = Processor.compile([:TestModule8])

    expected =
      %{
        [:TestModule8] => %Module{
          aliases: [%Alias{as: [:TestModule9], module: [:TestModule9]}],
          attributes: [],
          functions: [],
          imports: [],
          name: [:TestModule8]
        },
        [:TestModule9] => %Module{
          aliases: [%Alias{as: [:TestModule8], module: [:TestModule8]}],
          attributes: [],
          functions: [],
          imports: [],
          name: [:TestModule9]
        }
      }

    assert result == expected
  end
end
