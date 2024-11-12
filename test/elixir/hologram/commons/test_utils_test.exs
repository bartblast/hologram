defmodule Hologram.Commons.TestUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.TestUtils

  test "build_argument_error_msg/2" do
    assert build_argument_error_msg(2, "my blame") === """
           errors were found at the given arguments:

             * 2nd argument: my blame
           """
  end

  test "wrap_term/1" do
    assert wrap_term(:abc) == :abc
  end
end
