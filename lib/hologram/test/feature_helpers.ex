defmodule Hologram.Test.FeatureHelpers do
  @moduledoc false

  # This is not public API yet - it is consumed by the Hologram feature tests
  # and umbrella tests apps.
  # TODO: consider promoting to public API (docs, stable surface), so that
  # client apps can use these helpers in their own Wallaby suites.

  # Wallaby is not a Hologram dependency - client apps that use these helpers
  # bring their own. This lets the module compile without Wallaby present.
  @compile {:no_warn_undefined,
            [Wallaby.Browser, Wallaby.ExpectationNotMetError, Wallaby.Feature.Utils]}

  alias Hologram.Router
  alias Hologram.Sync.Evaluators
  alias Wallaby.Browser
  alias Wallaby.Feature.Utils

  @doc """
  Asserts that the session has navigated to the given page: blocks until the
  current path matches the page's route, the Hologram client runtime has
  mounted the page, and its server connections are established.

  ## Options

    * `:debug` - when true, prints the mounted vs expected page and the client
      logs on each mounting poll. Defaults to false.
  """
  @spec assert_page(struct, module, keyword, keyword) :: struct
  def assert_page(session, page_module, params \\ [], opts \\ []) do
    path = Router.Helpers.page_path(page_module, params)

    session
    |> wait_for_path(path)
    |> wait_for_page_mounting(page_module, opts)
    |> wait_for_ws_connection()
    |> wait_for_sse_connection()
  end

  @doc """
  Blocks until no sync evaluator from an earlier test is still alive.

  A test that empties the tables with TRUNCATE bypasses the write funnel, so no effect reaches
  the log and nothing tells a running evaluator its rows are gone - it would keep serving its
  pre-truncate round to whatever connects next. Waiting for the drain is what makes a test's
  first frame mean that test's rows.
  """
  @spec await_evaluator_drain(non_neg_integer) :: :ok
  def await_evaluator_drain(attempts_left \\ 2_000)

  def await_evaluator_drain(0) do
    raise "evaluators from an earlier test never drained"
  end

  def await_evaluator_drain(attempts_left) do
    if Evaluators.live() == [] do
      :ok
    else
      Process.sleep(1)
      await_evaluator_drain(attempts_left - 1)
    end
  end

  @doc """
  Blocks until the client holds the given number of write batches waiting to ship.

  The point a test can act on after releasing held mutation traffic: zero pending batches means
  every batch has been answered, so what is on screen is what the answers left there.
  """
  @spec await_pending_writes(struct, non_neg_integer, non_neg_integer) :: struct
  def await_pending_writes(session, count, attempts_left \\ 100)

  def await_pending_writes(session, count, 0) do
    callback = fn pending ->
      raise Wallaby.ExpectationNotMetError,
            "Timed out waiting for #{count} pending write batches, the client holds #{inspect(pending)}"
    end

    Browser.execute_script(session, pending_writes_script(), [], callback)
  end

  def await_pending_writes(session, count, attempts_left) do
    callback = fn pending ->
      if pending == count do
        :ok
      else
        Process.sleep(50)
        await_pending_writes(session, count, attempts_left - 1)
      end
    end

    Browser.execute_script(session, pending_writes_script(), [], callback)
  end

  @doc """
  Holds every mutation request the page makes AFTER it is sent, parking its answer until
  `release_mutations/1`.

  What it buys a test: the server applies the batch and its effects reach the stream, so the
  frame carrying this client's own write lands while the batch is still pending. That ordering
  happens on its own in the wild and never reliably in a test.
  """
  @spec hold_mutation_answers(struct) :: struct
  def hold_mutation_answers(session) do
    hold_mutations(session, "answers")
  end

  @doc """
  Holds every mutation request the page makes BEFORE it is sent, until `release_mutations/1`.

  What it buys a test: a write made elsewhere reaches the server first, so the browser meets a
  newer value under a write of its own that nobody has ruled on yet.
  """
  @spec hold_mutation_requests(struct) :: struct
  def hold_mutation_requests(session) do
    hold_mutations(session, "requests")
  end

  @doc """
  Releases whatever `hold_mutation_answers/1` or `hold_mutation_requests/1` is holding.

  Does nothing when nothing is held, and nothing again when called twice - a resolved gate stays
  resolved, so a test may release without tracking whether it has.
  """
  @spec release_mutations(struct) :: struct
  def release_mutations(session) do
    Browser.execute_script(session, "globalThis.__hologramMutationGate?.release();")
  end

  @doc """
  Starts the Wallaby sessions the test registered through the `@sessions`
  attribute and returns them as the test's setup context.

  The registered value is either a count or per-session options. Sessions carry
  the test's ownership metadata, so a session's requests reach the same
  checked-out state the test holds.
  """
  @spec start_sessions(map) :: keyword
  def start_sessions(context) do
    metadata = Utils.maybe_checkout_repos(context[:async])

    start_session_opts =
      Utils.put_create_session_fn([metadata: metadata], context[:create_session_fn])

    context
    |> get_in([:registered, :sessions])
    |> Utils.sessions_iterable()
    |> Enum.map(fn
      opts when is_list(opts) -> Utils.start_session(opts, start_session_opts)
      count when is_number(count) -> Utils.start_session([], start_session_opts)
    end)
    |> Utils.build_setup_return()
  end

  @doc """
  Visits the given path or URL in the session, without waiting for any
  Hologram page mounting or server connections.
  """
  @spec visit(struct, String.t()) :: struct
  def visit(session, path_or_url) when is_binary(path_or_url) do
    Browser.visit(session, path_or_url)
  end

  @doc """
  Visits the page in the session and blocks until the Hologram client runtime
  has mounted it and established its server connections, so that subsequent
  interactions can't race the runtime's event listener attachment.
  """
  @spec visit(struct, module, keyword) :: struct
  def visit(session, page_module, params \\ []) do
    path = Router.Helpers.page_path(page_module, params)

    session
    |> Browser.visit(path)
    |> wait_for_page_mounting(page_module, [])
    |> wait_for_ws_connection()
    |> wait_for_sse_connection()
  end

  defp current_time do
    :erlang.monotonic_time(:milli_seconds)
  end

  # One wrapper around fetch, installed once and re-armed on every call, so a test may hold, release
  # and hold again. Only the mutation endpoint is parked - the page's own requests, the SSE
  # handshake and every command go straight through, or holding a write would freeze the page.
  #
  # The abort race is not decoration: the sender gives a mutation request 30 seconds
  # (`Config.mutationTimeoutMs`) and aborts it through the signal it passes here. A parked request
  # that ignored the signal would wait on the gate forever, and the queue behind it with it - the
  # test would then be holding something the browser had already given up on.
  #
  # fetch is bound to the global, because calling it as a method of anything else is an illegal
  # invocation in a browser.
  defp hold_mutations(session, mode) do
    script = """
    (() => {
      const held = globalThis.__hologramMutationGate;

      if (held) {
        held.mode = "#{mode}";

        held.gate = new Promise((resolve) => {
          held.release = resolve;
        });

        return;
      }

      const gate = {mode: "#{mode}", real: globalThis.fetch.bind(globalThis)};

      gate.gate = new Promise((resolve) => {
        gate.release = resolve;
      });

      globalThis.__hologramMutationGate = gate;

      globalThis.fetch = (url, opts = {}) => {
        if (typeof url !== "string" || !url.endsWith("/hologram/mutation")) {
          return gate.real(url, opts);
        }

        const aborted = new Promise((_resolve, reject) => {
          const abort = () => reject(new DOMException("aborted", "AbortError"));

          if (opts.signal?.aborted) {
            abort();
          }

          opts.signal?.addEventListener("abort", abort);
        });

        const sent =
          gate.mode === "requests"
            ? gate.gate.then(() => gate.real(url, opts))
            : gate.real(url, opts).then((response) => gate.gate.then(() => response));

        return Promise.race([sent, aborted]);
      };
    })();\
    """

    Browser.execute_script(session, script)
  end

  # Read at runtime (not compile time) so that the client app's Wallaby config
  # is honored - this module is compiled as part of the Hologram dependency,
  # before the client app's config exists.
  defp max_wait_time do
    Application.get_env(:wallaby, :max_wait_time, 3_000)
  end

  defp maybe_print_page_mounting_debug_info(session, opts, mounted_page, expected_page) do
    if opts[:debug] do
      # credo:disable-for-lines:2 Credo.Check.Refactor.IoPuts
      IO.puts("----------")
      IO.puts("mounted page: #{inspect(mounted_page)}, expected page: #{inspect(expected_page)}")

      print_client_logs(session)
    end
  end

  # Answers null rather than zero for a page whose runtime has not attached the window yet, so a
  # wait for zero pending batches keeps waiting instead of passing before the client can write.
  defp pending_writes_script do
    "return globalThis.Hologram?.['writes']?.pendingCount() ?? null;"
  end

  defp print_client_logs(session) do
    script = "return sessionStorage.getItem('hologram_logs');"

    # credo:disable-for-next-line Credo.Check.Warning.IoInspect
    Browser.execute_script(session, script, [], &IO.inspect/1)
  end

  defp timed_out?(start_time) do
    current_time() - start_time > max_wait_time()
  end

  defp wait_for_page_mounting(session, expected_page, opts, start_time \\ nil) do
    start_time = start_time || current_time()

    callback = fn mounted_page ->
      cond do
        mounted_page == inspect(expected_page) ->
          :ok

        timed_out?(start_time) ->
          raise Wallaby.ExpectationNotMetError,
                "Timed out waiting for page mounting, expected #{inspect(expected_page)}, " <>
                  "mounted #{inspect(mounted_page)}"

        true ->
          maybe_print_page_mounting_debug_info(session, opts, mounted_page, expected_page)
          :timer.sleep(100)
          wait_for_page_mounting(session, expected_page, opts, start_time)
      end
    end

    script = "return globalThis.Hologram?.['mountedPage'];"

    Browser.execute_script(session, script, [], callback)
  end

  defp wait_for_path(session, path, start_time \\ nil) do
    start_time = start_time || current_time()
    current_path = Browser.current_path(session)

    cond do
      current_path == path ->
        session

      timed_out?(start_time) ->
        raise Wallaby.ExpectationNotMetError,
              "Timed out waiting for path #{path}, current path is #{current_path}"

      true ->
        :timer.sleep(100)
        wait_for_path(session, path, start_time)
    end
  end

  defp wait_for_sse_connection(session, start_time \\ nil) do
    start_time = start_time || current_time()

    callback = fn connected? ->
      cond do
        connected? ->
          :ok

        timed_out?(start_time) ->
          raise Wallaby.ExpectationNotMetError, "Timed out waiting for SSE connection"

        true ->
          :timer.sleep(100)
          wait_for_sse_connection(session, start_time)
      end
    end

    script = "return globalThis.Hologram?.['sseConnected?'];"

    Browser.execute_script(session, script, [], callback)
  end

  defp wait_for_ws_connection(session, start_time \\ nil) do
    start_time = start_time || current_time()

    callback = fn connected? ->
      cond do
        connected? ->
          :ok

        timed_out?(start_time) ->
          raise Wallaby.ExpectationNotMetError, "Timed out waiting for WebSocket connection"

        true ->
          :timer.sleep(100)
          wait_for_ws_connection(session, start_time)
      end
    end

    script = "return globalThis.Hologram?.['wsConnected?'];"

    Browser.execute_script(session, script, [], callback)
  end
end
