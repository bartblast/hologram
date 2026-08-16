defmodule Hologram.Sync.CursorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Cursor

  describe "encode/2" do
    test "names a place in the log" do
      assert encode(1_234, 56) == Base.url_encode64("1234.56", padding: false)
    end

    test "names different places differently" do
      refute encode(1_234, 56) == encode(1_234, 57)
      refute encode(1_234, 56) == encode(1_235, 56)
    end

    test "says nothing a client could read at a glance" do
      refute encode(1_234, 56) =~ "1234"
    end
  end

  describe "decode/1" do
    test "returns the place a cursor names" do
      assert decode(encode(1_234, 56)) == {:ok, 1_234, 56}
    end

    test "returns the very first place" do
      assert decode(encode(0, 0)) == {:ok, 0, 0}
    end

    test "returns the place a transaction id far beyond 32 bits names" do
      tx = 9_000_000_000

      assert decode(encode(tx, 1)) == {:ok, tx, 1}
    end

    test "refuses a cursor that is not even base64" do
      assert decode("not a cursor") == :error
    end

    test "refuses a cursor holding something other than a place" do
      assert decode(Base.url_encode64("nonsense", padding: false)) == :error
    end

    test "refuses a cursor holding parts that are not numbers" do
      assert decode(Base.url_encode64("tx.seq", padding: false)) == :error
    end

    test "refuses a cursor holding a negative place" do
      assert decode(Base.url_encode64("-1.0", padding: false)) == :error
      assert decode(Base.url_encode64("0.-1", padding: false)) == :error
    end

    test "refuses a cursor holding a number with something after it" do
      assert decode(Base.url_encode64("1x.2", padding: false)) == :error
      assert decode(Base.url_encode64("1.2x", padding: false)) == :error
    end

    test "refuses a cursor holding more parts than a place has" do
      assert decode(Base.url_encode64("1.2.3", padding: false)) == :error
    end

    test "refuses what is not a string at all" do
      assert decode(nil) == :error
    end
  end
end
