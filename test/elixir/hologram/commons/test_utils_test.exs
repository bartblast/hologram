defmodule Hologram.Commons.TestUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.TestUtils

  test "wrap_term/1" do
    assert wrap_term(:abc) == :abc
  end
end
