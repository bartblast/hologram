defmodule Hologram.Router do
  use GenServer

  alias Hologram.Commons.Reflection
  alias Hologram.Router.SearchTree
  alias Hologram.Runtime.Controller

  @persistent_term_key {__MODULE__, :search_tree}

  @doc """
  Uses the controller to handle the request if the request path is matched as route of any Hologram page.
  """
  @spec call(Plug.Conn.t(), keyword) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: request_path} = conn, opts) do
    persistent_term_key = opts[:persistent_term_key] || @persistent_term_key

    if page_module = resolve_page(request_path, persistent_term_key) do
      Controller.handle_request(conn, page_module)
    else
      conn
    end
  end

  @impl GenServer
  def init(persistent_term_key \\ @persistent_term_key) do
    search_tree =
      Enum.reduce(Reflection.list_pages(), %SearchTree.Node{}, fn page, acc ->
        SearchTree.add_route(acc, page.__hologram_route__(), page)
      end)

    :persistent_term.put(persistent_term_key, search_tree)

    {:ok, nil}
  end

  @doc """
  Given a request path returns the page module that handles it.
  """
  @spec resolve_page(String.t(), any) :: module
  def resolve_page(request_path, persistent_term_key \\ @persistent_term_key) do
    persistent_term_key
    |> :persistent_term.get()
    |> SearchTree.match_route(request_path)
  end
end
