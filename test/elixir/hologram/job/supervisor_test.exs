defmodule Hologram.Job.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Job.Supervisor

  alias Hologram.Job.RunLock
  alias Hologram.Job.Worker

  defp child_ids do
    {:ok, {_flags, children}} = init([])

    Enum.map(children, & &1.id)
  end

  describe "init/1" do
    test "starts the listener, then the run lock connection, then the worker" do
      assert child_ids() == [notifications(), RunLock, Worker]
    end

    test "starts the run lock connection under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {RunLock, :start_link, [opts]}} = Enum.find(children, &(&1.id == RunLock))

      assert opts[:name] == RunLock
    end

    test "starts the worker on both connections, under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {Worker, :start_link, [opts]}} =
               Enum.find(children, &(&1.id == Worker))

      assert opts[:name] == Worker
      assert opts[:notifications] == notifications()
      assert opts[:run_lock] == RunLock
    end

    # A worker left standing when its listener ends would keep waiting on one that is gone, which
    # nothing reports - it would fall back to its poll and simply be slower for good. One left
    # standing when its lock connection ends would carry on with runs that look abandoned.
    test "restarts the worker with either connection" do
      assert {:ok, {%{strategy: :rest_for_one}, _children}} = init([])
    end
  end
end
