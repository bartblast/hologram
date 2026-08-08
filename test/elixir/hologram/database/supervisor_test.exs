defmodule Hologram.Database.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.Supervisor

  alias Hologram.Database
  alias Hologram.Database.QueryCache

  test "init/1" do
    assert init(nil) ==
             {:ok,
              {%{strategy: :rest_for_one, intensity: 3, period: 5, auto_shutdown: :never},
               [
                 %{id: Database, start: {Database, :start_link, [[]]}, type: :supervisor},
                 %{id: QueryCache, start: {QueryCache, :start_link, [[]]}}
               ]}}
  end
end
