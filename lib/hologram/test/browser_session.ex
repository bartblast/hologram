defmodule Hologram.Test.BrowserSession do
  @moduledoc false

  # This is not public API - it is consumed by the Hologram test apps that run
  # browser tests, to keep a browser that stops answering from failing them.

  # Wallaby is not a Hologram dependency - client apps that use these helpers
  # bring their own. This lets the module compile without Wallaby present.
  @compile {:no_warn_undefined,
            [
              Wallaby,
              Wallaby.Chrome,
              Wallaby.Chrome.Chromedriver.Server,
              Wallaby.WebdriverClient
            ]}

  alias Wallaby.Chrome.Chromedriver.Server
  alias Wallaby.WebdriverClient

  # Tunable policy, not derived. A normal session start takes about a second. The
  # run's first one, which can take far longer on a fresh machine, is start_wallaby/1's.
  # The real bound is ExUnit's 60 s test timeout, which also covers setup, where
  # a test may start several sessions. Anything from about 5 s to 15 s per attempt
  # behaves the same.
  @default_attempt_timeout 10_000
  @default_attempts 3

  # Tunable policy, not derived. Wallaby's ChromeDriver server gives ChromeDriver a
  # hardcoded 10 s to get ready, so a shorter wait would restart a ChromeDriver
  # Wallaby would still take. Anything above that behaves the same.
  @default_ready_timeout 15_000

  # Tunable policy, not derived. Starting Wallaby runs before ExUnit, so no test
  # timeout bounds it. Each attempt takes up to the 10 s Wallaby allows.
  @default_start_attempts 3

  # Tunable policy, not derived. Ending a session takes well under a second. The
  # real bound is the on_exit callback's own timeout, which is the test timeout
  # (60 s), minus the store's 5 s shutdown wait on a restart.
  @default_teardown_timeout 10_000

  # Tunable policy, not derived. The first Chrome start on a fresh CI runner took
  # 36 s with three Chromes starting at once, and earlier hangs suggest it can take
  # over a minute. It's spent once per run, before any test, so a generous budget
  # costs nothing when Chrome answers. Anything from about 2 to 5 minutes behaves
  # the same.
  @default_warm_up_timeout 180_000

  @doc """
  Waits until Wallaby's session store has ended the browser sessions of the given
  test process. If the store doesn't get there within the timeout, it's stuck on a
  session that doesn't answer, so it's restarted. A restart drops the store's
  table, so every session in it gets deleted in the background once its test
  process is gone. Meant for an `on_exit` callback, given the test's pid.

  It checks the store's session table rather than asking the store, since the
  store gets the test process's `:DOWN` in no guaranteed order with a request
  from the `on_exit` process.

  ## Options

    * `:delete_fn` - deletes a session the store dropped, defaults to
      `&Wallaby.WebdriverClient.delete_session/1`
    * `:log_dir` - the dir whose `hangs.txt` gets a line on a restart, defaults to
      the one `start_wallaby/1` set up
    * `:sessions_fn` - lists the store's sessions as `{owner_pid, session}`
      tuples, defaults to reading the store's table
    * `:store` - the store's name and child id, defaults to `Wallaby.SessionStore`
    * `:supervisor` - the store's supervisor, defaults to `Wallaby.Supervisor`
    * `:timeout` - how long the store may take, in ms
  """
  @spec await_teardown(pid, keyword) :: :ok
  def await_teardown(test_pid, opts \\ []) do
    sessions_fn = Keyword.get(opts, :sessions_fn, &list_sessions/0)
    store = Keyword.get(opts, :store, Wallaby.SessionStore)
    timeout = Keyword.get(opts, :timeout, @default_teardown_timeout)

    opts =
      opts
      |> Keyword.put_new(:delete_fn, &WebdriverClient.delete_session/1)
      |> Keyword.put_new(:supervisor, Wallaby.Supervisor)
      |> Keyword.put(:sessions_fn, sessions_fn)
      |> Keyword.put(:store, store)
      |> Keyword.put(:timeout, timeout)

    # Taken first, so a store another test already restarted isn't restarted again.
    store_pid = GenServer.whereis(store)
    deadline = System.monotonic_time(:millisecond) + timeout

    case await_sessions_ended(test_pid, sessions_fn, deadline) do
      :ok ->
        :ok

      # One restart at a time, so tests stuck on the same store restart it once.
      :timeout ->
        :global.trans({__MODULE__, self()}, fn -> restart_store(store_pid, opts) end)
    end
  end

  @doc """
  Creates a ChromeDriver session like `Wallaby.WebdriverClient.create_session/2`,
  but gives up on an attempt that gets no answer within the attempt timeout and
  tries again. Passed to Wallaby as its `:create_session_fn`.

  A session that an abandoned attempt creates later is deleted. An attempt that
  answers with an error, raises or exits is not retried.

  ## Options

    * `:attempt_timeout` - how long one attempt waits for an answer, in ms
    * `:attempts` - how many attempts are made before raising
    * `:create_fn` - creates the session, defaults to
      `&Wallaby.WebdriverClient.create_session/2`
    * `:delete_fn` - deletes a session created by an abandoned attempt, given
      the base URL and the session id
    * `:log_dir` - the dir whose `hangs.txt` gets a line per abandoned attempt,
      defaults to the one `start_wallaby/1` set up
  """
  @spec create_session(String.t(), map, keyword) :: {:ok, map} | {:error, term}
  def create_session(base_url, capabilities, opts \\ []) do
    create_fn = Keyword.get(opts, :create_fn, &WebdriverClient.create_session/2)

    opts =
      opts
      |> Keyword.put_new(:attempt_timeout, @default_attempt_timeout)
      |> Keyword.put_new(:attempts, @default_attempts)
      |> Keyword.put_new(:delete_fn, &delete_session/2)

    create_session(fn -> create_fn.(base_url, capabilities) end, base_url, 1, opts)
  end

  @doc """
  Starts Wallaby with ChromeDriver's log on, in place of
  `Application.ensure_all_started(:wallaby)` in a test helper.

  Mix starts Wallaby before the test helper runs when it's a runtime dep, so a
  running Wallaby is stopped first, for the changes below to apply.

  Wallaby starts ChromeDriver with its log off, so its configured ChromeDriver
  path is pointed at a wrapper script that adds the log flags. Each ChromeDriver
  process writes `chromedriver-<os pid>.log` in the log dir, with Chrome's own
  output in it too. The log dir is emptied first, so it holds one run's logs, and
  it's where the other functions here write `hangs.txt`.

  Then it waits until every ChromeDriver Wallaby started is ready. Wallaby's tree
  can go down when they aren't ready in time, failing every test of the run, so
  Wallaby is restarted when one isn't, up to the attempt count.

  Last, it warms Chrome up: it starts one browser session and ends it. Chrome's
  first start on a fresh machine can outlast the attempts `create_session/3`
  makes, so it's paid here, before the suite runs, where no test timeout bounds
  it. It's a single attempt, so no second Chrome starts next to the slow one.
  Meanwhile Wallaby's HTTP requests get no receive timeout, since Wallaby sends a
  request again when one runs out.

  ## Options

    * `:attempts` - how many times Wallaby is started before raising
    * `:chromedrivers` - the partition supervisor of Wallaby's ChromeDriver
      servers, defaults to `Wallaby.Chromedrivers`
    * `:chromedriver_path` - the ChromeDriver the wrapper runs, defaults to the
      one Wallaby would run
    * `:create_fn` - creates the warm-up session, defaults to
      `&Wallaby.WebdriverClient.create_session/2`
    * `:delete_fn` - deletes a warm-up session created after its attempt was
      abandoned, given the base URL and the session id
    * `:end_session_fn` - ends the warm-up session, defaults to
      `&Wallaby.end_session/1`
    * `:log_dir` - defaults to `tmp/chromedriver` in the current dir
    * `:put_env_fn` - sets an app env key, defaults to `&Application.put_env/3`
    * `:ready_timeout` - how long to wait for each ChromeDriver, in ms
    * `:start_fn` - starts Wallaby
    * `:start_session_fn` - starts the warm-up session, given Wallaby's session
      opts, defaults to `&Wallaby.start_session/1`
    * `:stop_fn` - stops Wallaby
    * `:teardown_timeout` - how long ending the warm-up session may take, in ms
    * `:warm_up_timeout` - how long starting the warm-up session may take, in ms
  """
  @spec start_wallaby(keyword) :: :ok
  def start_wallaby(opts \\ []) do
    chromedriver_path = Keyword.get_lazy(opts, :chromedriver_path, &find_chromedriver!/0)
    put_env_fn = Keyword.get(opts, :put_env_fn, &Application.put_env/3)
    start_fn = Keyword.get(opts, :start_fn, &ensure_wallaby_started/0)
    stop_fn = Keyword.get(opts, :stop_fn, fn -> Application.stop(:wallaby) end)

    # Wallaby reads the ChromeDriver path when it starts.
    stop_fn.()

    log_dir =
      opts
      |> Keyword.get(:log_dir, "tmp/chromedriver")
      |> Path.expand()

    File.rm_rf!(log_dir)
    File.mkdir_p!(log_dir)

    wrapper_path = write_chromedriver_wrapper(log_dir, chromedriver_path)

    chromedriver_env =
      :wallaby
      |> Application.get_env(:chromedriver, [])
      |> Keyword.put(:path, wrapper_path)

    put_env_fn.(:wallaby, :chromedriver, chromedriver_env)
    put_env_fn.(:hologram, :__browser_session_log_dir__, log_dir)

    opts =
      opts
      |> Keyword.put_new(:attempts, @default_start_attempts)
      |> Keyword.put_new(:chromedrivers, Wallaby.Chromedrivers)
      |> Keyword.put_new(:create_fn, &WebdriverClient.create_session/2)
      |> Keyword.put_new(:delete_fn, &delete_session/2)
      |> Keyword.put_new(:end_session_fn, &Wallaby.end_session/1)
      |> Keyword.put_new(:ready_timeout, @default_ready_timeout)
      |> Keyword.put_new(:start_session_fn, &Wallaby.start_session/1)
      |> Keyword.put_new(:teardown_timeout, @default_teardown_timeout)
      |> Keyword.put_new(:warm_up_timeout, @default_warm_up_timeout)
      |> Keyword.put(:log_dir, log_dir)
      |> Keyword.put(:start_fn, start_fn)
      |> Keyword.put(:stop_fn, stop_fn)

    :ok = start_wallaby(1, opts)

    warm_up(opts)
  end

  defp await_exit(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    end
  end

  defp await_sessions_ended(test_pid, sessions_fn, deadline) do
    cond do
      not Enum.any?(sessions_fn.(), &match?({^test_pid, _session}, &1)) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(10)
        await_sessions_ended(test_pid, sessions_fn, deadline)
    end
  end

  # A crashed server or a gone tree exits the call. A tree going down mid-lookup
  # raises.
  defp chromedrivers_ready?(chromedrivers, timeout) do
    partitions = PartitionSupervisor.partitions(chromedrivers)

    # Integer keys pick partitions by rem/2, so 0..n-1 covers each one.
    Enum.all?(0..(partitions - 1), fn partition ->
      server = {:via, PartitionSupervisor, {chromedrivers, partition}}
      Server.wait_until_ready(server, timeout) == :ok
    end)
  rescue
    ArgumentError -> false
  catch
    :exit, _reason -> false
  end

  defp create_session(attempt_fn, base_url, attempt, opts) do
    attempt_timeout = opts[:attempt_timeout]
    attempts = opts[:attempts]

    case run_attempt(attempt_fn, base_url, opts) do
      {:ok, result} ->
        result

      :abandoned when attempt < attempts ->
        report_hang(
          "Chrome session didn't start within #{attempt_timeout} ms " <>
            "(attempt #{attempt} of #{attempts}), retrying",
          opts
        )

        create_session(attempt_fn, base_url, attempt + 1, opts)

      # Reported too, so the annotations also count a run that gave up.
      :abandoned ->
        message =
          "Chrome didn't start a browser session: ChromeDriver gave no answer to " <>
            "#{attempts} attempts, #{attempt_timeout} ms each"

        report_hang(message, opts)

        raise message
    end
  end

  defp delete_after_exit({owner_pid, session}, delete_fn) do
    await_exit(owner_pid)
    delete_fn.(session)
  end

  defp delete_created_session({:returned, {:ok, %{"sessionId" => session_id}}}, base_url, opts) do
    opts[:delete_fn].(base_url, session_id)
  end

  defp delete_created_session(_result, _base_url, _opts), do: :ok

  # A struct built at runtime, since Wallaby may be missing when this compiles.
  defp delete_session(base_url, session_id) do
    session_url = base_url <> "session/" <> session_id

    Wallaby.Session
    |> struct(id: session_id, session_url: session_url, url: session_url)
    |> WebdriverClient.delete_session()
  end

  # Wallaby.end_session/1 takes the session out of the store before its DELETE, so
  # the store is clean whatever the DELETE does. A Chrome that stays hung fails the
  # tests on their own attempts.
  defp end_first_session(session, opts) do
    timeout = opts[:teardown_timeout]
    attempt_opts = Keyword.put(opts, :attempt_timeout, timeout)
    end_fn = fn -> opts[:end_session_fn].(session) end

    case run_attempt(end_fn, nil, attempt_opts) do
      {:ok, _result} ->
        :ok

      :abandoned ->
        report_hang("Chrome didn't end its first browser session within #{timeout} ms", opts)
    end
  end

  defp ensure_wallaby_started do
    {:ok, _apps} = Application.ensure_all_started(:wallaby)
  end

  defp find_chromedriver! do
    case Wallaby.Chrome.find_chromedriver_executable() do
      {:ok, path} -> path
      {:error, exception} -> raise exception
    end
  end

  # Rows of Wallaby.SessionStore's table are {{ref, session_id, owner_pid}, session}.
  # The table is gone when Wallaby isn't running.
  defp list_sessions do
    :ets.select(:session_store, [{{{:_, :_, :"$1"}, :"$2"}, [], [{{:"$1", :"$2"}}]}])
  rescue
    ArgumentError -> []
  end

  # Appends to hangs.txt too, which CI checks to decide whether to upload the
  # ChromeDriver logs of a run that recovered.
  defp report_hang(message, opts) do
    line =
      if System.get_env("GITHUB_ACTIONS") == "true" do
        "::warning title=Browser hang::" <> message
      else
        message
      end

    # The leading newline ends the line ExUnit's dots leave open, since a workflow
    # command only counts at the start of a line.
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts("\n" <> line)

    log_dir =
      Keyword.get_lazy(opts, :log_dir, fn ->
        Application.get_env(:hologram, :__browser_session_log_dir__)
      end)

    if log_dir do
      log_dir
      |> Path.join("hangs.txt")
      |> File.write!(message <> "\n", [:append])
    end

    :ok
  end

  # Synchronous, so the next test finds the new store. The store traps exits, so
  # terminate_child/2 waits out the child's shutdown time before killing it. A
  # store another test restarted meanwhile is left alone.
  defp restart_store(store_pid, opts) do
    store = opts[:store]

    if GenServer.whereis(store) == store_pid do
      report_hang(
        "#{inspect(store)} didn't end the test's browser sessions within #{opts[:timeout]} ms, " <>
          "restarting it",
        opts
      )

      # Read before the restart drops them. The stuck store can't change them.
      sessions = opts[:sessions_fn].()

      :ok = Supervisor.terminate_child(opts[:supervisor], store)
      {:ok, _pid} = Supervisor.restart_child(opts[:supervisor], store)

      # One process each, since a DELETE to the hung session can block for minutes.
      Enum.each(sessions, &spawn(fn -> delete_after_exit(&1, opts[:delete_fn]) end))
    end

    :ok
  end

  # The attempt runs in a worker the caller can walk away from. Whether the result
  # goes to the caller or gets cleaned up is decided by a single compare-exchange,
  # so exactly one side owns it: the worker sets 1 when it is done first, the
  # caller sets 2 when its wait runs out first.
  defp run_attempt(attempt_fn, base_url, opts) do
    caller = self()
    owner = :atomics.new(1, [])
    ref = make_ref()

    spawn(fn ->
      result = run_attempt_fn(attempt_fn)

      cond do
        :atomics.compare_exchange(owner, 1, 0, 1) != :ok ->
          delete_created_session(result, base_url, opts)

        # ExUnit killed the test while the attempt ran.
        not Process.alive?(caller) ->
          delete_created_session(result, base_url, opts)

        true ->
          send(caller, {ref, result})
      end
    end)

    receive do
      {^ref, result} ->
        {:ok, unwrap_result(result)}
    after
      opts[:attempt_timeout] ->
        if :atomics.compare_exchange(owner, 1, 0, 2) == :ok do
          :abandoned
        else
          receive do
            {^ref, result} -> {:ok, unwrap_result(result)}
          end
        end
    end
  end

  defp run_attempt_fn(attempt_fn) do
    {:returned, attempt_fn.()}
  catch
    kind, reason ->
      {:raised, kind, reason, __STACKTRACE__}
  end

  defp shell_quote(string) do
    "'" <> String.replace(string, "'", "'\\''") <> "'"
  end

  defp start_first_session(opts) do
    timeout = opts[:warm_up_timeout]
    attempt_opts = Keyword.put(opts, :attempt_timeout, timeout)

    create_session_fn = fn base_url, capabilities ->
      create_fn = fn -> opts[:create_fn].(base_url, capabilities) end

      case run_attempt(create_fn, base_url, attempt_opts) do
        {:ok, result} ->
          result

        :abandoned ->
          message = "Chrome didn't start its first browser session within #{timeout} ms"
          report_hang(message, opts)
          raise message
      end
    end

    start_fn = fn -> opts[:start_session_fn].(create_session_fn: create_session_fn) end

    case without_recv_timeout(start_fn) do
      {:ok, session} ->
        session

      {:error, reason} ->
        raise "Chrome didn't start its first browser session: #{inspect(reason)}"
    end
  end

  defp start_wallaby(attempt, opts) do
    attempts = opts[:attempts]

    opts[:start_fn].()

    cond do
      chromedrivers_ready?(opts[:chromedrivers], opts[:ready_timeout]) ->
        :ok

      attempt < attempts ->
        report_hang(
          "ChromeDriver didn't get ready (attempt #{attempt} of #{attempts}), restarting Wallaby",
          opts
        )

        opts[:stop_fn].()
        start_wallaby(attempt + 1, opts)

      true ->
        message = "ChromeDriver didn't get ready after #{attempts} attempts"
        report_hang(message, opts)
        raise message
    end
  end

  defp unwrap_result({:returned, result}), do: result

  # The caller's frames go after the worker's, so the trace still shows the
  # setup line that started the session.
  defp unwrap_result({:raised, kind, reason, stacktrace}) do
    {:current_stacktrace, [_process_info | caller_stacktrace]} =
      Process.info(self(), :current_stacktrace)

    :erlang.raise(kind, reason, stacktrace ++ caller_stacktrace)
  end

  defp warm_up(opts) do
    opts
    |> start_first_session()
    |> end_first_session(opts)
  end

  # Wallaby's HTTP client sends a request again when hackney's receive timeout runs
  # out, and a second session request would start a second Chrome next to the slow
  # one, so the warm-up's own timeout is the only bound. Wallaby's default applies
  # when the key is unset.
  defp without_recv_timeout(fun) do
    original = Application.fetch_env(:wallaby, :hackney_options)

    hackney_options =
      case original do
        {:ok, options} -> options
        :error -> [hackney: [pool: :wallaby_pool]]
      end

    Application.put_env(
      :wallaby,
      :hackney_options,
      Keyword.put(hackney_options, :recv_timeout, :infinity)
    )

    try do
      fun.()
    after
      case original do
        {:ok, options} -> Application.put_env(:wallaby, :hackney_options, options)
        :error -> Application.delete_env(:wallaby, :hackney_options)
      end
    end
  end

  # The log flags go after Wallaby's args, since ChromeDriver takes the last of
  # a repeated switch, so --log-level=DEBUG wins over Wallaby's --log-level=OFF.
  # DEBUG logs the DevTools traffic, which shows whether a hung command reached
  # Chrome and whether Chrome answered. exec keeps the pid Wallaby tracks.
  defp write_chromedriver_wrapper(log_dir, chromedriver_path) do
    chromedriver = shell_quote(chromedriver_path)
    log_path = shell_quote(log_dir) <> "/chromedriver-$$.log"
    wrapper_path = Path.join(log_dir, "chromedriver")

    File.write!(wrapper_path, """
    #!/bin/sh
    # Runs ChromeDriver with its log on. Wallaby checks the version with
    # --version, which gets no log.
    if [ "$1" = "--version" ]; then
      exec #{chromedriver} "$@"
    fi
    exec #{chromedriver} "$@" --log-level=DEBUG --log-path=#{log_path} --enable-chrome-logs --readable-timestamp
    """)

    File.chmod!(wrapper_path, 0o755)

    wrapper_path
  end
end
