defmodule Hologram.Template.EmbeddedExpressionParserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.{AliasDirective, FunctionCall, ModuleAttributeOperator, TupleType}
  alias Hologram.Template.VDOM.{Expression, TextNode}
  alias Hologram.Template.EmbeddedExpressionParser

  @context %Context{}

  test "text" do
    str = "test"
    result = EmbeddedExpressionParser.parse(str, @context)

    assert result == [%TextNode{content: str}]
  end

  test "expression" do
    str = "{@abc}"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      }
    ]

    assert result == expected
  end

  test "text, expression" do
    str = "bcd{@abc}"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %TextNode{content: "bcd"},
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      }
    ]

    assert result == expected
  end

  test "expression, text" do
    str = "{@abc}bcd"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      },
      %TextNode{content: "bcd"}
    ]

    assert result == expected
  end

  test "expression, expression" do
    str = "{@abc}{@bcd}"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      },
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :bcd}]
        }
      }
    ]

    assert result == expected
  end

  test "text, expression, text" do
    str = "cde{@abc}bcd"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %TextNode{content: "cde"},
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      },
      %TextNode{content: "bcd"}
    ]

    assert result == expected
  end

  test "expression, text, expression" do
    str = "{@abc}bcd{@cde}"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      },
      %TextNode{content: "bcd"},
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :cde}]
        }
      }
    ]

    assert result == expected
  end

  test "text, expression, text, expression" do
    str = "cde{@abc}bcd{@def}"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %TextNode{content: "cde"},
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      },
      %TextNode{content: "bcd"},
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :def}]
        }
      }
    ]

    assert result == expected
  end

  test "expression, text, expression, text" do
    str = "{@abc}bcd{@cde}def"
    result = EmbeddedExpressionParser.parse(str, @context)

    expected = [
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :abc}]
        }
      },
      %TextNode{content: "bcd"},
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :cde}]
        }
      },
      %TextNode{content: "def"}
    ]

    assert result == expected
  end

  test "context passing" do
    context = %Context{
      aliases: [
        %AliasDirective{
          module: Abc.Bcd.Module1,
          as: [:Module1]
        }
      ]
    }

    str = "{Module1.test_fun()}"
    result = EmbeddedExpressionParser.parse(str, context)

    expected = [
      %Expression{
        ir: %TupleType{
          data: [
            %FunctionCall{
              module: Abc.Bcd.Module1,
              function: :test_fun,
              args: []
            }
          ]
        }
      }
    ]

    assert result == expected
  end

  test "handles JS code" do
    str = """
    function isPositiveNumber(param) \\{
      if (param > 0) \\{
        return true;
      \\}
      if (param <= 0) \\{
        return false;
      \\}
    \\}
    """

    result = EmbeddedExpressionParser.parse(str, @context)
    expected = [%TextNode{content: str}]

    assert result == expected
  end
end
