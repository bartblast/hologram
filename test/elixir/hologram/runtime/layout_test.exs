defmodule Hologram.Runtime.LayoutTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Layout
  alias Hologram.Test.Fixtures.Runtime.Layout.Module1

  test "__is_hologram_layout__/0" do
    assert Module1.__is_hologram_layout__()
  end
end
