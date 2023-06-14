defmodule Hologram.Commons.IntegerUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.IntegerUtils

  test "count_digits?/1" do
    assert count_digits(123) == 3
  end
end
