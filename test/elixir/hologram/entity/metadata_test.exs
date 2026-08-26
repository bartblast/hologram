defmodule Hologram.Entity.MetadataTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Entity.Metadata

  describe "inspect/2" do
    test "leaves out every field at its default" do
      assert inspect(%Metadata{}) == "#Hologram.Entity.Metadata<>"
    end

    test "shows the deltas when set" do
      assert inspect(%Metadata{attribute_deltas: %{votes: 1}}) ==
               "#Hologram.Entity.Metadata<attribute_deltas: %{votes: 1}>"
    end

    test "shows the revisions when set" do
      assert inspect(%Metadata{revisions: %{a: 3}}) ==
               "#Hologram.Entity.Metadata<revisions: %{a: 3}>"
    end

    test "shows the stamp when set" do
      assert inspect(%Metadata{stamp: 1_756_100_000_123_004}) ==
               "#Hologram.Entity.Metadata<stamp: 1756100000123004>"
    end
  end
end
