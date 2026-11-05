defmodule Hologram.Test.BrowserSessionTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO
  import Hologram.Test.BrowserSession

  @base_url "http://localhost:9515/"
  @capabilities %{browserName: "chrome"}

  defmodule StandInStore do
    use GenServer

    @spec start_link(atom) :: GenServer.on_start()
    def start_link(name), do: GenServer.start_link(__MODULE__, nil, name: name)

    @impl GenServer
    def init(state), do: {:ok, state}
  end

  defp alive_process do
    spawn(fn -> Process.sleep(:infinity) end)
  end

  defp blocking_create_fn(test_pid, session_id) do
    fn _base_url, _capabilities ->
      send(test_pid, {:attempt_started, self()})

      receive do
        :release -> {:ok, %{"sessionId" => session_id}}
      end
    end
  end

  defp counted_create_fn(counter, fun) do
    fn base_url, capabilities ->
      :counters.add(counter, 1, 1)
      attempt = :counters.get(counter, 1)

      fun.(attempt, base_url, capabilities)
    end
  end

  defp dead_process do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> pid
    end
  end

  defp deleting_fn(test_pid) do
    fn base_url, session_id -> send(test_pid, {:deleted, base_url, session_id}) end
  end

  defp start_store_supervisor(store) do
    child_spec = %{id: store, start: {StandInStore, :start_link, [store]}}

    start_supervised!(%{
      id: :store_supervisor,
      start: {Supervisor, :start_link, [[child_spec], [strategy: :one_for_one]]},
      type: :supervisor
    })
  end

  describe "await_teardown/2" do
    setup do
      # Tests within a module run one at a time, so a fixed name is safe.
      store = :browser_session_test_store
      supervisor = start_store_supervisor(store)

      [store: store, supervisor: supervisor]
    end

    test "returns :ok and keeps the store when the test has no sessions left", %{
      store: store,
      supervisor: supervisor
    } do
      store_pid = Process.whereis(store)
      other_test_pid = alive_process()

      assert await_teardown(self(),
               sessions_fn: fn -> [{other_test_pid, :other_test_session}] end,
               store: store,
               supervisor: supervisor,
               timeout: 5_000
             ) == :ok

      assert Process.whereis(store) == store_pid
    end

    test "waits for the store to end the test's sessions", %{store: store, supervisor: supervisor} do
      store_pid = Process.whereis(store)
      test_pid = self()
      {:ok, sessions} = Agent.start_link(fn -> [{test_pid, :session}] end)

      task =
        Task.async(fn ->
          await_teardown(test_pid,
            sessions_fn: fn -> Agent.get(sessions, & &1) end,
            store: store,
            supervisor: supervisor,
            timeout: 5_000
          )
        end)

      refute Task.yield(task, 100)

      Agent.update(sessions, fn _sessions -> [] end)

      assert Task.await(task) == :ok
      assert Process.whereis(store) == store_pid
    end

    test "returns :ok when Wallaby isn't running" do
      assert await_teardown(self(), store: :not_running_store, timeout: 5_000) == :ok
    end

    @tag :tmp_dir
    test "restarts a store that doesn't end the test's sessions in time, and reports it", %{
      store: store,
      supervisor: supervisor,
      tmp_dir: tmp_dir
    } do
      store_pid = Process.whereis(store)
      test_pid = self()

      capture_io(fn ->
        assert await_teardown(test_pid,
                 delete_fn: fn _session -> :ok end,
                 log_dir: tmp_dir,
                 sessions_fn: fn -> [{test_pid, :hung_session}] end,
                 store: store,
                 supervisor: supervisor,
                 timeout: 50
               ) == :ok
      end)

      new_store_pid = Process.whereis(store)

      assert is_pid(new_store_pid)
      refute new_store_pid == store_pid

      hangs =
        tmp_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs ==
               ":browser_session_test_store didn't end the test's browser sessions within 50 ms, restarting it\n"
    end

    test "deletes the sessions a restarted store dropped, each on its own", %{
      store: store,
      supervisor: supervisor
    } do
      test_pid = self()
      dead_test_pid = dead_process()

      # The hung session's DELETE never returns.
      delete_fn = fn
        :hung_session -> Process.sleep(:infinity)
        session -> send(test_pid, {:deleted, session})
      end

      sessions_fn = fn -> [{dead_test_pid, :hung_session}, {dead_test_pid, :other_session}] end

      capture_io(fn ->
        assert await_teardown(dead_test_pid,
                 delete_fn: delete_fn,
                 sessions_fn: sessions_fn,
                 store: store,
                 supervisor: supervisor,
                 timeout: 50
               ) == :ok
      end)

      assert_receive {:deleted, :other_session}
    end

    test "deletes a running test's session the restarted store dropped once that test ends", %{
      store: store,
      supervisor: supervisor
    } do
      test_pid = self()
      ended_test_pid = dead_process()
      other_test_pid = alive_process()

      sessions_fn = fn ->
        [{ended_test_pid, :hung_session}, {other_test_pid, :other_test_session}]
      end

      capture_io(fn ->
        await_teardown(ended_test_pid,
          delete_fn: fn session -> send(test_pid, {:deleted, session}) end,
          sessions_fn: sessions_fn,
          store: store,
          supervisor: supervisor,
          timeout: 50
        )
      end)

      assert_receive {:deleted, :hung_session}
      refute_receive {:deleted, :other_test_session}, 100

      Process.exit(other_test_pid, :kill)

      assert_receive {:deleted, :other_test_session}
    end

    @tag :tmp_dir
    test "leaves alone a store another test restarted meanwhile", %{
      store: store,
      supervisor: supervisor,
      tmp_dir: tmp_dir
    } do
      restarted = :counters.new(1, [])
      test_pid = self()

      # Restarts the store on the first look, as another test's await_teardown/2 would.
      sessions_fn = fn ->
        if :counters.get(restarted, 1) == 0 do
          :counters.add(restarted, 1, 1)
          :ok = Supervisor.terminate_child(supervisor, store)
          {:ok, pid} = Supervisor.restart_child(supervisor, store)
          send(test_pid, {:restarted, pid})
        end

        [{test_pid, :hung_session}]
      end

      await_teardown(test_pid,
        delete_fn: fn _session -> :ok end,
        log_dir: tmp_dir,
        sessions_fn: sessions_fn,
        store: store,
        supervisor: supervisor,
        timeout: 50
      )

      assert_received {:restarted, restarted_store_pid}
      assert Process.whereis(store) == restarted_store_pid
      hangs_path = Path.join(tmp_dir, "hangs.txt")
      refute File.exists?(hangs_path)
    end
  end

  describe "create_session/3" do
    test "returns the result of an attempt that answers in time" do
      create_fn = fn base_url, capabilities ->
        {:ok, %{"base_url" => base_url, "capabilities" => capabilities, "sessionId" => "abc"}}
      end

      assert create_session(@base_url, @capabilities,
               attempt_timeout: 5_000,
               create_fn: create_fn
             ) ==
               {:ok,
                %{"base_url" => @base_url, "capabilities" => @capabilities, "sessionId" => "abc"}}
    end

    test "retries an attempt that doesn't answer in time and returns the next attempt's result" do
      counter = :counters.new(1, [])

      create_fn =
        counted_create_fn(counter, fn
          1, _base_url, _capabilities -> Process.sleep(:infinity)
          2, _base_url, _capabilities -> {:ok, %{"sessionId" => "second"}}
        end)

      capture_io(fn ->
        assert create_session(@base_url, @capabilities,
                 attempt_timeout: 50,
                 attempts: 3,
                 create_fn: create_fn
               ) == {:ok, %{"sessionId" => "second"}}
      end)

      assert :counters.get(counter, 1) == 2
    end

    test "returns an error an attempt answers with, without retrying" do
      counter = :counters.new(1, [])

      create_fn =
        counted_create_fn(counter, fn _n, _base_url, _capabilities -> {:error, :invalid} end)

      assert create_session(@base_url, @capabilities,
               attempt_timeout: 5_000,
               create_fn: create_fn
             ) ==
               {:error, :invalid}

      assert :counters.get(counter, 1) == 1
    end

    test "deletes the session an abandoned attempt creates after it was abandoned" do
      counter = :counters.new(1, [])
      blocking_fn = blocking_create_fn(self(), "abandoned")

      create_fn =
        counted_create_fn(counter, fn
          1, base_url, capabilities -> blocking_fn.(base_url, capabilities)
          2, _base_url, _capabilities -> {:ok, %{"sessionId" => "second"}}
        end)

      capture_io(fn ->
        create_session(@base_url, @capabilities,
          attempt_timeout: 50,
          attempts: 2,
          create_fn: create_fn,
          delete_fn: deleting_fn(self())
        )
      end)

      assert_receive {:attempt_started, worker}
      refute_received {:deleted, _base_url, _session_id}

      send(worker, :release)

      assert_receive {:deleted, @base_url, "abandoned"}
    end

    test "deletes the session an attempt creates after its caller died" do
      test_pid = self()

      caller =
        spawn(fn ->
          create_session(@base_url, @capabilities,
            attempt_timeout: 5_000,
            create_fn: blocking_create_fn(test_pid, "orphaned"),
            delete_fn: deleting_fn(test_pid)
          )
        end)

      assert_receive {:attempt_started, worker}

      caller_ref = Process.monitor(caller)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^caller_ref, :process, ^caller, :killed}

      send(worker, :release)

      assert_receive {:deleted, @base_url, "orphaned"}
    end

    @tag :tmp_dir
    test "writes a line to hangs.txt in the log dir for each abandoned attempt", %{
      tmp_dir: tmp_dir
    } do
      counter = :counters.new(1, [])

      create_fn =
        counted_create_fn(counter, fn
          3, _base_url, _capabilities -> {:ok, %{"sessionId" => "third"}}
          _n, _base_url, _capabilities -> Process.sleep(:infinity)
        end)

      capture_io(fn ->
        create_session(@base_url, @capabilities,
          attempt_timeout: 50,
          attempts: 3,
          create_fn: create_fn,
          log_dir: tmp_dir
        )
      end)

      hangs =
        tmp_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs == """
             Chrome session didn't start within 50 ms (attempt 1 of 3), retrying
             Chrome session didn't start within 50 ms (attempt 2 of 3), retrying
             """
    end

    @tag :tmp_dir
    test "raises after the last attempt gets no answer, and reports it", %{tmp_dir: tmp_dir} do
      create_fn = fn _base_url, _capabilities -> Process.sleep(:infinity) end

      message =
        "Chrome didn't start a browser session: ChromeDriver gave no answer to 2 attempts, 50 ms each"

      capture_io(fn ->
        assert_error RuntimeError, message, fn ->
          create_session(@base_url, @capabilities,
            attempt_timeout: 50,
            attempts: 2,
            create_fn: create_fn,
            log_dir: tmp_dir
          )
        end
      end)

      hangs =
        tmp_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs == """
             Chrome session didn't start within 50 ms (attempt 1 of 2), retrying
             #{message}
             """
    end

    test "raises what an attempt raises, without retrying" do
      counter = :counters.new(1, [])
      create_fn = counted_create_fn(counter, fn _n, _base_url, _capabilities -> raise "boom" end)

      assert_error RuntimeError, "boom", fn ->
        create_session(@base_url, @capabilities, attempt_timeout: 5_000, create_fn: create_fn)
      end

      assert :counters.get(counter, 1) == 1
    end

    test "exits with what an attempt exits with, without retrying" do
      counter = :counters.new(1, [])
      create_fn = counted_create_fn(counter, fn _n, _base_url, _capabilities -> exit(:gone) end)

      assert catch_exit(
               create_session(@base_url, @capabilities,
                 attempt_timeout: 5_000,
                 create_fn: create_fn
               )
             ) == :gone

      assert :counters.get(counter, 1) == 1
    end
  end
end
