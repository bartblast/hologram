defmodule HologramSyncTests.Consistency.PlanTest do
  # async: false - a test truncates the shared tables.
  use HologramSyncTests.TestCase, async: false

  import HologramSyncTests.Helpers

  alias Hologram.DB
  alias HologramSyncTests.Consistency.History
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Consistency.Plan
  alias HologramSyncTests.Consistency.Writer
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Notice
  alias HologramSyncTests.Entities.NoticeBlock
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag
  alias HologramSyncTests.Entities.User

  test "a seed gives the same plan every time, and another seed another plan" do
    assert Plan.generate(1, 60) == Plan.generate(1, 60)
    assert Plan.generate(1, 60) != Plan.generate(2, 60)
  end

  test "spreads the transactions over the writers in the order the plan picked them" do
    plan = Plan.generate(3, 60)

    orders =
      plan.writers
      |> Enum.flat_map(& &1.transactions)
      |> Enum.map(& &1.order)
      |> Enum.sort()

    assert orders == Enum.to_list(0..59)
    assert Enum.all?(plan.writers, &(length(&1.transactions) == 20))
  end

  test "changes who may read what and values about half and half" do
    kinds =
      for seed <- 1..5,
          writer <- Plan.generate(seed, 60).writers,
          transaction <- writer.transactions,
          op <- transaction.ops,
          do: elem(op, 0)

    value_kinds = [:create_card, :rename, :tag_card, :untag_card]
    value_share = Enum.count(kinds, &(&1 in value_kinds)) / length(kinds)

    assert value_share > 0.35 and value_share < 0.65
  end

  test "keeps a tab per user and an anonymous one connected and cuts the others" do
    plan = Plan.generate(4, 60)
    {steady, cut} = Enum.split_with(plan.clients, &(&1.schedule == []))

    assert length(plan.clients) == 7
    assert Enum.count(steady, &is_nil(&1.user_id)) == 1

    assert steady_users(steady) == planned_users(plan)

    assert length(cut) == 3
    assert Enum.all?(cut, &(:cut in &1.schedule))
    assert Enum.any?(cut, &(:await_writers in &1.schedule))
  end

  test "cuts some reconnects on their first frame" do
    steps =
      for seed <- 1..5,
          client <- Plan.generate(seed, 60).clients,
          step <- client.schedule,
          do: step

    assert :connect_cut_mid_fill in steps
  end

  # Taken one after another in the order the plan picked them, every operation is one the state
  # before it allows - so a transaction rolls back at run time only for meeting another's write.
  test "every planned operation can be written in the state the plan leaves before it" do
    for seed <- 1..3 do
      truncate_tables()
      history = start_supervised!(History, id: {:history, seed})
      plan = Plan.generate(seed, 60)

      assert {:committed, _seed} = Writer.commit(history, :seed, writes(plan.seed_ops))

      transactions =
        plan.writers
        |> Enum.flat_map(& &1.transactions)
        |> Enum.sort_by(& &1.order)

      Enum.each(transactions, fn transaction ->
        assert {:committed, _entry} = Writer.commit(history, :replay, writes(transaction.ops))
      end)

      assert History.aborted(history) == []

      state = Model.snapshot()

      assert planned_view(state) == plan.planned

      assert written_values(state) ==
               planned_values(plan.seed_ops ++ Enum.flat_map(transactions, & &1.ops))
    end
  end

  test "reads the run's options from the environment" do
    assert Plan.options(%{"SYNC_RUNS" => "2", "SYNC_SEED" => "5", "SYNC_STEPS" => "7"}) ==
             %{runs: 2, seed: 5, steps: 7}

    assert Plan.options(%{}) == %{runs: 1, seed: ExUnit.configuration()[:seed], steps: 60}
  end

  test "takes a card gone and a deadlock as conflicts, and nothing else" do
    assert Plan.conflict?(%Hologram.MisuseError{
             message: "cannot update HologramSyncTests.Entities.Card - no entity with id \"c\""
           })

    assert Plan.conflict?(%Hologram.MisuseError{
             message: "add_relationship takes an entity struct, got: nil"
           })

    assert Plan.conflict?(%Postgrex.Error{postgres: %{code: :deadlock_detected}})

    assert Plan.conflict?(%Postgrex.Error{
             postgres: %{
               code: :foreign_key_violation,
               constraint: "#{DB.join_table_name(Card, :tags)}_source_id_$fk"
             }
           })

    refute Plan.conflict?(%Postgrex.Error{
             postgres: %{code: :foreign_key_violation, constraint: "another_constraint"}
           })

    refute Plan.conflict?(%Hologram.MisuseError{
             message: "cannot update HologramSyncTests.Entities.Board - no entity with id \"b\""
           })

    refute Plan.conflict?(%Hologram.WriteError{message: "cannot create Card"})

    refute Plan.conflict?(%DBConnection.ConnectionError{message: "connection is closed"})
    refute Plan.conflict?(%Hologram.MisuseError{message: "update takes recorded changes"})
    refute Plan.conflict?(%RuntimeError{message: "boom"})
  end

  test "spells an operation in words" do
    assert Plan.describe({:rename, HologramSyncTests.Entities.Tag, "t", :name, "name 3"}) ==
             "rename HologramSyncTests.Entities.Tag t name name 3"
  end

  # Each row's name or title, as the given operations leave them taken in order.
  defp planned_values(ops) do
    Enum.reduce(ops, %{}, fn
      {:create_board, id, _space_id, name, _archived}, acc -> Map.put(acc, {Board, id}, name)
      {:create_card, id, _board_id, title}, acc -> Map.put(acc, {Card, id}, title)
      {:create_notice, id, title}, acc -> Map.put(acc, {Notice, id}, title)
      {:create_space, id, name}, acc -> Map.put(acc, {Space, id}, name)
      {:create_tag, id, name}, acc -> Map.put(acc, {Tag, id}, name)
      {:create_user, id, name}, acc -> Map.put(acc, {User, id}, name)
      {:delete_card, id}, acc -> Map.delete(acc, {Card, id})
      {:rename, type, id, _field, value}, acc -> Map.put(acc, {type, id}, value)
      _other, acc -> acc
    end)
  end

  defp written_values(state) do
    for {type, field} <- [
          {Board, "name"},
          {Card, "title"},
          {Notice, "title"},
          {Space, "name"},
          {Tag, "name"},
          {User, "name"}
        ],
        {id, row} <- state.rows[type],
        into: %{},
        do: {{type, id}, row[field]}
  end

  defp planned_users(plan) do
    for {:create_user, id, _name} <- plan.seed_ops, do: id
  end

  defp steady_users(steady) do
    for %{user_id: user_id} <- steady, user_id != nil, do: user_id
  end

  # The tables' state as the plan keeps it.
  defp planned_view(state) do
    rows = state.rows

    %{
      blocks:
        Map.new(rows[NoticeBlock], fn {id, row} -> {id, {row["notice_id"], row["user_id"]}} end),
      boards:
        Map.new(rows[Board], fn {id, row} ->
          {id, %{archived: row["archived"], space_id: row["space_id"]}}
        end),
      cards:
        Map.new(rows[Card], fn {id, row} ->
          tags = for {^id, tag_id} <- state.pairs, into: MapSet.new(), do: tag_id

          {id, %{board_id: row["board_id"], tags: tags}}
        end),
      grants:
        for(
          {user_id, board_id} <- state.grants,
          board_id != :all,
          into: MapSet.new(),
          do: {user_id, board_id}
        ),
      members:
        Map.new(rows[SpaceMember], fn {id, row} -> {id, {row["space_id"], row["user_id"]}} end),
      notices: sorted_ids(rows[Notice]),
      spaces: sorted_ids(rows[Space]),
      tags: sorted_ids(rows[Tag]),
      users: sorted_ids(rows[User]),
      wide: for({user_id, :all} <- state.grants, into: MapSet.new(), do: user_id)
    }
  end

  defp sorted_ids(rows) do
    rows
    |> Map.keys()
    |> Enum.sort()
  end

  defp writes(ops) do
    Enum.map(ops, &{Plan.describe(&1), fn -> Plan.apply_op(&1) end, 0})
  end
end
