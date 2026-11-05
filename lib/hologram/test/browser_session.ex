defmodule Hologram.Test.BrowserSession do
  @moduledoc false

  # This is not public API - it is consumed by the Hologram test apps that run
  # browser tests, to keep a browser that stops answering from failing them.

  # Wallaby is not a Hologram dependency - client apps that use these helpers
  # bring their own. This lets the module compile without Wallaby present.
  @compile {:no_warn_undefined, [Wallaby.WebdriverClient]}

  alias Wallaby.WebdriverClient

  # Tunable policy, not derived. A normal session start takes about a second.
  # The real bound is ExUnit's 60 s test timeout, which also covers setup, where
  # a test may start several sessions. Anything from about 5 s to 15 s per attempt
  # behaves the same.
  @default_attempt_timeout 10_000
  @default_attempts 3

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

  # A struct built at runtime, since Wallaby may be missing when this compiles.
  defp delete_session(base_url, session_id) do
    session_url = base_url <> "session/" <> session_id

    Wallaby.Session
    |> struct(id: session_id, session_url: session_url, url: session_url)
    |> WebdriverClient.delete_session()
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

  defp delete_created_session({:returned, {:ok, %{"sessionId" => session_id}}}, base_url, opts) do
    opts[:delete_fn].(base_url, session_id)
  end

  defp delete_created_session(_result, _base_url, _opts), do: :ok

  defp run_attempt_fn(attempt_fn) do
    {:returned, attempt_fn.()}
  catch
    kind, reason ->
      {:raised, kind, reason, __STACKTRACE__}
  end

  defp unwrap_result({:returned, result}), do: result

  # The caller's frames go after the worker's, so the trace still shows the
  # setup line that started the session.
  defp unwrap_result({:raised, kind, reason, stacktrace}) do
    {:current_stacktrace, [_process_info | caller_stacktrace]} =
      Process.info(self(), :current_stacktrace)

    :erlang.raise(kind, reason, stacktrace ++ caller_stacktrace)
  end
end
