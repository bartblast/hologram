defmodule HologramSyncTests.Consistency.Plan do
  @moduledoc false

  # A randomized run worked out in full from a seed before anything runs: the data written first,
  # each writer's transactions and the holds between their operations, and each client's schedule
  # of cuts and reconnects. Ids come from the seed too, so one seed always gives the same plan - a
  # replay gives the same plan, not the same interleaving, which the run can't fix.
  #
  # Operations are picked against the state the plan leaves so far, taking the writers'
  # transactions in turn. At run time the writers go at once, so a transaction can meet a state
  # its plan didn't - a card another writer deleted - and roll back. About half the operations
  # change only values, and half change who may read what.
  #
  # Worked out in a process of its own, whose random state the seed sets and nothing else draws
  # from, and which keeps the counters behind ids and values.

  import Hologram.Query, only: [add_relationship: 3, delete_relationship: 3]
  import HologramSyncTests.Helpers, only: [create!: 2]

  alias Hologram.Auth
  alias Hologram.DB
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Notice
  alias HologramSyncTests.Entities.NoticeBlock
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag
  alias HologramSyncTests.Entities.User

  @default_steps 60

  @writers 3

  # How many of each row the data written first has.
  @seed_counts %{boards: 5, cards: 15, notices: 3, spaces: 3, tags: 4, users: 3}

  # How each kind of operation is weighted: the first group changes who may read what, the second
  # only values.
  @access_ops [
    add_member: 3,
    archive_board: 2,
    block: 2,
    delete_card: 2,
    grant_viewer: 2,
    grant_wide: 1,
    move_board: 2,
    move_card: 2,
    remove_member: 3,
    revoke_viewer: 2,
    revoke_wide: 1,
    unblock: 2
  ]

  @value_ops [
    create_card: 3,
    rename_board: 2,
    rename_notice: 2,
    rename_space: 2,
    rename_tag: 2,
    retitle_card: 4,
    tag_card: 3,
    untag_card: 3
  ]

  @renames %{
    rename_board: {Board, :name},
    rename_notice: {Notice, :title},
    rename_space: {Space, :name},
    rename_tag: {Tag, :name},
    retitle_card: {Card, :title}
  }

  @typedoc """
  One operation, as data: what `apply_op/1` writes and `describe/1` spells.
  """
  @type op :: tuple

  @typedoc """
  A planned run: its seed, the operations of the data written first, each writer's transactions -
  each a list of operations with the milliseconds to hold after each, and its place in the order the
  plan picked them in - each client's user and schedule, and the state the plan expects its
  operations to leave, taken one after another in that order: the ids of each type, the space and
  user of each member and the notice and user of each block by id, each board's space and whether
  it's archived, each card's board and tags, the viewer grants on boards as `{user_id, board_id}`
  and the users with a type-wide one.

  A schedule is what a client does in order once it first connects: `{:wait, ms}`, `:cut`,
  `:connect`, `:connect_cut_mid_fill` - connect, and cut the stream right after the first deltas
  frame it carries, so the cut lands part way through a fill or a catch-up - `:await_synced`, wait
  until the client is told it holds everything, and `:await_writers`, wait until every writer has
  returned.
  """
  @type t :: %{
          clients: list(%{name: String.t(), schedule: list(term), user_id: String.t() | nil}),
          planned: map,
          seed: integer,
          seed_ops: list(op),
          writers: list(%{name: String.t(), transactions: list(map)})
        }

  @doc """
  Writes the given operation as trusted code.
  """
  @spec apply_op(op) :: any
  def apply_op({:add_member, id, space_id, user_id}) do
    create!(SpaceMember, id: id, space_id: space_id, user_id: user_id)
  end

  def apply_op({:archive_board, id, archived}), do: DB.update!(Board, id, archived: archived)

  def apply_op({:block, id, notice_id, user_id}) do
    create!(NoticeBlock, id: id, notice_id: notice_id, user_id: user_id)
  end

  def apply_op({:create_board, id, space_id, name, archived}) do
    create!(Board, archived: archived, id: id, name: name, space_id: space_id)
  end

  def apply_op({:create_card, id, board_id, title}) do
    create!(Card, board_id: board_id, id: id, title: title)
  end

  def apply_op({:create_notice, id, title}), do: create!(Notice, id: id, title: title)

  def apply_op({:create_space, id, name}), do: create!(Space, id: id, name: name)

  def apply_op({:create_tag, id, name}), do: create!(Tag, id: id, name: name)

  def apply_op({:create_user, id, name}), do: create!(User, id: id, name: name)

  def apply_op({:delete_card, id}), do: DB.delete!(Card, id)

  def apply_op({:grant_viewer, user_id, board_id}) do
    Auth.grant_role(user_id, :viewer, DB.read(Board, board_id))
  end

  def apply_op({:grant_wide, user_id}), do: Auth.grant_role(user_id, :viewer, Board)

  def apply_op({:move_board, id, space_id}), do: DB.update!(Board, id, space_id: space_id)

  def apply_op({:move_card, id, board_id}), do: DB.update!(Card, id, board_id: board_id)

  def apply_op({:remove_member, id, _space_id, _user_id}), do: DB.delete!(SpaceMember, id)

  def apply_op({:rename, type, id, field, value}), do: DB.update!(type, id, [{field, value}])

  def apply_op({:revoke_viewer, user_id, board_id}) do
    Auth.revoke_role(user_id, :viewer, DB.read(Board, board_id))
  end

  def apply_op({:revoke_wide, user_id}), do: Auth.revoke_role(user_id, :viewer, Board)

  def apply_op({:tag_card, card_id, tag_id}) do
    Card
    |> DB.read(card_id)
    |> add_relationship(:tags, tag_id)
    |> DB.update!()
  end

  def apply_op({:unblock, id, _notice_id, _user_id}), do: DB.delete!(NoticeBlock, id)

  def apply_op({:untag_card, card_id, tag_id}) do
    Card
    |> DB.read(card_id)
    |> delete_relationship(:tags, tag_id)
    |> DB.update!()
  end

  @doc """
  Returns whether the given exception, raised by an operation, is a conflict the plan expects when
  the writers go at once: the card it names gone - only cards are ever deleted - or the transaction
  picked as a deadlock's victim. Anything else an operation raises is a failure of the run, a plan
  naming a row that never existed among them.
  """
  @spec conflict?(Exception.t()) :: boolean
  def conflict?(%Postgrex.Error{postgres: %{code: :deadlock_detected}}), do: true

  # TODO: drop this once #1768 is fixed - a card deleted while another writer tags it fails on the
  # tags join table's key on the card, since the delete removes the card's edges before it locks
  # the card.
  def conflict?(%Postgrex.Error{
        postgres: %{code: :foreign_key_violation, constraint: constraint}
      }) do
    constraint == "#{DB.join_table_name(Card, :tags)}_source_id_$fk"
  end

  # A tag or an untag reading the card finds none.
  def conflict?(%Hologram.MisuseError{
        message: "add_relationship takes an entity struct, got: nil"
      }),
      do: true

  def conflict?(%Hologram.MisuseError{
        message: "delete_relationship takes an entity struct, got: nil"
      }),
      do: true

  def conflict?(%Hologram.MisuseError{message: message}) do
    String.contains?(message, "#{inspect(Card)} - no entity with id")
  end

  def conflict?(_exception), do: false

  @doc """
  Returns the given operation in words, for the trace.
  """
  @spec describe(op) :: String.t()
  def describe(op) do
    op
    |> Tuple.to_list()
    |> Enum.map_join(" ", &spell/1)
  end

  @doc """
  Returns the plan of the given seed, with the given number of writer transactions in all.
  """
  @spec generate(integer, pos_integer) :: t
  def generate(seed, steps) do
    fn ->
      :rand.seed(:exsss, seed)
      Process.put(:next_id, 0)
      Process.put(:next_value, 0)

      build(seed, steps)
    end
    |> Task.async()
    |> Task.await()
  end

  @doc """
  Returns the run's options from the given environment: `SYNC_SEED`, the seed, which defaults to
  ExUnit's; `SYNC_STEPS`, the number of writer transactions; and `SYNC_RUNS`, how many times to run
  the seed.
  """
  @spec options(%{String.t() => String.t()}) :: %{
          runs: pos_integer,
          seed: integer,
          steps: pos_integer
        }
  def options(env \\ System.get_env()) do
    %{
      runs: positive_option(env, "SYNC_RUNS", 1),
      seed: integer_option(env, "SYNC_SEED", ExUnit.configuration()[:seed]),
      steps: positive_option(env, "SYNC_STEPS", @default_steps)
    }
  end

  defp build(seed, steps) do
    {seed_ops, seeded} = seed_ops()
    {transactions, planned} = Enum.map_reduce(0..(steps - 1)//1, seeded, &transaction/2)

    writers =
      for index <- 0..(@writers - 1) do
        %{
          name: "writer #{index + 1}",
          transactions: Enum.filter(transactions, &(rem(&1.order, @writers) == index))
        }
      end

    %{
      clients: clients(planned, steps),
      planned: planned,
      seed: seed,
      seed_ops: seed_ops,
      writers: writers
    }
  end

  defp positive_option(env, name, default) do
    case integer_option(env, name, default) do
      value when value > 0 -> value
      value -> raise ArgumentError, "#{name} has to be a positive number, got: #{value}"
    end
  end

  defp integer_option(env, name, default) do
    case Map.fetch(env, name) do
      {:ok, value} -> String.to_integer(value)
      :error -> default
    end
  end

  defp spell(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp spell(other), do: to_string(other)

  # The data written first. The planned state is what the plan's operations so far leave.
  defp seed_ops do
    users = create_many(:users, &{:create_user, &1, &2}, "user")
    spaces = create_many(:spaces, &{:create_space, &1, &2}, "space")
    tags = create_many(:tags, &{:create_tag, &1, &2}, "tag")
    notices = create_many(:notices, &{:create_notice, &1, &2}, "notice")

    empty = %{
      blocks: %{},
      boards: %{},
      cards: %{},
      grants: MapSet.new(),
      members: %{},
      notices: ids(notices),
      spaces: ids(spaces),
      tags: ids(tags),
      users: ids(users),
      wide: MapSet.new()
    }

    {memberships, with_members} = Enum.flat_map_reduce(empty.users, empty, &seed_memberships/2)
    {boards, with_boards} = Enum.map_reduce(1..@seed_counts.boards, with_members, &seed_board/2)
    {cards, with_cards} = Enum.flat_map_reduce(1..@seed_counts.cards, with_boards, &seed_card/2)
    {blocks, with_blocks} = Enum.map_reduce(1..2, with_cards, &seed_block/2)
    {grants, planned} = seed_grants(with_blocks)

    ops =
      users ++ spaces ++ tags ++ notices ++ memberships ++ boards ++ cards ++ blocks ++ grants

    {ops, planned}
  end

  defp create_many(kind, op, label) do
    Enum.map(1..Map.fetch!(@seed_counts, kind), &op.(next_id(), "#{label} #{&1}"))
  end

  defp ids(ops), do: Enum.map(ops, &elem(&1, 1))

  defp seed_memberships(user_id, planned) do
    space_ids = take_random(planned.spaces, :rand.uniform(2))

    Enum.map_reduce(space_ids, planned, &add_member(&2, &1, user_id))
  end

  # The last board starts archived.
  defp seed_board(index, planned) do
    id = next_id()
    space_id = pick(planned.spaces)
    archived = index == @seed_counts.boards

    {{:create_board, id, space_id, "board #{index}", archived},
     put_in(planned, [:boards, id], %{archived: archived, space_id: space_id})}
  end

  defp seed_card(_index, planned) do
    {create, with_card} = create_card(planned, pick(board_ids(planned)))
    card_id = elem(create, 1)
    tag_ids = take_random(planned.tags, :rand.uniform(3) - 1)

    {tag_ops, tagged} = Enum.map_reduce(tag_ids, with_card, &tag(&2, card_id, &1))

    {[create | tag_ops], tagged}
  end

  defp seed_block(_index, planned) do
    {notice_id, user_id} = pick(targets(planned, :block))

    block(planned, notice_id, user_id)
  end

  defp seed_grants(planned) do
    user_id = pick(planned.users)
    board_id = pick(board_ids(planned))
    wide_user_id = pick(planned.users)

    {[{:grant_viewer, user_id, board_id}, {:grant_wide, wide_user_id}],
     %{
       planned
       | grants: MapSet.put(planned.grants, {user_id, board_id}),
         wide: MapSet.put(planned.wide, wide_user_id)
     }}
  end

  defp transaction(order, planned) do
    {ops, after_ops} =
      Enum.map_reduce(1..:rand.uniform(3), planned, fn _index, acc -> pick_op(acc) end)

    holds = Enum.map(ops, fn _op -> :rand.uniform(41) - 1 end)

    {%{holds: holds, ops: ops, order: order}, after_ops}
  end

  # Half the time an operation changing who may read what, half one changing only values - each
  # picked by weight among the kinds the planned state allows, against one of the targets it allows.
  defp pick_op(planned) do
    group = if :rand.uniform(2) == 1, do: @access_ops, else: @value_ops
    applicable = Enum.reject(group, fn {kind, _weight} -> targets(planned, kind) == [] end)
    kind = pick_weighted(applicable)

    plan_op(planned, kind, pick(targets(planned, kind)))
  end

  # What an operation of the given kind can be written against in the planned state.
  defp targets(planned, :add_member) do
    held =
      planned.members
      |> Map.values()
      |> MapSet.new()

    for space_id <- planned.spaces,
        user_id <- planned.users,
        not MapSet.member?(held, {space_id, user_id}),
        do: {space_id, user_id}
  end

  defp targets(planned, :block) do
    held =
      planned.blocks
      |> Map.values()
      |> MapSet.new()

    for notice_id <- planned.notices,
        user_id <- planned.users,
        not MapSet.member?(held, {notice_id, user_id}),
        do: {notice_id, user_id}
  end

  defp targets(planned, :grant_viewer) do
    for user_id <- planned.users,
        board_id <- board_ids(planned),
        not MapSet.member?(planned.grants, {user_id, board_id}),
        do: {user_id, board_id}
  end

  defp targets(planned, :grant_wide) do
    Enum.reject(planned.users, &MapSet.member?(planned.wide, &1))
  end

  defp targets(planned, :move_board) do
    for board_id <- board_ids(planned),
        space_id <- planned.spaces,
        space_id != planned.boards[board_id].space_id,
        do: {board_id, space_id}
  end

  defp targets(planned, :move_card) do
    for card_id <- card_ids(planned),
        board_id <- board_ids(planned),
        board_id != planned.cards[card_id].board_id,
        do: {card_id, board_id}
  end

  defp targets(planned, :remove_member), do: sorted_keys(planned.members)

  defp targets(planned, :revoke_viewer), do: Enum.sort(planned.grants)

  defp targets(planned, :revoke_wide), do: Enum.sort(planned.wide)

  defp targets(planned, :tag_card) do
    for {card_id, card} <- Enum.sort(planned.cards),
        tag_id <- planned.tags,
        not MapSet.member?(card.tags, tag_id),
        do: {card_id, tag_id}
  end

  defp targets(planned, :unblock), do: sorted_keys(planned.blocks)

  defp targets(planned, :untag_card) do
    for {card_id, card} <- Enum.sort(planned.cards),
        tag_id <- Enum.sort(card.tags),
        do: {card_id, tag_id}
  end

  defp targets(planned, kind) when kind in [:archive_board, :create_card, :rename_board] do
    board_ids(planned)
  end

  defp targets(planned, kind) when kind in [:delete_card, :retitle_card], do: card_ids(planned)

  defp targets(planned, :rename_notice), do: planned.notices

  defp targets(planned, :rename_space), do: planned.spaces

  defp targets(planned, :rename_tag), do: planned.tags

  defp plan_op(planned, :add_member, {space_id, user_id}),
    do: add_member(planned, space_id, user_id)

  defp plan_op(planned, :archive_board, id) do
    archived = not planned.boards[id].archived

    {{:archive_board, id, archived}, put_in(planned, [:boards, id, :archived], archived)}
  end

  defp plan_op(planned, :block, {notice_id, user_id}), do: block(planned, notice_id, user_id)

  defp plan_op(planned, :create_card, board_id), do: create_card(planned, board_id)

  defp plan_op(planned, :delete_card, id) do
    {{:delete_card, id}, %{planned | cards: Map.delete(planned.cards, id)}}
  end

  defp plan_op(planned, :grant_viewer, {user_id, board_id} = grant) do
    {{:grant_viewer, user_id, board_id}, %{planned | grants: MapSet.put(planned.grants, grant)}}
  end

  defp plan_op(planned, :grant_wide, user_id) do
    {{:grant_wide, user_id}, %{planned | wide: MapSet.put(planned.wide, user_id)}}
  end

  defp plan_op(planned, :move_board, {id, space_id}) do
    {{:move_board, id, space_id}, put_in(planned, [:boards, id, :space_id], space_id)}
  end

  defp plan_op(planned, :move_card, {id, board_id}) do
    {{:move_card, id, board_id}, put_in(planned, [:cards, id, :board_id], board_id)}
  end

  defp plan_op(planned, :remove_member, id) do
    # The space and user ride along, so the trace names who lost what.
    {space_id, user_id} = planned.members[id]

    {{:remove_member, id, space_id, user_id},
     %{planned | members: Map.delete(planned.members, id)}}
  end

  defp plan_op(planned, :revoke_viewer, {user_id, board_id} = grant) do
    {{:revoke_viewer, user_id, board_id},
     %{planned | grants: MapSet.delete(planned.grants, grant)}}
  end

  defp plan_op(planned, :revoke_wide, user_id) do
    {{:revoke_wide, user_id}, %{planned | wide: MapSet.delete(planned.wide, user_id)}}
  end

  defp plan_op(planned, :tag_card, {card_id, tag_id}), do: tag(planned, card_id, tag_id)

  defp plan_op(planned, :unblock, id) do
    {notice_id, user_id} = planned.blocks[id]

    {{:unblock, id, notice_id, user_id}, %{planned | blocks: Map.delete(planned.blocks, id)}}
  end

  defp plan_op(planned, :untag_card, {card_id, tag_id}) do
    {{:untag_card, card_id, tag_id},
     update_in(planned, [:cards, card_id, :tags], &MapSet.delete(&1, tag_id))}
  end

  # Values carry a counter, so each write sets a value no other write sets, and a value on the wire
  # names the write behind it.
  defp plan_op(planned, rename, id) do
    {type, field} = Map.fetch!(@renames, rename)

    {{:rename, type, id, field, next_value(Atom.to_string(field))}, planned}
  end

  defp add_member(planned, space_id, user_id) do
    id = next_id()

    {{:add_member, id, space_id, user_id}, put_in(planned, [:members, id], {space_id, user_id})}
  end

  defp block(planned, notice_id, user_id) do
    id = next_id()

    {{:block, id, notice_id, user_id}, put_in(planned, [:blocks, id], {notice_id, user_id})}
  end

  defp create_card(planned, board_id) do
    id = next_id()
    card = %{board_id: board_id, tags: MapSet.new()}

    {{:create_card, id, board_id, next_value("card")}, put_in(planned, [:cards, id], card)}
  end

  defp tag(planned, card_id, tag_id) do
    {{:tag_card, card_id, tag_id},
     update_in(planned, [:cards, card_id, :tags], &MapSet.put(&1, tag_id))}
  end

  defp board_ids(planned), do: sorted_keys(planned.boards)

  defp card_ids(planned), do: sorted_keys(planned.cards)

  defp sorted_keys(map) do
    map
    |> Map.keys()
    |> Enum.sort()
  end

  # Each client: a tab per user and an anonymous one that stay connected the whole run, a second tab
  # for two users and an anonymous one that are cut often. Some reconnects cut again on the first
  # frame, so the cut lands part way through a fill or a catch-up. The second user's second tab is
  # cut once it holds everything and stays away until the writers are done, so its gap is most of
  # the run's writes, past the sync app's `gap_limit`, and it's sent everything again. The flaky
  # tabs' absences grow with the steps, so a longer run cuts as often as a short one.
  defp clients(planned, steps) do
    [first_user, second_user | _users] = planned.users

    specs =
      Enum.map(planned.users, &{"tab of #{&1}", &1, :steady}) ++
        [
          {"second tab of #{first_user}", first_user, :flaky},
          {"second tab of #{second_user}", second_user, :away_long},
          {"anonymous tab", nil, :steady},
          {"flaky anonymous tab", nil, :flaky}
        ]

    Enum.map(specs, fn {name, user_id, kind} ->
      %{name: name, schedule: schedule(kind, steps), user_id: user_id}
    end)
  end

  defp schedule(:steady, _steps), do: []

  defp schedule(:flaky, steps) do
    absences = max(div(steps, 20), 1) + :rand.uniform(4) - 1

    Enum.flat_map(1..absences, fn _index -> absence(:rand.uniform(300)) end)
  end

  defp schedule(:away_long, _steps) do
    [:await_synced, :cut, :await_writers, :connect]
  end

  defp absence(away_ms) do
    reconnect =
      if :rand.uniform(3) == 1,
        do: [:connect_cut_mid_fill, {:wait, 50}, :connect],
        else: [:connect]

    [{:wait, :rand.uniform(400)}, :cut, {:wait, away_ms} | reconnect]
  end

  # A UUIDv7 as `Hologram.Entity.generate_id/0` lays one out, its time a fixed base plus a counter,
  # so ids sort in the order the plan made them.
  defp next_id do
    count = Process.get(:next_id)
    Process.put(:next_id, count + 1)

    random_a = :rand.uniform(4_096) - 1
    random_b = :rand.uniform(4_611_686_018_427_387_904) - 1
    uuid = <<1_800_000_000_000 + count::48, 7::4, random_a::12, 2::2, random_b::62>>

    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> = Base.encode16(uuid, case: :lower)

    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  defp next_value(label) do
    count = Process.get(:next_value)
    Process.put(:next_value, count + 1)

    "#{label} #{count}"
  end

  defp pick(list), do: Enum.at(list, :rand.uniform(length(list)) - 1)

  defp pick_weighted(weighted) do
    roll =
      weighted
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()
      |> :rand.uniform()

    Enum.reduce_while(weighted, roll, fn {kind, weight}, left ->
      if left <= weight, do: {:halt, kind}, else: {:cont, left - weight}
    end)
  end

  defp take_random(list, count) do
    list
    |> Enum.shuffle()
    |> Enum.take(count)
  end
end
