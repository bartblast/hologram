defmodule Hologram.DB.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Supervisor

  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.Sync

  # Sync restarts with the database it reads through: rest_for_one takes it down when the
  # database goes, so no evaluator keeps rows read over a connection that no longer exists.
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
                 }
               ]}}
  end
end
