defmodule Hologram.DB.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Supervisor

  alias Hologram.DB
  alias Hologram.DB.QueryCache

  test "init/1" do
    assert init(nil) ==
             {:ok,
              {%{strategy: :rest_for_one, intensity: 3, period: 5, auto_shutdown: :never},
               [
                 %{id: DB, start: {DB, :start_link, [[]]}, type: :supervisor},
                 %{id: QueryCache, start: {QueryCache, :start_link, [[]]}}
               ]}}
  end
end
