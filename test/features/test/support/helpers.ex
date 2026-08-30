defmodule HologramFeatureTests.Helpers do
  import ExUnit.Assertions, only: [assert: 2, assert_raise: 3]
  import Hologram.Commons.Guards, only: [is_regex: 1]
  import Hologram.Test.FeatureHelpers, only: [visit: 2, visit: 3]

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.Realtime
  alias Hologram.Realtime.SSE
  alias Hologram.Realtime.SubscriptionRegistry
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTestsWeb.Plugs.SlowPageBundle
  alias Wallaby.Browser
  alias Wallaby.Element
  alias Wallaby.Query
  alias Wallaby.Query.ErrorMessage
  alias Wallaby.StaleReferenceError

  @max_wait_time Application.compile_env(:wallaby, :max_wait_time, 3_000)

  def assert_client_error(session, expected_module, expected_msg, fun) do
    fun.()
    wait_for_js_error(session)
  rescue
    Wallaby.JSError ->
      script = "return globalThis.Hologram?.['lastBoxedError'];"

      Browser.execute_script(session, script, [], fn result ->
        assert result["module"] == inspect(expected_module),
               "Expected exception #{inspect(expected_module)} but got #{result["module"]} (#{result["message"]})"

        message = fn expected_display, actual_msg ->
          """
          Wrong message for #{inspect(expected_module)}
          expected:
            "#{expected_display}"
          actual:
            "#{actual_msg}"\
          """
        end

        # A regex is matched rather than compared, and shows as its source - it has no
        # string form to interpolate.
        if is_regex(expected_msg) do
          assert result["message"] =~ expected_msg,
                 message.(Regex.source(expected_msg), result["message"])
        else
          assert result["message"] == expected_msg,
                 message.(expected_msg, result["message"])
        end
      end)
  end

  def assert_count(session, css_selector, count) do
    Browser.find(session, Query.css(css_selector, count: count))
    session
  end

  def assert_inline_script(session, css_selector, expected_value) do
    Browser.execute_script(
      session,
      "return document.querySelector('#{css_selector}').textContent;",
      [],
      fn actual_value ->
        assert String.contains?(actual_value, expected_value),
               "Expected inline script to contain '#{expected_value}' but got '#{actual_value}'"
      end
    )
  end

  def assert_input_value(session, css_selector, expected_value) do
    Browser.execute_script(
      session,
      "return document.querySelector('#{css_selector}').value;",
      [],
      fn actual_value ->
        assert actual_value == expected_value,
               "Expected input value to be '#{expected_value}' but got '#{actual_value}'"
      end
    )
  end

  # The console entry the browser writes for an uncaught error is capped in
  # length, and it elides the middle of anything longer, so only the message is
  # matched here and only where it starts. An error naming the exception it
  # raised is read from the page instead, by assert_client_error/4, which sees
  # the whole of it.
  def assert_js_error(session, expected_msg, fun) when is_binary(expected_msg) do
    regex = ~r/^There was an uncaught JavaScript error:.+?#{Regex.escape(expected_msg)}/su

    assert_js_error(session, regex, fun)
  end

  def assert_js_error(session, expected_msg, fun) when is_regex(expected_msg) do
    assert_raise Wallaby.JSError, expected_msg, fn ->
      fun.()
      wait_for_js_error(session)
    end
  end

  def assert_public_comment(session, comment) do
    script = "return document.documentElement.outerHTML;"

    callback = fn html ->
      regex = ~r/<!\-\-\s*#{Regex.escape(comment)}\s*\-\->/

      unless html =~ regex do
        raise Wallaby.ExpectationNotMetError,
              "Expected to find public comment \"#{comment}\" in page content, but it was not found"
      end
    end

    Browser.execute_script(session, script, [], callback)
  end

  def assert_scroll_position(session, x, y) do
    callback = fn scroll_position ->
      if scroll_position == [x, y] do
        session
      else
        raise Wallaby.ExpectationNotMetError,
              "Expected scroll position: [#{x}, #{y}], but got #{inspect(scroll_position)}"
      end
    end

    script = "return [window.scrollX, window.scrollY]"

    Browser.execute_script(session, script, [], callback)
  end

  def assert_script_result(session, script, expected_result) do
    callback = fn actual_result ->
      if actual_result == expected_result do
        session
      else
        raise Wallaby.ExpectationNotMetError,
              "Expected script result to be #{inspect(expected_result)}, but got #{inspect(actual_result)}"
      end
    end

    Browser.execute_script(session, script, [], callback)
  end

  def assert_text(parent, text) when is_binary(text) do
    Browser.assert_text(parent, text)
  end

  def assert_text(parent, regex) when is_regex(regex) do
    if has_text?(parent, regex) do
      parent
    else
      raise Wallaby.ExpectationNotMetError, "Text matching regex #{inspect(regex)} was not found."
    end
  end

  def assert_text(parent, query, text) when is_binary(text) do
    Browser.assert_text(parent, query, text)

    # TODO: return Browser.assert_text/3 result
    # once https://github.com/elixir-wallaby/wallaby/pull/792 is accepted.
    parent
  end

  def assert_text(parent, query, regex) when is_regex(regex) do
    parent
    |> Browser.find(query)
    |> assert_text(regex)

    parent
  end

  @doc """
  Blocks until this browser has written everything it holds to durable storage, then returns the
  `session`.

  What a test can act on afterwards: the rows a frame delivered, the place they are dated at and
  the clock are all committed, so a page load made after this reads them back rather than racing a
  transaction that has not finished. Without it a test that reloads immediately can find an empty
  database and conclude, wrongly, that nothing was kept.

  Answers `nil` rather than zero for a page whose runtime has not attached its window yet, which is
  what keeps the wait waiting instead of passing before the browser could have written anything.
  Raises if writes are still in flight after `@max_wait_time`.
  """
  @spec await_durable_writes(Wallaby.Session.t(), integer | nil) :: Wallaby.Session.t()
  def await_durable_writes(session, start_time \\ nil) do
    start_time = start_time || current_time()

    script = "return globalThis.Hologram.durability?.pendingWrites() ?? null;"

    case script_result(session, script) do
      0 ->
        session

      pending ->
        if timed_out?(start_time) do
          raise Wallaby.ExpectationNotMetError,
                "Timed out waiting for the browser's durable writes, #{inspect(pending)} in flight"
        end

        :timer.sleep(50)
        await_durable_writes(session, start_time)
    end
  end

  @doc """
  Blocks until the client's write queue holds at least one refused batch, and returns the
  refusals as the queue's own window reads them.

  The deterministic point at which a rollback has happened - asserting "the row appeared and then
  vanished" would race the round trip in whichever direction the machine happened to be faster.
  Raises if nothing is refused within `@max_wait_time`.
  """
  @spec await_rejected_writes(Wallaby.Session.t(), integer | nil) :: list
  def await_rejected_writes(session, start_time \\ nil) do
    start_time = start_time || current_time()

    case script_result(session, "return globalThis.Hologram.writes.rejected();") do
      [] ->
        if timed_out?(start_time) do
          raise Wallaby.ExpectationNotMetError,
                "Timed out waiting for the client to refuse a write batch"
        end

        :timer.sleep(50)
        await_rejected_writes(session, start_time)

      rejected ->
        rejected
    end
  end

  @doc """
  Polls the SERVER until it holds the given number of todos, and returns them sorted by title.

  The row arriving is the confirmation that a batch landed - nothing app-facing exposes a per-row
  durability to assert on instead. Answers whatever the server holds after the last attempt, so a
  caller matching on the result gets a real assertion failure rather than a timeout.
  """
  @spec await_server_todos(non_neg_integer) :: [struct]
  def await_server_todos(expected_count) do
    Enum.reduce_while(1..100, [], fn _attempt, _acc ->
      todos = Enum.sort_by(DB.read(Todo), & &1.title)

      if length(todos) == expected_count do
        {:halt, todos}
      else
        Process.sleep(50)
        {:cont, todos}
      end
    end)
  end

  def cookies(session) do
    session
    |> Browser.cookies()
    |> Enum.sort_by(& &1["name"], :asc)
  end

  @doc """
  Returns the `instance_id` of the given `session`'s browser.

  Read from the browser's own JS context rather than from the registry, so it
  holds however many connections are registered, and keeps working when this
  one has no registry entry - after `simulate_sse_disconnect/1`, or before the
  stream has attached.
  """
  @spec current_instance_id(Wallaby.Session.t()) :: String.t()
  def current_instance_id(session) do
    script_result(session, "return globalThis.Hologram.instanceId;")
  end

  @doc """
  Returns the `session_id` recorded for the given `session`'s connection, or
  `nil` when it has no registry entry.
  """
  @spec current_session_id(Wallaby.Session.t()) :: term
  def current_session_id(session) do
    case registry_entry(session) do
      nil -> nil
      entry -> entry.session_id
    end
  end

  @doc """
  Returns the `user_id` recorded for the given `session`'s connection, or `nil`
  when it has no registry entry.

  Returning `nil` rather than raising lets a poller keep waiting through the
  window where a connection has not attached yet, or has just been reaped.
  """
  @spec current_user_id(Wallaby.Session.t()) :: term
  def current_user_id(session) do
    case registry_entry(session) do
      nil -> nil
      entry -> entry.user_id
    end
  end

  @doc """
  Executes a query for refute_has with optimized retry behavior.

  - Returns immediately if element is NOT found (fast path for refute_has)
  - Retries if element IS found, waiting for it to disappear
  """
  def execute_refute_query(parent, query, start_time \\ nil) do
    start_time = start_time || current_time()

    case do_execute_query_once(parent, query) do
      {:ok, _query} = found ->
        # Element found - retry until it disappears or timeout
        if timed_out?(start_time) do
          found
        else
          execute_refute_query(parent, query, start_time)
        end

      {:error, :stale_reference} ->
        # Retry on stale reference
        execute_refute_query(parent, query, start_time)

      {:error, :invalid_selector} = error ->
        error

      {:error, _not_found} = error ->
        # Element not found - return immediately (fast path)
        error
    end
  end

  def go_back(session) do
    Browser.execute_script(session, "history.back();")
  end

  def go_forward(session) do
    Browser.execute_script(session, "history.forward();")
  end

  def has_text?(parent, text) when is_binary(text) do
    Browser.has_text?(parent, text)
  end

  def has_text?(parent, regex) when is_regex(regex) do
    result =
      Browser.retry(fn ->
        if Element.text(parent) =~ regex do
          {:ok, true}
        else
          {:error, false}
        end
      end)

    case result do
      {:ok, true} ->
        true

      {:error, false} ->
        false
    end
  end

  @doc """
  Custom refute_has that returns immediately when the element is not found.

  Unlike Wallaby.Browser.refute_has/2 which always waits for max_wait_time,
  this version:
  - Returns immediately if the element is NOT present (fast path)
  - Waits/retries if the element IS present, giving it time to disappear

  Pass `wait_time: ms` to assert absence only after waiting `ms` first, so an
  appearance arriving within that window is still caught.
  """
  defmacro refute_has(parent, query, opts \\ []) do
    quote do
      parent = unquote(parent)
      query = unquote(query)

      case unquote(opts)[:wait_time] do
        nil -> :ok
        wait_time -> :timer.sleep(wait_time)
      end

      case execute_refute_query(parent, query) do
        {:error, :invalid_selector} ->
          raise Wallaby.QueryError, ErrorMessage.message(query, :invalid_selector)

        {:error, _not_found} ->
          parent

        {:ok, query} ->
          raise Wallaby.ExpectationNotMetError, ErrorMessage.message(query, :found)
      end
    end
  end

  @doc """
  Refutes that the element matching `query` displays `text`. The negative
  counterpart to `assert_text/3`; accepts the same `opts` as `refute_has/3`.
  """
  defmacro refute_text(parent, query, text, opts \\ []) do
    quote do
      text_query =
        Map.update!(unquote(query), :conditions, &Keyword.put(&1, :text, unquote(text)))

      refute_has(unquote(parent), text_query, unquote(opts))
    end
  end

  @doc """
  What the server kept of one browser's batches - the number and the answer of each - scoped to
  the replica that sent them and ordered by number.
  """
  @spec mutation_record_rows(String.t()) :: [%{result: map | nil, seq: non_neg_integer}]
  def mutation_record_rows(replica_id) do
    statement = """
    SELECT "result", "seq" FROM "hologram_system"."mutation"
    WHERE "replica_id" = $1 ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [replica_id])

    Enum.map(rows, fn [result, seq] -> %{result: result, seq: seq} end)
  end

  def reload(session) do
    Browser.execute_script(session, "document.location.reload();")
  end

  @doc """
  Executes a script and returns its result to the caller.

  `Wallaby.Browser.execute_script/2` only exposes the result through a callback and returns the
  session, so this wraps the underlying driver call that yields the value directly.
  """
  def script_result(session, script) do
    {:ok, value} = session.driver.execute_script(session, script)
    value
  end

  def scroll_to(session, x, y) do
    Browser.execute_script(session, "window.scrollTo(#{x}, #{y});")
  end

  @doc """
  Sends keys to the page (the active element), releasing any held modifier keys afterward.

  Wallaby's session-level `send_keys/2` posts to the WebDriver `/keys` endpoint, where modifier keys
  (Ctrl, Shift, ...) stay pressed across calls. A chord like `[:control, "k"]` would otherwise leave
  Ctrl held, turning a later click into a Ctrl+click. The trailing `:null` (the WebDriver NULL key)
  releases the modifiers so each call is self-contained.
  """
  def send_keys(session, keys) do
    # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
    Browser.send_keys(session, List.wrap(keys) ++ [:null])
  end

  @doc """
  Arms a delay on every page bundle this browser fetches from now on, then
  returns the `session` so the helper can be piped.

  A navigation shows the destination as soon as the server describes it and
  mounts it once its bundle arrives. Over a local loop those two are
  milliseconds apart, which is too narrow for a test to act in between. This
  widens the gap to `delay_ms`.

  Scoped by cookie, so concurrently running test files are unaffected. Navigates
  to a blank page first, since a cookie cannot be set before the browser holds a
  document.
  """
  @spec simulate_slow_page_bundle(Wallaby.Session.t(), pos_integer) :: Wallaby.Session.t()
  def simulate_slow_page_bundle(session, delay_ms) do
    session
    |> visit("/external")
    |> Browser.set_cookie(SlowPageBundle.cookie(), to_string(delay_ms))
  end

  @doc """
  Arms a delay on this browser's next SSE attach, then returns the `session` so
  the helper can be piped.

  Holds the stream open long enough for a command dispatched during page boot to
  reach the server while the instance still has no `SubscriptionRegistry` entry.
  That race is real but unreproducible over a local loop, where the attach always
  wins: the client calls `Sse.connect()` synchronously at mount while the action
  queued by `init/3` is dispatched a tick later.

  Scoped by cookie, so concurrently running test files are unaffected. Navigates
  to a blank page first, since a cookie cannot be set before the browser holds a
  document.
  """
  @spec simulate_slow_sse_attach(Wallaby.Session.t(), pos_integer) :: Wallaby.Session.t()
  def simulate_slow_sse_attach(session, delay_ms) do
    session
    |> visit("/external")
    |> Browser.set_cookie(SSE.attach_delay_cookie(), to_string(delay_ms))
  end

  @doc """
  Simulates a network blip by killing the SSE process attached to the given
  `instance_id`.

  After this call the client's `EventSource` fires `onerror` and the
  JS-driven reconnect cycle begins: backoff, then POST handshake (the
  receipts in `App.subscriptionReceiptRegistry` are re-validated), then a
  fresh `EventSource` GET that re-registers bindings via
  `SubscriptionRegistry.attach_connection`. Callers typically follow with
  `wait_for_no_subscription/2` to gate the registry GC and then
  `wait_for_subscription/2` to gate the reconnect-attach.
  """
  @spec simulate_sse_disconnect(String.t()) :: :ok
  def simulate_sse_disconnect(instance_id) do
    [{^instance_id, entry}] = :ets.lookup(SubscriptionRegistry.ets_table_name(), instance_id)
    sse_pid = entry.sse_pid

    # Killing the SSE process makes Ranch log an expected `:killed` request-process
    # exit at :error level. That line is emitted asynchronously by the connection
    # process as the exit propagates, so the capture window is held open until the
    # killed process is confirmed down rather than closing the instant
    # Process.exit/2 returns.
    ExUnit.CaptureLog.capture_log(fn ->
      ref = Process.monitor(sse_pid)
      Process.exit(sse_pid, :kill)

      receive do
        {:DOWN, ^ref, :process, ^sse_pid, _reason} -> :ok
      after
        1_000 -> :ok
      end
    end)

    :ok
  end

  def sleep(session, duration) do
    :timer.sleep(duration)
    session
  end

  @doc """
  Reads the text content of the element matching `css_selector` and evaluates it as an Elixir term.

  Intended for elements that render a value via `inspect/1`, so the test can compare the recorded
  value field by field rather than against a formatted string.
  """
  def term_at(session, css_selector) do
    script = "return document.querySelector('#{css_selector}').textContent;"

    {term, _bindings} =
      session
      |> script_result(script)
      |> Code.eval_string()

    term
  end

  @doc """
  Visits `page_module` in `session` as a second tab of `origin`'s Hologram
  session, by copying `origin`'s signed `phoenix_session` cookie into it.

  Wallaby sessions have isolated cookie jars, so a second tab is otherwise a
  separate session. A cookie can only be set once the browser is on the domain,
  hence the throwaway `/external` visit (a plain page, no session/SSE) before
  setting it; the final `visit/3` then loads the page carrying `origin`'s
  cookie. Use it to give a connection a same-session sibling.
  """
  def visit_as_sibling(session, origin, page_module, params \\ []) do
    %{"value" => session_cookie} =
      origin
      |> cookies()
      |> Enum.find(&(&1["name"] == "phoenix_session"))

    session
    |> visit("/external")
    |> Browser.set_cookie("phoenix_session", session_cookie)
    |> visit(page_module, params)
  end

  @doc """
  Blocks until no `SubscriptionRegistry` entry holds a subscription on `channel`,
  then returns the `session` so the helper can be piped. Pass a `cid` to narrow
  the wait to a single `{channel, cid}` binding - needed to gate a single-cid
  `unsubscribe` whose channel keeps other cids bound, where the channel-wide
  wait would never return. Raises if the subscription persists past
  `@max_wait_time`.
  """
  def wait_for_no_subscription(session, channel, cid \\ nil, start_time \\ nil) do
    start_time = start_time || current_time()

    # Dropped AND no longer listening - the registry deletes the binding and then tells the
    # connection to leave the topic, so between the two a broadcast still lands and a refute
    # gated on the binding alone can see it. Channel-wide waits only: a single-cid drop
    # legitimately leaves the connection on the topic for the channel's other cids, so there is
    # no membership fact for that wait to check.
    cond do
      !has_subscription?(channel, cid) and (not is_nil(cid) or not sse_listening?(channel)) ->
        session

      timed_out?(start_time) ->
        raise Wallaby.ExpectationNotMetError,
              "Timed out waiting for subscription to drop on #{inspect(channel)} (cid: #{inspect(cid)})"

      true ->
        :timer.sleep(100)
        wait_for_no_subscription(session, channel, cid, start_time)
    end
  end

  @doc """
  Blocks until at least `count` (default 1) `SubscriptionRegistry` connections
  hold a binding on `channel` - or, when `cid` is given, a `{channel, cid}`
  binding specifically - then returns the `session` so the helper can be piped.
  Raises if the count is not reached within `@max_wait_time`.

  Gate any broadcast whose recipients a test asserts on: subscriptions register
  asynchronously after the page mounts (handshake POST + SSE attach), and
  `Phoenix.PubSub` is fire-and-forget, so a broadcast that fires first reaches
  no one - a missed delivery, or a refute that passes vacuously because the
  asserted-on session was never there. Pass `count` > 1 to require *every*
  participating connection in a multi-session test. Pass a `cid` when several
  bindings share one connection (e.g. multiple components on one page), where a
  connection count can't tell whether a specific cid is bound.
  """
  def wait_for_subscription(session, channel, count \\ 1, cid \\ nil, start_time \\ nil) do
    start_time = start_time || current_time()

    # Registered AND listening, because they happen apart: the registry writes the binding and
    # then tells the connection to join the channel's PubSub topic, so between the two a
    # broadcast reaches nobody. The binding is what a test can see - the topic membership is what
    # delivery needs - and gating on the first alone is how a broadcast fired "after the
    # subscription" still misses.
    cond do
      subscription_count(channel, cid) >= count and listener_count(channel, cid) >= count ->
        session

      timed_out?(start_time) ->
        raise Wallaby.ExpectationNotMetError,
              "Timed out waiting for #{count} subscription(s) on #{inspect(channel)} (cid: #{inspect(cid)})"

      true ->
        :timer.sleep(100)
        wait_for_subscription(session, channel, count, cid, start_time)
    end
  end

  @doc """
  Blocks until the `session`'s own SSE process records `user_id`, then returns
  the `session`. Gates on a handler-driven identity change (login or logout)
  having propagated to the connection before its effects are asserted - e.g.
  before broadcasting to check whether a binding was kept or dropped. Raises if
  the value does not appear within `@max_wait_time`.

  Resolves this browser's connection specifically, so another tab of the same
  session lingering in the registry does not affect it. A departed tab's SSE
  process is only reaped once a write to its dead socket fails, which may not
  happen until the next heartbeat.
  """
  def wait_for_user_id(session, user_id, start_time \\ nil) do
    start_time = start_time || current_time()

    cond do
      current_user_id(session) == user_id ->
        session

      timed_out?(start_time) ->
        raise Wallaby.ExpectationNotMetError,
              "Timed out waiting for connection user_id #{inspect(user_id)}"

      true ->
        :timer.sleep(100)
        wait_for_user_id(session, user_id, start_time)
    end
  end

  defp apply_at(query, elements) do
    case {Query.at_number(query), length(elements)} do
      {:all, _count} -> {:ok, elements}
      {n, count} when n < count -> {:ok, [Enum.at(elements, n)]}
      {_n, _count} -> {:error, {:not_found, elements}}
    end
  end

  defp current_time do
    :erlang.monotonic_time(:milli_seconds)
  end

  defp do_execute_query_once(%{driver: driver} = parent, query) do
    with {:ok, %Query{} = query} <- Query.validate(query),
         compiled_query <- Query.compile(query),
         {:ok, elements} <- driver.find_elements(parent, compiled_query),
         {:ok, elements} <- filter_by_visibility(query, elements),
         {:ok, elements} <- filter_by_text(query, elements),
         {:ok, elements} <- filter_by_selected(query, elements),
         {:ok, elements} <- validate_count(query, elements),
         {:ok, elements} <- apply_at(query, elements) do
      {:ok, %Query{query | result: elements}}
    end
  rescue
    StaleReferenceError ->
      {:error, :stale_reference}
  end

  defp filter_by_selected(query, elements) do
    case Query.selected?(query) do
      :any -> {:ok, elements}
      true -> {:ok, Enum.filter(elements, &Element.selected?(&1))}
      false -> {:ok, Enum.reject(elements, &Element.selected?(&1))}
    end
  end

  defp filter_by_text(query, elements) do
    text = Query.inner_text(query)

    if text do
      {:ok, Enum.filter(elements, &text_matches?(&1, text))}
    else
      {:ok, elements}
    end
  end

  defp filter_by_visibility(query, elements) do
    case Query.visible?(query) do
      :any -> {:ok, elements}
      true -> {:ok, Enum.filter(elements, &Element.visible?(&1))}
      false -> {:ok, Enum.reject(elements, &Element.visible?(&1))}
    end
  end

  # The pids on the channel's PubSub topic. phoenix_pubsub's subscribe is Registry.register on
  # the registry named by the pubsub, so membership is readable - an implementation detail,
  # pinned by the lockfile, and no deeper a peek than reading the SubscriptionRegistry's own
  # table beside it.
  defp channel_listeners(channel) do
    topic = Realtime.channel_topic(channel)

    Hologram.PubSub
    |> Registry.lookup(topic)
    |> MapSet.new(fn {pid, _value} -> pid end)
  end

  defp has_subscription?(channel, cid) do
    SubscriptionRegistry.ets_table_name()
    |> :ets.tab2list()
    |> Enum.any?(fn {_instance_id, entry} ->
      Enum.any?(entry.bindings, fn {{ch, c}, _user_id} ->
        ch == channel and (is_nil(cid) or c == cid)
      end)
    end)
  end

  # How many of the connections holding the binding are actually ON the channel's topic.
  defp listener_count(channel, cid) do
    listening = channel_listeners(channel)

    SubscriptionRegistry.ets_table_name()
    |> :ets.tab2list()
    |> Enum.count(fn {_instance_id, entry} ->
      MapSet.member?(listening, entry.sse_pid) and
        Enum.any?(entry.bindings, fn {{ch, c}, _user_id} ->
          ch == channel and (is_nil(cid) or c == cid)
        end)
    end)
  end

  # Whether any live connection is still on the channel's topic. Checked against the
  # connections rather than against binding-holders, because it gates the state where the
  # BINDINGS are already gone and only the membership lags.
  defp sse_listening?(channel) do
    listening = channel_listeners(channel)

    SubscriptionRegistry.ets_table_name()
    |> :ets.tab2list()
    |> Enum.any?(fn {_instance_id, entry} -> MapSet.member?(listening, entry.sse_pid) end)
  end

  # credo:disable-for-lines:9 Credo.Check.Refactor.IoPuts
  defp registry_entry(session) do
    instance_id = current_instance_id(session)

    case :ets.lookup(SubscriptionRegistry.ets_table_name(), instance_id) do
      [{^instance_id, entry}] -> entry
      [] -> nil
    end
  end

  defp subscription_count(channel, cid) do
    SubscriptionRegistry.ets_table_name()
    |> :ets.tab2list()
    |> Enum.count(fn {_instance_id, entry} ->
      Enum.any?(entry.bindings, fn {{ch, c}, _user_id} ->
        ch == channel and (is_nil(cid) or c == cid)
      end)
    end)
  end

  defp text_matches?(%Element{driver: driver} = element, text) do
    case driver.text(element) do
      {:ok, element_text} -> element_text =~ ~r/#{Regex.escape(text)}/
      {:error, _reason} -> false
    end
  end

  defp timed_out?(start_time) do
    current_time() - start_time > @max_wait_time
  end

  defp validate_count(query, elements) do
    if Query.matches_count?(query, Enum.count(elements)) do
      {:ok, elements}
    else
      {:error, {:not_found, elements}}
    end
  end

  defp wait_for_js_error(session, start_time \\ nil) do
    start_time = start_time || current_time()

    Browser.execute_script(session, "1 + 1")

    if !timed_out?(start_time) do
      :timer.sleep(100)
      wait_for_js_error(session, start_time)
    end
  end
end
