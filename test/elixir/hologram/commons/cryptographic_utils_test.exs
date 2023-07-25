defmodule Hologram.Commons.CryptographicUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.CryptographicUtils

  describe "digest/3" do
    test "SHA256 algorithm with hex output format" do
      assert digest("Hologram", :sha256, :hex) ==
               "ddff15a2da596882cfd545132004c8e7355e457517a3874f4853cc6ff1110c2e"
    end

    test "MD5 algorithm with binary output format" do
      assert digest("Hologram", :md5, :binary) ==
               <<8, 132, 19, 120, 33, 216, 230, 154, 210, 235, 180, 219, 210, 116, 125, 36>>
    end
  end
end
