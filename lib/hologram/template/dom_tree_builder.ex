# Covered in Hologram.Template.Parser integration tests

defmodule Hologram.Template.DOMTreeBuilder do
  alias Hologram.Template.{Helpers, SyntaxError}

  def build(tags, acc \\ [])

  def build([], acc), do: acc

  def build([{:self_closing_tag, {tag_name, attrs}} | rest], acc) do
    type = Helpers.tag_type(tag_name)
    build(rest, acc ++ [{type, tag_name, attrs, []}])
  end

  def build([{:start_tag, {tag_name, attrs}} | _] = tags, acc) do
    subtree_tags = get_subtree_tags(tags)
    remaining_tags = Enum.drop(tags, Enum.count(subtree_tags))

    children_tags =
      subtree_tags
      |> Enum.drop(1)
      |> Enum.drop(-1)

    type = Helpers.tag_type(tag_name)
    children = build(children_tags)
    subtree = {type, tag_name, attrs, children}

    build(remaining_tags, acc ++ [subtree])
  end

  def build([{:text_tag, str} | rest], acc) do
    build(rest, acc ++ [{:text, str}])
  end

  defp get_subtree_tags([{:start_tag, {tag_name, _}} = start_tag | rest]) do
    {tag_buffer, num_open_tags} =
      Enum.reduce_while(rest, {[start_tag], 1}, fn tag, {tag_buffer, num_open_tags} ->
        tag_buffer = tag_buffer ++ [tag]

        num_open_tags =
          case tag do
            {:start_tag, {^tag_name, _}} ->
              num_open_tags + 1

            {:end_tag, ^tag_name} ->
              num_open_tags - 1

            _ ->
              num_open_tags
          end

        res = if num_open_tags == 0, do: :halt, else: :cont
        {res, {tag_buffer, num_open_tags}}
      end)

    if num_open_tags > 0 do
      raise SyntaxError, message: "#{tag_name} tag is unclosed"
    end

    tag_buffer
  end
end
