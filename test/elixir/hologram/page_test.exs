defmodule Hologram.PageTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Page

  alias Hologram.Component
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Page.Module1
  alias Hologram.Test.Fixtures.Page.Module17
  alias Hologram.Test.Fixtures.Page.Module2
  alias Hologram.Test.Fixtures.Page.Module3
  alias Hologram.Test.Fixtures.Page.Module4
  alias Hologram.Test.Fixtures.Page.Module5
  alias Hologram.Test.Fixtures.Page.Module6
  alias Hologram.Test.Fixtures.Page.Module7
  alias Hologram.Test.Fixtures.Page.Module8

  describe "__derived__/0" do
    test "lists the derived fields, reading params and state" do
      assert Module17.__derived__() == [
               %{
                 args: [:project_id, :page_size],
                 function: &Module17.__derived_label__/2,
                 name: :label,
                 reads_state: true,
                 type: :string
               }
             ]
    end

    test "lists no derived fields for a page declaring none" do
      assert Module1.__derived__() == []
    end
  end

  test "__is_hologram_page__/0" do
    assert Module1.__is_hologram_page__()
  end

  test "__layout_module__/0" do
    assert Module1.__layout_module__() == Module4
  end

  describe "__layout_props__/0" do
    test "default" do
      assert Module1.__layout_props__() == []
    end

    test "custom" do
      assert Module3.__layout_props__() == [a: 1, b: 2]
    end
  end

  test "__params__/0" do
    assert Module7.__params__() == [{:a, :string, []}, {:b, :integer, []}]
  end

  test "__route__/0" do
    assert Module1.__route__() == "/hologram-test-fixtures-runtime-page-module1"
  end

  test "__state__/0" do
    assert Module8.__state__() == [{:count, :integer, [default: 0]}, {:user, :map, []}]
  end

  describe "cast_params/2" do
    test "string key" do
      assert cast_params(%{"a" => :test}, Module6) == %{a: :test}
    end

    test "atom key" do
      assert cast_params(%{a: :test}, Module6) == %{a: :test}
    end

    test "string value" do
      assert cast_params(%{d: "abc"}, Module6) == %{d: "abc"}
    end

    test "atom value" do
      assert cast_params(%{a: :test}, Module6) == %{a: :test}
    end

    test "string value cast to existing atom" do
      assert cast_params(%{a: "test"}, Module6) == %{a: :test}
    end

    test "string value cast to nonexistent atom" do
      random_string = random_string()

      assert_raise Hologram.ParamError,
                   ~s/can't cast param "a" with value "#{random_string}" to atom / <>
                     ~s/in page "Hologram.Test.Fixtures.Page.Module6", / <>
                     "because it's not an already existing atom",
                   fn ->
                     cast_params(%{a: random_string}, Module6)
                   end
    end

    test "float value" do
      assert cast_params(%{b: 1.23}, Module6) == %{b: 1.23}
    end

    test "valid string representation of float value, cast to float" do
      assert cast_params(%{b: "1.23abc"}, Module6) == %{b: 1.23}
    end

    test "invalid string representation of float value" do
      expected_msg =
        ~s/can't cast param "b" with value "abc" to float / <>
          ~s/in page "Hologram.Test.Fixtures.Page.Module6"/

      assert_raise Hologram.ParamError, expected_msg, fn ->
        cast_params(%{b: "abc"}, Module6)
      end
    end

    test "integer value" do
      assert cast_params(%{c: 123}, Module6) == %{c: 123}
    end

    test "valid string representation of integer value, cast to integer" do
      assert cast_params(%{c: "123abc"}, Module6) == %{c: 123}
    end

    test "invalid string representation of integer value" do
      expected_msg =
        ~s/can't cast param "c" with value "abc" to integer / <>
          ~s/in page "Hologram.Test.Fixtures.Page.Module6"/

      assert_raise Hologram.ParamError, expected_msg, fn ->
        cast_params(%{c: "abc"}, Module6)
      end
    end

    test "value of invalid type for a string param" do
      expected_msg =
        ~s/can't cast param "d" with value 123 to string / <>
          ~s/in page "Hologram.Test.Fixtures.Page.Module6", because it's of invalid type/

      assert_raise Hologram.ParamError, expected_msg, fn ->
        cast_params(%{d: 123}, Module6)
      end
    end

    test "multiple params" do
      assert cast_params(%{"a" => :test, c: "123"}, Module6) == %{a: :test, c: 123}
    end

    test "extraneous string key param" do
      assert_raise Hologram.ParamError,
                   ~s/page "Hologram.Test.Fixtures.Page.Module6" doesn't expect "x" param/,
                   fn ->
                     cast_params(%{"x" => 123}, Module6)
                   end
    end

    test "extraneous atom key param" do
      assert_raise Hologram.ParamError,
                   ~s/page "Hologram.Test.Fixtures.Page.Module6" doesn't expect "x" param/,
                   fn ->
                     cast_params(%{x: 123}, Module6)
                   end
    end
  end

  describe "derived/3" do
    test "raises on a head naming what is no field" do
      expected_msg =
        "nofile:10: total is not a field of Hologram.Test.Fixtures.Page.DerivedUnknownName - the arguments of derived field :double's function name the fields it reads: b"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.DerivedUnknownName do
          use Hologram.Page

          param :b, :integer

          route "/hologram-test-fixtures-page-derived-unknown-name/:b"

          layout Hologram.Test.Fixtures.LayoutFixture

          derived :double, :integer, fn total -> total * 2 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a name a param declares" do
      expected_msg =
        "nofile:10: derived field :b in Hologram.Test.Fixtures.Page.DerivedParamName has the same name as a param, which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.DerivedParamName do
          use Hologram.Page

          param :b, :integer

          route "/hologram-test-fixtures-page-derived-param-name/:b"

          layout Hologram.Test.Fixtures.LayoutFixture

          derived :b, :integer, fn -> 1 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on the name of the layout's cid prop" do
      expected_msg =
        "nofile:8: derived field :cid in Hologram.Test.Fixtures.Page.DerivedCidName has the same name as the layout's cid prop, which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.DerivedCidName do
          use Hologram.Page

          route "/hologram-test-fixtures-page-derived-cid-name"

          layout Hologram.Test.Fixtures.LayoutFixture

          derived :cid, :string, fn -> "x" end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a name a state entry declares" do
      expected_msg =
        "nofile:10: derived field :size in Hologram.Test.Fixtures.Page.DerivedStateName has the same name as a state entry, which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.DerivedStateName do
          use Hologram.Page

          route "/hologram-test-fixtures-page-derived-state-name"

          layout Hologram.Test.Fixtures.LayoutFixture

          state :size, :integer

          derived :size, :integer, fn -> 1 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises on a body reading a param its head doesn't name" do
      expected_msg =
        "nofile:10: b is a param of Hologram.Test.Fixtures.Page.DerivedUnnamedParam, which derived field :double's function doesn't name - add it to the head to read it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.DerivedUnnamedParam do
          use Hologram.Page

          param :b, :integer

          route "/hologram-test-fixtures-page-derived-unnamed-param/:b"

          layout Hologram.Test.Fixtures.LayoutFixture

          derived :double, :integer, fn -> b * 2 end

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end
  end

  describe "init/3" do
    test "default" do
      assert Module1.init(:params_dummy, :component_dummy, :server_dummy) ==
               {:component_dummy, :server_dummy}
    end

    test "overridden" do
      assert Module2.init(:params_dummy, build_component_struct(), build_server_struct()) ==
               {%Component{state: %{overriden: true}}, %Server{}}
    end
  end

  describe "param/3" do
    test "raises when any option is given" do
      expected_error_msg =
        ~s/params don't support options yet, got :default for param "b" in Hologram.Test.Fixtures.Page.ParamOpt/

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.ParamOpt do
          use Hologram.Page

          param :b, :integer, default: 1

          route "/hologram-test-fixtures-page-param-opt/:b"

          layout Hologram.Test.Fixtures.LayoutFixture

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "raises when the options are a literal that is not a list" do
      expected_error_msg =
        ~s/the options for param "b" in Hologram.Test.Fixtures.Page.NonListParamOpts / <>
          "must be a keyword list, got: :default"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.NonListParamOpts do
          use Hologram.Page

          param :b, :integer, :default

          route "/hologram-test-fixtures-page-non-list-param-opts/:b"

          layout Hologram.Test.Fixtures.LayoutFixture

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end

    test "doesn't raise when the options are not a literal keyword list" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.NonLiteralParamOpts do
          use Hologram.Page

          @my_opts []

          param :b, :integer, @my_opts

          route "/hologram-test-fixtures-page-non-literal-param-opts/:b"

          layout Hologram.Test.Fixtures.LayoutFixture

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__params__() == [{:b, :integer, []}]
    end
  end

  describe "state/3" do
    test "accepts a param declared after a state entry with another name" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.StateBeforeParam do
          use Hologram.Page

          state :count, :integer, default: 0

          param :id, :integer

          route "/hologram-test-fixtures-page-state-before-param/:id"

          layout Hologram.Test.Fixtures.LayoutFixture

          def template do
            ~HOLO""
          end
        end
        """)

      assert module.__params__() == [{:id, :integer, []}]
      assert module.__state__() == [{:count, :integer, [default: 0]}]
    end

    test "raises at the state entry when it has the same name as a param declared before it" do
      code = """
      defmodule Hologram.Test.Fixtures.Page.StateClashLineAfterParam do
        use Hologram.Page

        param :id, :integer

        state :id, :integer, default: 0

        route "/hologram-test-fixtures-page-state-clash-line-after-param/:id"

        layout Hologram.Test.Fixtures.LayoutFixture

        def template do
          ~HOLO""
        end
      end
      """

      expected_error_msg =
        ~s/state "id" in Hologram.Test.Fixtures.Page.StateClashLineAfterParam has the same name as a param, / <>
          "which it would shadow - give them different names"

      assert compile_error_at(code) == {expected_error_msg, 6}
    end

    test "raises at the param when it has the same name as a state entry declared before it" do
      code = """
      defmodule Hologram.Test.Fixtures.Page.StateClashLineBeforeParam do
        use Hologram.Page

        state :id, :integer, default: 0

        param :id, :integer

        route "/hologram-test-fixtures-page-state-clash-line-before-param/:id"

        layout Hologram.Test.Fixtures.LayoutFixture

        def template do
          ~HOLO""
        end
      end
      """

      expected_error_msg =
        ~s/state "id" in Hologram.Test.Fixtures.Page.StateClashLineBeforeParam has the same name as a param, / <>
          "which it would shadow - give them different names"

      assert compile_error_at(code) == {expected_error_msg, 6}
    end

    test "raises when an entry is named cid" do
      expected_error_msg =
        ~s/state "cid" in Hologram.Test.Fixtures.Page.StateNamedCid has the same name as the layout's cid prop, / <>
          "which it would shadow - give them different names"

      assert_error Hologram.CompileError, expected_error_msg, fn ->
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.Page.StateNamedCid do
          use Hologram.Page

          state :cid, :string, default: "my_cid"

          route "/hologram-test-fixtures-page-state-named-cid"

          layout Hologram.Test.Fixtures.LayoutFixture

          def template do
            ~HOLO""
          end
        end
        """)
      end
    end
  end

  describe "template/0" do
    test "function" do
      assert Module1.template().(%{}) == [text: "Module1 template"]
    end

    test "file (colocated)" do
      result = Module5.template().(%{})

      assert [
               {:text, text},
               {:component, Hologram.UI.Link,
                [{"to", [expression: {Hologram.Test.Fixtures.Page.Module2}]}], [text: "Module2"]}
             ] = result

      assert normalize_newlines(text) == "Module5 template\n"
    end
  end
end
