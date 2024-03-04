defmodule Hologram.PageTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Component
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Page.Module1
  alias Hologram.Test.Fixtures.Page.Module2
  alias Hologram.Test.Fixtures.Page.Module3
  alias Hologram.Test.Fixtures.Page.Module4
  alias Hologram.Test.Fixtures.Page.Module5

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
