defmodule Hologram.Commons.EncoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Commons.Encoder

  describe "wrap_with_array/1" do
    test "empty data" do
      assert Encoder.wrap_with_array("") == "[]"
    end

    test "non-empty data" do
      assert Encoder.wrap_with_array("test") == "[ test ]"
    end
  end

  describe "wrap_with_object/1" do
    test "empty data" do
      assert Encoder.wrap_with_object("") == "{}"
    end

    test "non-empty data" do
      assert Encoder.wrap_with_object("test") == "{ test }"
    end
  end
end
