defmodule HologramTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram

  test "env/0" do
    assert env() == :test
  end
end
