defmodule Hologram.Runtime.PageTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Test.Fixtures.Runtime.Page.Module1
  alias Hologram.Test.Fixtures.Runtime.Page.Module2
  alias Hologram.Test.Fixtures.Runtime.Page.Module3

  test "__is_hologram_page__/0" do
    assert Module1.__is_hologram_page__()
  end

  test "__hologram_layout_module__/0" do
    assert Module1.__hologram_layout_module__() == MyLayout
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
    assert Module1.__hologram_route__() == "/my_path"
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
