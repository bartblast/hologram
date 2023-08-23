defmodule Hologram.TemplateTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template
  alias Hologram.Test.Fixtures.Template.Module1

  describe "dom_ast_from_markup/1" do
    test "build DOM AST from the given markup" do
      assert dom_ast_from_markup("<div>content</div>") == [
               {:{}, [line: 1], [:element, "div", [], [{:text, "content"}]]}
             ]
    end

    test "remove doctype" do
      assert dom_ast_from_markup("<!DoCtYpE html test_1 test_2>content") == [{:text, "content"}]
    end

    test "remove comments" do
      special_chars = "abc \n \r \t < > / = \" { } ! -"
      markup = "aaa<!-- #{special_chars} -->bbb<!-- #{special_chars} -->ccc"

      assert dom_ast_from_markup(markup) == [{:text, "aaabbbccc"}]
    end

    test "trim leading and trailing whitespaces" do
      assert dom_ast_from_markup("\n\t content \t\n") == [{:text, "content"}]
    end
  end

  describe "H sigil" do
    test "template which uses data" do
      template = ~H"""
      <div>{@value}</div>
      """

      assert template.(%{value: 123}) == [{:element, "div", [], [expression: {123}]}]
    end

    test "template which doesn't use data" do
      template = ~H"""
      <div>abc</div>
      """

      assert template.(%{}) == [{:element, "div", [], [text: "abc"]}]
    end

    test "alias" do
      alias Aaa.Bbb.Ccc
      template = ~H"<Ccc />"

      assert template.(%{}) == [{:component, Aaa.Bbb.Ccc, [], []}]
    end

    test "whitespace trimming" do
      template = ~H"""

      <div>abc</div>

      """

      assert template.(%{}) == [{:element, "div", [], [text: "abc"]}]
    end

    test "bitstring argument" do
      assert sigil_H(<<"test">>, []).(%{}) == [text: "test"]
    end

    test "string argument" do
      assert sigil_H("test", []).(%{}) == [text: "test"]
    end

    test "compiler correctly detects alias used in template" do
      assert Module1.template().(%{}) == [
               text: "Remote function call result = ",
               expression: {:ok}
             ]
    end
  end
end
