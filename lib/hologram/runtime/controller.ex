defmodule Hologram.Runtime.Controller do
  alias Hologram.Template.Renderer
  alias Phoenix.Controller

  @doc """
  Extracts param values from the given URL path corresponding to the route of the given page module.
  """
  @spec extract_params(String.t(), module) :: %{atom => any}
  def extract_params(url_path, page_module) do
    route_segments = String.split(page_module.__route__(), "/")
    url_path_segments = String.split(url_path, "/")

    route_segments
    |> Enum.zip(url_path_segments)
    |> Enum.reduce([], fn
      {":" <> key, value}, acc ->
        [{String.to_existing_atom(key), value} | acc]

      _non_param_segment, acc ->
        acc
    end)
    |> Enum.into(%{})
  end

  @doc """
  Handles the page request by building HTML response body and halting the Plug pipeline.
  """
  @spec handle_request(Plug.Conn.t(), module) :: Plug.Conn.t()
  # sobelow_skip ["XSS.HTML"]
  def handle_request(conn, page_module) do
    params_dom =
      conn.request_path
      |> extract_params(page_module)
      |> Enum.map(fn {name, value} ->
        {to_string(name), [text: value]}
      end)

    {html, _client_components_data} = Renderer.render_page(page_module, params_dom)

    conn
    |> Controller.html(html)
    |> Plug.Conn.halt()
  end
end
