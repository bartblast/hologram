defmodule Hologram.Compiler.CaseExpressionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{CaseExpressionTransformer, Context}

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    Block,
    CaseConditionAccess,
    CaseExpression,
    IntegerType,
    MapAccess,
    MapType,
    Variable
  }

  test "single expression clause body" do
    code = """
    case x do
      1 -> :ok
    end
    """

    result =
      code
      |> ast()
      |> CaseExpressionTransformer.transform(%Context{})

    expected = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: %Block{expressions: [
            %AtomType{value: :ok}
          ]},
          pattern: %IntegerType{value: 1}
        }
      ],
      condition: %Variable{name: :x}
    }

    assert result == expected
  end

  test "multiple expression clause body" do
    code = """
    case x do
      1 ->
        :expr_1
        :expr_2
    end
    """

    result =
      code
      |> ast()
      |> CaseExpressionTransformer.transform(%Context{})

    expected = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: %Block{expressions: [
            %AtomType{value: :expr_1},
            %AtomType{value: :expr_2}
          ]},
          pattern: %IntegerType{value: 1}
        }
      ],
      condition: %Variable{name: :x}
    }

    assert result == expected
  end

  test "clause without bindings" do
    code = """
    case x do
      1 -> :ok
    end
    """

    result =
      code
      |> ast()
      |> CaseExpressionTransformer.transform(%Context{})

    expected = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: %Block{expressions: [
            %AtomType{value: :ok}
          ]},
          pattern: %IntegerType{value: 1}
        }
      ],
      condition: %Variable{name: :x}
    }

    assert result == expected
  end

  test "clause with bindings" do
    code = """
    case x do
      %{a: a} -> :ok
    end
    """

    result =
      code
      |> ast()
      |> CaseExpressionTransformer.transform(%Context{})

    expected = %CaseExpression{
      clauses: [
        %{
          bindings: [
            %Binding{
              name: :a,
              access_path: [
                %CaseConditionAccess{},
                %MapAccess{key: %AtomType{value: :a}}
              ]
            }
          ],
          body: %Block{expressions: [
            %AtomType{value: :ok}
          ]},
          pattern: %MapType{
            data: [
              {%AtomType{value: :a}, %Variable{name: :a}}
            ]
          }
        }
      ],
      condition: %Variable{name: :x}
    }

    assert result == expected
  end
end
