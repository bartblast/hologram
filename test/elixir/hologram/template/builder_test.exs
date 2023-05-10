defmodule Hologram.Template.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Builder

  test "build VDOM tree AST from the given markup" do
    assert build("<div>content</div>") == [
             {:{}, [line: 1], [:element, "div", [], [{:text, "content"}]]}
           ]
  end

  test "remove doctype" do
    assert build("<!DoCtYpE html test_1 test_2>content") == [{:text, "content"}]
  end

  test "remove comments" do
    special_chars = "abc \n \r \t < > / = \" { } ! -"
    markup = "aaa<!-- #{special_chars} -->bbb<!-- #{special_chars} -->ccc"

    assert build(markup) == [{:text, "aaabbbccc"}]
  end

  test "trim leading and trailing whitespaces" do
    assert build("\n\t content \t\n") == [{:text, "content"}]
  end
end
