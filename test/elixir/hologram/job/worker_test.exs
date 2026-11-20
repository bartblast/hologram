defmodule Hologram.Job.WorkerTest do
  use Hologram.Test.BasicCase, async: true

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
  # it to the test. The answer comes from the given function, :done unless it says otherwise.
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

  defp sweep_stub(test_pid) do
    fn job_types, skip_ids ->
      send(test_pid, {:swept, job_types, skip_ids})

      :ok
    end
  end

  # The ids of the jobs run, in the order they ran.
  defp ran(count) do
    for _run <- 1..count do
      assert_receive {:ran, job_type, id}, @timeout_ms

      {job_type, id}
    end
  end

  defp start_worker!(opts) do
    opts =
      opts
      |> Keyword.put_new(:queued, fn _job_type, _skip_ids, _count -> [] end)
      |> Keyword.put_new(:run, fn _job_type, _id -> :done end)
      |> Keyword.put_new(:sweep, fn _job_types, _skip_ids -> :ok end)
      |> Keyword.put_new(:poll_interval_ms, :timer.minutes(1))

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

    # A job that takes down the process running it would take down each worker that restarts, one
    # after the other, past the supervisor's limit.
    test "leaves the queued jobs to the first wake or poll as it starts" do
      start_worker_on!(start_queues(%{Module1 => ["a"]}))

      refute_receive {:asked, _job_type, _skip_ids}, 100
    end

    # Each worker restarting would otherwise crash at once on a sweep that keeps failing, past the
    # supervisor's limit - the poll's sweep tries again at its own pace.
    test "stays up when the sweep as it starts raises" do
      {:ok, refusing} = Agent.start_link(fn -> true end)

      sweep = fn _job_types, _skip_ids ->
        if Agent.get_and_update(refusing, &{&1, false}), do: raise("refused"), else: :ok
      end

      worker =
        start_worker_on!(start_queues(%{Module1 => ["a"]}),
          poll_interval_ms: @poll_interval_ms,
          sweep: sweep
        )

      # The poll that follows sweeps and looks.
      assert_receive {:ran, Module1, "a"}, @timeout_ms
      assert Process.alive?(worker)
    end

    # The runs a predecessor left are failed at once, not at the first poll.
    test "sweeps every job type as it starts" do
      start_worker!(sweep: sweep_stub(self()))

      assert_receive {:swept, [Module1, Module2, Module3], skip_ids}, @timeout_ms
      assert skip_ids == MapSet.new()
    end
  end

  describe "init/1" do
    # The default run takes the lock on it, and a job run without a lock connection would look
    # abandoned.
    test "requires a run lock connection when given no run" do
      assert_raise KeyError, ~r/:run_lock/, fn -> init([]) end
    end
  end

  describe "handle :wake" do
    test "runs the queued jobs of a type oldest first" do
      queues = start_queues(%{})
      worker = start_worker_on!(queues)

      Agent.update(queues, &Map.put(&1, Module1, ["a", "b"]))
      wake(worker)

      assert ran(2) == [{Module1, "a"}, {Module1, "b"}]
    end

    # A type whose jobs keep coming gets one turn a round, so it never holds up the types after it.
    test "runs one job of each type a round, the types in module order" do
      queues = start_queues(%{})
      worker = start_worker_on!(queues)

      Agent.update(queues, &Map.merge(&1, %{Module1 => ["a", "b"], Module3 => ["c"]}))
      wake(worker)

      assert ran(3) == [{Module1, "a"}, {Module3, "c"}, {Module1, "b"}]
    end

    # Not queued any more, the job is never answered again, and leaving it out of the next look
    # would only make the look read further.
    test "runs the next job after one another worker took, leaving out nothing" do
      queues = start_queues(%{})
      answer = fn id -> if id == "a", do: :taken, else: :done end
      worker = start_worker_on!(queues, run: run_stub(self(), queues, answer))

      Agent.update(queues, &Map.put(&1, Module1, ["a", "b"]))
      wake(worker)

      # The first round's ask, then the second round's, which follows the run.
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
      worker = start_worker_on!(queues, run: run_stub(self(), queues, answer))

      Agent.update(queues, &Map.put(&1, Module1, ["a", "b"]))
      wake(worker)

      assert_receive {:ran, Module1, "a"}, @timeout_ms
      assert_receive {:ran, Module1, "b"}, @timeout_ms
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

      Agent.update(queues, &Map.put(&1, Module1, ["a"]))
      wake(worker)

      assert_receive {:ran, Module1, "a"}, @timeout_ms
      refute_receive {:ran, Module1, "a"}, 100
      assert Process.alive?(worker)

      wake(worker)

      assert_receive {:ran, Module1, "a"}, @timeout_ms
    end

    test "skips a look that finds the data model under a hold" do
      test_pid = self()
      {:ok, held} = Agent.start_link(fn -> true end)

      queued = fn job_type, _skip_ids, _count ->
        send(test_pid, {:asked, job_type})

        if Agent.get_and_update(held, &{&1, false}), do: raise(Hologram.StaleModelError), else: []
      end

      worker = start_worker!(queued: queued)

      # The first look finds the hold, and gives up before the other types.
      wake(worker)

      assert_receive {:asked, Module1}, @timeout_ms
      refute_receive {:asked, Module2}, 100

      wake(worker)

      assert_receive {:asked, Module1}, @timeout_ms
      assert_receive {:asked, Module2}, @timeout_ms
    end

    # The wakes that arrive while a run works ask what the look after them answers. A run that
    # blocks holds the first look, and three wakes queue up behind it: Module1 is asked three times
    # in all - twice by the first look, whose second round finds nothing, and once by the look the
    # three wakes get.
    test "answers the wakes that arrived while it worked with one look" do
      queues = start_queues(%{Module1 => ["a"]})
      test_pid = self()

      run = fn job_type, id ->
        send(test_pid, {:running, self()})

        receive do
          :finish -> :ok
        end

        take_off(queues, job_type, id)
        :done
      end

      worker = start_worker_on!(queues, run: run)
      wake(worker)

      assert_receive {:running, ^worker}, @timeout_ms

      wake(worker)
      wake(worker)
      wake(worker)
      send(worker, :finish)

      for _ask <- 1..3, do: assert_receive({:asked, Module1, _skip_ids}, @timeout_ms)
      refute_receive {:asked, Module1, _skip_ids}, 100
    end

    test "sweeps nothing" do
      worker = start_worker!(sweep: sweep_stub(self()))

      assert_receive {:swept, _job_types, _skip_ids}, @timeout_ms

      wake(worker)

      refute_receive {:swept, _job_types, _skip_ids}, 100
    end
  end

  describe "handle :notification" do
    test "runs the job a write announces" do
      queues = start_queues(%{})
      worker = start_worker_on!(queues)

      Agent.update(queues, &Map.put(&1, Module2, ["a"]))
      send(worker, {:notification, self(), make_ref(), "hologram_oplog", ""})

      assert_receive {:ran, Module2, "a"}, @timeout_ms
    end
  end

  describe "handle :poll" do
    test "runs the queued jobs on its own, without being told to" do
      queues = start_queues(%{})
      start_worker_on!(queues, poll_interval_ms: @poll_interval_ms)

      Agent.update(queues, &Map.put(&1, Module1, ["a"]))

      assert_receive {:ran, Module1, "a"}, @timeout_ms
    end

    # A run cut short on another node is failed within one poll interval.
    test "keeps sweeping every job type" do
      start_worker!(sweep: sweep_stub(self()), poll_interval_ms: @poll_interval_ms)

      for _sweep <- 1..3 do
        assert_receive {:swept, [Module1, Module2, Module3], _skip_ids}, @timeout_ms
      end
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
