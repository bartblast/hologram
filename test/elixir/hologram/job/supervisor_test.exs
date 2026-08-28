defmodule Hologram.Job.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Job.Supervisor

  alias Hologram.Job.Worker

  defp child_ids do
    {:ok, {_flags, children}} = init([])

    Enum.map(children, & &1.id)
  end

  describe "init/1" do
    test "starts the connection writes are heard on, then the worker that hears them" do
      assert child_ids() == [notifications(), Worker]
    end

    test "starts the worker listening on that connection, under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {Worker, :start_link, [opts]}} =
               Enum.find(children, &(&1.id == Worker))

      assert opts[:name] == Worker
      assert opts[:notifications] == notifications()
    end

    # A worker left standing when its connection ends would keep waiting on one that is gone, which
    # nothing reports - it would fall back to its poll and simply be slower for good.
    test "restarts the worker with the connection it listens through" do
      assert {:ok, {%{strategy: :rest_for_one}, _children}} = init([])
    end
  end
end
