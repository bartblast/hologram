defmodule HologramSyncBenchmark.Cases.Tenants do
  @moduledoc false

  # A multi-tenant app: tenants with a few members each, and tasks only a tenant's members may
  # read, so a write reaches the few clients of its tenant. Sync sends each client the tasks its
  # user may read, so the server judges each written task against each client's user.
  #
  # Clients sign in as users in tenant order, so the first N clients fill whole tenants, and the
  # writes walk the tasks of the tenants with clients connected, one tenant after another.

  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.Entities.Task
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Seed
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  @doc """
  Returns the tenants case for the given options.
  """
  @spec sweep_case(keyword) :: map
  def sweep_case(opts) do
    users = opts[:tenants] * opts[:members]

    %{
      check!: &check!(opts, &1),
      clients: "signed-in clients, one per user, filling whole tenants in order",
      counts: Enum.filter(Sweep.default_counts(), &(&1 <= users)),
      name: "tenants" <> Step.group_suffix(opts),
      data:
        "#{opts[:tenants]} tenants of #{opts[:members]} members with #{opts[:tasks]} tasks " <>
          "each, #{opts[:tenants] * opts[:tasks]} tasks in all, read with " <>
          "`allow :read, when: any(member <- tenant.members, member.user_id == user_id())`",
      options: [
        "#{opts[:tenants]} tenants of #{opts[:members]} members with #{opts[:tasks]} tasks " <>
          "each, #{opts[:tenants] * opts[:tasks]} tasks in all, read with " <>
          "`allow :read, when: any(member <- tenant.members, member.user_id == user_id())`, " <>
          "so a write reaches the clients of its tenant's members"
      ],
      seed: &seed(&1, &2, opts),
      spec: &spec(&1, &2, &3, &4, opts),
      title: "Multi-tenant app" <> Step.group_title(opts)
    }
  end

  # The client counts have users to sign in as, and the fewest clients' tenants have a task of
  # their own for every write a step makes (see the board case for why each needs its own).
  defp check!(opts, counts) do
    users = opts[:tenants] * opts[:members]

    if Enum.max(counts) > users do
      raise ArgumentError, "#{Enum.max(counts)} clients need more users than the #{users} seeded"
    end

    writes = Step.writes(opts[:rate], opts[:duration])
    rows = tenants_reached(Enum.min(counts), opts) * opts[:tasks]

    if writes > rows do
      raise ArgumentError,
            "a step makes #{writes} writes, more than the #{rows} tasks the fewest clients read"
    end

    :ok
  end

  defp seed(conn, _max_count, opts) do
    {_seeding, {table, user_ids}} =
      Seeding.seed!(conn, fn peer ->
        user_ids = Peer.rpc(peer, Seed, :tenants, [opts[:tenants], opts[:members], opts[:tasks]])

        {Seeding.table_name(peer, Task), user_ids}
      end)

    :ok = Seeding.check_rows!(conn, table, opts[:tenants] * opts[:tasks])

    Enum.map(user_ids, &"/sign_in/#{&1}")
  end

  # The write with offset o goes to the tenant o mod t of the t tenants with clients, to that
  # tenant's task o div t, and reaches that tenant's clients.
  defp spec(conn, count, first_marker, cookie_paths, opts) do
    reached = tenants_reached(count, opts)
    members = opts[:members]

    %{
      client_opts: fn peer ->
        base = Clients.base_opts(peer, "HologramSyncBenchmark.TasksPage")

        cookie_paths
        |> Enum.take(count)
        |> Enum.map(&Keyword.put(base, :cookie_path, &1))
      end,
      conn: conn,
      duration_ms: opts[:duration] * 1_000,
      expected: fn offset ->
        tenant = rem(offset, reached)
        Enum.to_list((tenant * members)..(min((tenant + 1) * members, count) - 1))
      end,
      fill_group: opts[:fill_group],
      fill_timeout_ms: opts[:fill_timeout] * 1_000,
      first_marker: first_marker,
      rate: opts[:rate],
      rows: &Peer.rpc(&1, Writer, :ids, [Task]),
      write: fn peer, ids, offset, marker ->
        position = rem(offset, reached) * opts[:tasks] + div(offset, reached)
        args = [Task, elem(ids, position), :title, Client.marker(marker)]

        Peer.rpc(peer, Writer, :update, args)
      end
    }
  end

  defp tenants_reached(count, opts), do: div(count + opts[:members] - 1, opts[:members])
end
