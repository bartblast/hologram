defmodule HologramFeatureTests.Helpers do
  import ExUnit.Assertions, only: [assert: 2, assert_raise: 3]
  import Hologram.Commons.Guards, only: [is_regex: 1]

  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Router
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

        message = fn expected_module, expected_msg, actual_msg ->
          """
          Wrong message for #{inspect(expected_module)}
          expected:
            "#{expected_msg}"
          actual:
            "#{actual_msg}"\
          """
        end

        if is_binary(expected_msg) do
          assert result["message"] == expected_msg,
                 message.(expected_module, expected_msg, result["message"])
        else
          assert result["message"] =~ expected_msg,
                 message.(expected_module, expected_msg, result["message"])
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

  def assert_js_error(session, expected_msg, fun) when is_binary(expected_msg) do
    regex = ~r/^There was an uncaught JavaScript error:.+: #{Regex.escape(expected_msg)}\n$/su

    assert_js_error(session, regex, fun)
  end

  def assert_js_error(session, expected_msg, fun) when is_regex(expected_msg) do
    assert_raise Wallaby.JSError, expected_msg, fn ->
      fun.()
      wait_for_js_error(session)
    end
  end

  def assert_page(session, page_module, params \\ [], opts \\ []) do
    path = Router.Helpers.page_path(page_module, params)

    session
    |> wait_for_path(path)
    |> wait_for_page_mounting(page_module, opts)
    |> wait_for_ws_connection()
    |> wait_for_sse_connection()
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

  def cookies(session) do
    session
    |> Browser.cookies()
    |> Enum.sort_by(& &1["name"], :asc)
  end

  @doc """
  Returns the `instance_id` of the currently-attached SSE process.

  Assumes exactly one SSE process is currently registered. Useful for tests
  that need to target the connected client from outside the connection
  (e.g., `Realtime.unsubscribe_all({:instance, current_instance_id()}, channel)`).
  """
  @spec current_instance_id() :: String.t()
  def current_instance_id do
    [{instance_id, _entry}] = :ets.tab2list(SubscriptionRegistry.ets_table_name())
    instance_id
  end

  @doc """
  Returns the `session_id` recorded for the currently-attached SSE process.

  Assumes exactly one SSE process is currently registered. Useful for capturing
  a connection's session id before a second connection opens, e.g. to target it
  via `Realtime.broadcast_action_except({:session, current_session_id()}, ...)`.
  """
  @spec current_session_id() :: term
  def current_session_id do
    [{_instance_id, entry}] = :ets.tab2list(SubscriptionRegistry.ets_table_name())
    entry.session_id
  end

  @doc """
  Returns the `user_id` recorded for the currently-attached SSE process.

  Assumes exactly one SSE process is currently registered. Useful for gating on
  a handler-driven identity change having propagated to the connection.
  """
  @spec current_user_id() :: term
  def current_user_id do
    [{_instance_id, entry}] = :ets.tab2list(SubscriptionRegistry.ets_table_name())
    entry.user_id
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

  defp print_client_logs(session) do
    script = "return sessionStorage.getItem('hologram_logs');"

    # credo:disable-for-next-line Credo.Check.Warning.IoInspect
    Browser.execute_script(session, script, [], &IO.inspect/1)
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

  def reload(session) do
    Browser.execute_script(session, "document.location.reload();")
  end

  def scroll_to(session, x, y) do
    Browser.execute_script(session, "window.scrollTo(#{x}, #{y});")
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
    Process.exit(entry.sse_pid, :kill)
    :ok
  end

  def sleep(session, duration) do
    :timer.sleep(duration)
    session
  end

  def visit(session, path_or_url) when is_binary(path_or_url) do
    Browser.visit(session, path_or_url)
  end

  def visit(session, page_module, params \\ []) do
    path = Router.Helpers.page_path(page_module, params)

    session
    |> Browser.visit(path)
    |> wait_for_page_mounting(page_module)
    |> wait_for_ws_connection()
    |> wait_for_sse_connection()
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

    cond do
      !has_subscription?(channel, cid) ->
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

    cond do
      subscription_count(channel, cid) >= count ->
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
  Blocks until the currently-attached SSE process records `user_id`, then
  returns the `session`. Gates on a handler-driven identity change (login or
  logout) having propagated to the connection before its effects are asserted -
  e.g. before broadcasting to check whether a binding was kept or dropped.
  Raises if the value does not appear within `@max_wait_time`.
  """
  def wait_for_user_id(session, user_id, start_time \\ nil) do
    start_time = start_time || current_time()

    cond do
      current_user_id() == user_id ->
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
    with {:ok, query} <- Query.validate(query),
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

  defp has_subscription?(channel, cid) do
    SubscriptionRegistry.ets_table_name()
    |> :ets.tab2list()
    |> Enum.any?(fn {_instance_id, entry} ->
      Enum.any?(entry.bindings, fn {{ch, c}, _user_id} ->
        ch == channel and (is_nil(cid) or c == cid)
      end)
    end)
  end

  # credo:disable-for-lines:9 Credo.Check.Refactor.IoPuts
  defp maybe_print_page_mounting_debug_info(session, opts, mounted_page, expected_page) do
    if opts[:debug] do
      IO.puts("----------")

      IO.puts("mounted page: #{inspect(mounted_page)}, expected page: #{inspect(expected_page)}")

      print_client_logs(session)
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

  defp wait_for_page_mounting(
         session,
         expected_page,
         opts \\ [],
         start_time \\ nil
       ) do
    start_time = start_time || current_time()

    callback = fn mounted_page ->
      if mounted_page != inspect(expected_page) && !timed_out?(start_time) do
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

    if Browser.current_path(session) != path && !timed_out?(start_time) do
      :timer.sleep(100)
      wait_for_path(session, path, start_time)
    end

    session
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
          raise Wallaby.ExpectationNotMetError, "Timed out waiting for WS connection"

        true ->
          :timer.sleep(100)
          wait_for_ws_connection(session, start_time)
      end
    end

    script = "return globalThis.Hologram?.['wsConnected?'];"

    Browser.execute_script(session, script, [], callback)
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
