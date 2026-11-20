defmodule HologramSyncTests.ConsistencyTest do
  # async: false - a run truncates the shared tables and serves every client from this node.
  use HologramSyncTests.TestCase, async: false

  alias HologramSyncTests.Consistency.Plan
  alias HologramSyncTests.Consistency.Report
  alias HologramSyncTests.Consistency.Run
  alias HologramSyncTests.Entities.Card

  @trace_dir Path.expand("../tmp/sync_consistency", __DIR__)

  # Clients take random writes, access changes, cuts and reconnects, and once the writes stop each
  # holds exactly what its user may read (check 1), having received no row its user couldn't read
  # when it was sent, nor a set or pair naming one (check 2). The plan comes from the seed:
  # SYNC_SEED, ExUnit's by default.
  #
  # TODO: run it in CI again once #1749 is fixed - a live batch queued behind a returning client's
  # catch-up can send an older row under the catch-up's place, which check 2 flags.
  @tag :randomized
  @tag timeout: :infinity
  test "clients converge on what they may read and never receive what they may not" do
    options = Plan.options()
    plan = Plan.generate(options.seed, options.steps)

    for run <- 1..options.runs do
      outcome =
        try do
          Run.run(plan, base_url())
        catch
          kind, reason ->
            kind
            |> Exception.format(reason, __STACKTRACE__)
            |> Report.crash_message(options, run)
            |> flunk()
        end

      if Report.failed?(outcome) do
        path = Report.write(outcome, plan, run, @trace_dir)

        flunk(Report.message(outcome, options, run, path))
      end
    end
  end

  test "a run that raises names the seed, the replay and the error" do
    message =
      :error
      |> Exception.format(%RuntimeError{message: "the seed rolled back"}, [])
      |> Report.crash_message(%{runs: 2, seed: 7, steps: 3}, 1)

    assert message =~ "seed 7 (run 1 of 2)"

    assert message =~
             "SYNC_SEED=7 SYNC_STEPS=3 mix test --include randomized test/consistency_test.exs"

    assert message =~ "the seed rolled back"
  end

  test "a failed run's message names the seed, the replay and the commits behind the row" do
    plan = Plan.generate(7, 3)

    record = %{
      applied?: true,
      carried: %{"title" => "stale"},
      cursor_tx: 1_234,
      id: "card-1",
      named: [],
      opened_at: 0,
      received_at: 10,
      type: Card
    }

    client = %{
      differences: [],
      events: [
        %{at: 0, cursor: nil, kind: :connect, request_id: make_ref()},
        %{at: 5, cause: :cut, kind: :closed}
      ],
      leaks: [],
      name: "tab of u",
      records: [record],
      schedule: [],
      user_id: "u"
    }

    state = %{rows: %{Card => %{"card-1" => %{"board_id" => "board-1", "title" => "fresh"}}}}

    outcome = %{
      clients: [client],
      differences: [
        %{client: "tab of u", difference: {:missing, Card, "card-1", %{"title" => "fresh"}}}
      ],
      failures: [],
      history: %{
        aborted: [
          %{ops: ["tag_card card-1 tag-1"], reason: "no entity with id", writer: "writer 1"},
          %{
            ops: ["rename x"],
            reason: %DBConnection.ConnectionError{message: "closed"},
            writer: "writer 2"
          }
        ],
        entries: [
          %{
            after_lock_at: 1,
            committed_at: 2,
            ops: ["retitle_card card-1 fresh"],
            state: state,
            writer: "writer 1",
            xid: 1_233
          },
          %{
            after_lock_at: 3,
            committed_at: 4,
            ops: ["archive_board board-1 true"],
            state: state,
            writer: "writer 2",
            xid: 1_235
          }
        ]
      },
      leaks: [%{candidates: [0], client: "tab of u", record: record, user_id: "u"}],
      missed_resyncs: []
    }

    message =
      Report.message(outcome, %{runs: 1, seed: 7, steps: 3}, 1, "tmp/sync_consistency/7-1.log")

    assert message =~ "seed 7"

    assert message =~
             "SYNC_SEED=7 SYNC_STEPS=3 mix test --include randomized test/consistency_test.exs"

    assert message =~ "may not come from the change under test"
    assert message =~ "tmp/sync_consistency/7-1.log"
    assert message =~ "misses HologramSyncTests.Entities.Card card-1"

    assert message =~
             "commit 0 (writer 1, xid 1233, lock 1, committed 2): retitle_card card-1 fresh"

    assert message =~
             "commit 1 (writer 2, xid 1235, lock 3, committed 4): archive_board board-1 true"

    assert message =~ "5 closed: :cut"
    assert message =~ "at 10, on a connection opened at 0, bounded by tx 1234"

    dir =
      Path.join(System.tmp_dir!(), "sync_consistency_test_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(dir) end)

    trace =
      outcome
      |> Report.write(plan, 1, dir)
      |> File.read!()

    assert trace =~ "COMMITS IN LOCK ORDER"

    assert trace =~ "writer 1: tag_card card-1 tag-1 - no entity with id"
    assert trace =~ "writer 2: rename x - %DBConnection.ConnectionError{"
  end
end
