defmodule Hologram.Job.WorkerTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog
  import Hologram.Job.Worker

  alias Hologram.Job.Worker
  alias Hologram.Test.Fixtures.Job.Module1
  alias Hologram.Test.Fixtures.Job.Module2
  alias Hologram.Test.Fixtures.Job.Module3

  @poll_interval_ms 20

  @timeout_ms 2_000

  # Stands in for a Hologram.DB.Listener connection, which answers listen/2 with a reference and
  # would otherwise need a connection of its own.
  defmodule NotificationsStub do
    @moduledoc false

    use GenServer

    @spec start_link(keyword) :: GenServer.on_start()
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts), do: {:ok, opts[:reply_to]}

    @impl GenServer
    def handle_call({{:listen, channel}, _caller}, _from, reply_to) do
      send(reply_to, {:listening, channel})

      {:reply, {:ok, make_ref()}, reply_to}
    end
  end

  # The queues the stubs below read and run from, a list of job ids per job type, oldest first.
  defp start_queues(queues) do
    {:ok, agent} = Agent.start_link(fn -> queues end)

    agent
  end

  defp add_jobs(queues, job_type, ids) do
    Agent.update(queues, fn queues -> Map.update(queues, job_type, ids, &(&1 ++ ids)) end)
  end

  # Answers the oldest ids of the type not in the skip set, the way Runner.queued/3 does, and
  # reports each ask to the test.
  defp queued_stub(test_pid, queues) do
    fn job_type, skip_ids, count ->
      send(test_pid, {:asked, job_type, skip_ids})

      queues
      |> Agent.get(&Map.get(&1, job_type, []))
      |> Enum.reject(&MapSet.member?(skip_ids, &1))
      |> Enum.take(count)
      |> Enum.map(&%{id: &1})
    end
  end

  defp take_off(queues, job_type, id) do
    Agent.update(queues, fn queues -> Map.update!(queues, job_type, &List.delete(&1, id)) end)
  end

  # Runs a job by taking it off its queue, the way a claim moves its row out of queued, and reports
  # it to the test. What it answers comes from the given function, :done unless it says otherwise,
  # and a job it answers :locked for stays queued.
  defp run_stub(test_pid, queues, answer \\ fn _id -> :done end) do
    fn job_type, id ->
      send(test_pid, {:ran, job_type, id})

      case answer.(id) do
        :locked ->
          :locked

        result ->
          take_off(queues, job_type, id)
          result
      end
    end
  end

  # A run that reports it started, then waits for the test to let it finish.
  defp blocking_run_stub(test_pid, queues) do
    fn job_type, id ->
      take_off(queues, job_type, id)
      send(test_pid, {:running, job_type, id, self()})

      receive do
        :finish -> :done
      end
    end
  end

  defp crashing_run_stub(test_pid, end_run) do
    fn job_type, id ->
      send(test_pid, {:ran, job_type, id})

      end_run.()
    end
  end

  defp release_stub(test_pid) do
    fn id ->
      send(test_pid, {:released, id})

      :ok
    end
  end

  defp sweep_stub(test_pid) do
    fn job_types, skip_ids ->
      send(test_pid, {:swept, job_types, skip_ids})

      :ok
    end
  end

  # The look a worker makes as it starts asks each type once, the last in module order last. On
  # queues the test fills only after it, a job the test adds is run by a look the test asks for, and
  # the asks left in the mailbox are the ones made after it.
  defp await_first_look do
    assert_receive {:asked, Module3, _skip_ids}, @timeout_ms

    flush_asks()
  end

  # Drops the asks the looks so far made, so that a test can tell the asks of the next look.
  defp flush_asks do
    receive do
      {:asked, _job_type, _skip_ids} -> flush_asks()
    after
      0 -> :ok
    end
  end

  # The ids of the jobs run, in the order they ran.
  defp ran(count) do
    for _run <- 1..count do
      assert_receive {:ran, job_type, id}, @timeout_ms

      {job_type, id}
    end
  end

  defp start_runs do
    start_supervised!(Supervisor.child_spec(Task.Supervisor, id: make_ref()))
  end

  defp start_worker!(opts) do
    opts =
      opts
      |> Keyword.put_new(:max_concurrency, fn _job_type -> 10 end)
      |> Keyword.put_new(:queued, fn _job_type, _skip_ids, _count -> [] end)
      |> Keyword.put_new(:release, fn _id -> :ok end)
      |> Keyword.put_new(:run, fn _job_type, _id -> :done end)
      |> Keyword.put_new(:sweep, fn _job_types, _skip_ids -> :ok end)
      |> Keyword.put_new(:poll_interval_ms, :timer.minutes(1))
      |> Keyword.put_new_lazy(:runs, &start_runs/0)

    start_supervised!({Worker, opts})
  end

  defp start_worker_on!(queues, opts \\ []) do
    test_pid = self()

    opts
    |> Keyword.put_new(:queued, queued_stub(test_pid, queues))
    |> Keyword.put_new(:run, run_stub(test_pid, queues))
    |> start_worker!()
  end

  describe "start_link/1" do
    test "listens for writes on the oplog channel" do
      notifications = start_supervised!({NotificationsStub, reply_to: self()})

      start_worker!(notifications: notifications)

      assert_receive {:listening, "hologram_oplog"}, @timeout_ms
    end

    test "listens for nothing when given no notifications process" do
      start_worker!([])

      refute_receive {:listening, _channel}, 100
    end

    # The jobs queued while no worker ran wait for nothing.
    test "runs the queued jobs as it starts" do
      start_worker_on!(start_queues(%{Module1 => ["a"]}))

      assert_receive {:ran, Module1, "a"}, @timeout_ms
    end

    # The runs a predecessor left are failed at once, not at the first poll.
    test "sweeps every job type as it starts" do
      start_worker!(sweep: sweep_stub(self()))

      assert_receive {:swept, [Module1, Module2, Module3], skip_ids}, @timeout_ms
      assert skip_ids == MapSet.new()
    end

    # A run its predecessor left would go on with its lock given up under it.
    test "kills the runs its predecessor left as it starts" do
      runs = start_runs()
      # Started the way the worker starts its runs.
      {:ok, left} =
        Task.Supervisor.start_child(runs, fn -> Process.sleep(:infinity) end,
          shutdown: :brutal_kill
        )

      monitor_ref = Process.monitor(left)

      start_worker!(runs: runs)

      assert_receive {:DOWN, ^monitor_ref, :process, ^left, :killed}, @timeout_ms
    end

    # Each worker restarting would otherwise crash at once on a sweep that keeps failing, past the
    # supervisor's limit - the poll's sweep tries again at its own pace.
    test "stays up, and logs nothing, when the sweep as it starts raises" do
      {:ok, refusing} = Agent.start_link(fn -> true end)

      sweep = fn _job_types, _skip_ids ->
        if Agent.get_and_update(refusing, &{&1, false}), do: raise("refused"), else: :ok
      end

      log =
        capture_log(fn ->
          worker = start_worker_on!(start_queues(%{Module1 => ["a"]}), sweep: sweep)

          # A sweep failing for a reason of its own doesn't hold up the look.
          assert_receive {:ran, Module1, "a"}, @timeout_ms
          assert Process.alive?(worker)
        end)

      # Only an earlier go at what the first poll does and logs.
      assert log == ""
    end

    test "stays up, and logs nothing, when the look as it starts raises" do
      queues = start_queues(%{Module1 => ["a"]})
      {:ok, refusing} = Agent.start_link(fn -> true end)
      stub = queued_stub(self(), queues)

      queued = fn job_type, skip_ids, count ->
        if Agent.get_and_update(refusing, &{&1, false}), do: raise("refused")

        stub.(job_type, skip_ids, count)
      end

      log =
        capture_log(fn ->
          worker = start_worker_on!(queues, queued: queued)

          refute_receive {:ran, Module1, "a"}, 100

          wake(worker)

          assert_receive {:ran, Module1, "a"}, @timeout_ms
        end)

      # A worker can start before the job tables are there, in a test env, and a log line then
      # would only be noise.
      assert log == ""
    end
  end

  describe "start_link/1, as it starts" do
    test "logs nothing when it can't get a database connection" do
      {:ok, refusing} = Agent.start_link(fn -> true end)

      sweep = fn _job_types, _skip_ids ->
        if Agent.get_and_update(refusing, &{&1, false}) do
          raise DBConnection.ConnectionError, "connection not available"
        end

        :ok
      end

      log =
        capture_log(fn ->
          worker = start_worker!(sweep: sweep)
          :sys.get_state(worker)
        end)

      assert log == ""
    end
  end

  describe "init/1" do
    # The default run takes the lock on it, and a job run without a lock connection would look
    # abandoned.
    test "requires a run lock connection when given no run" do
      assert_raise KeyError, ~r/:run_lock/, fn ->
        init(release: fn _id -> :ok end, runs: self())
      end
    end

    test "requires a run lock connection when given no release" do
      assert_raise KeyError, ~r/:run_lock/, fn ->
        init(run: fn _job_type, _id -> :done end, runs: self())
      end
    end

    test "requires the supervisor the runs are started under" do
      assert_raise KeyError, ~r/:runs/, fn ->
        init(release: fn _id -> :ok end, run: fn _job_type, _id -> :done end)
      end
    end
  end

  describe "handle :wake" do
    test "runs the queued jobs of a type oldest first" do
      queues = start_queues(%{})
      worker = start_worker_on!(queues, max_concurrency: fn _job_type -> 1 end)
      await_first_look()

      add_jobs(queues, Module1, ["a", "b"])
      wake(worker)

      assert ran(2) == [{Module1, "a"}, {Module1, "b"}]
    end

    test "runs up to a type's limit at once, and the next as one ends" do
      queues = start_queues(%{})
      test_pid = self()

      worker =
        start_worker_on!(queues,
          max_concurrency: fn _job_type -> 2 end,
          run: blocking_run_stub(test_pid, queues)
        )

      await_first_look()

      add_jobs(queues, Module1, ["a", "b", "c"])
      wake(worker)

      assert_receive {:running, Module1, "a", first}, @timeout_ms
      assert_receive {:running, Module1, "b", _second}, @timeout_ms
      refute_receive {:running, Module1, "c", _third}, 100

      send(first, :finish)

      assert_receive {:running, Module1, "c", _third}, @timeout_ms
    end

    test "runs the jobs of one type while another type is at its limit" do
      queues = start_queues(%{})
      test_pid = self()
      blocking = blocking_run_stub(test_pid, queues)
      running = run_stub(test_pid, queues)

      run = fn
        Module1, id -> blocking.(Module1, id)
        job_type, id -> running.(job_type, id)
      end

      worker = start_worker_on!(queues, max_concurrency: fn _job_type -> 1 end, run: run)
      await_first_look()

      add_jobs(queues, Module1, ["a", "b"])
      add_jobs(queues, Module3, ["c"])
      wake(worker)

      assert_receive {:running, Module1, "a", _pid}, @timeout_ms
      assert_receive {:ran, Module3, "c"}, @timeout_ms
      refute_receive {:running, Module1, "b", _pid}, 100
    end

    test "leaves out of a look the jobs it runs" do
      queues = start_queues(%{})
      worker = start_worker_on!(queues, run: blocking_run_stub(self(), queues))
      await_first_look()

      add_jobs(queues, Module1, ["a"])
      wake(worker)
      assert_receive {:running, Module1, "a", _pid}, @timeout_ms

      wake(worker)

      skip_ids = MapSet.new(["a"])

      assert_receive {:asked, Module1, ^skip_ids}, @timeout_ms
    end

    # Not queued any more, the job is never answered again, and leaving it out of the next look
    # would only make the look read further.
    test "runs the next job after one another worker took, leaving out nothing" do
      queues = start_queues(%{})
      answer = fn id -> if id == "a", do: :taken, else: :done end

      worker =
        start_worker_on!(queues,
          max_concurrency: fn _job_type -> 1 end,
          run: run_stub(self(), queues, answer)
        )

      await_first_look()

      add_jobs(queues, Module1, ["a", "b"])
      wake(worker)

      # The wake's ask, then the one after the run that ended.
      assert_receive {:asked, Module1, _skip_ids}, @timeout_ms
      assert_receive {:ran, Module1, "a"}, @timeout_ms
      assert_receive {:asked, Module1, skip_ids}, @timeout_ms
      assert skip_ids == MapSet.new()
      assert_receive {:ran, Module1, "b"}, @timeout_ms
    end

    # Asked for again at once, a job whose lock another session holds would be answered the same
    # way for as long as the lock lasts.
    test "leaves a job whose run lock another session holds until the next wake" do
      queues = start_queues(%{})
      answer = fn id -> if id == "a", do: :locked, else: :done end

      worker =
        start_worker_on!(queues,
          max_concurrency: fn _job_type -> 1 end,
          run: run_stub(self(), queues, answer)
        )

      await_first_look()

      add_jobs(queues, Module1, ["a", "b"])
      wake(worker)

      assert ran(2) == [{Module1, "a"}, {Module1, "b"}]

      skip_ids = MapSet.new(["a"])

      assert_receive {:asked, Module1, ^skip_ids}, @timeout_ms
      refute_receive {:ran, Module1, "a"}, 100

      wake(worker)

      assert_receive {:ran, Module1, "a"}, @timeout_ms
    end

    # A hold on the data model refuses the claim, and asking again at once would be refused the
    # same way for as long as the hold stands.
    test "leaves a job whose run finds the data model under a hold until the next wake" do
      queues = start_queues(%{})
      {:ok, held} = Agent.start_link(fn -> true end)
      test_pid = self()

      run = fn job_type, id ->
        send(test_pid, {:ran, job_type, id})

        if Agent.get_and_update(held, &{&1, false}), do: raise(Hologram.StaleModelError)

        take_off(queues, job_type, id)
        :done
      end

      worker = start_worker_on!(queues, run: run)
      await_first_look()

      add_jobs(queues, Module1, ["a"])
      wake(worker)

      assert_receive {:ran, Module1, "a"}, @timeout_ms
      refute_receive {:ran, Module1, "a"}, 100
      assert Process.alive?(worker)

      wake(worker)

      assert_receive {:ran, Module1, "a"}, @timeout_ms
    end

    test "skips a look that finds the data model under a hold" do
      test_pid = self()
      {:ok, held} = Agent.start_link(fn -> false end)

      queued = fn job_type, _skip_ids, _count ->
        send(test_pid, {:asked, job_type})

        if Agent.get_and_update(held, &{&1, false}), do: raise(Hologram.StaleModelError), else: []
      end

      worker = start_worker!(queued: queued)

      for job_type <- [Module1, Module2, Module3] do
        assert_receive {:asked, ^job_type}, @timeout_ms
      end

      # The look finds the hold, and gives up before the other types.
      Agent.update(held, fn _held -> true end)
      wake(worker)

      assert_receive {:asked, Module1}, @timeout_ms
      refute_receive {:asked, Module2}, 100

      wake(worker)

      assert_receive {:asked, Module1}, @timeout_ms
      assert_receive {:asked, Module2}, @timeout_ms
    end

    # Crashing would kill every run on the node, through the kill as the next worker starts, for a
    # wait the next wake or poll gets past.
    test "keeps its runs going when a look can't get a database connection" do
      queues = start_queues(%{})
      test_pid = self()
      {:ok, refusing} = Agent.start_link(fn -> false end)
      stub = queued_stub(test_pid, queues)

      queued = fn job_type, skip_ids, count ->
        if Agent.get(refusing, & &1) do
          raise DBConnection.ConnectionError, "connection not available"
        end

        stub.(job_type, skip_ids, count)
      end

      worker =
        start_worker_on!(queues, queued: queued, run: blocking_run_stub(test_pid, queues))

      await_first_look()

      add_jobs(queues, Module1, ["a"])
      wake(worker)
      assert_receive {:running, Module1, "a", run}, @timeout_ms

      run_ref = Process.monitor(run)
      Agent.update(refusing, fn _refusing -> true end)

      log =
        capture_log(fn ->
          wake(worker)
          refute_receive {:DOWN, ^run_ref, :process, ^run, _reason}, 100
        end)

      assert log =~ "the job worker couldn't get a database connection"
      assert Process.alive?(worker)

      Agent.update(refusing, fn _refusing -> false end)
      send(run, :finish)

      assert_receive {:DOWN, ^run_ref, :process, ^run, :normal}, @timeout_ms
    end

    # A run the fill started before a later type's look failed is still the worker's to hear from:
    # its answer would otherwise match none of the runs the worker knows of.
    test "keeps the runs a look started when a later type's look fails" do
      queues = start_queues(%{})
      test_pid = self()
      {:ok, refusing} = Agent.start_link(fn -> false end)
      stub = queued_stub(test_pid, queues)

      queued = fn job_type, skip_ids, count ->
        if job_type == Module2 and Agent.get(refusing, & &1) do
          raise DBConnection.ConnectionError, "connection not available"
        end

        stub.(job_type, skip_ids, count)
      end

      worker =
        start_worker_on!(queues, queued: queued, run: blocking_run_stub(test_pid, queues))

      await_first_look()

      add_jobs(queues, Module1, ["a"])
      Agent.update(refusing, fn _refusing -> true end)

      capture_log(fn ->
        wake(worker)
        assert_receive {:running, Module1, "a", run}, @timeout_ms
        assert_receive {:asked, Module1, _skip_ids}, @timeout_ms

        add_jobs(queues, Module1, ["b"])
        send(run, :finish)

        assert_receive {:running, Module1, "b", _run}, @timeout_ms
      end)

      assert Process.alive?(worker)
    end

    # A failure of one type's own, like an error on its table, would otherwise hold up every type
    # after it in module order for as long as it lasts.
    test "looks at the types after one whose look fails for a reason of its own" do
      queues = start_queues(%{})
      stub = queued_stub(self(), queues)

      queued = fn
        Module1, _skip_ids, _count -> raise "no such table"
        job_type, skip_ids, count -> stub.(job_type, skip_ids, count)
      end

      log =
        capture_log(fn ->
          worker = start_worker_on!(queues, queued: queued)
          await_first_look()

          add_jobs(queues, Module3, ["a"])
          wake(worker)

          assert_receive {:ran, Module3, "a"}, @timeout_ms
        end)

      assert log =~ "no such table"
    end

    # Only that type's slot freed.
    test "looks again at the type of a run that ends, and no other" do
      queues = start_queues(%{})
      worker = start_worker_on!(queues, run: blocking_run_stub(self(), queues))
      await_first_look()

      add_jobs(queues, Module1, ["a"])
      wake(worker)
      assert_receive {:running, Module1, "a", run}, @timeout_ms
      assert_receive {:asked, Module3, _skip_ids}, @timeout_ms
      flush_asks()

      send(run, :finish)

      assert_receive {:asked, Module1, _skip_ids}, @timeout_ms
      refute_receive {:asked, Module2, _skip_ids}, 100
    end

    # The wakes that arrive while a look works ask what the look after them answers. A look that
    # blocks as the worker starts holds three wakes up behind it: Module1 is asked twice in all -
    # once by the look as it starts, and once by the look the three wakes get.
    test "answers the wakes that arrived while it worked with one look" do
      test_pid = self()
      {:ok, first?} = Agent.start_link(fn -> true end)

      queued = fn job_type, _skip_ids, _count ->
        send(test_pid, {:asked, job_type, self()})

        if Agent.get_and_update(first?, &{&1, false}) do
          receive do
            :finish -> :ok
          end
        end

        []
      end

      worker = start_worker!(queued: queued)

      assert_receive {:asked, Module1, ^worker}, @timeout_ms

      wake(worker)
      wake(worker)
      wake(worker)
      send(worker, :finish)

      assert_receive {:asked, Module1, ^worker}, @timeout_ms
      refute_receive {:asked, Module1, ^worker}, 100
    end

    test "sweeps nothing" do
      worker = start_worker!(sweep: sweep_stub(self()))

      assert_receive {:swept, _job_types, _skip_ids}, @timeout_ms

      wake(worker)

      refute_receive {:swept, _job_types, _skip_ids}, 100
    end
  end

  describe "handle a run going down" do
    for {label, end_run} <- [
          {"raises", quote(do: fn -> raise "boom" end)},
          {"is killed", quote(do: fn -> Process.exit(self(), :kill) end)}
        ] do
      # A run that went down never answered, so its lock may still be held, its row may be left
      # running, and its claim, tried again at once, would most likely go down the same way.
      test "gives up the lock of a run that #{label}, sweeps its type, and leaves the job until the next wake" do
        queues = start_queues(%{})
        test_pid = self()

        worker =
          start_worker_on!(queues,
            release: release_stub(test_pid),
            run: crashing_run_stub(test_pid, unquote(end_run)),
            sweep: sweep_stub(test_pid)
          )

        assert_receive {:swept, _job_types, _skip_ids}, @timeout_ms
        await_first_look()

        add_jobs(queues, Module1, ["a"])

        capture_log(fn ->
          wake(worker)

          assert_receive {:ran, Module1, "a"}, @timeout_ms
          assert_receive {:released, "a"}, @timeout_ms
        end)

        assert_receive {:swept, [Module1], _skip_ids}, @timeout_ms

        skip_ids = MapSet.new(["a"])

        assert_receive {:asked, Module1, ^skip_ids}, @timeout_ms
        assert Process.alive?(worker)
      end
    end

    test "frees the run's slot" do
      queues = start_queues(%{})
      test_pid = self()
      crashing = crashing_run_stub(test_pid, fn -> Process.exit(self(), :kill) end)
      running = run_stub(test_pid, queues)

      run = fn
        job_type, "a" -> crashing.(job_type, "a")
        job_type, id -> running.(job_type, id)
      end

      worker = start_worker_on!(queues, max_concurrency: fn _job_type -> 1 end, run: run)
      await_first_look()

      add_jobs(queues, Module1, ["a", "b"])
      wake(worker)

      assert ran(2) == [{Module1, "a"}, {Module1, "b"}]
    end
  end

  describe "handle :notification" do
    test "runs the job a write announces" do
      queues = start_queues(%{})
      worker = start_worker_on!(queues)
      await_first_look()

      add_jobs(queues, Module2, ["a"])
      send(worker, {:notification, self(), make_ref(), "hologram_oplog", ""})

      assert_receive {:ran, Module2, "a"}, @timeout_ms
    end
  end

  describe "handle :poll" do
    test "runs the queued jobs on its own, without being told to" do
      queues = start_queues(%{})
      start_worker_on!(queues, poll_interval_ms: @poll_interval_ms)

      add_jobs(queues, Module1, ["a"])

      assert_receive {:ran, Module1, "a"}, @timeout_ms
    end

    # A run cut short on another node is failed within one poll interval.
    test "keeps sweeping every job type" do
      start_worker!(sweep: sweep_stub(self()), poll_interval_ms: @poll_interval_ms)

      for _sweep <- 1..3 do
        assert_receive {:swept, [Module1, Module2, Module3], _skip_ids}, @timeout_ms
      end
    end

    # Their locks are held by this node's own session, so a sweep would only find them held.
    test "leaves out of a sweep the jobs it runs" do
      queues = start_queues(%{Module1 => ["a"]})
      test_pid = self()

      start_worker_on!(queues,
        poll_interval_ms: @poll_interval_ms,
        run: blocking_run_stub(test_pid, queues),
        sweep: sweep_stub(test_pid)
      )

      assert_receive {:running, Module1, "a", _pid}, @timeout_ms

      skip_ids = MapSet.new(["a"])

      assert_receive {:swept, _job_types, ^skip_ids}, @timeout_ms
    end

    test "looks when its sweep fails for a reason of its own" do
      queues = start_queues(%{})

      log =
        capture_log(fn ->
          start_worker_on!(queues,
            poll_interval_ms: @poll_interval_ms,
            sweep: fn _job_types, _skip_ids -> raise "no such table" end
          )

          await_first_look()
          add_jobs(queues, Module1, ["a"])

          assert_receive {:ran, Module1, "a"}, @timeout_ms
        end)

      # Logged at the poll, which a sweep failing as the worker starts is left to.
      assert log =~ "the job worker failed to look for jobs or to fail the runs cut short"
      assert log =~ "no such table"
    end

    test "tries a job left queued again" do
      queues = start_queues(%{Module1 => ["a"]})
      answer = fn _id -> :locked end

      start_worker_on!(queues,
        poll_interval_ms: @poll_interval_ms,
        run: run_stub(self(), queues, answer)
      )

      assert_receive {:ran, Module1, "a"}, @timeout_ms
      assert_receive {:ran, Module1, "a"}, @timeout_ms
    end
  end
end
