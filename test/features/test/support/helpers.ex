defmodule HologramFeatureTests.Helpers do
  import ExUnit.Assertions, only: [assert: 2, assert_raise: 3]
  import Hologram.Commons.Guards, only: [is_regex: 1]

  alias Hologram.Router
  alias Wallaby.Browser
  alias Wallaby.Element

  @max_wait_time Application.compile_env(:wallaby, :max_wait_time, 3_000)

  def assert_client_error(session, expected_module, expected_msg, fun) do
    fun.()
    wait_for_js_error(session)
  rescue
    Wallaby.JSError ->
      script = "return window?.hologram?.['lastBoxedError'];"

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

  def assert_page(session, page_module, params \\ []) do
    path = Router.Helpers.page_path(page_module, params)

    session
    |> wait_for_path(path)
    |> wait_for_page_mounting(page_module)
    |> wait_for_server_connection()
  end

  def assert_scroll_position(session, x, y) do
    callback = fn scroll_position ->
      if scroll_position == [x, y] do
        session
      else
        raise Wallaby.ExpectationNotMetError, "Scroll position is different than [#{x}, #{y}]"
      end
    end

    script = "return [window.scrollX, window.scrollY]"

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
  end

  def assert_text(parent, query, regex) when is_regex(regex) do
    parent
    |> Browser.find(query)
    |> assert_text(regex)
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

  def reload(session) do
    Browser.execute_script(session, "document.location.reload();")
  end

  def scroll_to(session, x, y) do
    Browser.execute_script(session, "window.scrollTo(#{x}, #{y});")
  end

  def visit(session, path_or_url) when is_binary(path_or_url) do
    Browser.visit(session, path_or_url)
  end

  def visit(session, page_module, params \\ []) do
    path = Router.Helpers.page_path(page_module, params)

    session
    |> Browser.visit(path)
    |> wait_for_page_mounting(page_module)
    |> wait_for_server_connection()
  end

  defp timed_out?(start_time) do
    DateTime.diff(DateTime.utc_now(), start_time, :millisecond) > @max_wait_time
  end

  defp wait_for_path(session, path, start_time \\ DateTime.utc_now()) do
    if Browser.current_path(session) != path && !timed_out?(start_time) do
      :timer.sleep(100)
      wait_for_path(session, path, start_time)
    end

    session
  end

  defp wait_for_page_mounting(session, page_module, start_time \\ DateTime.utc_now()) do
    callback = fn mounted_page ->
      if mounted_page != inspect(page_module) && !timed_out?(start_time) do
        :timer.sleep(100)
        wait_for_page_mounting(session, page_module, start_time)
      end
    end

    script = "return window?.hologram?.['mountedPage'];"

    Browser.execute_script(session, script, [], callback)
  end

  defp wait_for_server_connection(session, start_time \\ DateTime.utc_now()) do
    callback = fn connected? ->
      if !connected? && !timed_out?(start_time) do
        :timer.sleep(100)
        wait_for_server_connection(session, start_time)
      end
    end

    script = "return window?.hologram?.['connected?'];"

    Browser.execute_script(session, script, [], callback)
  end

  defp wait_for_js_error(session, start_time \\ DateTime.utc_now()) do
    Browser.execute_script(session, "1 + 1")

    if !timed_out?(start_time) do
      :timer.sleep(100)
      wait_for_js_error(session, start_time)
    end
  end
end
