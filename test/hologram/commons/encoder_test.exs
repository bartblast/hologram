defmodule Hologram.Commons.EncoderTest do
  use Hologram.Test.UnitCase , async: true
  alias Hologram.Commons.Encoder

  describe "wrap_with_array/1" do
    test "empty array" do
      assert Encoder.wrap_with_array("") == "[]"
    end

    test "non-empty array" do
      assert Encoder.wrap_with_array("test") == "[ test ]"
    end
  end
end
