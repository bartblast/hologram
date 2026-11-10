defmodule Hologram.TemplateTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template
  alias Hologram.Template.TrustedHTML
  alias Hologram.Test.Fixtures.Template.Module1
  alias Hologram.Test.Fixtures.Template.Module3
  alias Hologram.Test.Fixtures.Template.Module4

  describe "dom_ast/1" do
    test "build DOM AST from the given markup" do
      assert [
               {:{}, [line: 1], [:element, "div", [{"$key", [text: _key]}], [{:text, "content"}]]}
             ] = dom_ast("<div>content</div>")
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

      assert [{:element, "div", [{"$key", [text: _key]}], [expression: {123}]}] =
               template.(%{value: 123})
    end

    test "template which doesn't use vars" do
      template = ~HOLO"""
      <div>abc</div>
      """

      assert [{:element, "div", [{"$key", [text: _key]}], [text: "abc"]}] = template.(%{})
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

      assert [{:element, "div", [{"$key", [text: _key]}], [text: "abc"]}] = template.(%{})
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

      assert [
               {:element, "div", [{:spread, {%{id: "my_id"}}}, {"$key", [text: _key]}], []}
             ] = template.(%{my_var: %{id: "my_id"}})
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

      assert [
               {:element, "div",
                [
                  {"class", [text: "btn"]},
                  {:spread, {%{title: "my_title"}}},
                  {"id", [expression: {"my_id"}]},
                  {"$key", [text: _key]}
                ], []}
             ] = template.(%{my_var: %{title: "my_title"}, my_id: "my_id"})
    end

    test "multiple spreads" do
      template = ~HOLO"""
      <div ...{@my_var_1} ...{@my_var_2}></div>
      """

      assert [
               {:element, "div",
                [{:spread, {%{a: 1}}}, {:spread, {[b: 2]}}, {"$key", [text: _key]}], []}
             ] = template.(%{my_var_1: %{a: 1}, my_var_2: [b: 2]})
    end

    test "spread with implicit keyword list" do
      template = ~HOLO"""
      <div ...{my_key_1: "abc", my_key_2: [my_key_3: "xyz"]}></div>
      """

      assert [
               {:element, "div",
                [
                  {:spread, {[my_key_1: "abc", my_key_2: [my_key_3: "xyz"]]}},
                  {"$key", [text: _key]}
                ], []}
             ] = template.(%{})
    end

    test "spread with expression" do
      template = ~HOLO"""
      <div ...{Map.merge(@my_base, @my_overrides)}></div>
      """

      assert [
               {:element, "div", [{:spread, {%{a: 1, b: 2}}}, {"$key", [text: _key]}], []}
             ] = template.(%{my_base: %{a: 1}, my_overrides: %{b: 2}})
    end

    test "dynamic tag with module value" do
      template = ~HOLO"<{@module} />"

      assert [{:dynamic_tag, {Aaa.Bbb.Ccc}, [{"$key", [text: _key]}], []}] =
               template.(%{module: Aaa.Bbb.Ccc})
    end

    test "dynamic tag with element name value" do
      template = ~HOLO"<{@tag} />"

      assert [{:dynamic_tag, {"div"}, [{"$key", [text: _key]}], []}] = template.(%{tag: "div"})
    end

    test "dynamic tag with alias in tag name expression" do
      alias Aaa.Bbb.Ccc
      template = ~HOLO"<{Ccc} />"

      assert [{:dynamic_tag, {Aaa.Bbb.Ccc}, [{"$key", [text: _key]}], []}] = template.(%{})
    end

    test "dynamic tag with conditional tag name expression" do
      template = ~HOLO"""
      <{if @flag do "a" else "button" end} />
      """

      assert [{:dynamic_tag, {"a"}, [{"$key", [text: _key]}], []}] = template.(%{flag: true})

      assert [{:dynamic_tag, {"button"}, [{"$key", [text: _key]}], []}] =
               template.(%{flag: false})
    end

    test "dynamic tag with attributes" do
      template = ~HOLO"""
      <{@tag} my_key_1="my_value_1" my_key_2={@my_value_2} />
      """

      assert [
               {:dynamic_tag, {"div"},
                [
                  {"my_key_1", [text: "my_value_1"]},
                  {"my_key_2", [expression: {123}]},
                  {"$key", [text: _key]}
                ], []}
             ] = template.(%{tag: "div", my_value_2: 123})
    end

    test "dynamic tag with spread" do
      template = ~HOLO"""
      <{@tag} ...{@my_var} />
      """

      assert [
               {:dynamic_tag, {"div"}, [{:spread, {%{id: "my_id"}}}, {"$key", [text: _key]}], []}
             ] = template.(%{tag: "div", my_var: %{id: "my_id"}})
    end

    test "dynamic tag with children" do
      template = ~HOLO"""
      <{@tag}>abc{@my_value}</{@tag}>
      """

      assert [
               {:dynamic_tag, {"div"}, [{"$key", [text: _key]}], [text: "abc", expression: {123}]}
             ] = template.(%{tag: "div", my_value: 123})
    end

    test "compiler correctly detects alias used in template" do
      assert Module1.template().(%{}) == [
               text: "Remote function call result = ",
               expression: {:ok}
             ]
    end
  end

  describe "HOLO sigil, element lookups" do
    test "raises for a call through the JS alias" do
      assert_error Hologram.CompileError, element_lookup_message("ElementLookupAlias"), fn ->
        compile_template("ElementLookupAlias", ~S"""
        alias Hologram.JS
        def template, do: ~HOLO"<div>{JS.element(:feed)}</div>"
        """)
      end
    end

    test "raises for a call through the full module name" do
      assert_error Hologram.CompileError, element_lookup_message("ElementLookupFullName"), fn ->
        compile_template("ElementLookupFullName", ~S"""
        def template, do: ~HOLO"<div>{Hologram.JS.element(:feed)}</div>"
        """)
      end
    end

    test "raises for an imported call" do
      assert_error Hologram.CompileError, element_lookup_message("ElementLookupImport"), fn ->
        compile_template("ElementLookupImport", ~S"""
        import Hologram.JS, only: [element: 1]
        def template, do: ~HOLO"<div>{element(:feed)}</div>"
        """)
      end
    end

    test "raises for a call in an attribute value" do
      assert_error Hologram.CompileError, element_lookup_message("ElementLookupAttribute"), fn ->
        compile_template("ElementLookupAttribute", ~S"""
        alias Hologram.JS
        def template, do: ~HOLO"<div data-feed={JS.element(:feed)}></div>"
        """)
      end
    end

    test "raises for a pipe into it" do
      assert_error Hologram.CompileError, element_lookup_message("ElementLookupPipe"), fn ->
        compile_template("ElementLookupPipe", ~S"""
        alias Hologram.JS
        def template, do: ~HOLO"<div>{@feed_ref |> JS.element()}</div>"
        """)
      end
    end

    test "raises for a capture of it" do
      assert_error Hologram.CompileError, element_lookup_message("ElementLookupCapture"), fn ->
        compile_template("ElementLookupCapture", ~S"""
        alias Hologram.JS
        def template, do: ~HOLO"<div>{inspect(&JS.element/1)}</div>"
        """)
      end
    end

    test "raises outside a module, naming no module" do
      expected_msg =
        "JS.element/1 can't be called in a template - a template also renders on the server, " <>
          "and in the browser the element it names may not exist yet, so pass the ref itself, " <>
          "like scroll_ref={:feed}, and look the element up in an action"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string(~S"""
        import Hologram.Template
        alias Hologram.JS
        ~HOLO"<div>{JS.element(:feed)}</div>"
        """)
      end
    end

    test "other JS functions pass" do
      {template, _bindings} =
        Code.eval_string(~S"""
        import Hologram.Template
        require Hologram.JS
        alias Hologram.JS
        ~HOLO"<div>{JS.call(:feed, [])}</div>"
        """)

      assert [{:element, "div", [{"$key", [text: _key]}], [expression: {:ok}]}] = template.(%{})
    end

    test "an element function of another module aliased as JS passes" do
      {template, _bindings} =
        Code.eval_string(~S"""
        import Hologram.Template
        alias Hologram.Test.Fixtures.Template.Module5, as: JS
        ~HOLO"<div>{JS.element(:feed)}</div>"
        """)

      assert [{:element, "div", [{"$key", [text: _key]}], [expression: {:feed}]}] =
               template.(%{})
    end
  end

  describe "trust_html/1" do
    test "string" do
      assert trust_html("<p>Hello</p>") == %TrustedHTML{html: "<p>Hello</p>"}
    end

    test "empty string" do
      assert trust_html("") == %TrustedHTML{html: ""}
    end

    test "iolist" do
      assert trust_html(["<p>", "Hello", "</p>"]) == %TrustedHTML{html: "<p>Hello</p>"}
    end

    test "nested iolist with bytes" do
      assert trust_html(["<p>", [?H, "ello"], "</p>"]) == %TrustedHTML{html: "<p>Hello</p>"}
    end

    test "empty list" do
      assert trust_html([]) == %TrustedHTML{html: ""}
    end

    test "neither a string nor iodata" do
      assert_raise ArgumentError, "trust_html/1 takes a string or iodata, got: :abc", fn ->
        trust_html(:abc)
      end
    end

    test "list that isn't iodata" do
      assert_raise ArgumentError, fn ->
        trust_html([:abc])
      end
    end

    test "imported into components" do
      assert Module3.trusted_html() == %TrustedHTML{html: "<b>component</b>"}
    end

    test "imported into pages" do
      assert Module4.trusted_html() == %TrustedHTML{html: "<b>page</b>"}
    end
  end

  # Compiles a module under the given name whose body holds the given code, with the sigil imported.
  defp compile_template(name, code) do
    Code.compile_string("""
    defmodule Hologram.Test.Fixtures.Template.#{name} do
      import Hologram.Template
      #{code}
    end
    """)
  end

  defp element_lookup_message(name) do
    "JS.element/1 can't be called in the template of Hologram.Test.Fixtures.Template.#{name} - " <>
      "a template also renders on the server, and in the browser the element it names may not exist yet, " <>
      "so pass the ref itself, like scroll_ref={:feed}, and look the element up in an action"
  end
end
