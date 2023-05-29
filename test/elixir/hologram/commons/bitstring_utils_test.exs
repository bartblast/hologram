defmodule Hologram.Commons.BitstringUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.BitstringUtils

  test "to_bit_list/1" do
    assert to_bit_list(<<0b101010101010::12>>) == [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0]
  end
end
