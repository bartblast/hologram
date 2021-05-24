defmodule Hologram.Template.TransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM.{Expression, ElementNode, TextNode}
  alias Hologram.Template.{Parser, Transformer}
  alias Hologram.Compiler.IR.{ModuleAttributeOperator}

  describe "transform/1" do
    test "element nodes without attrs" do
      result =
        Parser.parse!("<div><h1><span></span></h1></div>")
        |> Transformer.transform()

      expected = [
        %ElementNode{
          attrs: %{},
          children: [
            %ElementNode{
              attrs: %{},
              children: [
                %ElementNode{attrs: %{}, children: [], tag: "span"}
              ],
              tag: "h1"
            }
          ],
          tag: "div"
        }
      ]

      assert result == expected
    end

    test "element nodes with attrs" do
      html = """
      <div class="class_1"><h1><span class="class_2" id="id_2"></span></h1></div>
      """

      result =
        Parser.parse!(html)
        |> Transformer.transform()

      expected = [
        %ElementNode{
          attrs: %{"class" => "class_1"},
          children: [
            %ElementNode{
              attrs: %{},
              children: [
                %ElementNode{
                  attrs: %{"class" => "class_2", "id" => "id_2"},
                  children: [],
                  tag: "span"
                }
              ],
              tag: "h1"
            }
          ],
          tag: "div"
        },
        %TextNode{text: "\n"}
      ]

      assert result == expected
    end

    test "text nodes" do
      result =
        Parser.parse!("<div>test_text_1<h1><span>test_text_2</span></h1></div>")
        |> Transformer.transform()

      expected = [
        %ElementNode{
          attrs: %{},
          children: [
            %TextNode{text: "test_text_1"},
            %ElementNode{
              attrs: %{},
              children: [
                %ElementNode{
                  attrs: %{},
                  children: [%TextNode{text: "test_text_2"}],
                  tag: "span"
                }
              ],
              tag: "h1"
            }
          ],
          tag: "div"
        }
      ]

      assert result == expected
    end

    test "expression interpolation in attrs" do
      html = """
      <div class="class_1" :if={{ @var_1 }} id="id_1" :show={{ @var_2 }}>
        <h1>
          <span class="class_2" :if={{ @var_3 }} id="id_2" :show={{ @var_4 }}></span>
        </h1>
      </div>
      """

      result =
        Parser.parse!(html)
        |> Transformer.transform()

      expected = [
        %ElementNode{
          attrs: %{
            ":if" => %Expression{ir: %ModuleAttributeOperator{name: :var_1}},
            ":show" => %Expression{ir: %ModuleAttributeOperator{name: :var_2}},
            "class" => "class_1",
            "id" => "id_1"
          },
          children: [
            %TextNode{text: "\n  "},
            %ElementNode{
              attrs: %{},
              children: [
                %TextNode{text: "\n    "},
                %ElementNode{
                  attrs: %{
                    ":if" => %Expression{ir: %ModuleAttributeOperator{name: :var_3}},
                    ":show" => %Expression{ir: %ModuleAttributeOperator{name: :var_4}},
                    "class" => "class_2",
                    "id" => "id_2"
                  },
                  children: [],
                  tag: "span"
                },
                %TextNode{text: "\n  "}
              ],
              tag: "h1"
            },
            %TextNode{text: "\n"}
          ],
          tag: "div"
        },
        %TextNode{text: "\n"}
      ]

      assert result == expected
    end

    test "expression interpolation in text" do
      html = "<div>test_1{{ @x1 }}test_2{{ @x2 }}test_3</div>"

      result =
        Parser.parse!(html)
        |> Transformer.transform()

      expected = [
        %ElementNode{
          attrs: %{},
          children: [
            %TextNode{text: "test_1"},
            %Expression{
              ir: %ModuleAttributeOperator{name: :x1}
            },
            %TextNode{text: "test_2"},
            %Expression{
              ir: %ModuleAttributeOperator{name: :x2}
            },
            %TextNode{text: "test_3"}
          ],
          tag: "div"
        }
      ]

      assert result == expected
    end
  end
end
