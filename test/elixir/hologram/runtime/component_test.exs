defmodule Hologram.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

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
  end
end
