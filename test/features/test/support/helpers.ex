defmodule HologramFeatureTests.Helpers do
  alias Hologram.Router
  alias Wallaby.Browser
  alias Wallaby.Element

  defguard is_regex(term) when is_map(term) and term.__struct__ == Regex

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
    Browser.visit(session, path)
  end

  @doc """
  Returns the given argument.
  It prevents compiler warnings in tests when the given value is not permitted is specific situation.
  """
  @spec wrap_value(any) :: any
  def wrap_value(value) do
    value
  end
end
