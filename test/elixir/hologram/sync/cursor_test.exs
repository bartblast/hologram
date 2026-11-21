defmodule Hologram.Sync.CursorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Cursor

  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @policy_hash "0123456789abcdef0123456789abcdef"
  @types_hash "fedcba9876543210fedcba9876543210"

  describe "encode/4" do
    test "names a place in the log under the given rules and types" do
      assert encode(1_234, 56, @policy_hash, @types_hash) ==
               "1234.56.#{@policy_hash}.#{@types_hash}"
    end

    test "names different places differently" do
      refute encode(1_234, 56, @policy_hash, @types_hash) ==
               encode(1_234, 57, @policy_hash, @types_hash)

      refute encode(1_234, 56, @policy_hash, @types_hash) ==
               encode(1_235, 56, @policy_hash, @types_hash)
    end

    test "names one place under different rules differently" do
      refute encode(1_234, 56, @policy_hash, @types_hash) ==
               encode(1_234, 56, "fedcba9876543210", @types_hash)
    end

    test "names one place with different types differently" do
      refute encode(1_234, 56, @policy_hash, @types_hash) ==
               encode(1_234, 56, @policy_hash, "0123456789abcdef")
    end
  end

  describe "decode/1" do
    test "returns the place a cursor names, the rules it was judged under and its types" do
      assert decode(encode(1_234, 56, @policy_hash, @types_hash)) ==
               {:ok, 1_234, 56, @policy_hash, @types_hash}
    end

    test "returns the very first place" do
      assert decode(encode(0, 0, @policy_hash, @types_hash)) ==
               {:ok, 0, 0, @policy_hash, @types_hash}
    end

    test "returns the place a transaction id far beyond 32 bits names" do
      tx = 9_000_000_000

      assert decode(encode(tx, 1, @policy_hash, @types_hash)) ==
               {:ok, tx, 1, @policy_hash, @types_hash}
    end

    test "refuses a cursor that is not a place at all" do
      assert decode("not a cursor") == :error
    end

    test "refuses a cursor holding something other than a place" do
      assert decode("nonsense") == :error
    end

    test "refuses a cursor holding parts that are not numbers" do
      assert decode("tx.seq.#{@policy_hash}.#{@types_hash}") == :error
    end

    test "refuses a cursor holding a negative place" do
      assert decode("-1.0.#{@policy_hash}.#{@types_hash}") == :error
      assert decode("0.-1.#{@policy_hash}.#{@types_hash}") == :error
    end

    # The log's columns have ceilings and an Elixir integer does not, so a place above them is one
    # no row could carry - and left unrefused it reaches the driver as a value it cannot encode,
    # raising on a connection that has already answered 200 instead of resyncing it.
    test "refuses a place beyond what the log's columns hold" do
      past_xid8 = "18446744073709551616.0.#{@policy_hash}.#{@types_hash}"
      past_bigint = "0.9223372036854775808.#{@policy_hash}.#{@types_hash}"

      assert decode(past_xid8) == :error
      assert decode(past_bigint) == :error
    end

    test "reads a place at the very top of what they hold" do
      topmost = "18446744073709551615.9223372036854775807.#{@policy_hash}.#{@types_hash}"

      assert decode(topmost) ==
               {:ok, 18_446_744_073_709_551_615, 9_223_372_036_854_775_807, @policy_hash,
                @types_hash}
    end

    test "refuses a cursor holding a number with something after it" do
      assert decode("1x.2.#{@policy_hash}.#{@types_hash}") == :error
      assert decode("1.2x.#{@policy_hash}.#{@types_hash}") == :error
    end

    # What a cursor written before cursors named their rules looks like.
    test "refuses a cursor naming no rules" do
      assert decode("1.2") == :error
    end

    # What a cursor written before cursors named their types looks like.
    test "refuses a cursor naming no types" do
      assert decode("1.2.#{@policy_hash}") == :error
    end

    test "refuses a cursor naming empty rules or types" do
      assert decode("1.2..#{@types_hash}") == :error
      assert decode("1.2.#{@policy_hash}.") == :error
    end

    test "refuses a cursor naming rules or types that are not a hash" do
      assert decode("1.2.XYZ.#{@types_hash}") == :error
      assert decode("1.2.#{@policy_hash}.XYZ") == :error
    end

    test "refuses a cursor naming rules or types in uppercase" do
      assert decode("1.2.ABCDEF.#{@types_hash}") == :error
      assert decode("1.2.#{@policy_hash}.ABCDEF") == :error
    end

    test "refuses a cursor holding more parts than a place, its rules and its types have" do
      assert decode("1.2.#{@policy_hash}.#{@types_hash}.3") == :error
    end

    test "refuses what is not a string at all" do
      assert decode(nil) == :error
    end
  end

  describe "types_hash/2" do
    test "hashes the types as lowercase hex" do
      assert types_hash([Module2], false) =~ ~r/\A[0-9a-f]+\z/
    end

    test "hashes different types differently" do
      refute types_hash([Module2], false) == types_hash([Module2, Module3], false)
    end

    test "hashes the same types the same whatever their order" do
      assert types_hash([Module2, Module3], false) == types_hash([Module3, Module2], false)
    end

    test "hashes the same types differently when the browser checks permissions" do
      refute types_hash([Module2], true) == types_hash([Module2], false)
    end
  end
end
