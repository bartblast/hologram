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

    # The log's columns have ceilings and an Elixir integer does not, so a place above them is one
    # no row could carry - and left unrefused it reaches the driver as a value it cannot encode,
    # raising on a connection that has already answered 200 instead of resyncing it.
    test "refuses a place beyond what the log's columns hold" do
      past_xid8 = Base.url_encode64("18446744073709551616.0", padding: false)
      past_bigint = Base.url_encode64("0.9223372036854775808", padding: false)

      assert decode(past_xid8) == :error
      assert decode(past_bigint) == :error
    end

    test "reads a place at the very top of what they hold" do
      topmost = Base.url_encode64("18446744073709551615.9223372036854775807", padding: false)

      assert decode(topmost) == {:ok, 18_446_744_073_709_551_615, 9_223_372_036_854_775_807}
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
