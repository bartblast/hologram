defmodule Hologram.Runtime.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

  alias Hologram.Test.Fixtures.Runtime.Component.Module1
  alias Hologram.Test.Fixtures.Runtime.Component.Module2

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

  test "__is_hologram_component__/0" do
    assert Module1.__is_hologram_component__()
  end

  describe "init/1" do
    test "default" do
      assert Module1.init(:arg) == %{}
    end

    test "overridden" do
      assert Module2.init(:arg) == %{overridden_1: true}
    end
  end

  describe "init/2" do
    test "default" do
      assert Module1.init(:arg_1, :arg_2) == %{}
    end

    test "overridden" do
      assert Module2.init(:arg_1, :arg_2) == %{overridden_2: true}
    end
  end
end
