defmodule HologramSyncBenchmark.Cases.Board do
  @moduledoc false

  # A shared board: every client may read every card, so every write reaches every client. Two
  # variants read the same cards with different rules: a bare `allow :read`, and a role on the
  # board the cards belong to, which every client's user holds.

  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.Entities.Card
  alias HologramSyncBenchmark.Entities.RoleCard
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Seed
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  @doc """
  Returns the board case of the given variant, `:plain` or `:roles`, for the given options.
  """
  @spec sweep_case(keyword, :plain | :roles) :: map
  def sweep_case(opts, variant) do
    variant
    |> variant()
    |> Map.merge(%{
      check!: &check!(opts, &1),
      counts: Sweep.default_counts(),
      options: [
        "#{opts[:cards]} cards read with #{variant(variant).rule}, which lets every client " <>
          "read every card, so every write reaches every client"
      ],
      seed: &seed(&1, &2, opts, variant(variant)),
      spec: &spec(&1, &2, &3, &4, opts, variant(variant))
    })
  end

  # Each timed write in a step goes to a row of its own: rounds merge, and a patch carries the
  # row's current value, so two writes to one row in one round would lose the first marker.
  defp check!(opts, _counts) do
    writes = Step.writes(opts[:rate], opts[:duration])

    if writes > opts[:cards] do
      raise ArgumentError,
            "a step makes #{writes} writes, more than the #{opts[:cards]} cards they go to"
    end

    :ok
  end

  defp seed(conn, max_count, opts, variant) do
    {_seeding, cookie_paths} =
      Seeding.board!(conn, variant.card_type, opts[:cards], &variant.prepare.(&1, max_count))

    cookie_paths
  end

  defp spec(conn, count, first_marker, cookie_paths, opts, variant) do
    every_client = Enum.to_list(0..(count - 1))

    %{
      client_opts: fn peer ->
        base = Clients.base_opts(peer, variant.page)

        cookie_paths
        |> Enum.take(count)
        |> Enum.map(&Keyword.put(base, :cookie_path, &1))
      end,
      conn: conn,
      duration_ms: opts[:duration] * 1_000,
      expected: fn _offset -> every_client end,
      fill_timeout_ms: opts[:fill_timeout] * 1_000,
      first_marker: first_marker,
      rate: opts[:rate],
      rows: &Peer.rpc(&1, Writer, :ids, [variant.card_type]),
      write: fn peer, ids, offset, marker ->
        args = [variant.card_type, elem(ids, offset), :title, Client.marker(marker)]
        Peer.rpc(peer, Writer, :update, args)
      end
    }
  end

  defp variant(:plain) do
    %{
      card_type: Card,
      clients: "anonymous clients",
      name: "board",
      page: "HologramSyncBenchmark.BoardPage",
      prepare: fn _peer, count -> {[], List.duplicate("/session", count)} end,
      rule: "a bare `allow :read`",
      title: "Shared board"
    }
  end

  # Each client signs in as a user of its own who holds the viewer role on the one board the cards
  # belong to. Every client still reads every card, but every rule check reads the card's board
  # and asks for the user's grants on it.
  defp variant(:roles) do
    %{
      card_type: RoleCard,
      clients: "signed-in clients, each user holding the viewer role on the board",
      name: "board_roles",
      page: "HologramSyncBenchmark.RoleBoardPage",
      prepare: fn peer, count ->
        user_ids = Peer.rpc(peer, Seed, :users, [count])
        board_id = Peer.rpc(peer, Seed, :role_board, [user_ids])

        {[board_id: board_id], Enum.map(user_ids, &"/sign_in/#{&1}")}
      end,
      rule:
        "`allow :read, via: {:read, board}` on cards and `allow :read, to: :viewer` on the board",
      title: "Shared board read by role"
    }
  end
end
