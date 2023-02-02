defmodule Hologram.Compiler.CaseExpressionTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.CaseExpressionTransformer

  alias Hologram.Compiler.IR.{
    AtomType,
    Binding,
    Block,
    CaseConditionAccess,
    CaseExpression,
    IntegerType,
    MapAccess,
    MapType,
    Symbol
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
      |> CaseExpressionTransformer.transform()

    expected = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: %Block{
            expressions: [
              %AtomType{value: :ok}
            ]
          },
          pattern: %IntegerType{value: 1}
        }
      ],
      condition: %Symbol{name: :x}
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
      |> CaseExpressionTransformer.transform()

    expected = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: %Block{
            expressions: [
              %AtomType{value: :expr_1},
              %AtomType{value: :expr_2}
            ]
          },
          pattern: %IntegerType{value: 1}
        }
      ],
      condition: %Symbol{name: :x}
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
      |> CaseExpressionTransformer.transform()

    expected = %CaseExpression{
      clauses: [
        %{
          bindings: [],
          body: %Block{
            expressions: [
              %AtomType{value: :ok}
            ]
          },
          pattern: %IntegerType{value: 1}
        }
      ],
      condition: %Symbol{name: :x}
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
      |> CaseExpressionTransformer.transform()

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
          body: %Block{
            expressions: [
              %AtomType{value: :ok}
            ]
          },
          pattern: %MapType{
            data: [
              {%AtomType{value: :a}, %Symbol{name: :a}}
            ]
          }
        }
      ],
      condition: %Symbol{name: :x}
    }

    assert result == expected
  end
end
