defmodule Hologram.Runtime.Controller do
  alias Hologram.Template.Renderer
  alias Phoenix.Controller

  @doc """
  Extracts param values from the given URL path corresponding to the route of the given page module.
  """
  @spec extract_params(String.t(), module) :: %{atom => any}
  def extract_params(url_path, page_module) do
    url_path
    |> String.split("/")
    |> then(fn url_path_segments ->
      page_module.__route__()
      |> String.split("/")
      |> Enum.zip(url_path_segments)
    end)
    |> Enum.reduce(%{}, fn
      {":" <> key, value}, acc ->
        key
        |> String.to_existing_atom()
        |> then(&Map.put(acc, &1, value))

      _non_param_segment, acc ->
        acc
    end)
  end

  @doc """
  Handles the page request by building HTML response body and halting the Plug pipeline.
  """
  @spec handle_request(Plug.Conn.t(), module) :: Plug.Conn.t()
  # sobelow_skip ["XSS.HTML"]
  def handle_request(conn, page_module) do
    conn.request_path
    |> extract_params(page_module)
    |> Enum.map(fn {name, value} ->
      {to_string(name), [text: value]}
    end)
    |> then(&Renderer.render_page(page_module, &1))
    |> then(fn {html, _clients} ->
      html
      |> then(&Controller.html(conn, &1))
      |> Plug.Conn.halt()
    end)
  end
end
