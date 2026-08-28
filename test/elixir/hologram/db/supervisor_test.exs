defmodule Hologram.DB.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Supervisor

  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.Job
  alias Hologram.Sync

  # Sync and the jobs restart with the database they read through: rest_for_one takes them down
  # when the database goes, so no evaluator keeps rows read over a connection that no longer exists
  # and no worker goes on scanning through one.
  test "init/1" do
    assert init(nil) ==
             {:ok,
              {%{strategy: :rest_for_one, intensity: 3, period: 5, auto_shutdown: :never},
               [
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
end
