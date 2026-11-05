defmodule Hologram.Test.BrowserSessionTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO
  import Hologram.Test.BrowserSession

  @base_url "http://localhost:9515/"
  @capabilities %{browserName: "chrome"}

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

  defp deleting_fn(test_pid) do
    fn base_url, session_id -> send(test_pid, {:deleted, base_url, session_id}) end
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
