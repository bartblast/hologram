defmodule Hologram.Migration.Value.ResolverDatabaseTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Migration.Value.Resolver

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection

  defp round_trip(value, type, sql_type) do
    {:ok, %{rows: [[read]]}} =
      Connection.query("SELECT $1::#{sql_type}", [Codec.encode(value, type)])

    Codec.decode(read, type)
  end

  describe "storable?/1" do
    test "the earliest date is one a date column holds" do
      value = ~D[-4713-11-24]

      assert storable?(value)
      assert round_trip(value, :date, "date") == value
    end

    test "the latest date is one a date column holds" do
      value = Date.new!(5_874_897, 12, 31)

      assert storable?(value)
      assert round_trip(value, :date, "date") == value
    end

    test "the earliest datetime is one a timestamp column holds" do
      value = ~U[-4713-11-24 00:00:00.000000Z]

      assert storable?(value)
      assert round_trip(value, :datetime, "timestamptz") == value
    end

    test "the latest datetime is one a timestamp column holds" do
      value = ~U[9999-12-31 23:59:59.999999Z]

      assert storable?(value)
      assert round_trip(value, :datetime, "timestamptz") == value
    end
  end
end
