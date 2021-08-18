defmodule Hologram.Template.InterpolatorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, ModuleAttributeOperator, TupleType}
  alias Hologram.Template.Document.{Component, Expression, ElementNode, TextNode}
  alias Hologram.Template.Interpolator

  describe "text node" do
    test "text" do
      nodes = [%TextNode{content: "test"}]
      result = Interpolator.interpolate(nodes)

      assert result == nodes
    end

    test "expression" do
      nodes = [%TextNode{content: "{@abc}"}]
      result = Interpolator.interpolate(nodes)

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
      nodes = [%TextNode{content: "bcd{@abc}"}]
      result = Interpolator.interpolate(nodes)

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
      nodes = [%TextNode{content: "{@abc}bcd"}]
      result = Interpolator.interpolate(nodes)

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
      nodes = [%TextNode{content: "{@abc}{@bcd}"}]
      result = Interpolator.interpolate(nodes)

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
      nodes = [%TextNode{content: "cde{@abc}bcd"}]
      result = Interpolator.interpolate(nodes)

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
      nodes = [%TextNode{content: "{@abc}bcd{@cde}"}]
      result = Interpolator.interpolate(nodes)

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
      nodes = [%TextNode{content: "cde{@abc}bcd{@def}"}]
      result = Interpolator.interpolate(nodes)

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
      nodes = [%TextNode{content: "{@abc}bcd{@cde}def"}]
      result = Interpolator.interpolate(nodes)

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

  describe "element node" do
    test "doesn't have children and attributes" do
      nodes = [%ElementNode{children: [], attrs: %{}}]
      result = Interpolator.interpolate(nodes)

      assert result == nodes
    end

    test "attribute with string value" do
      nodes = [
        %ElementNode{
          children: [],
          attrs: %{
            test_key: %{value: "test_value", modifiers: []}
          }
        }
      ]

      result = Interpolator.interpolate(nodes)
      assert result == nodes
    end

    test "attribute with expression value" do
      nodes = [
        %ElementNode{
          tag: "div",
          children: [],
          attrs: %{
            key: %{value: "{1}", modifiers: []}
          }
        }
      ]

      result = Interpolator.interpolate(nodes)

      expected = [
        %ElementNode{
          attrs: %{
            key: %{
              value: %Expression{
                ir: %TupleType{
                  data: [%IntegerType{value: 1}]
                }
              },
              modifiers: []
            }
          },
          children: [],
          tag: "div"
        }
      ]

      assert result == expected
    end

    test "has children" do
      nodes = [
        %ElementNode{
          children: [
            %TextNode{content: "abc"},
            %TextNode{content: "xyz"}
          ],
          attrs: %{}
        }
      ]

      result = Interpolator.interpolate(nodes)

      assert result == nodes
    end
  end

  describe "component" do
    test "child text node interpolation" do
      nodes = [
        %Component{
          module: Abc.Bcd,
          children: [%TextNode{content: "bcd{@abc}"}]
        }
      ]

      result = Interpolator.interpolate(nodes)

      expected = [
        %Component{
          children: [
            %TextNode{content: "bcd"},
            %Expression{
              ir: %TupleType{
                data: [%ModuleAttributeOperator{name: :abc}]
              }
            }
          ],
          module: Abc.Bcd
        }
      ]

      assert result == expected
    end

    test "child element node interpolation" do
      nodes = [
        %Component{
          module: Abc.Bcd,
          children: [
            %ElementNode{
              tag: "div",
              children: [],
              attrs: %{
                key: %{value: "{1}", modifiers: []}
              }
            }
          ]
        }
      ]

      result = Interpolator.interpolate(nodes)

      expected = [
        %Component{
          children: [
            %ElementNode{
              attrs: %{
                key: %{
                  modifiers: [],
                  value: %Expression{
                    ir: %TupleType{
                      data: [%IntegerType{value: 1}]
                    }
                  }
                }
              },
              children: [],
              tag: "div"
            }
          ],
          module: Abc.Bcd
        }
      ]

      assert result == expected
    end

    test "prop interpolation" do
      nodes = [
        %Component{
          module: Abc.Bcd,
          props: %{
            key: "{1}"
          },
          children: []
        }
      ]

      result = Interpolator.interpolate(nodes)

      expected = [
        %Component{
          children: [],
          module: Abc.Bcd,
          props: %{
            key: %Expression{
              ir: %TupleType{
                data: [%IntegerType{value: 1}]
              }
            }
          }
        }
      ]

      assert result == expected
    end
  end

  test "nodes tree" do
    nodes = [
      %TextNode{content: "abc{1}cde"},
      %ElementNode{
        tag: "div",
        attrs: %{m: %{value: "{2}", modifiers: []}},
        children: [
          %TextNode{content: "xyz"},
          %ElementNode{
            tag: "div",
            children: [
              %ElementNode{tag: "span", children: [], attrs: %{}}
            ],
            attrs: %{n: %{value: "{3}", modifiers: []}}
          },
          %TextNode{content: "def{4}fgh"}
        ]
      },
      %TextNode{content: "ghi"}
    ]

    result = Interpolator.interpolate(nodes)

    expected = [
      %TextNode{content: "abc"},
      %Expression{ir: %TupleType{
        data: [%IntegerType{value: 1}]
        }
      },
      %TextNode{content: "cde"},
      %ElementNode{
        tag: "div",
        attrs: %{
          m: %{
            value: %Expression{
              ir: %TupleType{
                data: [%IntegerType{value: 2}]
              }
            },
            modifiers: []
          }
        },
        children: [
          %TextNode{content: "xyz"},
          %ElementNode{
            tag: "div",
            children: [
              %ElementNode{tag: "span", children: [], attrs: %{}}
            ],
            attrs: %{
              n: %{
                value: %Expression{
                  ir: %TupleType{
                    data: [%IntegerType{value: 3}]
                  }
                },
                modifiers: []
              }
            }
          },
          %TextNode{content: "def"},
          %Expression{
            ir: %TupleType{
              data: [%IntegerType{value: 4}]
            }
          },
          %TextNode{content: "fgh"}
        ]
      },
      %TextNode{content: "ghi"}
    ]

    assert result == expected
  end
end
