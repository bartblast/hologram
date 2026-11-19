defmodule Hologram.Test.BrowserSessionTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO
  import ExUnit.CaptureLog
  import Hologram.Test.BrowserSession

  @base_url "http://localhost:9515/"
  @beam_command "/usr/local/lib/erlang/erts-16.0/bin/beam.smp -- -root /usr/local/lib/erlang"
  @capabilities %{browserName: "chrome"}
  @default_chrome_args ["--headless", "--no-sandbox"]
  @warm_up_messages [{:session_started, "warm-up"}, {:session_ended, "warm-up"}]

  defmodule StandInChromedriver do
    use GenServer

    # answer_fn says how to answer a readiness wait: :ready, :silent or :crash.
    @spec start_link((-> atom)) :: GenServer.on_start()
    def start_link(answer_fn), do: GenServer.start_link(__MODULE__, answer_fn)

    @impl GenServer
    def init(answer_fn), do: {:ok, answer_fn}

    @impl GenServer
    def handle_call(:wait_until_ready, _from, answer_fn) do
      case answer_fn.() do
        :crash -> raise "not ready"
        :ready -> {:reply, :ok, answer_fn}
        :silent -> {:noreply, answer_fn}
      end
    end
  end

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

  defp assert_restarted_once(log_dir, messages_after_start) do
    wrapper_path = Path.join(log_dir, "chromedriver")

    assert Process.info(self(), :messages) ==
             {:messages,
              [
                :stopped,
                {:put_env, :wallaby, :chromedriver,
                 [path: wrapper_path, capabilities: marked_capabilities()]},
                {:put_env, :hologram, :__browser_session_log_dir__, log_dir},
                :started,
                :stopped,
                :started
              ] ++ messages_after_start}
  end

  # A crashed stand-in is restarted by its supervisor in the background, while a
  # real Wallaby start returns with every ChromeDriver server up.
  defp await_chromedrivers do
    children = PartitionSupervisor.which_children(:browser_session_test_chromedrivers)

    all_alive? =
      Enum.all?(children, fn {_partition, pid, _type, _modules} ->
        is_pid(pid) and Process.alive?(pid)
      end)

    if !all_alive? do
      Process.sleep(1)
      await_chromedrivers()
    end
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

  # The capabilities start_wallaby/1 gives Wallaby when its config has none: the
  # stand-in defaults with the run's marker after their Chrome args.
  defp marked_capabilities do
    %{chromeOptions: %{args: ["--headless", "--no-sandbox", run_marker(System.pid())]}}
  end

  # What `ps` prints: a line per process, with the pid right-aligned and then the
  # command line.
  defp ps_fn(processes) do
    listing =
      Enum.map_join(processes, fn {pid, command} ->
        String.pad_leading(pid, 5) <> " " <> command <> "\n"
      end)

    fn -> listing end
  end

  defp run_marker(run_pid), do: "--hologram-test-run=" <> run_pid

  # Partition 1 answers as answer_fn says for the current start, partition 0 is ready.
  defp start_chromedrivers(answer_fn) do
    starts = :counters.new(1, [])

    partition_answer_fn = fn
      0 ->
        :ready

      1 ->
        start = :counters.get(starts, 1)
        answer_fn.(start)
    end

    start_supervised!(
      {PartitionSupervisor,
       child_spec: {StandInChromedriver, nil},
       name: :browser_session_test_chromedrivers,
       partitions: 2,
       with_arguments: fn [nil], partition -> [fn -> partition_answer_fn.(partition) end] end}
    )

    starts
  end

  # A Chrome that ChromeDriver started for the run of the BEAM with the given pid.
  defp test_browser_command(run_pid) do
    "/opt/chrome/chrome --headless --test-type=webdriver --no-sandbox " <> run_marker(run_pid)
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

      assert_receive {:deleted, :other_session}, 5_000
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

      assert_receive {:deleted, :hung_session}, 5_000
      refute_receive {:deleted, :other_test_session}, 100

      Process.exit(other_test_pid, :kill)

      assert_receive {:deleted, :other_test_session}, 5_000
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
                 attempt_timeout: 500,
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
          attempt_timeout: 500,
          attempts: 2,
          create_fn: create_fn,
          delete_fn: deleting_fn(self())
        )
      end)

      assert_receive {:attempt_started, worker}, 5_000
      refute_received {:deleted, _base_url, _session_id}

      send(worker, :release)

      assert_receive {:deleted, @base_url, "abandoned"}, 5_000
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

      assert_receive {:attempt_started, worker}, 5_000

      caller_ref = Process.monitor(caller)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^caller_ref, :process, ^caller, :killed}, 5_000

      send(worker, :release)

      assert_receive {:deleted, @base_url, "orphaned"}, 5_000
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
          attempt_timeout: 500,
          attempts: 3,
          create_fn: create_fn,
          log_dir: tmp_dir
        )
      end)

      hangs =
        tmp_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs ==
               normalize_newlines("""
               Chrome session didn't start within 500 ms (attempt 1 of 3), retrying
               Chrome session didn't start within 500 ms (attempt 2 of 3), retrying
               """)
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

      assert hangs ==
               normalize_newlines("""
               Chrome session didn't start within 50 ms (attempt 1 of 2), retrying
               #{message}
               """)
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

  describe "start_wallaby/1" do
    @describetag :skip_on_windows
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} = context do
      # A ChromeDriver stand-in that writes its pid and args, one per line.
      args_path = Path.join(tmp_dir, "args.txt")
      chromedriver_path = Path.join(tmp_dir, "fake chromedriver")

      File.write!(chromedriver_path, """
      #!/bin/sh
      args_path="$(dirname "$0")/args.txt"
      echo $$ > "$args_path"
      for arg in "$@"; do echo "$arg" >> "$args_path"; done
      """)

      File.chmod!(chromedriver_path, 0o755)

      # A quote and a space, so the wrapper has to quote its paths.
      runs_log_dir = Path.join(tmp_dir, "it's logs")
      log_dir = Path.join(runs_log_dir, System.pid())

      # How partition 1 answers on each start, :ready unless a test tags otherwise.
      answers = Map.get(context, :chromedriver_answers, %{})
      starts = start_chromedrivers(&Map.get(answers, &1, :ready))

      # The warm-up session ends in a worker, so its stand-in sends to the test.
      test_pid = self()

      opts = [
        chromedriver_path: chromedriver_path,
        chromedrivers: :browser_session_test_chromedrivers,
        create_fn: fn _base_url, _capabilities -> {:ok, %{"sessionId" => "warm-up"}} end,
        default_capabilities_fn: fn -> %{chromeOptions: %{args: @default_chrome_args}} end,
        end_session_fn: fn session -> send(test_pid, {:session_ended, session}) end,
        kill_fn: fn pids -> send(self(), {:killed, pids}) end,
        log_dir: runs_log_dir,
        # No ps, unless a test lists processes of its own.
        ps_fn: fn -> nil end,
        put_env_fn: fn app, key, value -> send(self(), {:put_env, app, key, value}) end,
        ready_timeout: 5_000,
        start_fn: fn ->
          await_chromedrivers()
          :counters.add(starts, 1, 1)
          send(self(), :started)
        end,
        # Like Wallaby.start_session/1, it answers what the create fn answers.
        start_session_fn: fn session_opts ->
          with {:ok, %{"sessionId" => session}} <-
                 session_opts[:create_session_fn].(@base_url, @capabilities) do
            send(test_pid, {:session_started, session})
            {:ok, session}
          end
        end,
        stop_fn: fn -> send(self(), :stopped) end
      ]

      [args_path: args_path, log_dir: log_dir, opts: opts, runs_log_dir: runs_log_dir]
    end

    test "stops Wallaby, points it at a ChromeDriver wrapper, marks its browsers and sets the run's log dir, starts it, then starts and ends a browser session",
         %{
           log_dir: log_dir,
           opts: opts
         } do
      assert start_wallaby(opts) == :ok

      wrapper_path = Path.join(log_dir, "chromedriver")

      assert Process.info(self(), :messages) ==
               {:messages,
                [
                  :stopped,
                  {:put_env, :wallaby, :chromedriver,
                   [path: wrapper_path, capabilities: marked_capabilities()]},
                  {:put_env, :hologram, :__browser_session_log_dir__, log_dir},
                  :started
                  | @warm_up_messages
                ]}
    end

    test "keeps the rest of Wallaby's ChromeDriver config", %{log_dir: log_dir, opts: opts} do
      # No other test reads it, and tests within a module run one at a time.
      Application.put_env(:wallaby, :chromedriver, binary: "/opt/chrome/chrome")
      on_exit(fn -> Application.delete_env(:wallaby, :chromedriver) end)

      start_wallaby(opts)

      wrapper_path = Path.join(log_dir, "chromedriver")

      assert_received {:put_env, :wallaby, :chromedriver, chromedriver_env}

      assert chromedriver_env == [
               path: wrapper_path,
               capabilities: marked_capabilities(),
               binary: "/opt/chrome/chrome"
             ]
    end

    test "adds the run's marker after the configured Chrome args, keeping the other capabilities",
         %{opts: opts} do
      capabilities = %{
        chromeOptions: %{args: ["--headless", "--window-size=1280,800"], binary: "/opt/chrome"},
        javascriptEnabled: true
      }

      # No other test reads it, and tests within a module run one at a time.
      Application.put_env(:wallaby, :chromedriver, capabilities: capabilities)
      on_exit(fn -> Application.delete_env(:wallaby, :chromedriver) end)

      start_wallaby(opts)

      assert_received {:put_env, :wallaby, :chromedriver, chromedriver_env}

      assert chromedriver_env[:capabilities] == %{
               chromeOptions: %{
                 args: ["--headless", "--window-size=1280,800", run_marker(System.pid())],
                 binary: "/opt/chrome"
               },
               javascriptEnabled: true
             }
    end

    test "adds the run's marker to configured capabilities that have no Chrome options", %{
      opts: opts
    } do
      # No other test reads it, and tests within a module run one at a time.
      Application.put_env(:wallaby, :chromedriver, capabilities: %{javascriptEnabled: true})
      on_exit(fn -> Application.delete_env(:wallaby, :chromedriver) end)

      start_wallaby(opts)

      assert_received {:put_env, :wallaby, :chromedriver, chromedriver_env}

      assert chromedriver_env[:capabilities] == %{
               chromeOptions: %{args: [run_marker(System.pid())]},
               javascriptEnabled: true
             }
    end

    test "replaces a run's marker already among the configured Chrome args", %{opts: opts} do
      capabilities = %{chromeOptions: %{args: [run_marker("123"), "--headless"]}}

      # No other test reads it, and tests within a module run one at a time.
      Application.put_env(:wallaby, :chromedriver, capabilities: capabilities)
      on_exit(fn -> Application.delete_env(:wallaby, :chromedriver) end)

      start_wallaby(opts)

      assert_received {:put_env, :wallaby, :chromedriver, chromedriver_env}

      assert chromedriver_env[:capabilities] == %{
               chromeOptions: %{args: ["--headless", run_marker(System.pid())]}
             }
    end

    test "kills the test browsers whose run's BEAM is gone, before it starts Wallaby", %{
      opts: opts
    } do
      ps_fn =
        ps_fn([
          {"1", "/sbin/launchd"},
          {"700", test_browser_command("500")},
          {"701", test_browser_command("500")}
        ])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      assert {:messages,
              [:stopped, {:killed, ["700", "701"]}, {:put_env, :wallaby, _key, _value} | _rest]} =
               Process.info(self(), :messages)
    end

    test "kills a test browser whose program's path holds spaces", %{opts: opts} do
      command =
        "/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing " <>
          "--headless --test-type=webdriver " <> run_marker("500")

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn([{"700", command}])))

      assert_received {:killed, ["700"]}
    end

    test "leaves alone a test browser whose run's BEAM is still running", %{opts: opts} do
      ps_fn = ps_fn([{"500", @beam_command}, {"700", test_browser_command("500")}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      refute_received {:killed, _pids}
    end

    test "leaves alone the test browsers of BEAMs of other builds, at a path with a space, and with no args",
         %{opts: opts} do
      ps_fn =
        ps_fn([
          {"500", "/opt/erlang/erts-16.0/bin/beam.debug.smp -- -root /opt/erlang"},
          {"501", "/opt/erlang/erts-16.0/bin/beam.debug.emu.smp -- -root /opt/erlang"},
          {"502", "/opt/my erlang/erts-16.0/bin/beam.smp"},
          {"700", test_browser_command("500")},
          {"701", test_browser_command("501")},
          {"702", test_browser_command("502")}
        ])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      refute_received {:killed, _pids}
    end

    test "kills a test browser whose run's pid now names a process that isn't a BEAM", %{
      opts: opts
    } do
      # Not a BEAM, though it names one.
      ps_fn = ps_fn([{"500", "/usr/bin/vim beam.smp.txt"}, {"700", test_browser_command("500")}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      assert_received {:killed, ["700"]}
    end

    test "kills a test browser marked with this BEAM's pid, left by an earlier run that had it",
         %{
           opts: opts
         } do
      ps_fn =
        ps_fn([{System.pid(), @beam_command}, {"700", test_browser_command(System.pid())}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      assert_received {:killed, ["700"]}
    end

    test "kills a test browser whose run's pid is only the start of a running BEAM's pid", %{
      opts: opts
    } do
      ps_fn = ps_fn([{"5000", @beam_command}, {"700", test_browser_command("500")}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      assert_received {:killed, ["700"]}
    end

    test "leaves alone a test browser with no run marker, a marked process that isn't a test browser, and every other process",
         %{opts: opts} do
      ps_fn =
        ps_fn([
          {"1", "/sbin/launchd"},
          {"700", "/opt/chrome/chrome --headless --test-type=webdriver --no-sandbox"},
          {"701", "/opt/chrome/chrome --type=renderer --test-type=webdriver"},
          {"702", "/opt/chrome/chrome --headless " <> run_marker("500")},
          {"703", @beam_command}
        ])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      refute_received {:killed, _pids}
    end

    test "leaves alone a process that isn't Chrome, with a test browser's switches among its args",
         %{opts: opts} do
      ps_fn = ps_fn([{"700", "/bin/zsh -c echo " <> test_browser_command("500")}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      refute_received {:killed, _pids}
    end

    test "leaves alone a process whose switches only start like a test browser's, hold a marker inside, or name no pid",
         %{opts: opts} do
      ps_fn =
        ps_fn([
          {"700", "/opt/chrome/chrome --test-type=webdriver2 " <> run_marker("500")},
          {"701", "/opt/chrome/chrome --test-type=webdriver --x" <> run_marker("500")},
          {"702", "/opt/chrome/chrome --test-type=webdriver " <> run_marker("abc")}
        ])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      refute_received {:killed, _pids}
    end

    test "kills nothing when the processes can't be listed", %{opts: opts} do
      start_wallaby(Keyword.put(opts, :ps_fn, fn -> nil end))

      refute_received {:killed, _pids}
    end

    test "kills a test browser whose run's BEAM is gone, found with the real ps", %{
      opts: opts,
      tmp_dir: tmp_dir
    } do
      # A stand-in that sleeps, named like Chrome, with a test browser's switches
      # after its own args. No process has the pid it names, since pids stay far
      # below it.
      chrome_path = Path.join(tmp_dir, "chrome")

      "perl"
      |> System.find_executable()
      |> File.ln_s!(chrome_path)

      port =
        Port.open({:spawn_executable, chrome_path}, [
          :exit_status,
          args: ["-e", "sleep 60", "--", "--test-type=webdriver", run_marker("999999999")]
        ])

      {:os_pid, os_pid} = Port.info(port, :os_pid)
      on_exit(fn -> System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true) end)

      opts = Keyword.drop(opts, [:kill_fn, :ps_fn])

      assert start_wallaby(opts) == :ok

      # SIGTERM ends it with status 128 + 15.
      assert_receive {^port, {:exit_status, 143}}, 5_000
    end

    test "the wrapper runs ChromeDriver with the log flags after Wallaby's args", %{
      args_path: args_path,
      log_dir: log_dir,
      opts: opts
    } do
      start_wallaby(opts)

      wrapper_path = Path.join(log_dir, "chromedriver")
      {"", 0} = System.cmd(wrapper_path, ["--log-level=OFF", "--port=9515"])

      [pid | args] =
        args_path
        |> File.read!()
        |> String.split("\n", trim: true)

      assert args == [
               "--log-level=OFF",
               "--port=9515",
               "--log-level=DEBUG",
               "--log-path=#{log_dir}/chromedriver-#{pid}.log",
               "--enable-chrome-logs",
               "--readable-timestamp"
             ]
    end

    test "the wrapper passes --version on without the log flags", %{
      args_path: args_path,
      log_dir: log_dir,
      opts: opts
    } do
      start_wallaby(opts)

      wrapper_path = Path.join(log_dir, "chromedriver")
      {"", 0} = System.cmd(wrapper_path, ["--version"])

      [_pid | args] =
        args_path
        |> File.read!()
        |> String.split("\n", trim: true)

      assert args == ["--version"]
    end

    @tag chromedriver_answers: %{1 => :silent}
    test "restarts Wallaby when a ChromeDriver doesn't get ready in time, and reports it", %{
      log_dir: log_dir,
      opts: opts
    } do
      capture_io(fn ->
        assert start_wallaby(Keyword.merge(opts, attempts: 3, ready_timeout: 500)) == :ok
      end)

      assert_restarted_once(log_dir, @warm_up_messages)

      hangs =
        log_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs == "ChromeDriver didn't get ready (attempt 1 of 3), restarting Wallaby\n"
    end

    @tag chromedriver_answers: %{1 => :crash}
    test "restarts Wallaby when a ChromeDriver server crashes", %{log_dir: log_dir, opts: opts} do
      capture_log(fn ->
        capture_io(fn -> assert start_wallaby(opts) == :ok end)
      end)

      assert_restarted_once(log_dir, @warm_up_messages)
    end

    test "deletes the log dir of a run whose BEAM is gone, and keeps the log dir of a run whose BEAM is still running",
         %{opts: opts, runs_log_dir: runs_log_dir} do
      for run_pid <- ["500", "501"] do
        run_log_dir = Path.join(runs_log_dir, run_pid)
        File.mkdir_p!(run_log_dir)

        run_log_dir
        |> Path.join("chromedriver-123.log")
        |> File.write!("another run")
      end

      ps_fn = ps_fn([{"501", @beam_command}, {System.pid(), @beam_command}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      run_log_dirs =
        runs_log_dir
        |> File.ls!()
        |> Enum.sort()

      assert run_log_dirs == Enum.sort(["501", System.pid()])

      kept_logs =
        runs_log_dir
        |> Path.join("501")
        |> File.ls!()

      assert kept_logs == ["chromedriver-123.log"]
    end

    test "keeps the log dir of a run that starts after the log dirs are read", %{
      opts: opts,
      runs_log_dir: runs_log_dir
    } do
      # The run is too new to be among the processes, and so is its log dir.
      ps_fn = fn ->
        runs_log_dir
        |> Path.join("600")
        |> File.mkdir_p!()

        ps_fn([{System.pid(), @beam_command}]).()
      end

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      run_log_dirs =
        runs_log_dir
        |> File.ls!()
        |> Enum.sort()

      assert run_log_dirs == Enum.sort(["600", System.pid()])
    end

    test "deletes the log dir of a run whose pid now names a process that isn't a BEAM", %{
      opts: opts,
      runs_log_dir: runs_log_dir
    } do
      runs_log_dir
      |> Path.join("500")
      |> File.mkdir_p!()

      ps_fn = ps_fn([{"500", "/usr/bin/vim notes.txt"}, {System.pid(), @beam_command}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      assert File.ls!(runs_log_dir) == [System.pid()]
    end

    test "deletes the files left from when the log dir held one run's logs", %{
      opts: opts,
      runs_log_dir: runs_log_dir
    } do
      File.mkdir_p!(runs_log_dir)

      for file_name <- ["chromedriver", "chromedriver-123.log", "hangs.txt"] do
        runs_log_dir
        |> Path.join(file_name)
        |> File.write!("earlier run")
      end

      ps_fn = ps_fn([{System.pid(), @beam_command}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      assert File.ls!(runs_log_dir) == [System.pid()]
    end

    test "empties its own log dir, left by an earlier run whose BEAM had the same pid", %{
      log_dir: log_dir,
      opts: opts
    } do
      File.mkdir_p!(log_dir)

      log_dir
      |> Path.join("hangs.txt")
      |> File.write!("earlier run")

      ps_fn = ps_fn([{System.pid(), @beam_command}])

      start_wallaby(Keyword.put(opts, :ps_fn, ps_fn))

      assert File.ls!(log_dir) == ["chromedriver"]
    end

    test "deletes every other run's log dir when the processes can't be listed", %{
      opts: opts,
      runs_log_dir: runs_log_dir
    } do
      runs_log_dir
      |> Path.join("500")
      |> File.mkdir_p!()

      start_wallaby(Keyword.put(opts, :ps_fn, fn -> nil end))

      assert File.ls!(runs_log_dir) == [System.pid()]
    end

    test "raises after the last attempt, also when Wallaby's ChromeDriver tree is gone", %{
      log_dir: log_dir,
      opts: opts
    } do
      capture_io(fn ->
        assert_error RuntimeError, "ChromeDriver didn't get ready after 2 attempts", fn ->
          start_wallaby(Keyword.merge(opts, attempts: 2, chromedrivers: :missing_chromedrivers))
        end
      end)

      assert_restarted_once(log_dir, [])

      hangs =
        log_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs ==
               normalize_newlines("""
               ChromeDriver didn't get ready (attempt 1 of 2), restarting Wallaby
               ChromeDriver didn't get ready after 2 attempts
               """)
    end

    test "lets Wallaby's HTTP requests wait while the browser session starts, then unsets the config again",
         %{opts: opts} do
      test_pid = self()

      create_fn = fn _base_url, _capabilities ->
        send(test_pid, {:hackney_options, Application.get_env(:wallaby, :hackney_options)})
        {:ok, %{"sessionId" => "warm-up"}}
      end

      assert start_wallaby(Keyword.put(opts, :create_fn, create_fn)) == :ok

      assert_received {:hackney_options,
                       [recv_timeout: :infinity, hackney: [pool: :wallaby_pool]]}

      assert Application.fetch_env(:wallaby, :hackney_options) == :error
    end

    test "lets Wallaby's HTTP requests wait while the browser session starts, then puts the config back before ending it",
         %{opts: opts} do
      # No other test reads it, and tests within a module run one at a time.
      Application.put_env(:wallaby, :hackney_options, timeout: 60_000, recv_timeout: 60_000)
      on_exit(fn -> Application.delete_env(:wallaby, :hackney_options) end)

      test_pid = self()

      create_fn = fn _base_url, _capabilities ->
        send(test_pid, {:hackney_options, Application.get_env(:wallaby, :hackney_options)})
        {:ok, %{"sessionId" => "warm-up"}}
      end

      end_session_fn = fn _session ->
        send(test_pid, {:ending_hackney_options, Application.get_env(:wallaby, :hackney_options)})
      end

      assert start_wallaby(
               Keyword.merge(opts, create_fn: create_fn, end_session_fn: end_session_fn)
             ) == :ok

      assert_received {:hackney_options, [recv_timeout: :infinity, timeout: 60_000]}
      assert_received {:ending_hackney_options, [timeout: 60_000, recv_timeout: 60_000]}

      assert Application.fetch_env(:wallaby, :hackney_options) ==
               {:ok, [timeout: 60_000, recv_timeout: 60_000]}
    end

    test "raises when the browser session doesn't start in time, and reports it", %{
      log_dir: log_dir,
      opts: opts
    } do
      create_fn = fn _base_url, _capabilities -> Process.sleep(:infinity) end
      message = "Chrome didn't start its first browser session within 50 ms"

      capture_io(fn ->
        assert_error RuntimeError, message, fn ->
          start_wallaby(Keyword.merge(opts, create_fn: create_fn, warm_up_timeout: 50))
        end
      end)

      hangs =
        log_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs == message <> "\n"
      assert Application.fetch_env(:wallaby, :hackney_options) == :error
    end

    test "deletes the browser session that starts after it was given up on", %{opts: opts} do
      opts =
        Keyword.merge(opts,
          create_fn: blocking_create_fn(self(), "warm-up"),
          delete_fn: deleting_fn(self()),
          warm_up_timeout: 50
        )

      capture_io(fn ->
        assert_error RuntimeError,
                     "Chrome didn't start its first browser session within 50 ms",
                     fn -> start_wallaby(opts) end
      end)

      assert_receive {:attempt_started, worker}, 5_000
      refute_received {:deleted, _base_url, _session_id}

      send(worker, :release)

      assert_receive {:deleted, @base_url, "warm-up"}, 5_000
    end

    test "raises when the browser session start answers with an error, without reporting it", %{
      log_dir: log_dir,
      opts: opts
    } do
      create_fn = fn _base_url, _capabilities -> {:error, :invalid} end

      assert_error RuntimeError, "Chrome didn't start its first browser session: :invalid", fn ->
        start_wallaby(Keyword.put(opts, :create_fn, create_fn))
      end

      refute log_dir
             |> Path.join("hangs.txt")
             |> File.exists?()
    end

    test "raises what the browser session start raises, without reporting it", %{
      log_dir: log_dir,
      opts: opts
    } do
      create_fn = fn _base_url, _capabilities -> raise "boom" end

      assert_error RuntimeError, "boom", fn ->
        start_wallaby(Keyword.put(opts, :create_fn, create_fn))
      end

      refute log_dir
             |> Path.join("hangs.txt")
             |> File.exists?()
    end

    test "exits with what the browser session start exits with", %{opts: opts} do
      create_fn = fn _base_url, _capabilities -> exit(:gone) end

      assert catch_exit(start_wallaby(Keyword.put(opts, :create_fn, create_fn))) == :gone
    end

    test "reports a browser session that doesn't end in time, and returns :ok", %{
      log_dir: log_dir,
      opts: opts
    } do
      end_session_fn = fn _session -> Process.sleep(:infinity) end

      capture_io(fn ->
        assert start_wallaby(
                 Keyword.merge(opts, end_session_fn: end_session_fn, teardown_timeout: 50)
               ) == :ok
      end)

      hangs =
        log_dir
        |> Path.join("hangs.txt")
        |> File.read!()

      assert hangs == "Chrome didn't end its first browser session within 50 ms\n"
    end
  end
end
