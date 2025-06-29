defmodule Graph.SerializerTests do
  use ExUnit.Case, async: true

  test "to_dot/1" do
    g = kitchen_sink_graph()

    assert {:ok,
            """
            strict digraph {
                97[label="start"]
                98[label="{:complex, :label}"]
                99[label="c"]
                100[label="finish"]
                97 -> 98 [weight=3]
                98 -> 99 [label=5; weight=1]
                98 -> 100 [label=1.0; weight=3]
                99 -> 100 [weight=1]
            }
            """} = Graph.to_dot(g)
  end

  test "to_edgelist" do
    g = kitchen_sink_graph()

    {:ok, actual} = Graph.to_edgelist(g)

    expected = """
    "start" "{:complex, :label}"
    "{:complex, :label}" "c"
    "{:complex, :label}" "finish"
    "c" "finish"
    """

    assert actual == expected
  end

  test "to_flowchart" do
    g = kitchen_sink_graph()

    {:ok, actual} = Graph.to_flowchart(g)

    expected = """
    flowchart
        97["start"]
        98["{:complex, :label}"]
        99["c"]
        100["finish"]
        97 ----> 98
        98 --> |5| 99
        98 ----> |1.0| 100
        99 --> 100
    """

    assert actual == expected
  end

  defp kitchen_sink_graph do
    Graph.new()
    |> Graph.add_vertices([:a, :b, :c, :d])
    |> Graph.add_edges([{:a, :b, weight: 3}, {:b, :c, label: 5}, {:b, :d, label: 1.0}, {:c, :d}])
    |> Graph.label_vertex(:a, :start)
    |> Graph.label_vertex(:b, {:complex, :label})
    |> Graph.label_vertex(:d, "finish")
    |> Graph.update_labelled_edge(:b, :d, 1.0, weight: 3)
  end
end
