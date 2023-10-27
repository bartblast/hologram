defmodule Hologram.Router.SearchTree do
  alias Hologram.Router.SearchTree

  defmodule Node do
    defstruct value: nil, children: %{}

    @type t :: %__MODULE__{value: module | nil, children: %{String.t() => __MODULE__.t()}}
  end

  @doc """
  Adds route info for the given URL path to the search tree by creating all nodes related to that URL path.
  """
  @spec add_route(SearchTree.Node.t(), String.t(), module) :: SearchTree.Node.t()
  def add_route(search_tree, url_path, page_module) do
    url_path
    |> url_path_segments()
    |> then(&insert_node(search_tree, &1, page_module))
  end

  @doc """
  Matches the given URL path against the search tree.
  """
  @spec match_route(SearchTree.Node.t(), String.t()) :: atom | false
  def match_route(search_tree, url_path) do
    url_path
    |> url_path_segments()
    |> then(&(find_node(search_tree, &1) || false))
  end

  defp find_node(current_node, tree_path)

  defp find_node(%{value: nil}, []), do: false

  defp find_node(%{value: value}, []), do: value

  defp find_node(%{children: children}, [head | tail]) do
    cond do
      children[head] -> find_node(children[head], tail)
      children["*"] -> find_node(children["*"], tail)
      true -> nil
    end
  end

  defp insert_node(current_node, tree_path, value)

  defp insert_node(current_node, [], value) do
    %{current_node | value: value}
  end

  defp insert_node(%{children: children} = current_node, [head | tail], value) do
    children[head]
    |> then(&(&1 || %SearchTree.Node{}))
    |> then(&insert_node(&1, tail, value))
    |> then(&Map.put(children, head, &1))
    |> then(&Map.put(current_node, :children, &1))
  end

  defp url_path_segments(url_path) do
    url_path
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn
      ":" <> _segment -> "*"
      segment -> segment
    end)
  end
end
