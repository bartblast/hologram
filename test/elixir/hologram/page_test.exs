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

  test "__route__/0" do
    assert Module1.__route__() == "/hologram-test-fixtures-runtime-page-module1"
  end

  describe "cast params" do
    test "atom -> atom" do
      assert cast_params(Module6, %{a: :test}) == %{a: :test}
    end

    test "string -> atom" do
      assert cast_params(Module6, %{a: "test"}) == %{a: :test}
    end

    test "map -> atom" do
      assert_raise Hologram.ParamError,
                   ~s/can't cast param "a" with value %{y: 2, x: 1} to atom, because it's of invalid type/,
                   fn ->
                     cast_params(Module6, %{a: %{x: 1, y: 2}})
                   end
    end

    test "float -> float" do
      assert cast_params(Module6, %{b: 1.23}) == %{b: 1.23}
    end

    test "(valid) string -> float" do
      assert cast_params(Module6, %{b: "1.23abc"}) == %{b: 1.23}
    end

    test "(invalid) string -> float" do
      assert_raise Hologram.ParamError, ~s/can't cast param "b" with value "abc" to float/, fn ->
        cast_params(Module6, %{b: "abc"})
      end
    end

    test "map -> float" do
      assert_raise Hologram.ParamError,
                   ~s/can't cast param "b" with value %{y: 2, x: 1} to float, because it's of invalid type/,
                   fn ->
                     cast_params(Module6, %{b: %{x: 1, y: 2}})
                   end
    end

    test "integer -> integer" do
      assert cast_params(Module6, %{c: 123}) == %{c: 123}
    end

    test "(valid) string -> integer" do
      assert cast_params(Module6, %{c: "123abc"}) == %{c: 123}
    end

    test "(invalid) string -> integer" do
      assert_raise Hologram.ParamError,
                   ~s/can't cast param "c" with value "abc" to integer/,
                   fn ->
                     cast_params(Module6, %{c: "abc"})
                   end
    end

    test "map -> integer" do
      assert_raise Hologram.ParamError,
                   ~s/can't cast param "c" with value %{y: 2, x: 1} to integer, because it's of invalid type/,
                   fn ->
                     cast_params(Module6, %{c: %{x: 1, y: 2}})
                   end
    end

    test "string -> string" do
      assert cast_params(Module6, %{d: "abc"}) == %{d: "abc"}
    end

    test "map -> string" do
      assert_raise Hologram.ParamError,
                   ~s/can't cast param "d" with value %{y: 2, x: 1} to string, because it's of invalid type/,
                   fn ->
                     cast_params(Module6, %{d: %{x: 1, y: 2}})
                   end
    end

    test "multiple params" do
      assert cast_params(Module6, %{a: "test", c: "123"}) == %{a: :test, c: 123}
    end

    test "extraneous param" do
      assert_raise Hologram.ParamError,
                   ~s/page "Hologram.Test.Fixtures.Page.Module6" doesn't expect "x" param/,
                   fn ->
                     cast_params(Module6, %{x: 123})
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

  describe "template/0" do
    test "function" do
      assert Module1.template().(%{}) == [text: "Module1 template"]
    end

    test "file (colocated)" do
      assert Module5.template().(%{}) == [text: "Module5 template"]
    end
  end
end
