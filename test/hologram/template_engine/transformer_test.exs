defmodule Hologram.TemplateEngine.TransformerTest do
  use ExUnit.Case
  import Hologram.TemplateEngine.Parser, only: [parse!: 1]

  alias Hologram.TemplateEngine.AST.TagNode
  alias Hologram.TemplateEngine.Transformer

  describe "transform/1" do
    test "nesting, html tags" do
      result =
        parse!("<div><h1><span></span></h1></div>")
        |> Transformer.transform()

      expected = [
        %TagNode{
          children: [
            %TagNode{
              children: [
                %TagNode{children: [], tag: "span"}
              ],
              tag: "h1"
            }
          ],
          tag: "div"
        }
      ]

      assert result == expected
    end
  end
end
