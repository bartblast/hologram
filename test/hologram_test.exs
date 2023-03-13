defmodule HologramTest do
  use ExUnit.Case
  doctest Hologram

  test "greets the world" do
    assert Hologram.hello() == :world
  end
end
