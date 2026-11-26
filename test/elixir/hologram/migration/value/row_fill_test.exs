defmodule Hologram.Migration.Value.RowFillTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Value.RowFill

  @filled [
    {"row-1", "02wLIRxqmq3AUo6vl2OW37", "encoded"},
    {"row-2", "02wLIRxqmq3AUo6vl2OksX", "encoded"},
    {"row-3", "02wLIRxqmq3AUo6vl2OW39", "encoded"}
  ]

  describe "missing_target/3" do
    test "names the row holding the key the detail gives" do
      detail =
        ~s|Key (owner_id)=(018f0000-0000-7000-8000-00000000dead) is not present in table "user".|

      assert missing_target(detail, @filled, MyApp.User) ==
               "writes 02wLIRxqmq3AUo6vl2OksX on row row-2, which no MyApp.User " <>
                 "holds - change the fn or add that row"
    end

    test "names the page when the detail doesn't tell the row" do
      assert missing_target(nil, @filled, MyApp.User) ==
               "writes an id on a row that can't be identified in the page of rows from " <>
                 "row-1 to row-3, which no MyApp.User holds - change the fn or add that row"
    end

    test "names the only row of a page when the detail doesn't tell it" do
      filled = [hd(@filled)]

      assert missing_target(nil, filled, MyApp.User) ==
               "writes an id on row row-1, which no MyApp.User holds - change the fn or add " <>
                 "that row"
    end
  end
end
