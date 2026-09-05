defmodule Hologram.Template.DOMTreeTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Template.DOMTree, only: [from_parse: 1]

  alias Hologram.Template.DOMTree
  alias Hologram.Template.DOMTree.Node

  test "parses simple text" do
    result =
      "Hello world"
      |> parsed_tags()
      |> from_parse()

    assert result == {:ok, [%Node{type: :text, content: "Hello world"}]}
  end

  test "parses simple element" do
    result =
      "<div id=\"test\"></div>"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:ok,
              [
                %Node{
                  type: :element,
                  name: "div",
                  attributes: [{"id", [text: "test"]}],
                  children: []
                }
              ]}
  end

  test "parses self-closing element" do
    result =
      "<br />"
      |> parsed_tags()
      |> from_parse()

    assert result == {:ok, [%Node{type: :element, name: "br", children: []}]}
  end

  test "parses component" do
    result =
      "<MyComponent prop=\"val\" />"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:ok,
              [
                %Node{
                  type: :component,
                  name: "MyComponent",
                  attributes: [{"prop", [text: "val"]}],
                  children: []
                }
              ]}
  end

  test "parses nested elements" do
    result =
      "<div><span>Text</span></div>"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:ok,
              [
                %Node{
                  type: :element,
                  name: "div",
                  children: [
                    %Node{
                      type: :element,
                      name: "span",
                      children: [
                        %Node{type: :text, content: "Text"}
                      ]
                    }
                  ]
                }
              ]}
  end

  test "respects explicit CIDs in markup as attributes" do
    {:ok, [div]} =
      ~s(<div cid="custom_id"><span cid="nested_id"></span></div>)
      |> parsed_tags()
      |> from_parse()

    # ensure CIDs are preserved as standard attributes
    assert [{"cid", [text: "custom_id"]}] = div.attributes

    [span] = div.children
    assert [{"cid", [text: "nested_id"]}] = span.attributes
  end

  test "parses expression" do
    result =
      "{1 + 1}"
      |> parsed_tags()
      |> from_parse()

    assert result == {:ok, [%Node{type: :expression, content: "{1 + 1}"}]}
  end

  test "parses doctype" do
    result =
      "<!DOCTYPE html>"
      |> parsed_tags()
      |> from_parse()

    assert result == {:ok, [%Node{type: :doctype, content: "html"}]}
  end

  test "parses comments" do
    result =
      "<!-- comment -->"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:ok,
              [
                %Node{
                  type: :comment,
                  children: [
                    %Node{type: :text, content: " comment "}
                  ]
                }
              ]}
  end

  test "parses if block" do
    result =
      "{%if true}content{/if}"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:ok,
              [
                %Node{
                  type: :block,
                  name: "if",
                  content: "{ true}",
                  children: [
                    %Node{type: :text, content: "content"}
                  ]
                }
              ]}
  end

  test "parses if/else block" do
    result =
      "{%if true}yes{%else}no{/if}"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:ok,
              [
                %Node{
                  type: :block,
                  name: "if",
                  content: "{ true}",
                  children: [
                    %Node{type: :text, content: "yes"},
                    %Node{
                      type: :block,
                      name: "else",
                      children: [
                        %Node{type: :text, content: "no"}
                      ]
                    }
                  ]
                }
              ]}
  end

  test "parses for block" do
    result =
      "{%for item <- list}item{/for}"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:ok,
              [
                %Node{
                  type: :block,
                  name: "for",
                  content: "{ item <- list}",
                  children: [
                    %Node{type: :text, content: "item"}
                  ]
                }
              ]}
  end

  test "handles unclosed tag error" do
    result =
      "<div>"
      |> parsed_tags()
      |> from_parse()

    assert result == {:error, {:unclosed_tag, %Node{type: :element, name: "div"}, []}}
  end

  test "handles mismatched closing tag error" do
    result =
      "<div></span>"
      |> parsed_tags()
      |> from_parse()

    assert result ==
             {:error,
              {:unexpected_closing_tag, "span", :html, [%Node{type: :element, name: "div"}]}}
  end

  test "handles unexpected else tag error" do
    result =
      "<div>{%else}</div>"
      |> parsed_tags()
      |> from_parse()

    assert result == {:error, {:unexpected_tag, "else", [%Node{type: :element, name: "div"}]}}
  end

  test "parses complex template with nesting and blocks" do
    markup = ~s(

      <div class="container">

        {%if @authenticated}

          <Header title="Welcome {@user.name}" />

          <ul>

            {%for item <- @items}

              <li class="item">

                {item.label}

                {%if item.urgent}

                  <span class="badge">Urgent</span>

                {%else}

                  <span>Regular</span>

                {/if}

              </li>

            {/for}

          </ul>

        {%else}

          <p>Please <a href="/login">login</a>.</p>

        {/if}

        <footer>Page {1 + 2}</footer>

      </div>

      )

    {:ok, nodes} =
      markup
      |> parsed_tags()
      |> from_parse()

    {_nodes, result_map} =
      DOMTree.traverse(nodes, %{components: [], blocks: [], elements: []}, fn node, acc ->
        updated_acc =
          case node do
            %Node{type: :component, name: name} ->
              Map.update!(acc, :components, &[name | &1])

            %Node{type: :block, name: name} ->
              Map.update!(acc, :blocks, &[name | &1])

            %Node{type: :element, name: name} ->
              Map.update!(acc, :elements, &[name | &1])

            _node ->
              acc
          end

        {node, updated_acc}
      end)

    assert result_map.components == ["Header"]
    # Blocks are collected in pre-order traversal
    # Div -> If -> (Header, Ul -> For -> (Li -> (If -> (Else), Else))) -> Else -> Footer
    # But traversal order depends on implementation.
    # traverse is depth-first pre-order.
    # 1. Div (element)
    # 2. If (@authenticated) (block)
    # 3. Header (component)
    # 4. Ul (element)
    # 5. For (@items) (block)
    # 6. Li (element)
    # 7. If (urgent) (block)
    # 8. Span (badge) (element)
    # 9. Else (block)
    # 10. Span (regular) (element)
    # 11. Else (block)
    # 12. P (element)
    # 13. Footer (element)
    #
    # Result list is prepended, so reverse order of traversal.

    assert "if" in result_map.blocks
    assert "for" in result_map.blocks
    assert "else" in result_map.blocks

    assert "div" in result_map.elements
    assert "footer" in result_map.elements
    assert "li" in result_map.elements
    assert "ul" in result_map.elements
    assert "span" in result_map.elements
    assert "p" in result_map.elements
  end

  describe "edge cases" do
    test "parses raw block" do
      result =
        "{ %raw}<div />{/raw}"
        |> parsed_tags()
        |> from_parse()

      assert {:ok, _nodes} = result
    end

    test "parses boolean attributes" do
      {:ok, [node]} =
        "<input disabled />"
        |> parsed_tags()
        |> from_parse()

      assert [{"disabled", []}] = node.attributes
    end

    test "parses script tag content" do
      result =
        "<script>console.log('<div>');</script>"
        |> parsed_tags()
        |> from_parse()

      assert {:ok, [node]} = result
      assert node.type == :element
      assert node.name == "script"
      assert [%{type: :text, content: "console.log('<div>');"}] = node.children
    end

    test "parses mixed attributes" do
      {:ok, [node]} =
        "<div class=\"a {b}\"></div>"
        |> parsed_tags()
        |> from_parse()

      assert [{"class", [text: "a ", expression: "{b}", text: ""]}] = node.attributes
    end

    test "parses multiple fragments" do
      result =
        "<div></div><span></span>"
        |> parsed_tags()
        |> from_parse()

      assert result ==
               {:ok, [%Node{type: :element, name: "div"}, %Node{type: :element, name: "span"}]}
    end
  end

  describe "traverse/3" do
    test "traverses and transforms nodes while accumulating state" do
      nodes =
        [
          struct(Node,
            type: :element,
            name: "div",
            children: [
              struct(Node, type: :text, content: "a"),
              struct(Node, type: :text, content: "b")
            ]
          ),
          struct(Node, type: :text, content: "c")
        ]

      callback = fn
        %{type: :text} = node, acc ->
          {%{node | content: String.upcase(node.content)}, [node.content | acc]}

        node, acc ->
          {node, acc}
      end

      {new_nodes, acc} = DOMTree.traverse(nodes, [], callback)

      assert acc == ["c", "b", "a"]

      assert(
        [
          %Node{
            name: "div",
            children: [
              %Node{content: "A"},
              %Node{content: "B"}
            ]
          },
          %Node{content: "C"}
        ] = new_nodes
      )
    end

    test "handles single node" do
      node = struct(Node, type: :text, content: "hello")
      callback = fn node, acc -> {%{node | content: "world"}, acc + 1} end

      assert {%Node{content: "world"}, 1} = DOMTree.traverse(node, 0, callback)
    end
  end
end
