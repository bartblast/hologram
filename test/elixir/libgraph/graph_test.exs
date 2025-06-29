defmodule GraphTest do
  use ExUnit.Case, async: true
  doctest Graph
  doctest Graph.Edge
  alias Graph.Edge
  alias Graph.Test.Generators

  test "injectable vertex_identifier" do
    g = Graph.new()

    g_with_custom_vertex_identifier =
      Graph.new(vertex_identifier: fn v -> :erlang.phash2(v, trunc(:math.pow(2, 16))) end)

    g = Graph.add_vertex(g, :v1, :labelA)

    g_with_custom_vertex_identifier =
      Graph.add_vertex(g_with_custom_vertex_identifier, :v1, :labelA)

    assert Graph.has_vertex?(g, :v1)
    assert Graph.has_vertex?(g_with_custom_vertex_identifier, :v1)
  end

  test "delete vertex" do
    g = Graph.new()
    g = Graph.add_vertex(g, :v1, :labelA)
    g = Graph.delete_vertex(g, :v1)
    g = Graph.add_vertex(g, :v1, :labelB)

    assert [:labelB] = Graph.vertex_labels(g, :v1)
  end

  test "delete vertices" do
    graph =
      Graph.new()
      |> Graph.add_vertices([1, 2, 4, 6])
      |> Graph.add_edge(1, 2)
      |> Graph.add_edge(2, 4)
      |> Graph.add_edge(4, 6)

    graph_two =
      graph
      |> Graph.add_vertices([3, 5, 7])
      |> Graph.add_edge(1, 3)
      |> Graph.add_edge(3, 4)
      |> Graph.add_edge(3, 5)
      |> Graph.add_edge(5, 6)
      |> Graph.add_edge(5, 7)

    assert graph == Graph.delete_vertices(graph_two, [3, 5, 7])
  end

  test "inspect" do
    g =
      Graph.new()
      |> Graph.add_edges([
        {:a, :b},
        {:a, :b, label: :foo},
        {:b, :c, weight: 3},
        {:b, :a, label: {:complex, :label}}
      ])

    ug =
      Graph.new(type: :undirected)
      |> Graph.add_edges([
        {:a, :b},
        {:a, :b, label: :foo},
        {:b, :c, weight: 3},
        {:b, :a, label: {:complex, :label}}
      ])

    # structs: false
    structs_false = "#{inspect(g, structs: false)}"
    doc = Inspect.Algebra.format(Inspect.Algebra.to_doc(g, %Inspect.Opts{structs: false}), 99999)
    assert ^structs_false = :erlang.iolist_to_binary(doc)

    # pretty printed
    str = "#{inspect(g)}"

    assert "#Graph<type: directed, vertices: [:a, :b, :c], edges: [:a -[foo]-> :b, :a -> :b, :b -[{:complex, :label}]-> :a, :b -> :c]>" =
             str

    ustr = "#{inspect(ug)}"

    assert "#Graph<type: undirected, vertices: [:a, :b, :c], edges: [:a <-[foo]-> :b, :a <-> :b, :a <-[{:complex, :label}]-> :b, :b <-> :c]>" =
             ustr

    # large graph
    g = Enum.reduce(1..150, Graph.new(), fn i, g -> Graph.add_edge(g, i, i + 1) end)
    str = "#{inspect(g)}"
    assert "#Graph<type: directed, num_vertices: 151, num_edges: 150>" = str
  end

  test "get info about graph" do
    g = build_basic_cyclic_graph()
    assert %{type: :directed, num_vertices: 5, num_edges: 7} = Graph.info(g)
  end

  test "is_cyclic?" do
    dg = build_basic_cyclic_digraph()
    refute :digraph_utils.is_acyclic(dg)

    g = build_basic_cyclic_graph()
    assert Graph.is_cyclic?(g)
    refute Graph.is_acyclic?(g)
  end

  test "is_acyclic?" do
    dg = build_basic_acyclic_digraph()
    assert :digraph_utils.is_acyclic(dg)

    g = build_basic_acyclic_graph()
    assert Graph.is_acyclic?(g)
    refute Graph.is_cyclic?(g)
  end

  test "is_tree?" do
    dg = build_basic_tree_digraph()
    assert :digraph_utils.is_tree(dg)

    g = build_basic_tree_graph()
    assert Graph.is_tree?(g)
  end

  test "is_arborescence?" do
    dg = build_basic_tree_digraph()
    assert :digraph_utils.is_arborescence(dg)

    g = build_basic_tree_graph()
    assert Graph.is_arborescence?(g)
  end

  test "arborescence_root" do
    dg = build_basic_tree_digraph()
    assert {:yes, root} = :digraph_utils.arborescence_root(dg)

    g = build_basic_tree_graph()
    assert ^root = Graph.arborescence_root(g)
  end

  test "edges/2 returns both directions" do
    generated_result =
      Graph.new()
      |> Graph.add_edges([
        {:a, :b, label: "label1"},
        {:a, :b, label: "label2"},
        {:b, :a, label: "label3"}
      ])
      |> Graph.edges(:a)

    expected_result = [
      %Graph.Edge{label: "label3", v1: :b, v2: :a, weight: 1},
      %Graph.Edge{label: "label1", v1: :a, v2: :b, weight: 1},
      %Graph.Edge{label: "label2", v1: :a, v2: :b, weight: 1}
    ]

    assert generated_result == expected_result
  end

  test "is_subgraph?" do
    g = build_basic_tree_graph()
    sg = Graph.subgraph(g, [:a, :b, :c])
    assert Graph.is_subgraph?(sg, g)
  end

  test "topsort" do
    dg = build_basic_acyclic_digraph()
    dg_sorted = :digraph_utils.topsort(dg)
    assert is_list(dg_sorted)

    g = build_basic_acyclic_graph()
    assert ^dg_sorted = Graph.topsort(g)
  end

  test "find all paths" do
    g = build_basic_cyclic_graph()

    assert [[:a, :c, :d, :e], [:a, :b, :d, :e], [:a, :b, :c, :d, :e]] = Graph.get_paths(g, :a, :e)
  end

  test "find all paths on loopy graph" do
    g =
      Graph.new()
      |> Graph.add_edge(:a, :b)
      |> Graph.add_edge(:a, :c)
      |> Graph.add_edge(:b, :d)
      |> Graph.add_edge(:c, :d)
      |> Graph.add_edge(:d, :e)
      |> Graph.add_edge(:e, :d)
      |> Graph.add_edge(:d, :f)
      |> Graph.add_edge(:f, :d)

    assert [[:a, :c, :d], [:a, :b, :d]] == Graph.get_paths(g, :a, :d)
  end

  test "find shortest path" do
    g = build_basic_cyclic_graph()

    assert [:a, :b, :d, :e] = Graph.get_shortest_path(g, :a, :e)
  end

  test "shortest path is correct" do
    g = Generators.dag(1_000)
    dg = Generators.libgraph_to_digraph(g)

    paths = Graph.get_paths(g, 1, 1_000)

    shortest_g = Graph.dijkstra(g, 1, 1_000)
    shortest_dg = :digraph.get_short_path(dg, 1, 1_000)
    assert is_list(shortest_g)
    assert is_list(shortest_dg)

    assert is_list(paths)
    [shortest | _] = Enum.sort_by(paths, &length/1)
    shortest_len = length(shortest)

    assert ^shortest_len = length(shortest_dg)
    assert ^shortest_len = length(shortest_g)
  end

  test "shortest path for complex graph" do
    g = build_complex_graph()

    shortest_g = Graph.dijkstra(g, "start", "end")

    assert shortest_g ==
             [
               "start",
               "start_0",
               96,
               97,
               98,
               33,
               100,
               34,
               35,
               36,
               37,
               19,
               65,
               66,
               67,
               "end_0",
               "end"
             ]
  end

  test "shortest path for complex undirected graph" do
    g = build_complex_graph(:undirected)

    shortest_g = Graph.dijkstra(g, "start", "end")

    assert shortest_g ==
             ["start", "start_0", 95, 94, 93, 39, 38, 21, 69, 68, "end_0", "end"]
  end

  test "shortest path for complex graph using float weights" do
    g = build_complex_graph_float()

    shortest_g = Graph.dijkstra(g, "start", "end")

    assert shortest_g ==
             [
               "start",
               "start_0",
               96,
               97,
               98,
               33,
               100,
               34,
               35,
               36,
               37,
               19,
               65,
               66,
               67,
               "end_0",
               "end"
             ]
  end

  test "shortest path for complex undirected graph using float weights" do
    g = build_complex_graph_float(:undirected)

    shortest_g = Graph.dijkstra(g, "start", "end")

    assert shortest_g ==
             ["start", "start_0", 95, 94, 93, 39, 38, 21, 69, 68, "end_0", "end"]
  end

  test "shortest paths for complex graph using signed weights (negative and positive)" do
    g = build_complex_signed_graph()
    shortest_paths = Graph.bellman_ford(g, :a)
    assert shortest_paths == %{a: 0, b: -1, c: 2, d: -2, e: 1}
  end

  test "edge undirected graph v1 > v2" do
    g = build_basic_undirected_graph()
    e1 = Graph.edge(g, :a, :b)
    e2 = Graph.edge(g, :b, :a)
    assert e1 == e2
  end

  test "edge undirected graph v1 < v2" do
    g = build_basic_undirected_graph()
    e1 = Graph.edge(g, :b, :c)
    e2 = Graph.edge(g, :c, :b)
    assert e1 == e2
  end

  test "edges undirected graph v1 > v2" do
    g = build_basic_undirected_graph()
    e1 = Graph.edges(g, :a, :b)
    e2 = Graph.edges(g, :b, :a)
    assert e1 == e2
  end

  test "edges undirected graph v1 < v2" do
    g = build_basic_undirected_graph()
    e1 = Graph.edges(g, :b, :c)
    e2 = Graph.edges(g, :c, :b)
    assert e1 == e2
  end

  test "out_edges" do
    g = build_basic_acyclic_graph()
    assert [%Edge{v1: :c, v2: :d}] = Graph.out_edges(g, :c)
  end

  test "in_edges" do
    g = build_basic_acyclic_graph()
    assert [%Edge{v1: :b, v2: :d}, %Edge{v1: :c, v2: :d}] = Graph.in_edges(g, :d)
  end

  test "out_neighbors" do
    g = build_basic_acyclic_graph()
    assert [:d] = Graph.out_neighbors(g, :c)
  end

  test "in_neighbors" do
    g = build_basic_acyclic_graph()
    assert [:b, :c] = Graph.in_neighbors(g, :d)
  end

  test "cliques/1" do
    g =
      Graph.new(type: :undirected)
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f])
      |> Graph.add_edges([{:a, :b}, {:b, :c}, {:c, :d}, {:d, :e}, {:e, :a}, {:e, :b}, {:d, :f}])

    cliques = Graph.cliques(g)
    assert [[:a, :b, :e], [:b, :c], [:c, :d], [:d, :e], [:d, :f]] = cliques
  end

  test "k_cliques/2" do
    g =
      Graph.new(type: :undirected)
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f])
      |> Graph.add_edges([{:a, :b}, {:b, :c}, {:c, :d}, {:d, :e}, {:e, :a}, {:e, :b}, {:d, :f}])

    assert [[:a, :b, :e]] = Graph.k_cliques(g, 3)
  end

  test "k_core/2" do
    g =
      Graph.new(type: :undirected)
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Graph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    zero_core = Graph.k_core(g, 0)
    assert Graph.is_subgraph?(zero_core, g)
    assert Graph.vertices(g) == Graph.vertices(zero_core)

    one_core = Graph.k_core(g, 1)
    assert Graph.is_subgraph?(one_core, zero_core)
    assert Graph.vertices(one_core) == [:a, :b, :c, :d, :e, :f, :g, :h]

    three_core = Graph.k_core(g, 3)
    assert Graph.is_subgraph?(three_core, one_core)
    assert Graph.vertices(three_core) == [:a, :b, :c, :d]

    g =
      Graph.new(type: :undirected)
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Graph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:d, :e},
        {:e, :f},
        {:f, :g},
        {:g, :h},
        {:h, :i},
        {:i, :f},
        {:f, :h},
        {:i, :g}
      ])

    three_core = Graph.k_core(g, 3)
    assert Graph.vertices(three_core) == [:a, :b, :c, :d, :f, :g, :h, :i]

    g =
      Graph.new()
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Graph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :a},
        {:b, :c},
        {:b, :d},
        {:c, :a},
        {:c, :b},
        {:c, :d},
        {:d, :a},
        {:d, :b},
        {:d, :c},
        {:d, :e},
        {:e, :d},
        {:e, :f},
        {:f, :e},
        {:f, :g},
        {:g, :f},
        {:g, :h},
        {:h, :g},
        {:h, :i},
        {:i, :h},
        {:i, :f},
        {:f, :i},
        {:h, :f},
        {:f, :h},
        {:g, :i},
        {:i, :g}
      ])

    three_core = Graph.k_core(g, 3)
    assert Graph.vertices(three_core) == [:a, :b, :c, :d, :f, :g, :h, :i]
  end

  test "k_core_components/1" do
    g =
      Graph.new(type: :undirected)
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Graph.add_edges([
        {:a, :a},
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    components = Graph.k_core_components(g)
    assert [:i] = components[0]
    assert [:e, :f, :g, :h] = components[1]
    assert is_nil(components[2])
    assert [:a, :b, :c, :d] = components[3]
  end

  test "coreness/2" do
    g =
      Graph.new(type: :undirected)
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Graph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    assert 3 = Graph.coreness(g, :a)
  end

  test "degeneracy_core/1" do
    g =
      Graph.new(type: :undirected)
      |> Graph.add_vertices([:a, :b, :c, :d, :e, :f, :g, :h, :i])
      |> Graph.add_edges([
        {:a, :b},
        {:a, :c},
        {:a, :d},
        {:b, :c},
        {:b, :d},
        {:c, :d},
        {:c, :e},
        {:e, :f},
        {:f, :g},
        {:f, :h}
      ])

    assert 3 = Graph.degeneracy(g)
    dg = Graph.degeneracy_core(g)
    assert [:a, :b, :c, :d] = Graph.vertices(dg)
  end

  @tag timeout: 120_000
  @enron_emails Path.join([__DIR__, "fixtures", "email-Enron.txt"])
  test "degeneracy/1 - Enron emails" do
    g = Graph.Test.Fixtures.Parser.parse(@enron_emails)
    assert 36_692 = Graph.num_vertices(g)
    assert 183_831 = Graph.num_edges(g)
    assert 43 = Graph.degeneracy(g)
  end

  @tag timeout: 120_000
  @hamster_friends Path.join([__DIR__, "fixtures", "petster", "edges.txt"])
  test "degeneracy/1 - Petster hamster friendships" do
    g = Graph.Test.Fixtures.Parser.parse(@hamster_friends)
    assert 1_858 = Graph.num_vertices(g)
    assert 12_534 = Graph.num_edges(g)
    assert 20 = Graph.degeneracy(g)
  end

  defp build_basic_cyclic_graph do
    Graph.new()
    |> Graph.add_vertex(:a)
    |> Graph.add_vertex(:b)
    |> Graph.add_vertex(:c)
    |> Graph.add_vertex(:d)
    |> Graph.add_vertex(:e)
    |> Graph.add_edge(:a, :b)
    |> Graph.add_edge(:a, :c)
    |> Graph.add_edge(:b, :c)
    |> Graph.add_edge(:b, :d)
    |> Graph.add_edge(:c, :d)
    |> Graph.add_edge(:c, :a)
    |> Graph.add_edge(:d, :e)
  end

  defp build_basic_cyclic_digraph do
    dg = :digraph.new()
    :digraph.add_vertex(dg, :a)
    :digraph.add_vertex(dg, :b)
    :digraph.add_vertex(dg, :c)
    :digraph.add_vertex(dg, :d)
    :digraph.add_vertex(dg, :e)
    :digraph.add_edge(dg, :a, :b)
    :digraph.add_edge(dg, :a, :c)
    :digraph.add_edge(dg, :b, :c)
    :digraph.add_edge(dg, :b, :d)
    :digraph.add_edge(dg, :c, :d)
    :digraph.add_edge(dg, :c, :a)
    :digraph.add_edge(dg, :d, :e)
    dg
  end

  defp build_basic_acyclic_graph do
    Graph.new()
    |> Graph.add_vertex(:a)
    |> Graph.add_vertex(:b)
    |> Graph.add_vertex(:c)
    |> Graph.add_vertex(:d)
    |> Graph.add_vertex(:e)
    |> Graph.add_edge(:a, :b)
    |> Graph.add_edge(:a, :c)
    |> Graph.add_edge(:b, :c)
    |> Graph.add_edge(:b, :d)
    |> Graph.add_edge(:c, :d)
    |> Graph.add_edge(:d, :e)
  end

  defp build_basic_acyclic_digraph do
    dg = :digraph.new()
    :digraph.add_vertex(dg, :a)
    :digraph.add_vertex(dg, :b)
    :digraph.add_vertex(dg, :c)
    :digraph.add_vertex(dg, :d)
    :digraph.add_vertex(dg, :e)
    :digraph.add_edge(dg, :a, :b)
    :digraph.add_edge(dg, :a, :c)
    :digraph.add_edge(dg, :b, :c)
    :digraph.add_edge(dg, :b, :d)
    :digraph.add_edge(dg, :c, :d)
    :digraph.add_edge(dg, :d, :e)
    dg
  end

  defp build_basic_tree_graph do
    Graph.new()
    |> Graph.add_vertex(:a)
    |> Graph.add_vertex(:b)
    |> Graph.add_vertex(:c)
    |> Graph.add_vertex(:d)
    |> Graph.add_vertex(:e)
    |> Graph.add_edge(:a, :b)
    |> Graph.add_edge(:b, :c)
    |> Graph.add_edge(:c, :d)
    |> Graph.add_edge(:c, :e)
  end

  defp build_basic_tree_digraph do
    dg = :digraph.new()
    :digraph.add_vertex(dg, :a)
    :digraph.add_vertex(dg, :b)
    :digraph.add_vertex(dg, :c)
    :digraph.add_vertex(dg, :d)
    :digraph.add_vertex(dg, :e)
    :digraph.add_edge(dg, :a, :b)
    :digraph.add_edge(dg, :b, :c)
    :digraph.add_edge(dg, :c, :d)
    :digraph.add_edge(dg, :c, :e)
    dg
  end

  defp build_basic_undirected_graph do
    Graph.new(type: :undirected)
    |> Graph.add_vertices([:a, :b, :c])
    |> Graph.add_edge(:a, :b)
    |> Graph.add_edge(:c, :b)
  end

  defp build_complex_signed_graph do
    Graph.new()
    |> Graph.add_edge(:a, :b, weight: -1)
    |> Graph.add_edge(:b, :e, weight: 2)
    |> Graph.add_edge(:e, :d, weight: -3)
    |> Graph.add_edge(:d, :c, weight: 5)
    |> Graph.add_edge(:a, :c, weight: 4)
    |> Graph.add_edge(:b, :c, weight: 3)
    |> Graph.add_edge(:b, :d, weight: 2)
    |> Graph.add_edge(:d, :b, weight: 1)
  end

  defp build_complex_graph(type \\ :directed) do
    Graph.new(type: type)
    |> Graph.add_edge(42, 25, weight: 2525)
    |> Graph.add_edge(66, 67, weight: 2254)
    |> Graph.add_edge(71, 72, weight: 3895)
    |> Graph.add_edge(79, 80, weight: 37236)
    |> Graph.add_edge(0, 1, weight: 1573)
    |> Graph.add_edge(0, 64, weight: 1595)
    |> Graph.add_edge(30, 31, weight: 518)
    |> Graph.add_edge(58, 56, weight: 431)
    |> Graph.add_edge(58, 60, weight: 468)
    |> Graph.add_edge(58, 47, weight: 1175)
    |> Graph.add_edge(23, 24, weight: 1807)
    |> Graph.add_edge(50, 56, weight: 1192)
    |> Graph.add_edge(50, 49, weight: 198)
    |> Graph.add_edge(50, 57, weight: 1192)
    |> Graph.add_edge(22, 23, weight: 1919)
    |> Graph.add_edge(22, 91, weight: 4032)
    |> Graph.add_edge(43, 44, weight: 255)
    |> Graph.add_edge(60, 46, weight: 1167)
    |> Graph.add_edge(60, 55, weight: 159)
    |> Graph.add_edge(60, 58, weight: 468)
    |> Graph.add_edge(36, 37, weight: 9132)
    |> Graph.add_edge(75, 77, weight: 2120)
    |> Graph.add_edge(14, 15, weight: 3483)
    |> Graph.add_edge(32, 33, weight: 1008)
    |> Graph.add_edge(41, 20, weight: 2271)
    |> Graph.add_edge(101, 102, weight: 27752)
    |> Graph.add_edge(102, 104, weight: 44964)
    |> Graph.add_edge(102, 103, weight: 1287)
    |> Graph.add_edge(104, 78, weight: 944)
    |> Graph.add_edge(85, 86, weight: 3029)
    |> Graph.add_edge(72, 73, weight: 2872)
    |> Graph.add_edge(88, 89, weight: 7817)
    |> Graph.add_edge(103, 92, weight: 2884)
    |> Graph.add_edge(69, 70, weight: 1719)
    |> Graph.add_edge(69, 21, weight: 3059)
    |> Graph.add_edge(13, 14, weight: 3002)
    |> Graph.add_edge(84, 85, weight: 3735)
    |> Graph.add_edge(48, 47, weight: 204)
    |> Graph.add_edge(34, 35, weight: 6487)
    |> Graph.add_edge(80, 90, weight: 29876)
    |> Graph.add_edge(80, 103, weight: 2047)
    |> Graph.add_edge(95, "start_0", weight: 3130)
    |> Graph.add_edge(49, 50, weight: 198)
    |> Graph.add_edge(38, 39, weight: 11222)
    |> Graph.add_edge(37, 19, weight: 5284)
    |> Graph.add_edge(68, 69, weight: 2476)
    |> Graph.add_edge(77, 78, weight: 2138)
    |> Graph.add_edge(86, 87, weight: 8289)
    |> Graph.add_edge(61, 64, weight: 508)
    |> Graph.add_edge(61, 46, weight: 1181)
    |> Graph.add_edge(61, 59, weight: 490)
    |> Graph.add_edge("end_0", 68, weight: 288)
    |> Graph.add_edge("end_0", "end", weight: 0)
    |> Graph.add_edge(87, 88, weight: 5729)
    |> Graph.add_edge(94, 95, weight: 2665)
    |> Graph.add_edge(74, 75, weight: 1641)
    |> Graph.add_edge(12, 13, weight: 5014)
    |> Graph.add_edge(25, 30, weight: 1645)
    |> Graph.add_edge(25, 24, weight: 248)
    |> Graph.add_edge(15, 1, weight: 2005)
    |> Graph.add_edge(4, 12, weight: 3150)
    |> Graph.add_edge(54, 56, weight: 547)
    |> Graph.add_edge(54, 52, weight: 1332)
    |> Graph.add_edge(54, 27, weight: 2095)
    |> Graph.add_edge(70, 71, weight: 22390)
    |> Graph.add_edge(29, 32, weight: 2449)
    |> Graph.add_edge(59, 47, weight: 1190)
    |> Graph.add_edge(59, 57, weight: 418)
    |> Graph.add_edge(59, 61, weight: 490)
    |> Graph.add_edge(35, 36, weight: 6814)
    |> Graph.add_edge(52, 51, weight: 195)
    |> Graph.add_edge(52, 54, weight: 1332)
    |> Graph.add_edge(52, 55, weight: 1186)
    |> Graph.add_edge("start", "start_0", weight: 0)
    |> Graph.add_edge(78, 84, weight: 3418)
    |> Graph.add_edge(78, 79, weight: 6596)
    |> Graph.add_edge("start_0", 96, weight: 120)
    |> Graph.add_edge(39, 93, weight: 4220)
    |> Graph.add_edge(39, 40, weight: 5082)
    |> Graph.add_edge(45, 46, weight: 235)
    |> Graph.add_edge(18, 29, weight: 600)
    |> Graph.add_edge(73, 74, weight: 788)
    |> Graph.add_edge(98, 41, weight: 2187)
    |> Graph.add_edge(98, 33, weight: 1496)
    |> Graph.add_edge(93, 94, weight: 13132)
    |> Graph.add_edge(20, 42, weight: 566)
    |> Graph.add_edge(67, "end_0", weight: 483)
    |> Graph.add_edge(64, 0, weight: 1595)
    |> Graph.add_edge(64, 44, weight: 1174)
    |> Graph.add_edge(64, 61, weight: 508)
    |> Graph.add_edge(96, 13, weight: 2865)
    |> Graph.add_edge(96, 97, weight: 2773)
    |> Graph.add_edge(46, 60, weight: 1167)
    |> Graph.add_edge(46, 45, weight: 235)
    |> Graph.add_edge(46, 61, weight: 1181)
    |> Graph.add_edge(19, 70, weight: 2732)
    |> Graph.add_edge(19, 65, weight: 1911)
    |> Graph.add_edge(65, 66, weight: 2886)
    |> Graph.add_edge(51, 52, weight: 195)
    |> Graph.add_edge(33, 100, weight: 4369)
    |> Graph.add_edge(89, 21, weight: 3165)
    |> Graph.add_edge(89, 65, weight: 3221)
    |> Graph.add_edge(1, 0, weight: 1573)
    |> Graph.add_edge(1, 3, weight: 1999)
    |> Graph.add_edge(100, 93, weight: 2056)
    |> Graph.add_edge(100, 34, weight: 4038)
    |> Graph.add_edge(55, 60, weight: 159)
    |> Graph.add_edge(55, 52, weight: 1186)
    |> Graph.add_edge(55, 57, weight: 358)
    |> Graph.add_edge(21, 38, weight: 16458)
    |> Graph.add_edge(40, 41, weight: 5104)
    |> Graph.add_edge(3, 4, weight: 3476)
    |> Graph.add_edge(91, 22, weight: 4032)
    |> Graph.add_edge(91, 101, weight: 1970)
    |> Graph.add_edge(44, 64, weight: 1174)
    |> Graph.add_edge(44, 57, weight: 1129)
    |> Graph.add_edge(44, 43, weight: 255)
    |> Graph.add_edge(24, 22, weight: 1820)
    |> Graph.add_edge(24, 25, weight: 248)
    |> Graph.add_edge(27, 54, weight: 2095)
    |> Graph.add_edge(27, 29, weight: 1205)
    |> Graph.add_edge(57, 44, weight: 1129)
    |> Graph.add_edge(57, 50, weight: 1192)
    |> Graph.add_edge(57, 55, weight: 358)
    |> Graph.add_edge(57, 59, weight: 418)
    |> Graph.add_edge(92, 38, weight: 3589)
    |> Graph.add_edge(47, 48, weight: 204)
    |> Graph.add_edge(47, 59, weight: 1190)
    |> Graph.add_edge(47, 58, weight: 1175)
    |> Graph.add_edge(56, 50, weight: 1192)
    |> Graph.add_edge(56, 54, weight: 547)
    |> Graph.add_edge(56, 58, weight: 431)
    |> Graph.add_edge(90, 91, weight: 2301)
    |> Graph.add_edge(31, 18, weight: 861)
    |> Graph.add_edge(31, 27, weight: 1178)
    |> Graph.add_edge(97, 98, weight: 13465)
  end

  defp build_complex_graph_float(type \\ :directed) do
    build_complex_graph(type)
    |> Graph.edges()
    |> Enum.reduce(Graph.new(type: type), fn %Graph.Edge{weight: weight} = edge, acc ->
      acc
      |> Graph.add_edge(%Graph.Edge{edge | weight: weight / 1000})
    end)
  end
end
