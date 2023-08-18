defmodule Hologram.Router.SearchTree do
  alias Hologram.Router.SearchTree

  defmodule Node do
    defstruct value: nil, children: %{}
  end

  def add_route(root_node, url_path, page_module) do
    url_path_segments =
      url_path
      |> String.split("/")
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn segment ->
        if String.starts_with?(segment, ":") do
          "*"
        else
          segment
        end
      end)

    insert_node(root_node, url_path_segments, page_module)
  end

  defp insert_node(current_node, tree_path, value)

  defp insert_node(current_node, [], value) do
    %{current_node | value: value}
  end

  defp insert_node(%{children: children} = current_node, [head | tail], value) do
    child = children[head] || %SearchTree.Node{}
    new_children = Map.put(children, head, insert_node(child, tail, value))
    %{current_node | children: new_children}
  end
end
