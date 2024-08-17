defmodule HologramFeatureTests.Helpers do
  import ExUnit.Assertions, only: [assert: 1, assert_raise: 3]
  import Hologram.Commons.Guards, only: [is_regex: 1]

  alias Hologram.Router
  alias Wallaby.Browser
  alias Wallaby.Element

  @max_wait_time Application.compile_env(:wallaby, :max_wait_time, 3_000)

  def assert_js_error(expected_msg, fun) do
    assert_raise Wallaby.JSError, expected_msg, fn ->
      fun.()
      :timer.sleep(@max_wait_time)
    end
  end

  def assert_page(session, page_module, params \\ []) do
    path = Router.Helpers.page_path(page_module, params)
    assert Browser.current_path(session) == path

    session
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

  def visit(session, page_module, params \\ []) do
    path = Router.Helpers.page_path(page_module, params)

    session
    |> Browser.visit(path)
    |> wait_for_server_connection()
  end

  def wait_for_server_connection(session, start_time \\ DateTime.utc_now()) do
    callback = fn connected? ->
      if !connected? &&
           DateTime.diff(DateTime.utc_now(), start_time, :millisecond) < @max_wait_time - 100 do
        :timer.sleep(100)
        wait_for_server_connection(session, start_time)
      end
    end

    script = "return window?.hologram?.['connected?'];"

    Browser.execute_script(session, script, [], callback)
  end
end
