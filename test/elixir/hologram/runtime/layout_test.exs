defmodule Hologram.Runtime.LayoutTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Layout

  alias Hologram.Component
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Runtime.Layout.Module1
  alias Hologram.Test.Fixtures.Runtime.Layout.Module2
  alias Hologram.Test.Fixtures.Runtime.Layout.Module3
  alias Hologram.Test.Fixtures.Runtime.Layout.Module4

  test "__is_hologram_layout__/0" do
    assert Module1.__is_hologram_layout__()
  end

  test "__props__/0" do
    assert Module4.__props__() == [{:b, :integer, [opt_1: 111, opt_2: 222]}, {:a, :string, []}]
  end

  describe "init/3" do
    test "default" do
      assert Module1.init(:props_dummy, :component_dummy, :server_dummy) ==
               {:component_dummy, :server_dummy}
    end

    test "overridden" do
      assert Module2.init(:props_dummy, build_component_struct(), build_server_struct()) ==
               {%Component{state: %{overriden: true}}, %Server{}}
    end
  end

  describe "template/0" do
    test "function" do
      assert Module1.template().(%{}) == [text: "Module1 template"]
    end

    test "file (colocated)" do
      assert Module3.template().(%{}) == [text: "Module3 template"]
    end
  end
end
