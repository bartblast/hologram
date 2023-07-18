defmodule Hologram.Runtime.PageTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Test.Fixtures.Runtime.Page.Module1
  alias Hologram.Test.Fixtures.Runtime.Page.Module2

  test "__is_hologram_page__/0" do
    assert Module1.__is_hologram_page__()
  end

  test "__hologram_layout__/0" do
    assert Module1.__hologram_layout__() == MyLayout
  end

  test "__hologram_route__/0" do
    assert Module1.__hologram_route__() == "/my_path"
  end

  describe "init/2" do
    test "default" do
      assert Module1.init(:arg_1, :arg_2) == %{}
    end

    test "overridden" do
      assert Module2.init(:arg_1, :arg_2) == :overridden
    end
  end
end
