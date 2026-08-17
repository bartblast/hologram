defmodule Hologram.Sync.PlaceTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Place

  alias Hologram.Sync.Place

  defp start_place! do
    start_supervised!(Place)
  end

  describe "get/1" do
    test "remembers nothing before the first round" do
      assert get(start_place!()) == nil
    end
  end

  describe "put/2" do
    test "records how far the log has been read" do
      place = start_place!()

      :ok = put(place, 4_216)

      assert get(place) == 4_216
    end

    test "keeps only where reading got to last" do
      place = start_place!()

      :ok = put(place, 4_216)
      :ok = put(place, 4_217)

      assert get(place) == 4_217
    end
  end

  # The name a dispatcher is handed to resume from is the module's own, so registering under it is
  # what makes the holder findable rather than a convenience.
  describe "start_link/1" do
    test "answers to the module's own name" do
      place = start_place!()

      assert Process.whereis(Place) == place
    end
  end
end
