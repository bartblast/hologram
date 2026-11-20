defmodule HologramSyncTests.Helpers do
  @moduledoc false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.Test.FeatureHelpers
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Card

  @doc """
  Truncates every entity table of the app, the join table behind a card's tags and the role grant
  store, in one statement - PostgreSQL refuses to truncate a table another one references without
  it.

  The simulated clients sync the whole app, so a row an earlier test left in any of them would
  arrive in the next test's fill. The truncate reaches no log, so it waits first for every sync
  evaluator an earlier test left running to end, or one would go on serving the rows from before.
  """
  @spec truncate_tables() :: :ok
  def truncate_tables do
    FeatureHelpers.await_evaluator_drain()

    tables =
      Model.types()
      |> Enum.concat([RoleGrant])
      |> Enum.map(&DB.table_name/1)
      |> Enum.concat([DB.join_table_name(Card, :tags)])
      |> Enum.map_join(", ", &~s("hologram_data"."#{&1}"))

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end
end
