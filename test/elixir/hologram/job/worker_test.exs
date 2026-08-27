defmodule Hologram.Job.WorkerTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Job.Worker

  alias Hologram.Job.Worker
  alias Hologram.Test.Fixtures.Job.Module1
  alias Hologram.Test.Fixtures.Job.Module2
  alias Hologram.Test.Fixtures.Job.Module3

  @poll_interval_ms 20

  @timeout_ms 2_000

  # Stands in for a Postgrex.Notifications process, which answers listen/2 with a reference and
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

  # Reports every sweep to the test and answers how many jobs it ran, taken from the given list -
  # which is what lets a test say "this pass ran something, the next one did not" and watch the
  # worker keep passing until it stops.
  defp counting_pass(test_pid, counts) do
    {:ok, remaining} = Agent.start_link(fn -> counts end)

    fn job_types ->
      send(test_pid, {:passed, job_types})

      Agent.get_and_update(remaining, fn
        [] -> {0, []}
        [count | rest] -> {count, rest}
      end)
    end
  end

  defp start_worker!(opts) do
    opts =
      opts
      |> Keyword.put_new(:pass, fn _job_types -> 0 end)
      |> Keyword.put_new(:poll_interval_ms, :timer.minutes(1))

    start_supervised!({Worker, opts})
  end

  describe "start_link/1" do
    test "listens for writes on the outbox channel" do
      notifications = start_supervised!({NotificationsStub, reply_to: self()})

      start_worker!(notifications: notifications)

      assert_receive {:listening, "hologram_outbox"}, @timeout_ms
    end

    test "listens for nothing when given no notifications process" do
      start_worker!([])

      refute_receive {:listening, _channel}, 100
    end
  end

  describe "handle :wake" do
    test "passes over every job type the model holds, in module order" do
      worker = start_worker!(pass: counting_pass(self(), []))

      wake(worker)

      assert_receive {:passed, job_types}, @timeout_ms
      assert job_types == [Module1, Module2, Module3]
    end

    test "passes again while a pass runs something" do
      worker = start_worker!(pass: counting_pass(self(), [2, 1]))

      wake(worker)

      # Three in all: two that ran something, and the one that found nothing left.
      assert_receive {:passed, _job_types}, @timeout_ms
      assert_receive {:passed, _job_types}, @timeout_ms
      assert_receive {:passed, _job_types}, @timeout_ms
      refute_receive {:passed, _job_types}, 100
    end

    test "answers the wakes that arrived while it worked with one pass" do
      worker = start_worker!(pass: counting_pass(self(), []))

      wake(worker)
      wake(worker)
      wake(worker)

      assert_receive {:passed, _job_types}, @timeout_ms
      refute_receive {:passed, _job_types}, 100
    end
  end

  describe "handle :notification" do
    test "passes when a write is announced" do
      worker = start_worker!(pass: counting_pass(self(), []))

      send(worker, {:notification, self(), make_ref(), "hologram_outbox", ""})

      assert_receive {:passed, _job_types}, @timeout_ms
    end
  end

  describe "handle :poll" do
    test "passes on its own, without being told to" do
      start_worker!(pass: counting_pass(self(), []), poll_interval_ms: @poll_interval_ms)

      assert_receive {:passed, _job_types}, @timeout_ms
    end

    test "keeps polling" do
      start_worker!(pass: counting_pass(self(), []), poll_interval_ms: @poll_interval_ms)

      assert_receive {:passed, _job_types}, @timeout_ms
      assert_receive {:passed, _job_types}, @timeout_ms
    end
  end
end
