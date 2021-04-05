defmodule Hologram.TemplateEngine.TransformerTest do
  use ExUnit.Case
  import Hologram.TemplateEngine.Parser, only: [parse!: 1]

  alias Hologram.TemplateEngine.AST.TagNode
  alias Hologram.TemplateEngine.AST.TextNode
  alias Hologram.TemplateEngine.Transformer
  alias Hologram.Transpiler.AST.{ModuleAttribute}


  describe "transform/1" do
    test "tag nodes without attrs" do
      result =
        parse!("<div><h1><span></span></h1></div>")
        |> Transformer.transform()

      expected =
        %TagNode{
          attrs: %{},
          children: [
            %TagNode{
              attrs: %{},
              children: [
                %TagNode{attrs: %{}, children: [], tag: "span"}
              ],
              tag: "h1"
            }
          ],
          tag: "div"
        }

      assert result == expected
    end

    test "tag nodes with attrs" do
      html = """
        <div class="class_1"><h1><span class="class_2" id="id_2"></span></h1></div>
      """

      result =
        parse!(html)
        |> Transformer.transform()

      expected =
        %TagNode{
          attrs: %{"class" => "class_1"},
          children: [
            %TagNode{
              attrs: %{},
              children: [
                %TagNode{
                  attrs: %{"class" => "class_2", "id" => "id_2"},
                  children: [],
                  tag: "span"
                }
              ],
              tag: "h1"
            }
          ],
          tag: "div"
        }

      assert result == expected
    end

    test "text nodes" do
      result =
        parse!("<div>test_text_1<h1><span>test_text_2</span></h1></div>")
        |> Transformer.transform()

      expected =
        %TagNode{
          attrs: %{},
          children: [
            %TextNode{text: "test_text_1"},
            %TagNode{
              attrs: %{},
              children: [
                %TagNode{
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

      assert result == expected
    end

    test "expression interpolation" do
      html = """
        <div class="class_1" :if={{ @var_1 }} id="id_1" :show={{ @var_2 }}>
          <h1>
            <span class="class_2" :if={{ @var_3 }} id="id_2" :show={{ @var_4 }}></span>
          </h1>
        </div>
      """

      result =
        parse!(html)
        |> Transformer.transform()

      expected =
        %TagNode{
          attrs: %{
            ":if" => %ModuleAttribute{name: :var_1},
            ":show" => %ModuleAttribute{name: :var_2},
            "class" => "class_1",
            "id" => "id_1"
          },
          children: [
            %TextNode{text: "\n    "},
            %TagNode{
              attrs: %{},
              children: [
                %TextNode{text: "\n      "},
                %TagNode{
                  attrs: %{
                    ":if" => %ModuleAttribute{name: :var_3},
                    ":show" => %ModuleAttribute{name: :var_4},
                    "class" => "class_2",
                    "id" => "id_2"
                  },
                  children: [],
                  tag: "span"
                },
                %TextNode{text: "\n    "}
              ],
              tag: "h1"
            },
            %TextNode{text: "\n  "}
          ],
          tag: "div"
        }

      assert result == expected
    end
  end
end
