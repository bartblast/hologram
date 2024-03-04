defmodule Hologram.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

  alias Hologram.Component
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Component.Module1
  alias Hologram.Test.Fixtures.Component.Module2
  alias Hologram.Test.Fixtures.Component.Module3
  alias Hologram.Test.Fixtures.Component.Module4

  test "__is_hologram_component__/0" do
    assert Module1.__is_hologram_component__()
  end

  test "__props__/0" do
    assert Module4.__props__() == [{:b, :integer, [opt_1: 111, opt_2: 222]}, {:a, :string, []}]
  end

  describe "init/1" do
    test "no default" do
      refute function_exported?(Module1, :init, 2)
    end

    test "implementation" do
      assert Module2.init(:props_dummy, build_component_struct()) == %Component{
               state: %{overriden: true}
             }
    end
  end

  describe "init/3" do
    test "no default" do
      refute function_exported?(Module1, :init, 3)
    end

    test "implementation" do
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