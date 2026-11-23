defmodule HologramSyncBenchmark.Seed do
  @moduledoc false

  # Writes a case's rows through Hologram on the server node, so they are stored exactly as an
  # app's writes are. Runs before any client connects, and the driver empties the log afterwards,
  # so no session ever sees these writes.

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Sync.Search
  alias HologramSyncBenchmark.Entities.Doc
  alias HologramSyncBenchmark.Entities.Member
  alias HologramSyncBenchmark.Entities.Project
  alias HologramSyncBenchmark.Entities.ProjectMember
  alias HologramSyncBenchmark.Entities.RoleBoard
  alias HologramSyncBenchmark.Entities.SetPost
  alias HologramSyncBenchmark.Entities.SetTag
  # Named apart from Elixir's Task, which seeding runs its writes with.
  alias HologramSyncBenchmark.Entities.Task, as: TenantTask
  alias HologramSyncBenchmark.Entities.Tenant
  alias HologramSyncBenchmark.Entities.User

  # Rows per transaction. Each create inside a transaction opens two savepoints, one in the
  # Writer's deadlock retry and one in the entity's own create, and a transaction holding more than
  # PostgreSQL's 64 cached subtransactions slows every other session's visibility checks (see
  # Hologram.DB.transaction/2). Committing one row at a time makes seeding slow.
  @chunk_size 30

  @max_concurrency 8

  @doc """
  Creates the given number of cards of the given board type, positioned 0 up, and returns :ok.
  Runs on the server node.

  `values` are set on every card, like the board the cards belong to.
  """
  @spec cards(module, pos_integer, keyword) :: :ok
  def cards(card_type, count, values \\ []) do
    0..(count - 1)
    |> Stream.map(&card_type.new([position: &1, title: "card #{&1}"] ++ values))
    |> create_all()

    :ok
  end

  @doc """
  Creates one project with the given number of members, each a user of its own, and the given
  number of docs, and returns the users' ids and the project's id. Runs on the server node.
  """
  @spec project(pos_integer, pos_integer) :: {[String.t()], String.t()}
  def project(members, docs) do
    user_ids = users(members)

    project =
      [name: "project"]
      |> Project.new()
      |> DB.create!()

    user_ids
    |> Stream.map(&ProjectMember.new(project_id: project.id, user_id: &1))
    |> create_all()

    0..(docs - 1)
    |> Stream.map(&Doc.new(position: &1, project_id: project.id, title: "doc #{&1}"))
    |> create_all()

    {user_ids, project.id}
  end

  @doc """
  Creates one board and grants each given user the viewer role on it, returning the board's id.
  Runs on the server node, as trusted code, which may grant without holding the role.
  """
  @spec role_board([String.t()]) :: String.t()
  def role_board(user_ids) do
    board =
      [name: "board"]
      |> RoleBoard.new()
      |> DB.create!()

    user_ids
    |> Task.async_stream(&Auth.grant_role(&1, :viewer, board),
      max_concurrency: @max_concurrency,
      timeout: :infinity
    )
    |> Stream.run()

    board.id
  end

  @doc """
  Creates one tag with the given number of hidden posts in its set, and the given number of visible
  posts outside it, and returns the tag's id and the visible posts' ids. Runs on the server node.

  The hidden posts go in with one statement rather than through the Writer: at 300,000 they'd take
  minutes that way, nothing reads their values, and no client may read them.
  """
  @spec big_set(pos_integer, pos_integer) :: %{post_ids: [String.t()], tag_id: String.t()}
  def big_set(hidden, visible) do
    tag =
      [name: "tag"]
      |> SetTag.new()
      |> DB.create!()

    posts =
      0..(visible - 1)
      |> Stream.map(&SetPost.new(position: &1, title: "visible #{&1}", visible: true))
      |> create_all()

    :ok = insert_hidden_posts(hidden, visible, tag.id)

    %{post_ids: Enum.map(posts, & &1.id), tag_id: tag.id}
  end

  defp insert_hidden_posts(hidden, first_position, tag_id) do
    posts =
      SetPost
      |> DB.table_name()
      |> Search.qualified_table()

    pairs =
      DB.mapping()
      |> Search.join_table(SetPost, :tags)
      |> Search.qualified_table()

    statement = """
    WITH hidden AS (
      INSERT INTO #{posts}
        ("id", "position", "title", "visible", "created_at", "server_created_at",
         "server_updated_at", "updated_at", "$revisions")
      SELECT gen_random_uuid(), $1::bigint + number, 'hidden ' || number, false,
             now(), now(), now(), now(), '{}'::jsonb
      FROM generate_series(1, $2::bigint) AS number
      RETURNING "id"
    )
    INSERT INTO #{pairs} ("source_id", "target_id")
    SELECT "id", $3::uuid FROM hidden
    """

    {:ok, _result} =
      Connection.with_timeout(:infinity, fn ->
        Connection.query(statement, [first_position, hidden, Codec.encode(tag_id, :uuid)])
      end)

    :ok
  end

  @doc """
  Creates the given number of tenants, each with the given number of members, each a user of
  its own, and the given number of tasks, and returns the users' ids in tenant order: the first
  tenant's members first. Runs on the server node.

  Tasks are positioned 0 up across tenants, the first tenant's first, so a tenant's tasks sit
  next to each other.
  """
  @spec tenants(pos_integer, pos_integer, pos_integer) :: [String.t()]
  def tenants(tenant_count, members, tasks) do
    user_ids = users(tenant_count * members)

    tenant_ids =
      0..(tenant_count - 1)
      |> Stream.map(&Tenant.new(name: "tenant #{&1}"))
      |> create_all()
      |> Enum.map(& &1.id)
      |> List.to_tuple()

    user_ids
    |> Stream.with_index()
    |> Stream.map(fn {user_id, index} ->
      Member.new(tenant_id: elem(tenant_ids, div(index, members)), user_id: user_id)
    end)
    |> create_all()

    0..(tenant_count * tasks - 1)
    |> Stream.map(fn position ->
      TenantTask.new(
        position: position,
        tenant_id: elem(tenant_ids, div(position, tasks)),
        title: "task #{position}"
      )
    end)
    |> create_all()

    user_ids
  end

  @doc """
  Creates the given number of users and returns their ids, in the order the clients sign in as
  them. Runs on the server node.
  """
  @spec users(pos_integer) :: [String.t()]
  def users(count) do
    0..(count - 1)
    |> Stream.map(&User.new(name: "user #{&1}"))
    |> create_all()
    |> Enum.map(& &1.id)
  end

  # In the order given, so the ids line up with what they were created from.
  defp create_all(entities) do
    entities
    |> Stream.chunk_every(@chunk_size)
    |> Task.async_stream(&create_chunk/1, max_concurrency: @max_concurrency, timeout: :infinity)
    |> Enum.flat_map(fn {:ok, created} -> created end)
  end

  defp create_chunk(entities) do
    {:ok, created} = DB.transaction(fn -> Enum.map(entities, &DB.create!/1) end)

    created
  end
end
