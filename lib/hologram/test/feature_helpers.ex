defmodule Hologram.Test.FeatureHelpers do
  @moduledoc false

  # This is not public API yet - it is consumed by the Hologram feature tests
  # and umbrella tests apps.
  # TODO: consider promoting to public API (docs, stable surface), so that
  # client apps can use these helpers in their own Wallaby suites.

  # Wallaby is not a Hologram dependency - client apps that use these helpers
  # bring their own. This lets the module compile without Wallaby present.
  @compile {:no_warn_undefined, [Wallaby.Browser, Wallaby.ExpectationNotMetError]}

  alias Hologram.Router
  alias Wallaby.Browser

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
