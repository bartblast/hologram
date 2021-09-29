defmodule Hologram.Template.InterpolationParserTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.Document.{Expression, TextNode}
  alias Hologram.Template.InterpolationParser

  test "text" do
    str = "test"
    result = InterpolationParser.parse(str)

    assert result == [%TextNode{content: str}]
  end

  test "expression" do
    str = "{@abc}"
    result = InterpolationParser.parse(str)

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
    result = InterpolationParser.parse(str)

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
    result = InterpolationParser.parse(str)

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
    result = InterpolationParser.parse(str)

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
    result = InterpolationParser.parse(str)

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
    result = InterpolationParser.parse(str)

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
    result = InterpolationParser.parse(str)

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
    result = InterpolationParser.parse(str)
    
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
end
