defmodule Hologram.Commons.EncoderTest do
  use Hologram.Test.UnitCase , async: true
  alias Hologram.Commons.Encoder

  describe "encode_array/1" do
    test "empty array" do
      assert Encoder.encode_array("") == "[]"
    end

    test "non-empty array" do
      assert Encoder.encode_array("test") == "[ test ]"
    end
  end
end
