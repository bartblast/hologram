defmodule Hologram.PageTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Page

  alias Hologram.Component
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Page.Module1
  alias Hologram.Test.Fixtures.Page.Module2
  alias Hologram.Test.Fixtures.Page.Module3
  alias Hologram.Test.Fixtures.Page.Module4
  alias Hologram.Test.Fixtures.Page.Module5
  alias Hologram.Test.Fixtures.Page.Module6
  alias Hologram.Test.Fixtures.Page.Module7

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
