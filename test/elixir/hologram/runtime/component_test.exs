defmodule Hologram.Runtime.ComponentTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Component

  alias Hologram.Test.Fixtures.Runtime.Component.Module1
  alias Hologram.Test.Fixtures.Runtime.Component.Module2

  test "__is_hologram_component__/0" do
    assert Module1.__is_hologram_component__()
  end

  describe "init/1" do
    test "default" do
      assert Module1.init(:arg) == %{}
    end

    test "overridden" do
      assert Module2.init(:arg) == %{overridden_1: true}
    end
  end

  describe "init/2" do
    test "default" do
      assert Module1.init(:arg_1, :arg_2) == %{}
    end

    test "overridden" do
      assert Module2.init(:arg_1, :arg_2) == %{overridden_2: true}
    end
  end
end
