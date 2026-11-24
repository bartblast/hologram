defmodule Hologram.DB.SupervisorTest do
  # Not async: a test here takes down a telemetry handler every process shares.
  use Hologram.Test.BasicCase, async: false

  import Hologram.DB.Supervisor

  alias Hologram.Auth.SpawnMark
  alias Hologram.DB
  alias Hologram.DB.EctoGuard
  alias Hologram.DB.IndexBuilder
  alias Hologram.DB.QueryCache
  alias Hologram.Job
  alias Hologram.Sync

  # Sync and the jobs restart with the database they read through: rest_for_one takes them down
  # when the database goes, so no session goes on reading over a connection that no longer exists
  # and no worker goes on scanning through one.
  test "init/1" do
    assert init(nil) ==
             {:ok,
              {%{strategy: :rest_for_one, intensity: 3, period: 5, auto_shutdown: :never},
               [
                 %{id: SpawnMark, start: {SpawnMark, :start_link, [[]]}},
                 %{id: DB, start: {DB, :start_link, [[]]}, type: :supervisor},
                 %{id: QueryCache, start: {QueryCache, :start_link, [[]]}},
                 %{
                   id: Sync.Supervisor,
                   start: {Sync.Supervisor, :start_link, [[]]},
                   type: :supervisor
                 },
                 %{
                   id: Job.Supervisor,
                   start: {Job.Supervisor, :start_link, [[]]},
                   type: :supervisor
                 }
               ]}}
  end

  test "init/1 starts watching Ecto repos" do
    event = [:ecto, :repo, :init]
    id = {EctoGuard, event}
    :telemetry.detach(id)

    init(nil)

    handlers = :telemetry.list_handlers(event)

    assert Enum.any?(handlers, &(&1.id == id))
  end

  describe "children/1" do
    test "leaves the index builder out in dev and test" do
      for env <- [:dev, :test] do
        assert children(env) == [SpawnMark, DB, QueryCache, Sync.Supervisor, Job.Supervisor]
      end
    end

    # Last, so the node serves while it builds.
    test "starts the index builder last where migrations manage the database" do
      assert children(:prod) == [
               SpawnMark,
               DB,
               QueryCache,
               Sync.Supervisor,
               Job.Supervisor,
               {IndexBuilder, []}
             ]

      # Started again when an earlier child's restart takes it down, and killed outright on a stop.
      assert %{restart: :transient, shutdown: :brutal_kill} = IndexBuilder.child_spec([])
    end
  end
end
