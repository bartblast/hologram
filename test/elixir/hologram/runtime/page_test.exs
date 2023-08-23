defmodule Hologram.Runtime.PageTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Component
  alias Hologram.Test.Fixtures.Runtime.Page.Module1
  alias Hologram.Test.Fixtures.Runtime.Page.Module2
  alias Hologram.Test.Fixtures.Runtime.Page.Module3
  alias Hologram.Test.Fixtures.Runtime.Page.Module4
  alias Hologram.Test.Fixtures.Runtime.Page.Module5

  test "__is_hologram_page__/0" do
    assert Module1.__is_hologram_page__()
  end

  test "__hologram_layout_module__/0" do
    assert Module1.__hologram_layout_module__() == Module4
  end

  describe "__hologram_layout_props__/0" do
    test "default" do
      assert Module1.__hologram_layout_props__() == []
    end

    test "custom" do
      assert Module3.__hologram_layout_props__() == [a: 1, b: 2]
    end
  end

  test "__hologram_route__/0" do
    assert Module1.__hologram_route__() == "/module_1"
  end

  describe "init/3" do
    test "default" do
      assert Module1.init(:params_dummy, :client_dummy, :server_dummy) ==
               {:client_dummy, :server_dummy}
    end

    test "overridden" do
      assert Module2.init(:params_dummy, build_component_client(), build_component_server()) ==
               {%Component.Client{state: %{overriden: true}}, %Component.Server{}}
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
