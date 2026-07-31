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

    test "template with raw block" do
      template = ~HOLO"""
      {%raw}{%if true}Hologram{/if}{/raw}
      """

      assert template.(%{}) == [text: "{%if true}Hologram{/if}"]
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

    test "element spread" do
      template = ~HOLO"""
      <div ...{@my_var}></div>
      """

      assert template.(%{my_var: %{id: "my_id"}}) == [
               {:element, "div", [spread: {%{id: "my_id"}}], []}
             ]
    end

    test "component spread" do
      alias Aaa.Bbb.Ccc
      template = ~HOLO"<Ccc ...{@my_var} />"

      assert template.(%{my_var: %{id: "my_id"}}) == [
               {:component, Aaa.Bbb.Ccc, [spread: {%{id: "my_id"}}], []}
             ]
    end

    test "spread interleaved with named attributes" do
      template = ~HOLO"""
      <div class="btn" ...{@my_var} id={@my_id}></div>
      """

      assert template.(%{my_var: %{title: "my_title"}, my_id: "my_id"}) == [
               {:element, "div",
                [
                  {"class", [text: "btn"]},
                  {:spread, {%{title: "my_title"}}},
                  {"id", [expression: {"my_id"}]}
                ], []}
             ]
    end

    test "multiple spreads" do
      template = ~HOLO"""
      <div ...{@my_var_1} ...{@my_var_2}></div>
      """

      assert template.(%{my_var_1: %{a: 1}, my_var_2: [b: 2]}) == [
               {:element, "div", [spread: {%{a: 1}}, spread: {[b: 2]}], []}
             ]
    end

    test "spread with implicit keyword list" do
      template = ~HOLO"""
      <div ...{my_key_1: "abc", my_key_2: [my_key_3: "xyz"]}></div>
      """

      assert template.(%{}) == [
               {:element, "div", [spread: {[my_key_1: "abc", my_key_2: [my_key_3: "xyz"]]}], []}
             ]
    end

    test "spread with expression" do
      template = ~HOLO"""
      <div ...{Map.merge(@my_base, @my_overrides)}></div>
      """

      assert template.(%{my_base: %{a: 1}, my_overrides: %{b: 2}}) == [
               {:element, "div", [spread: {%{a: 1, b: 2}}], []}
             ]
    end

    test "dynamic tag with module value" do
      template = ~HOLO"<{@module} />"

      assert template.(%{module: Aaa.Bbb.Ccc}) == [{:dynamic_tag, {Aaa.Bbb.Ccc}, [], []}]
    end

    test "dynamic tag with element name value" do
      template = ~HOLO"<{@tag} />"

      assert template.(%{tag: "div"}) == [{:dynamic_tag, {"div"}, [], []}]
    end

    test "dynamic tag with alias in tag name expression" do
      alias Aaa.Bbb.Ccc
      template = ~HOLO"<{Ccc} />"

      assert template.(%{}) == [{:dynamic_tag, {Aaa.Bbb.Ccc}, [], []}]
    end

    test "dynamic tag with conditional tag name expression" do
      template = ~HOLO"""
      <{if @flag do "a" else "button" end} />
      """

      assert template.(%{flag: true}) == [{:dynamic_tag, {"a"}, [], []}]
      assert template.(%{flag: false}) == [{:dynamic_tag, {"button"}, [], []}]
    end

    test "dynamic tag with attributes" do
      template = ~HOLO"""
      <{@tag} my_key_1="my_value_1" my_key_2={@my_value_2} />
      """

      assert template.(%{tag: "div", my_value_2: 123}) == [
               {:dynamic_tag, {"div"},
                [{"my_key_1", [text: "my_value_1"]}, {"my_key_2", [expression: {123}]}], []}
             ]
    end

    test "dynamic tag with spread" do
      template = ~HOLO"""
      <{@tag} ...{@my_var} />
      """

      assert template.(%{tag: "div", my_var: %{id: "my_id"}}) == [
               {:dynamic_tag, {"div"}, [spread: {%{id: "my_id"}}], []}
             ]
    end

    test "dynamic tag with children" do
      template = ~HOLO"""
      <{@tag}>abc{@my_value}</{@tag}>
      """

      assert template.(%{tag: "div", my_value: 123}) == [
               {:dynamic_tag, {"div"}, [], [text: "abc", expression: {123}]}
             ]
    end

    test "compiler correctly detects alias used in template" do
      assert Module1.template().(%{}) == [
               text: "Remote function call result = ",
               expression: {:ok}
             ]
    end
  end
end
