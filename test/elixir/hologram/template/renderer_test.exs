defmodule Hologram.Template.RendererTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Renderer

  test "multiple nodes" do
    nodes = [{:text, "abc"}, {:text, "xyz"}]
    assert render(nodes) == "abcxyz"
  end

  describe "element" do
    test "non-void element, without attributes or children" do
      node = {:element, "div", [], []}
      assert render(node) == "<div></div>"
    end

    test "non-void element, with attributes" do
      node =
        {:element, "div",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}

      assert render(node) == ~s(<div attr_1="aaa" attr_2="123" attr_3="ccc987eee"></div>)
    end

    test "non-void element, with children" do
      node = {:element, "div", [], [{:element, "span", [], [text: "abc"]}, {:text, "xyz"}]}

      assert render(node) == "<div><span>abc</span>xyz</div>"
    end

    test "void element, without attributes" do
      node = {:element, "img", [], []}
      assert render(node) == "<img />"
    end

    test "void element, with attributes" do
      node = [
        {:element, "img",
         [
           {"attr_1", [text: "aaa"]},
           {"attr_2", [expression: {123}]},
           {"attr_3", [text: "ccc", expression: {987}, text: "eee"]}
         ], []}
      ]

      assert render(node) == ~s(<img attr_1="aaa" attr_2="123" attr_3="ccc987eee" />)
    end
  end

  test "expression" do
    node = {:expression, {123}}
    assert render(node) == "123"
  end

  test "text" do
    node = {:text, "abc"}
    assert render(node) == "abc"
  end
end
