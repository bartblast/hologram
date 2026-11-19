defmodule Hologram.Sync.PoolTest do
  use Hologram.Test.BasicCase, async: false

  alias Hologram.DB.Connection
  alias Hologram.Sync.Gate
  alias Hologram.Sync.Pool

  defp application_name do
    {:ok, %Postgrex.Result{rows: [[name]]}} =
      Connection.query("SELECT current_setting('application_name')")

    name
  end

  describe "child_spec/1" do
    test "starts none when the configured size is 0" do
      put_app_env(:sync, pool_size: 0)

      assert Pool.child_spec() == nil
    end

    test "starts a pool of the configured size under the pool's name" do
      put_app_env(:sync, pool_size: 2)

      spec = Pool.child_spec()

      assert spec.id == Pool.name()
    end
  end

  describe "run/1" do
    # Opens connections of its own, so it needs a database server.
    @tag :database
    test "runs the function on the pool when it is started, telling the database who it is" do
      put_app_env(:sync, pool_size: 1)
      start_supervised!(Pool.child_spec())

      assert Pool.run(&application_name/0) == "hologram_sync"
    end

    test "runs the function as it is when no pool is started" do
      assert Pool.run(fn -> :ran end) == :ran
    end
  end

  describe "size/0" do
    test "answers the configured size" do
      put_app_env(:sync, pool_size: 3)

      assert Pool.size() == 3
    end

    # Each catch-up the gate lets in has a connection of its own.
    test "answers how many catch-ups run at once when none is configured" do
      put_app_env(:sync, catchups_at_once: 6)

      sync = Application.get_env(:hologram, :sync)
      Application.put_env(:hologram, :sync, Keyword.delete(sync, :pool_size))

      assert Pool.size() == Gate.catchups_at_once()
      assert Pool.size() == 6
    end

    test "raises for anything but a non-negative integer" do
      put_app_env(:sync, pool_size: -1)

      assert_raise ArgumentError, ~r/expects a non-negative integer, got: -1/, fn ->
        Pool.size()
      end
    end
  end

  describe "Hologram.Sync.Supervisor" do
    # The sessions read through it, so they go when it is replaced.
    test "starts the pool before the gate and the sessions when it opens any connection" do
      put_app_env(:sync, pool_size: 2)

      {:ok, {_flags, children}} = Hologram.Sync.Supervisor.init([])
      ids = Enum.map(children, & &1.id)

      assert Enum.find_index(ids, &(&1 == Pool.name())) < Enum.find_index(ids, &(&1 == Gate))
    end
  end
end
