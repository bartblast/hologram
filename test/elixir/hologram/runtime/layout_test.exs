defmodule Hologram.Runtime.LayoutTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Layout

  alias Hologram.Test.Fixtures.Runtime.Layout.Module1
  alias Hologram.Test.Fixtures.Runtime.Layout.Module2

  test "__is_hologram_layout__/0" do
    assert Module1.__is_hologram_layout__()
  end

  describe "init/2" do
    test "default" do
      assert Module1.init(:arg_1, :arg_2) == %{}
    end

    test "overridden" do
      assert Module2.init(:arg_1, :arg_2) == %{overridden: true}
    end
  end
end
