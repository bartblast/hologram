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
    assert Module7.__params__() == [{:a, :string, []}, {:b, :integer, [opt_1: 111, opt_2: 222]}]
  end

  test "__route__/0" do
    assert Module1.__route__() == "/hologram-test-fixtures-runtime-page-module1"
  end

  describe "cast params" do
    test "existing atom" do
      assert cast_params(Module6, %{a: "test"}) == %{a: :test}
    end

    test "non-existing atom" do
      random_string = random_string()

      assert_raise Hologram.ParamError,
                   ~s/can't cast param "a" with value "#{random_string}" to atom, because it's not an already existing atom/,
                   fn ->
                     cast_params(Module6, %{a: random_string})
                   end
    end

    test "valid float" do
      assert cast_params(Module6, %{b: "1.23abc"}) == %{b: 1.23}
    end

    test "invalid float" do
      assert_raise Hologram.ParamError, ~s/can't cast param "b" with value "abc" to float/, fn ->
        cast_params(Module6, %{b: "abc"})
      end
    end

    test "valid integer" do
      assert cast_params(Module6, %{c: "123abc"}) == %{c: 123}
    end

    test "invalid integer" do
      assert_raise Hologram.ParamError,
                   ~s/can't cast param "c" with value "abc" to integer/,
                   fn ->
                     cast_params(Module6, %{c: "abc"})
                   end
    end

    test "string" do
      assert cast_params(Module6, %{d: "abc"}) == %{d: "abc"}
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
