defmodule Hologram.Database.SchemaReconcilerTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Database.SchemaReconciler

  @marker %{
    otp_app: "hologram",
    env: "test",
    managed_by: "reconciliation",
    hologram_version: "0.5.0",
    last_reconciled_at: ~U[2026-07-20 12:30:00.000000Z]
  }

  describe "create_system_tables/0" do
    test "creates the marker and registry tables" do
      assert create_system_tables() == :ok

      assert read_marker() == nil
    end
  end

  describe "read_marker/0" do
    test "returns nil when no marker has been written" do
      create_system_tables()

      assert read_marker() == nil
    end

    test "returns the written marker" do
      create_system_tables()
      write_marker(@marker)

      assert read_marker() == @marker
    end
  end

  describe "write_marker/1" do
    test "replaces the previous marker row" do
      create_system_tables()
      write_marker(@marker)
      write_marker(%{@marker | env: "dev", last_reconciled_at: ~U[2026-07-20 13:00:00.000000Z]})

      assert read_marker() == %{
               @marker
               | env: "dev",
                 last_reconciled_at: ~U[2026-07-20 13:00:00.000000Z]
             }
    end
  end
end
