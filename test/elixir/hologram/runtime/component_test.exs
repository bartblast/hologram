defmodule Hologram.Runtime.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

  alias Hologram.Component
  alias Hologram.Test.Fixtures.Runtime.Component.Module1
  alias Hologram.Test.Fixtures.Runtime.Component.Module2
  alias Hologram.Test.Fixtures.Runtime.Component.Module3

  test "__is_hologram_component__/0" do
    assert Module1.__is_hologram_component__()
  end

  describe "init/1" do
    test "default" do
      assert Module1.init(:props_dummy, :client_dummy) == :client_dummy
    end

    test "overridden" do
      assert Module2.init(:props_dummy, build_component_client()) == %Component.Client{
               state: %{overriden: true}
             }
    end
  end

  describe "init/3" do
    test "default" do
      assert Module1.init(:props_dummy, :client_dummy, :server_dummy) ==
               {:client_dummy, :server_dummy}
    end

    test "overridden" do
      assert Module2.init(:props_dummy, build_component_client(), build_component_server()) ==
               {%Component.Client{state: %{overriden: true}}, %Component.Server{}}
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
