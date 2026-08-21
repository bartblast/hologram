defmodule Hologram.Test.ScratchDatabaseCaseTest do
  # The case template's own spec. Every test of the scratch-database tier rests on three
  # guarantees it never states: what a routed transaction writes is COMMITTED and visible
  # to any other session, each test runs on a database of its OWN that nothing touched
  # before, and route/2 points the gateway at that database and no other. The migration
  # suites assume all three on every line - a resumption test reads what an earlier apply
  # committed, a contention test watches one session's index build from another, a claim
  # test needs a database with no Hologram schemas in it.
  #
  # The other case templates have no tests because their guarantees cannot break quietly:
  # a sandbox that stopped isolating would fail half the suite at once. This tier's can. A
  # scratch connection that wrapped each test in a transaction - the sandbox's own trick,
  # the obvious optimization - would leave the contention tests hanging on builds that
  # never see a commit, and a database shared between tests would turn every "virgin" and
  # "absent" assertion into a guess about what ran before. Pinning the three here turns
  # either change into a failure that names the harness.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection,
  # several in the contention suites, so the tier's modules run one at a time to keep the
  # server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  alias Hologram.DB.Connection

  # The two tests below create the same table after asserting it is absent, so whichever
  # of them runs second proves the databases are distinct - in either order ExUnit picks.
  defp smoke_table_exists?(session) do
    %{rows: [[regclass]]} = Postgrex.query!(session, "SELECT to_regclass('public.smoke')", [])

    regclass != nil
  end

  test "routes the calling process at the test's own database", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    {:ok, %{rows: [[database]]}} =
      route(scratch, fn -> Connection.query("SELECT current_database()") end)

    assert database == scratch_opts[:database]
    assert String.starts_with?(database, "hologram_scratch_")
  end

  test "commits what a routed transaction writes, for a second session to read", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    refute smoke_table_exists?(scratch)

    route(scratch, fn ->
      Connection.transaction(fn ->
        {:ok, _result} = Connection.query(~s{CREATE TABLE "smoke" ("id" integer)})
        {:ok, _result} = Connection.query(~s{INSERT INTO "smoke" ("id") VALUES (1)})
      end)
    end)

    {:ok, second_session} = Postgrex.start_link(scratch_opts)

    assert Postgrex.query!(second_session, ~s(SELECT "id" FROM "smoke"), []).rows == [[1]]
  end

  test "starts every test on a database holding nothing", %{scratch: scratch} do
    refute smoke_table_exists?(scratch)

    Postgrex.query!(scratch, ~s{CREATE TABLE "smoke" ("id" integer)}, [])

    assert smoke_table_exists?(scratch)
  end
end
