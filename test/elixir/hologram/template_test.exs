defmodule Hologram.TemplateTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template
  alias Hologram.Test.Fixtures.Template.Module1

  describe "dom_ast/1" do
    test "build DOM AST from the given markup" do
      assert dom_ast("<div>content</div>") == [
               {:{}, [line: 1], [:element, "div", [], [{:text, "content"}]]}
             ]
    end

    test "trim leading and trailing whitespaces" do
      assert dom_ast("\n\t content \t\n") == [{:text, "content"}]
    end
  end

  describe "HOLO sigil" do
    test "template which uses vars" do
      template = ~HOLO"""
      <div>{@value}</div>
      """

      assert template.(%{value: 123}) == [{:element, "div", [], [expression: {123}]}]
    end

    test "template which doesn't use vars" do
      template = ~HOLO"""
      <div>abc</div>
      """

      assert template.(%{}) == [{:element, "div", [], [text: "abc"]}]
    end

    test "alias" do
      alias Aaa.Bbb.Ccc
      template = ~HOLO"<Ccc />"

      assert template.(%{}) == [{:component, Aaa.Bbb.Ccc, [], []}]
    end

    test "whitespace trimming" do
      template = ~HOLO"""

      <div>abc</div>

      """

      assert template.(%{}) == [{:element, "div", [], [text: "abc"]}]
    end

    test "bitstring argument" do
      assert sigil_HOLO(<<"test">>, []).(%{}) == [text: "test"]
    end

    test "string argument" do
      assert sigil_HOLO("test", []).(%{}) == [text: "test"]
    end

    test "compiler correctly detects alias used in template" do
      assert Module1.template().(%{}) == [
               text: "Remote function call result = ",
               expression: {:ok}
             ]
    end
  end
end
