defmodule Hologram.Template.DOMTree do
  @moduledoc """
  Converts the output of the template parser into a DOMTree structure.
  """

  alias Hologram.Template.Helpers
  alias Hologram.Template.Parser

  defmodule Node do
    @type t :: %__MODULE__{
            type: :component | :element | :text | :expression | :block | :doctype | :comment,
            name: String.t() | nil,
            attributes: list({String.t(), any()}) | nil,
            children: Hologram.Template.DOMTree.nodes() | nil,
            content: String.t() | any() | nil,
            module: module() | nil
          }

    defstruct [:type, :name, :content, :module, attributes: [], children: []]
  end

  @type nodes :: list(Node.t())

  @doc """
  Converts a list of parsed tags into a list of DOMTree nodes.
  """
  @spec from_parse(list(Parser.parsed_tag())) :: {:ok, nodes()} | {:error, any()}
  def from_parse(tags) do
    process(tags, [], [])
  end

  # End of input
  defp process([], [], roots) do
    {:ok, Enum.reverse(roots)}
  end

  defp process([], [{node, _children} | tail], _roots) do
    {:error, {:unclosed_tag, node, parents(tail)}}
  end

  # Text
  defp process([{:text, content} | rest], stack, roots) do
    node = %Node{type: :text, content: content}
    add_node(node, rest, stack, roots)
  end

  # Start Tag
  defp process([{:start_tag, {tag_name, attrs}} | rest], stack, roots) do
    node = %Node{
      type: Helpers.tag_type(tag_name),
      name: tag_name,
      attributes: attrs
    }

    process(rest, [{node, []} | stack], roots)
  end

  # Self Closing Tag
  defp process([{:self_closing_tag, {tag_name, attrs}} | rest], stack, roots) do
    node = %Node{
      type: Helpers.tag_type(tag_name),
      name: tag_name,
      attributes: attrs
    }

    add_node(node, rest, stack, roots)
  end

  # End Tag
  defp process([{:end_tag, tag_name} | rest], stack, roots) do
    handle_end_tag(tag_name, :html, rest, stack, roots)
  end

  # Block Start: Else
  defp process([{:block_start, "else"} | _rest], [], _roots) do
    {:error, {:unexpected_tag, "else", []}}
  end

  defp process([{:block_start, "else"} | rest], stack, roots) do
    case stack do
      [{%Node{type: :block, name: "if"}, _children} | _tail] ->
        node = %Node{type: :block, name: "else"}
        process(rest, [{node, []} | stack], roots)

      _stack ->
        {:error, {:unexpected_tag, "else", parents(stack)}}
    end
  end

  # Block Start: Raw
  defp process([{:block_start, "raw"} | rest], stack, roots) do
    node = %Node{type: :block, name: "raw"}
    process(rest, [{node, []} | stack], roots)
  end

  # Block Start: Generic
  defp process([{:block_start, {name, expr}} | rest], stack, roots) do
    node = %Node{
      type: :block,
      name: name,
      content: expr
    }

    process(rest, [{node, []} | stack], roots)
  end

  # Block End
  defp process([{:block_end, name} | rest], stack, roots) do
    handle_end_tag(name, :block, rest, stack, roots)
  end

  # Expression
  defp process([{:expression, content} | rest], stack, roots) do
    node = %Node{
      type: :expression,
      content: content
    }

    add_node(node, rest, stack, roots)
  end

  # Doctype
  defp process([{:doctype, content} | rest], stack, roots) do
    node = %Node{type: :doctype, content: content}
    add_node(node, rest, stack, roots)
  end

  # Comment Start
  defp process([:public_comment_start | rest], stack, roots) do
    node = %Node{type: :comment}
    process(rest, [{node, []} | stack], roots)
  end

  # Comment End
  defp process([:public_comment_end | rest], stack, roots) do
    case stack do
      [{%{type: :comment} = node, children} | stack_tail] ->
        finished_node = %{node | children: Enum.reverse(children)}
        add_node(finished_node, rest, stack_tail, roots)

      _stack ->
        {:error, {:unexpected_closing_tag, "-->", :html, parents(stack)}}
    end
  end

  # Helpers

  defp add_node(node, rest, [], roots) do
    process(rest, [], [node | roots])
  end

  defp add_node(node, rest, [{parent, children} | tail], roots) do
    new_stack = [{parent, [node | children]} | tail]
    process(rest, new_stack, roots)
  end

  defp handle_end_tag(tag_name, kind, rest, stack, roots) do
    case stack do
      [{%{name: ^tag_name} = node, children} | stack_tail] ->
        finished_node = %{node | children: Enum.reverse(children)}
        add_node(finished_node, rest, stack_tail, roots)

      [{%{name: "else"}, _else_children} | [{%{name: "if"}, _if_children} | _if_tail]]
      when tag_name == "if" ->
        handle_implicit_else_closing(rest, stack, roots)

      _stack ->
        {:error, {:unexpected_closing_tag, tag_name, kind, parents(stack)}}
    end
  end

  defp handle_implicit_else_closing(rest, stack, roots) do
    [
      {%{name: "else"} = else_node, else_children}
      | [{%{name: "if"} = if_node, if_children} | if_tail]
    ] = stack

    finished_else = %{else_node | children: Enum.reverse(else_children)}
    new_if_children = [finished_else | if_children]

    finished_if = %{if_node | children: Enum.reverse(new_if_children)}
    add_node(finished_if, rest, if_tail, roots)
  end

  defp parents(stack) do
    Enum.map(stack, fn {node, _children} -> node end)
  end

  @doc """
  Traverses the DOM tree(s) in a map/reduce style (depth-first, pre-order).

  The callback function should take a node and an accumulator, and return
  a tuple `{new_node, new_accumulator}`. This is useful for transforming the
  tree while collecting data, such as a list of used components.
  """
  @spec traverse(Node.t() | nodes(), any(), (Node.t(), any() -> {Node.t(), any()})) ::
          {Node.t() | nodes(), any()}
  def traverse(nodes, acc, callback) when is_list(nodes) and is_function(callback, 2) do
    Enum.map_reduce(nodes, acc, fn node, current_acc ->
      traverse(node, current_acc, callback)
    end)
  end

  def traverse(node, acc, callback) when is_function(callback, 2) do
    {new_node, new_acc} = callback.(node, acc)

    case new_node.children do
      children when is_list(children) ->
        {new_children, final_acc} = traverse(children, new_acc, callback)
        {%{new_node | children: new_children}, final_acc}

      _children ->
        {new_node, new_acc}
    end
  end
end
