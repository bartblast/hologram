defmodule Hologram.Commons.CryptographicUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.CryptographicUtils

  describe "digest/2" do
    test "encode as hex string" do
      assert digest("Hologram", true) ==
               "ddff15a2da596882cfd545132004c8e7355e457517a3874f4853cc6ff1110c2e"
    end

    test "encode as binary" do
      assert digest("Hologram", false) ==
               <<221, 255, 21, 162, 218, 89, 104, 130, 207, 213, 69, 19, 32, 4, 200, 231, 53, 94,
                 69, 117, 23, 163, 135, 79, 72, 83, 204, 111, 241, 17, 12, 46>>
    end
  end
end
