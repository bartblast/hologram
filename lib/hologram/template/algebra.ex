defmodule Hologram.Template.Algebra do
  @moduledoc """
    The `Inspect.Algebra` for Hologram templates
  """

  import Inspect.Algebra

  @inline_tags ~w(a abbr b bdi bdo br button canvas cite code data datalist del dfn em embed i iframe img input ins kbd label map mark meter noscript object output picture progress q ruby s samp script select slot small span strong sub sup svg template textarea time u var video wbr)
  @inviolable_tags ~w(script style)
  @whitespace_regex ~r/\s+/

  def format_tokens(tokens, opts \\ []) do
    tokens
    |> cleanup_tokens()
    |> parse_tokens()
    |> join_nodes(opts)
  end

  defp cleanup_tokens(tokens) do
    do_cleanup_tokens(tokens, nil)
  end

  defp do_cleanup_tokens([], _last_text), do: []

  defp do_cleanup_tokens([{:block_start, "raw"} = token | rest], last_text) do
    case rest do
      [{:text, t} | tail] when not is_nil(last_text) ->
        if String.starts_with?(t, last_text) do
          new_t = String.replace_prefix(t, last_text, "")
          [token | [{:text, new_t} | do_cleanup_tokens(tail, nil)]]
        else
          [token | do_cleanup_tokens(rest, nil)]
        end

      _ ->
        [token | do_cleanup_tokens(rest, nil)]
    end
  end

  defp do_cleanup_tokens([{:text, t} = token | rest], _last_text) do
    [token | do_cleanup_tokens(rest, t)]
  end

  defp do_cleanup_tokens([token | rest], _last_text) do
    [token | do_cleanup_tokens(rest, nil)]
  end

  defp parse_tokens(tokens) do
    do_parse_tokens(tokens, [])
  end

  defp do_parse_tokens([], acc), do: Enum.reverse(acc)

  defp do_parse_tokens([{:start_tag, {tag, attrs}} | rest], acc) do
    {content_tokens, rest_after} = consume_until_end_tag(rest, tag)

    content =
      if tag in @inviolable_tags do
        content_tokens
      else
        parse_tokens(content_tokens)
      end

    do_parse_tokens(rest_after, [{:start_tag, tag, attrs, content} | acc])
  end

  defp do_parse_tokens([{:block_start, {tag, exp}} | rest], acc) do
    {content_tokens, rest_after} = consume_until_end_block(rest, tag)
    do_parse_tokens(rest_after, [{:block_start, tag, exp, parse_tokens(content_tokens)} | acc])
  end

  defp do_parse_tokens([{:block_start, tag} | rest], acc) when is_binary(tag) do
    cond do
      tag == "raw" ->
        {content_tokens, rest_after} = consume_until_end_block(rest, tag)
        do_parse_tokens(rest_after, [{:raw, content_tokens} | acc])

      tag == "else" ->
        do_parse_tokens(rest, [{:block_interior, tag} | acc])

      true ->
        {content_tokens, rest_after} = consume_until_end_block(rest, tag)
        do_parse_tokens(rest_after, [{:block_start, tag, "", parse_tokens(content_tokens)} | acc])
    end
  end

  defp do_parse_tokens([{:self_closing_tag, {tag, attrs}} | rest], acc) do
    do_parse_tokens(rest, [{:self_closing_tag, tag, attrs} | acc])
  end

  defp do_parse_tokens([{:text, _} = text | rest], acc) do
    do_parse_tokens(rest, [text | acc])
  end

  defp do_parse_tokens([{:expression, _} = exp | rest], acc) do
    do_parse_tokens(rest, [exp | acc])
  end

  defp do_parse_tokens([{:doctype, _} = doctype | rest], acc) do
    do_parse_tokens(rest, [doctype | acc])
  end

  defp do_parse_tokens([:public_comment_start | rest], acc) do
    {content_tokens, rest_after} = consume_until_public_comment_end(rest)
    do_parse_tokens(rest_after, [{:public_comment, parse_tokens(content_tokens)} | acc])
  end

  defp do_parse_tokens([_token | rest], acc) do
    do_parse_tokens(rest, acc)
  end

  defp consume_until_end_tag(tokens, tag_to_match) do
    do_consume_until_end_tag(tokens, tag_to_match, [], 0)
  end

  defp do_consume_until_end_tag([{:start_tag, {tag, _}} = token | rest], tag_to_match, acc, level)
       when tag == tag_to_match do
    do_consume_until_end_tag(rest, tag_to_match, [token | acc], level + 1)
  end

  defp do_consume_until_end_tag([{:end_tag, tag} = _token | rest], tag_to_match, acc, level)
       when tag == tag_to_match do
    if level == 0 do
      {Enum.reverse(acc), rest}
    else
      do_consume_until_end_tag(rest, tag_to_match, [{:end_tag, tag} | acc], level - 1)
    end
  end

  defp do_consume_until_end_tag([token | rest], tag_to_match, acc, level) do
    do_consume_until_end_tag(rest, tag_to_match, [token | acc], level)
  end

  defp consume_until_end_block(tokens, tag_to_match) do
    do_consume_until_end_block(tokens, tag_to_match, [], 0)
  end

  defp do_consume_until_end_block(
         [{:block_start, {tag, _}} = token | rest],
         tag_to_match,
         acc,
         level
       )
       when tag == tag_to_match do
    do_consume_until_end_block(rest, tag_to_match, [token | acc], level + 1)
  end

  defp do_consume_until_end_block([{:block_end, tag} = _token | rest], tag_to_match, acc, level)
       when tag == tag_to_match do
    if level == 0 do
      {Enum.reverse(acc), rest}
    else
      do_consume_until_end_block(rest, tag_to_match, [{:block_end, tag} | acc], level - 1)
    end
  end

  defp do_consume_until_end_block([token | rest], tag_to_match, acc, level) do
    do_consume_until_end_block(rest, tag_to_match, [token | acc], level)
  end

  defp consume_until_public_comment_end(tokens) do
    do_consume_until_public_comment_end(tokens, [])
  end

  defp do_consume_until_public_comment_end([:public_comment_end | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp do_consume_until_public_comment_end([token | rest], acc) do
    do_consume_until_public_comment_end(rest, [token | acc])
  end

  defp from_node(node, opts) do
    case node do
      {:start_tag, tag, attrs, content_nodes} ->
        open = group(concat([string("<"), string(tag), from_attrs(attrs), string(">")]))
        close = string("</" <> tag <> ">")

        if tag in @inviolable_tags do
          if content_nodes == [] do
            concat(open, close)
          else
            {content, _raw?} =
              Enum.reduce(content_nodes, {"", false}, fn node, {acc_content, acc_raw?} ->
                case node do
                  {:block_start, "raw"} ->
                    {acc_content <> tag_to_markup(node, acc_raw?), true}

                  {:block_end, "raw"} ->
                    {acc_content <> tag_to_markup(node, true), false}

                  _ ->
                    {acc_content <> tag_to_markup(node, acc_raw?), acc_raw?}
                end
              end)

            if String.contains?(content, "\n") do
              lines =
                content
                |> String.split("\n")
                |> Enum.map(&String.trim_trailing/1)
                |> Enum.drop_while(&(String.trim(&1) == ""))
                |> Enum.reverse()
                |> Enum.drop_while(&(String.trim(&1) == ""))
                |> Enum.reverse()

              common_indent =
                lines
                |> Enum.filter(&(String.trim(&1) != ""))
                |> Enum.map(fn line ->
                  case Regex.run(~r/^\s*/, line) do
                    [indent] -> String.length(indent)
                    _ -> 0
                  end
                end)
                |> case do
                  [] -> 0
                  indents -> Enum.min(indents)
                end

              content_doc =
                lines
                |> Enum.map(fn line ->
                  if String.trim(line) == "" do
                    ""
                  else
                    String.slice(line, common_indent..-1//1)
                  end
                end)
                |> Enum.map(&string/1)
                |> Enum.intersperse(line())
                |> concat()

              concat([open, nest(concat(line(), content_doc), 2), line(), close])
            else
              concat([open, string(content), close])
            end
          end
        else
          content_doc = join_nodes(content_nodes, opts)

          if (tag in @inline_tags or opts[:layout] == :inline) and
               can_be_inline?(content_nodes, opts) do
            group(concat([open, nest(content_doc, 2), close]))
          else
            if content_doc == empty() do
              concat(open, close)
            else
              concat([open, nest(concat(line(), content_doc), 2), line(), close])
            end
          end
        end

      {:self_closing_tag, tag, attrs} ->
        group(concat([string("<"), string(tag), from_attrs(attrs), break(" "), string("/>")]))

      {:block_start, tag, exp, content_nodes} ->
        open = concat([string("{%"), string(tag), from_block_expression(exp), string("}")])
        close = concat([string("{/"), string(tag), string("}")])

        if content_nodes == [] do
          concat(open, close)
        else
          content_doc = format_block_content(content_nodes, opts)
          concat([open, content_doc, line(), close])
        end

      {:block_interior, tag} ->
        concat([line(), concat([string("{%"), string(tag), string("}")])])

      {:expression, e} ->
        content = expression_content(e)

        case Code.string_to_quoted(content) do
          {:ok, ast} ->
            group(
              concat([
                string("{"),
                nest(Code.quoted_to_algebra(ast, []), 2),
                string("}")
              ])
            )

          _ ->
            string(tighten_expression(e))
        end

      {:text, t} ->
        t =
          t
          |> String.replace("{", "\\{")
          |> String.replace("}", "\\}")

        if String.trim(t) == "" do
          empty()
        else
          if String.contains?(t, "\n") do
            t
            |> String.split(~r/\n\s*/)
            |> Enum.map(&string/1)
            |> Enum.intersperse(line())
            |> concat()
          else
            doc =
              t
              |> String.replace(@whitespace_regex, " ")
              |> String.split(" ")
              |> Enum.map(&string/1)
              |> Enum.intersperse(break(" "))
              |> concat()

            group(doc)
          end
        end

      {:raw, content_tags} ->
        content = Enum.map_join(content_tags, "", &tag_to_markup(&1, true))
        concat([string("{%raw}"), string(content), string("{/raw}")])

      {:doctype, content} ->
        concat([string("<!DOCTYPE "), string(content), string(">"), line()])

      {:public_comment, content_nodes} ->
        content_doc = join_nodes(content_nodes, opts)
        concat([string("<!--"), content_doc, string("-->")])

      _ ->
        empty()
    end
  end

  defp format_block_content(nodes, opts) do
    nodes
    |> Enum.chunk_by(fn node -> match?({:block_interior, _}, node) end)
    |> Enum.map(fn
      [{:block_interior, tag}] ->
        from_node({:block_interior, tag}, opts)

      group ->
        nest(concat(line(), join_nodes(group, opts)), 2)
    end)
    |> concat()
  end

  defp join_nodes(nodes, opts) do
    nodes
    |> Enum.chunk_by(&is_inline_node?(&1, opts))
    |> Enum.map(fn group ->
      if is_inline_node?(hd(group), opts) do
        join_inline_group(group, opts)
      else
        join_block_group(group, opts)
      end
    end)
    |> Enum.intersperse(if opts[:layout] == :inline, do: break(""), else: line())
    |> flatten_docs()
    |> dedup_lines()
    |> trim_lines()
    |> concat()
  end

  defp is_inline_node?(node, opts) do
    case node do
      {:text, _} -> true
      _ -> opts[:layout] == :inline or can_be_inline?([node], opts)
    end
  end

  defp join_inline_group(nodes, opts) do
    nodes
    |> Enum.map(&from_node(&1, opts))
    |> Enum.filter(fn doc -> doc != empty() end)
    |> Enum.intersperse(break(""))
    |> flatten_docs()
    |> dedup_lines()
    |> trim_lines()
    |> concat()
  end

  defp join_block_group(nodes, opts) do
    nodes
    |> Enum.map(&from_node(&1, opts))
    |> Enum.filter(fn doc -> doc != empty() end)
    |> Enum.intersperse(line())
    |> flatten_docs()
    |> dedup_lines()
    |> trim_lines()
    |> concat()
  end

  defp flatten_docs(docs) do
    docs
    |> Enum.flat_map(fn
      {:doc_cons, a, b} -> flatten_docs([a, b])
      doc -> [doc]
    end)
    |> Enum.filter(fn doc -> not is_empty_doc?(doc) end)
  end

  defp dedup_lines(docs) do
    Enum.reduce(docs, [], fn
      doc, [] ->
        [doc]

      doc, [prev | rest] = acc ->
        case {doc, prev} do
          {:doc_line, :doc_line} ->
            case rest do
              [:doc_line | _] -> acc
              _ -> [doc | acc]
            end

          {:doc_line, {:doc_break, _, _}} ->
            [doc | rest]

          {{:doc_break, _, _}, :doc_line} ->
            acc

          {{:doc_break, b1, _}, {:doc_break, b2, _}} ->
            if b1 == " " or b2 == " " do
              [break(" ") | rest]
            else
              [doc | rest]
            end

          _ ->
            if is_empty_doc?(doc) do
              acc
            else
              [doc | acc]
            end
        end
    end)
    |> Enum.reverse()
  end

  defp trim_lines(docs) do
    docs
    |> Enum.drop_while(fn doc ->
      doc == line() or match?({:doc_break, " ", _}, doc) or is_empty_doc?(doc)
    end)
    |> Enum.reverse()
    |> Enum.drop_while(fn doc ->
      doc == line() or match?({:doc_break, " ", _}, doc) or is_empty_doc?(doc)
    end)
    |> Enum.reverse()
  end

  defp is_empty_doc?(doc) do
    doc == empty() or doc == string("") or doc == ""
  end

  defp can_be_inline?([], _opts), do: true

  defp can_be_inline?(nodes, opts) do
    Enum.all?(nodes, fn
      {:expression, _} -> true
      {:text, t} -> not String.contains?(t, "\n")
      {:start_tag, tag, _, _} -> tag in @inline_tags or opts[:layout] == :inline
      {:self_closing_tag, tag, _} -> tag in @inline_tags or opts[:layout] == :inline
      {:raw, _} -> true
      _ -> false
    end)
  end

  defp from_attrs([]), do: empty()

  defp from_attrs(attrs) do
    attrs_doc =
      attrs
      |> Enum.map(fn {key, value} ->
        group(concat(string(key), from_attr_value(value)))
      end)
      |> Enum.intersperse(break(" "))
      |> concat()

    nest(concat(break(" "), attrs_doc), 2)
  end

  defp from_attr_value([]), do: empty()

  defp from_attr_value(parts) when is_list(parts) do
    relevant_parts =
      Enum.filter(parts, fn
        {:text, t} -> String.trim(t) != ""
        {:expression, _} -> true
      end)

    if relevant_parts == [] do
      empty()
    else
      value =
        Enum.map_join(parts, fn
          {:text, t} -> t
          {:expression, e} -> tighten_expression(e)
        end)

      if length(relevant_parts) == 1 and elem(hd(relevant_parts), 0) == :expression do
        concat(string("="), string(value))
      else
        concat(string("="), string("\"" <> value <> "\""))
      end
    end
  end

  defp expression_content(estr) do
    estr
    |> String.trim()
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
    |> case do
      ^estr -> estr |> String.trim()
      trimmed -> expression_content(trimmed)
    end
  end

  defp tighten_expression(estr) do
    "{" <> expression_content(estr) <> "}"
  end

  defp from_block_expression(""), do: empty()

  defp from_block_expression(e) do
    content = expression_content(e)
    if content == "", do: empty(), else: concat(break(" "), string(content))
  end

  defp tag_to_markup(tag, raw?) do
    case tag do
      {:symbol, s} ->
        s

      {:string, s} ->
        s

      {:whitespace, s} ->
        s

      {:text, t} ->
        if raw? do
          t
        else
          t |> String.replace("{", "\\{") |> String.replace("}", "\\}")
        end

      {:expression, e} ->
        e

      {:start_tag, {tag, attrs}} ->
        "<" <> tag <> attrs_to_markup(attrs) <> ">"

      {:end_tag, tag} ->
        "</" <> tag <> ">"

      {:self_closing_tag, {tag, attrs}} ->
        "<" <> tag <> attrs_to_markup(attrs) <> "/>"

      {:block_start, {tag, exp}} ->
        suffix = if exp != "", do: " " <> exp, else: ""
        "{%" <> tag <> suffix <> "}"

      {:block_start, tag} ->
        "{%" <> tag <> "}"

      {:block_end, tag} ->
        "{/" <> tag <> "}"

      {:doctype, content} ->
        "<!DOCTYPE " <> content <> ">
"

      :public_comment_start ->
        "<!--"

      :public_comment_end ->
        "-->"

      _ ->
        ""
    end
  end

  defp attrs_to_markup([]), do: ""

  defp attrs_to_markup(attrs) do
    Enum.map_join(attrs, "", fn {key, value} ->
      " " <> key <> "=" <> attr_value_to_markup(value)
    end)
  end

  defp attr_value_to_markup(value) when is_list(value) do
    inner =
      Enum.map_join(value, "", fn
        {:text, t} -> t
        {:expression, e} -> e
      end)

    if length(value) == 1 and elem(hd(value), 0) == :expression do
      inner
    else
      "\"" <> inner <> "\""
    end
  end
end
