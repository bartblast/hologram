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

  describe "short_digest/2" do
    test "keeps the given number of bytes of the SHA-256, spelled as lowercase hex" do
      assert short_digest("Hologram", 16) == "ddff15a2da596882cfd545132004c8e7"
    end

    test "spells each kept byte as two characters" do
      assert short_digest("Hologram", 4) == "ddff15a2"
    end

    test "keeps the whole digest at 32 bytes" do
      assert short_digest("Hologram", 32) == digest("Hologram", :sha256, :hex)
    end

    test "raises for a width beyond the 32 bytes a SHA-256 holds" do
      assert_raise FunctionClauseError, fn -> short_digest("Hologram", 33) end
    end
  end
end
