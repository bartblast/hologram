defmodule Hologram.Server.StatusTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Server.Status

  describe "code/1" do
    test "returns the numeric code for a known atom alias" do
      assert code(:not_found) == 404
    end

    test "raises ArgumentError for an unknown atom alias" do
      assert_error ArgumentError, "Unknown status alias: :bogus", fn ->
        code(:bogus)
      end
    end
  end
end
