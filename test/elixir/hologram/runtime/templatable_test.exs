defmodule Hologram.Runtime.TemplatableTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.Templatable

  alias Hologram.Component
  alias Hologram.Test.Fixtures.Runtime.Templatable.Module1

  test "colocated_template_path/1" do
    assert colocated_template_path("/my_dir_1/my_dir_2/my_dir_3/my_file.ex") ==
             "/my_dir_1/my_dir_2/my_dir_3/my_file.holo"
  end

  describe "maybe_define_template_fun/1" do
    test "valid template path" do
      template_path = "#{@fixtures_path}/runtime/templatable/template_1.holo"

      assert maybe_define_template_fun(template_path, Component) ==
               {:__block__, [],
                [
                  {:@, [context: Hologram.Runtime.Templatable, imports: [{1, Kernel}]],
                   [{:impl, [context: Hologram.Runtime.Templatable], [Hologram.Component]}]},
                  {:def,
                   [context: Hologram.Runtime.Templatable, imports: [{1, Kernel}, {2, Kernel}]],
                   [
                     {:template, [context: Hologram.Runtime.Templatable],
                      Hologram.Runtime.Templatable},
                     [do: {:sigil_H, [], ["My template 1", []]}]
                   ]}
                ]}
    end

    test "invalid template path" do
      refute maybe_define_template_fun("/my_invalid_template_path.holo", Component)
    end
  end

  test "put_state/3" do
    assert put_state(%Component.Client{}, :abc, 123) == %Component.Client{state: %{abc: 123}}
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
