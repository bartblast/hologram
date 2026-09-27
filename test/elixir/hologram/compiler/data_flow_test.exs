defmodule Hologram.Compiler.DataFlowTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.DataFlow
  import Hologram.Test.DataFlowTrees

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules
  alias Hologram.Compiler.DataFlow.ShapeSet
  alias Hologram.Compiler.DataFlow.Store
  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module10
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module11
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module12
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module13
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module14
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module15
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module16
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module17
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module18
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module19
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module20
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module21
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module24
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module25
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module4
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module5
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module6
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module7
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module8
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module9
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Rules1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct4
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct5

  # The fields an empty Struct1 or Struct2 literal holds: its one field, holding the default value.
  @defaults %{field: tree_set([{:atom, nil}])}

  @param_0 tree_set([{:param, 0}])

  # A value a pattern takes out of what param 0 holds.
  @part_of_param_0 tree_set([{:part, @param_0}])

  @struct_1 {:struct, Struct1, @defaults}
  @struct_2 {:struct, Struct2, @defaults}

  # A stored answer's atoms that are not modules are primitives (see summary/2): a struct literal's
  # default, nil, becomes a primitive.
  @stored_defaults %{field: tree_set([:prim])}
  @struct_1_stored {:struct, Struct1, @stored_defaults}
  @struct_2_stored {:struct, Struct2, @stored_defaults}

  # What a pattern naming Struct1 with no fields names.
  @struct_1_named {:struct, Struct1, %{}}

  # The tree of what the summary gives with the given arguments put in (see apply_summary/2).
  defp apply_tree(summary, args) do
    flow = flow()
    arg_sets = Enum.map(args, &ShapeSet.from_tree(&1, flow.store))

    summary
    |> ShapeSet.from_tree(flow.store)
    |> apply_summary(arg_sets, flow)
    |> to_tree(flow)
  end

  # The tree of a tuple of one-atom tuples, one for each given atom.
  defp atom_tuples(atoms) do
    tuples = for atom <- atoms, do: tree_set([{:tuple, [tree_set([{:atom, atom}])]}])
    tree_set([{:tuple, tuples}])
  end

  defp clause(module, function) do
    %IR.ModuleDefinition{body: %IR.Block{expressions: expressions}} = IR.for_module(module)

    Enum.find_value(expressions, fn
      %IR.FunctionDefinition{name: ^function, clause: clause} -> clause
      _expression -> nil
    end)
  end

  # How many times the analysis works out a summary from a function's code while running the given
  # function, counted in the calling process only, so tests running in parallel don't count.
  defp count_code_summaries(fun) do
    mfa = {DataFlow, :code_summary, 2}
    test_pid = self()
    counter = spawn(fn -> count_trace_messages(test_pid, 0) end)
    :erlang.trace_pattern(mfa, true, [:local])
    :erlang.trace(self(), true, [:arity, :call, {:tracer, counter}])

    try do
      fun.()
    after
      :erlang.trace(self(), false, [:arity, :call])
      :erlang.trace_pattern(mfa, false, [:local])
    end

    ref = :erlang.trace_delivered(self())

    receive do
      {:trace_delivered, _pid, ^ref} -> send(counter, :done)
    end

    receive do
      {:trace_messages, count} -> count
    end
  end

  defp count_trace_messages(test_pid, count) do
    receive do
      {:trace, _pid, :call, _mfa} -> count_trace_messages(test_pid, count + 1)
      :done -> send(test_pid, {:trace_messages, count})
    end
  end

  # Whether the body of the given function's only clause certainly gives a map or a struct.
  defp definite_map_of(module, function) do
    %IR.FunctionClause{params: params, body: body} = clause = clause(module, function)

    definite_map?(body, clause, {module, function, length(params)}, flow())
  end

  defp flow, do: start(PLT.start(), module_info_plt_fixture())

  # The tree of a tuple of four empty Struct1 literals, as the literal gives it.
  defp four_structs do
    struct = tree_set([@struct_1])
    tree_set([{:tuple, List.duplicate(struct, 4)}])
  end

  # The bytes of the distinct sets the tree stands for, each counted once, each nested set in them a
  # reference of one small integer: what the cap measures (see @max_summary_size).
  defp graph_bytes(tree) do
    store = Store.start()
    graph_bytes([ShapeSet.from_tree(tree, store)], store, MapSet.new(), 0)
  end

  defp graph_bytes([], _store, _visited, total), do: total

  defp graph_bytes([set | sets], store, visited, total) do
    if MapSet.member?(visited, set) do
      graph_bytes(sets, store, visited, total)
    else
      content = ShapeSet.to_list(set, store)
      nested = Enum.flat_map(content, &nested_sets/1)

      bytes =
        content
        |> Enum.map(&map_nested(&1, fn _nested -> 0 end))
        |> :erlang.external_size()

      graph_bytes(nested ++ sets, store, MapSet.put(visited, set), total + bytes)
    end
  end

  # The call graph of the given modules, built with the module info PLT of the test build.
  defp graph_of(modules) do
    modules
    |> Enum.reduce(CallGraph.start(module_info_plt: module_info_plt_fixture()), fn module, acc ->
      CallGraph.build(acc, IR.for_module(module))
    end)
    |> CallGraph.get_graph()
  end

  # The module info PLT of the test build, built once per test run and kept for the tests that take
  # no context (the analysis reads which functions are protocol functions from it). setup_all
  # builds it first, in a process that lives for the whole module, so the linked PLT does too.
  defp module_info_plt_fixture do
    case :persistent_term.get({__MODULE__, :module_info_plt}, nil) do
      nil ->
        module_info_plt = Compiler.build_module_info_plt!(PLT.start(), nil)
        :persistent_term.put({__MODULE__, :module_info_plt}, module_info_plt)
        module_info_plt

      module_info_plt ->
        module_info_plt
    end
  end

  # The tree of the shapes of the value the given function of the given module returns, from its only
  # clause.
  defp shapes_of(module, function) do
    %IR.FunctionClause{params: params, body: body} = clause = clause(module, function)

    shapes_tree(body, clause, {module, function, length(params)}, flow())
  end

  # The tree of shapes/4's answer.
  defp shapes_tree(expr, clause, mfa, flow), do: to_tree(shapes(expr, clause, mfa, flow), flow)

  # A chain of the given number of sets over param 0, each a tuple holding the one before twice.
  defp shared_chain(length, flow) do
    Enum.reduce(1..length, ShapeSet.new([{:param, 0}], flow.store), fn _index, set ->
      ShapeSet.new([{:tuple, [set, set]}], flow.store)
    end)
  end

  defp summary_of(module, function, arity), do: summary_tree({module, function, arity}, flow())

  # The tree of summary/2's answer.
  defp summary_tree(mfa, flow), do: to_tree(summary(mfa, flow), flow)

  defp types_fixture(modules, reach, structs) do
    %{modules: MapSet.new(modules), reach: MapSet.new(reach), structs: MapSet.new(structs)}
  end

  # The types of the given shapes, where Struct1 and Struct2 are struct modules and Module1 is a
  # module that defines no struct.
  defp types_of(shapes) do
    module_info_plt =
      PLT.put(PLT.start(), [
        {Module1, %{struct?: false}},
        {Struct1, %{struct?: true}},
        {Struct2, %{struct?: true}}
      ])

    flow = start(PLT.start(), module_info_plt)

    shapes
    |> tree_set()
    |> ShapeSet.from_tree(flow.store)
    |> types(flow)
  end

  setup_all do
    module_info_plt_fixture()
    :ok
  end

  describe "apply_summary/3" do
    test "puts the arguments in for the params, at any depth" do
      summary = tree_set([{:list, @param_0}, {:tuple, [tree_set([{:param, 1}])]}])
      args = [tree_set([@struct_1]), tree_set([:prim])]

      assert apply_tree(summary, args) ==
               tree_set([
                 {:list, tree_set([@struct_1])},
                 {:tuple, [tree_set([:prim])]}
               ])
    end

    test "a missing argument gives nothing" do
      assert apply_tree(tree_set([{:param, 2}, {:atom, :ok}]), [@param_0]) ==
               tree_set([{:atom, :ok}])
    end

    test "keeps what holds no params" do
      summary = tree_set([{:reach, {Module3, :build, 0}}, :prim])

      assert apply_tree(summary, []) == summary
    end

    test "makes the call of an anonymous function a param stood for" do
      ref = {{Module5, :closure_arg, 0}, 1}
      fun = {:fun, ref, tree_set([{:tuple, [tree_set([{:arg, ref, 0}])]}])}
      summary = tree_set([{:call, @param_0, [tree_set([@struct_1])]}])

      assert apply_tree(summary, [tree_set([fun])]) ==
               tree_set([{:tuple, [tree_set([@struct_1])]}])
    end

    test "leaves a dynamic call on a module a param stood for as it is" do
      summary = tree_set([{:dyn, @param_0, :build, 0, []}])
      args = [tree_set([{:atom, Module3}])]

      assert apply_tree(summary, args) ==
               tree_set([{:dyn, tree_set([{:atom, Module3}]), :build, 0, []}])
    end

    test "a param a map pattern matched is whichever alternative of the argument is a map" do
      args = [tree_set([@struct_1, {:atom, :ok}, {:map, %{}}])]

      assert apply_tree(tree_set([{:as_map, @param_0}]), args) ==
               tree_set([@struct_1, {:map, %{}}])
    end

    test "a collapsed route gives every type inside the argument" do
      summary = summary_of(Module19, :nested, 1)
      inner = tree_set([{:tuple, [tree_set([@struct_1])]}])
      arg = tree_set([{:tuple, [inner]}])

      assert Struct1 in types_of(apply_tree(summary, [arg])).structs
    end

    test "a part of a param is what is inside the argument, at any depth" do
      args = [tree_set([{:tuple, [tree_set([{:atom, :ok}]), tree_set([@struct_1])]}])]

      inside =
        tree_set([
          {:atom, :ok},
          @struct_1_named,
          {:atom, nil}
        ])

      assert apply_tree(@part_of_param_0, args) == tree_set([{:bag, inside}])
    end

    # A chain of 30 sets, each a tuple holding the one before twice: 2^30 leaves as a tree, 30 sets in
    # the store. Each substitution replaces each distinct set once, and each walk remembers its result
    # per set, so putting an argument in takes 30 steps, not 2^30.
    @tag timeout: 10_000
    # widen/1 makes a set nested three levels deep a bag of its leaves (see shape_leaves/2), so a value
    # under three tuples shows which leaves a bag keeps. `other` stands for an anonymous function that
    # is still whole elsewhere, whose placeholders a later call fills; `ref` for one dissolved here.
    test "in a bag, a step into a value not known yet is that value" do
      other = {{Module1, :other, 0}, 1}

      assert apply_tree(under_three_tuples(tree_set([{:part, tree_set([{:arg, other, 1}])}])), []) ==
               under_three_tuples(tree_set([{:bag, tree_set([{:arg, other, 1}])}]))
    end

    test "in a bag, a dissolved function's own argument placeholders and dots on them are gone" do
      ref = {{Module1, :fun, 0}, 1}
      other = {{Module1, :other, 0}, 1}

      returned =
        tree_set([
          {:arg, ref, 0},
          {:atom, :x},
          {:dot, tree_set([{:arg, ref, 0}]), :name},
          {:dot, tree_set([{:arg, other, 0}]), :name}
        ])

      leaves = tree_set([{:atom, :x}, {:dot, tree_set([{:arg, other, 0}]), :name}])

      assert apply_tree(under_three_tuples(tree_set([{:fun, ref, returned}])), []) ==
               under_three_tuples(tree_set([{:bag, leaves}]))
    end

    test "a substitution replaces a repeated set once" do
      flow = flow()
      arg = ShapeSet.new([{:atom, :x}], flow.store)

      bag = tree_set([{:bag, tree_set([{:atom, :x}])}])
      level_2 = tree_set([{:tuple, [bag, bag]}])
      level_1 = tree_set([{:tuple, [level_2, level_2]}])

      value =
        30
        |> shared_chain(flow)
        |> apply_summary([arg], flow)

      assert to_tree(value, flow) == tree_set([{:tuple, [level_1, level_1]}])
    end

    # 30 dynamic calls, each given the one before twice, in an anonymous function dissolved into a bag:
    # dropping the function's placeholders walks each distinct set once, not the 2^30 paths to them.
    @tag timeout: 10_000
    test "a dissolved function's placeholders are dropped walking each set once" do
      flow = flow()
      store = flow.store
      ref = {{Module1, :fun, 0}, 1}
      module = ShapeSet.new([{:arg, {{Module1, :other, 0}, 1}, 0}], store)

      calls =
        Enum.reduce(1..30, ShapeSet.new([{:arg, ref, 0}], store), fn _index, set ->
          ShapeSet.new([{:dyn, module, :build, 2, [set, set]}], store)
        end)

      value =
        Enum.reduce(1..3, ShapeSet.new([{:fun, ref, calls}], store), fn _level, inner ->
          ShapeSet.new([{:tuple, [inner]}], store)
        end)

      apply_summary(value, [], flow)

      assert Store.memo_count(store, :without_args) in 1..100
    end

    @tag timeout: 10_000
    test "a set widened twice at one depth is widened once" do
      flow = flow()
      arg = ShapeSet.new([{:atom, :x}], flow.store)

      30
      |> shared_chain(flow)
      |> apply_summary([arg], flow)

      assert Store.memo_count(flow.store, :widen) == 4
    end
  end

  describe "broadcast_analysis/3" do
    setup do
      [graph: graph_of([Module11, Module13])]
    end

    test "a struct in the params of a broadcast is a dispatch type", %{graph: graph} do
      for {function, struct} <- [
            broadcast_except: Struct5,
            broadcast_in_closure: Struct3,
            broadcast_struct: Struct1,
            queue_broadcast: Struct4
          ] do
        analysis = broadcast_analysis(graph, {Module13, function, 1}, flow())

        assert struct in analysis.dispatch_types
      end
    end

    test "a struct built and dropped before a broadcast is not a dispatch type", %{graph: graph} do
      refute Struct2 in broadcast_analysis(graph, {Module13, :broadcast_label, 1}, flow()).dispatch_types
    end

    test "a component module in the params of a broadcast is a referenced component", %{
      graph: graph
    } do
      analysis = broadcast_analysis(graph, {Module13, :broadcast_component, 1}, flow())

      assert analysis.referenced_components == [Module11]
    end

    test "params from the function's own params, or no params, hold nothing", %{graph: graph} do
      built_in_types = CallGraph.protocol_dispatch_types([], module_info_plt_fixture())

      for caller <- [
            {Module13, :broadcast_from_param, 2},
            {Module13, :broadcast_without_params, 1}
          ] do
        assert broadcast_analysis(graph, caller, flow()) == %{
                 dispatch_types: built_in_types,
                 referenced_components: []
               }
      end
    end
  end

  describe "definite_map?/4" do
    test "map literal" do
      assert definite_map_of(Module14, :map_literal)
    end

    test "struct literal" do
      assert definite_map_of(Module14, :struct_literal)
    end

    test "param a map pattern matched" do
      assert definite_map_of(Module14, :matched)
    end

    test "value of a call returning a param a map pattern matched" do
      assert definite_map_of(Module14, :validated)
    end

    test "rescued exception" do
      assert definite_map_of(Module14, :rescued)
    end

    test "atom" do
      refute definite_map_of(Module14, :atom)
    end

    test "param" do
      refute definite_map_of(Module14, :param)
    end

    test "expression that never returns" do
      refute definite_map_of(Module14, :raises)
    end
  end

  describe "map_nested/2" do
    test "applies the function to each set nested in the shape" do
      assert map_nested({:tuple, [1, 2]}, &(&1 * 10)) == {:tuple, [10, 20]}
      assert map_nested({:call, 1, [2, 3]}, &(&1 * 10)) == {:call, 10, [20, 30]}
      assert map_nested({:dyn, 1, :build, 1, [2]}, &(&1 * 10)) == {:dyn, 10, :build, 1, [20]}

      assert map_nested({:struct, Struct1, %{field: 1}}, &(&1 * 10)) ==
               {:struct, Struct1, %{field: 10}}

      assert map_nested({:map, %{:a => 1, {:rest} => 2}}, &(&1 * 10)) ==
               {:map, %{:a => 10, {:rest} => 20}}
    end

    test "a shape with no nested sets is given back" do
      assert map_nested({:param, 1}, &(&1 * 10)) == {:param, 1}
      assert map_nested({:atom, :ok}, &(&1 * 10)) == {:atom, :ok}
    end
  end

  describe "nested_sets/1" do
    test "the sets nested in the shape" do
      assert nested_sets({:fun, {{Module1, :fun, 0}, 1}, 7}) == [7]
      assert nested_sets({:dot, 3, :name}) == [3]
      assert nested_sets({:dyn, 1, :build, 1, [2]}) == [1, 2]
    end

    test "a shape with no nested sets" do
      assert nested_sets({:arg, {{Module1, :fun, 0}, 1}, 0}) == []
      assert nested_sets(:prim) == []
    end
  end

  describe "server_callback_analysis/3" do
    setup do
      [graph: graph_of([Module10, Module11, Module12])]
    end

    test "a struct that reaches the state is a dispatch type", %{graph: graph} do
      assert Struct2 in server_callback_analysis(graph, Module10, flow()).dispatch_types
    end

    test "a struct sent in the params of a command's action is a dispatch type", %{graph: graph} do
      assert Struct4 in server_callback_analysis(graph, Module10, flow()).dispatch_types
    end

    test "a struct built and dropped on the server is not a dispatch type", %{graph: graph} do
      refute Struct1 in server_callback_analysis(graph, Module10, flow()).dispatch_types
    end

    test "a struct put in the session is a dispatch type: another handler can read it back", %{
      graph: graph
    } do
      assert Struct3 in server_callback_analysis(graph, Module10, flow()).dispatch_types
    end

    test "a component module that reaches the state is a referenced component", %{graph: graph} do
      assert server_callback_analysis(graph, Module10, flow()).server_referenced_components ==
               [Module11]
    end

    test "a templatable with the default callbacks hands nothing to the client", %{graph: graph} do
      assert server_callback_analysis(graph, Module11, flow()) == %{
               dispatch_types: CallGraph.protocol_dispatch_types([], module_info_plt_fixture()),
               server_referenced_components: []
             }
    end

    test "where the analysis can't follow the code, the rule before it applies from there", %{
      graph: graph
    } do
      assert Struct5 in server_callback_analysis(graph, Module12, flow()).dispatch_types
    end
  end

  describe "shapes/4" do
    test "a call whose value is larger than the cap is a bag of its leaves" do
      clause = clause(Module17, :calls_repeat)
      mfa = {Module17, :calls_repeat, 0}
      value = shapes_tree(clause.body, clause, mfa, flow())

      flow =
        start(PLT.start(), module_info_plt_fixture(), max_summary_size: graph_bytes(value) - 1)

      assert value == four_structs()

      assert summary_tree({Module17, :repeat, 1}, flow) ==
               tree_set([{:tuple, List.duplicate(@param_0, 4)}])

      assert shapes_tree(clause.body, clause, mfa, flow) ==
               tree_set([{:bag, tree_set([{:atom, nil}, @struct_1_named])}])
    end

    # The cap is exactly what twice/2's substitution copies into the value: its summary and the value it
    # is given. The function it is given is only called (see used_indexes/3), so its shape is not
    # counted, the summary is not flattened, and both calls are made: the value names every atom and no
    # anonymous function's argument. Counted as copied, the function would take the summary over the
    # cap, its calls would be dissolved unmade, and its argument would be left in the value.
    test "a function a param stands for, only called, is not counted as copied" do
      clause = clause(Module21, :calls_twice)
      mfa = {Module21, :calls_twice, 0}
      value = atom_tuples([:u, :v, :w, :x, :y, :z])
      cap = graph_bytes(value) + graph_bytes(summary_tree({Module21, :twice, 2}, flow()))
      atoms = for atom <- [:a, :b, :c, :d, :e, :f, :u, :v, :w, :x, :y, :z], do: {:atom, atom}
      flow = start(PLT.start(), module_info_plt_fixture(), max_summary_size: cap)

      assert shapes_tree(clause.body, clause, mfa, flow) == tree_set([{:bag, tree_set(atoms)}])
    end

    test "an argument larger than the cap is flattened before it is put in" do
      clause = clause(Module21, :calls_wrap)
      mfa = {Module21, :calls_wrap, 0}
      argument = atom_tuples([:a, :b, :c, :d, :e, :f])
      bag = tree_set([{:bag, tree_set(for atom <- [:a, :b, :c, :d, :e, :f], do: {:atom, atom})}])

      flow =
        start(PLT.start(), module_info_plt_fixture(), max_summary_size: graph_bytes(argument) - 1)

      assert shapes_tree(clause.body, clause, mfa, flow) ==
               tree_set([{:tuple, [tree_set([{:atom, :ok}]), bag]}])
    end

    # The call's value joins what each module's function gives; with the cap one byte under that value,
    # it becomes a bag of its leaves: the types of both modules' values, their structure dropped.
    test "a join of dynamic calls larger than the cap is a bag of its leaves" do
      clause = clause(Module21, :calls_dispatch)
      mfa = {Module21, :calls_dispatch, 1}
      value = shapes_tree(clause.body, clause, mfa, flow())
      leaves = tree_set([:prim, @struct_1_named, {:struct, Struct2, %{}}])

      flow =
        start(PLT.start(), module_info_plt_fixture(), max_summary_size: graph_bytes(value) - 1)

      assert shapes_tree(clause.body, clause, mfa, flow) == tree_set([{:bag, leaves}])
    end

    test "a call whose leaves are larger than the cap is the caller's top" do
      clause = clause(Module17, :calls_repeat)
      mfa = {Module17, :calls_repeat, 0}
      flow = start(PLT.start(), module_info_plt_fixture(), max_summary_size: 1)

      assert shapes_tree(clause.body, clause, mfa, flow) == top(mfa)
    end

    test "atom" do
      assert shapes_of(Module1, :atom) == tree_set([{:atom, :ok}])
    end

    test "bitstring" do
      assert shapes_of(Module1, :bitstring) == tree_set([:prim])
    end

    test "block gives its last expression" do
      assert shapes_of(Module1, :block) == tree_set([{:atom, :ok}])
    end

    test "cons operator" do
      assert shapes_of(Module1, :cons) ==
               tree_set([{:list, tree_set([:prim, {:atom, :a}])}])
    end

    test "integer" do
      assert shapes_of(Module1, :integer) == tree_set([:prim])
    end

    test "list" do
      assert shapes_of(Module1, :list) ==
               tree_set([{:list, tree_set([:prim, {:atom, :a}])}])
    end

    test "map" do
      assert shapes_of(Module1, :map) == tree_set([{:map, %{a: tree_set([:prim])}}])
    end

    test "match gives its right side" do
      assert shapes_of(Module1, :match) == tree_set([{:struct, Struct1, @defaults}])
    end

    test "module atom" do
      assert shapes_of(Module1, :module_atom) == tree_set([{:atom, Module1}])
    end

    test "nested" do
      list = {:list, tree_set([{:struct, Struct1, @defaults}])}

      assert shapes_of(Module1, :nested) ==
               tree_set([{:tuple, [tree_set([{:atom, :ok}]), tree_set([list])]}])
    end

    test "string" do
      assert shapes_of(Module1, :string) == tree_set([:prim])
    end

    test "struct" do
      assert shapes_of(Module1, :struct) == tree_set([{:struct, Struct1, @defaults}])
    end

    test "map with a __struct__ key is a struct" do
      assert shapes_of(Module1, :struct_map) ==
               tree_set([{:struct, Struct1, %{field: tree_set([{:atom, :x}])}}])
    end

    test "struct with fields" do
      assert shapes_of(Module1, :struct_with_fields) ==
               tree_set([{:struct, Struct1, %{field: tree_set([{:atom, :x}])}}])
    end

    test "tuple" do
      assert shapes_of(Module1, :tuple) ==
               tree_set([{:tuple, [tree_set([{:atom, :ok}]), tree_set([:prim])]}])
    end

    test "an expression it can't follow is the function's top" do
      expr = %IR.IgnoredExpression{type: :public_macro_definition}
      clause = %IR.FunctionClause{params: [], guards: [], body: %IR.Block{expressions: [expr]}}
      mfa = {Module1, :atom, 0}

      assert shapes_tree(expr, clause, mfa, flow()) == top(mfa)
    end

    test "variable bound by a match" do
      assert shapes_of(Module2, :bound) == tree_set([@struct_1])
    end

    test "case gives every clause's value" do
      assert shapes_of(Module2, :case_clauses) == tree_set([@struct_1, @struct_2])
    end

    test "case condition variable takes what a clause's pattern names" do
      assert shapes_of(Module2, :case_named) ==
               tree_set([{:param, 0}, @struct_1_named, {:atom, nil}])
    end

    test "variables of the same name in two case clauses are apart" do
      assert shapes_of(Module2, :case_same_name) ==
               tree_set([{:tuple, [@part_of_param_0]}, {:list, @part_of_param_0}])
    end

    test "comprehension into a list" do
      assert shapes_of(Module2, :comprehension) ==
               tree_set([{:list, tree_set([@struct_1])}])
    end

    test "comprehension into a map" do
      # Its keys are not known: the keys and the values are the rest.
      assert shapes_of(Module2, :comprehension_into_map) ==
               tree_set([{:map, rest_fields(tree_set([{:atom, :a}, @struct_1]))}])
    end

    test "comprehension with a reducer" do
      mfa = {Module2, :comprehension_reduce, 0}
      body = {:tuple, [tree_set([:prim]), top(mfa)]}

      assert shapes_of(Module2, :comprehension_reduce) ==
               tree_set([{:bag, tree_set([@struct_1, body])}])
    end

    test "cond gives every clause's value" do
      assert shapes_of(Module2, :cond_clauses) == tree_set([@struct_1, @struct_2])
    end

    test "variable taken from a list" do
      assert shapes_of(Module2, :from_list) == tree_set([@struct_1])
    end

    test "variable taken from a map holds what the map holds under the key" do
      assert shapes_of(Module2, :from_map) == tree_set([@struct_1])
    end

    test "variable taken from a struct's field" do
      assert shapes_of(Module2, :from_struct_field) == tree_set([@struct_2])
    end

    test "variable taken from a tuple" do
      assert shapes_of(Module2, :from_tuple) == tree_set([@struct_1])
    end

    test "variable taken from the tuples a pattern can match only" do
      assert shapes_of(Module2, :from_tuple_alternatives) == tree_set([@struct_1])
    end

    test "param" do
      assert shapes_of(Module2, :param) == @param_0
    end

    test "param matched against a struct pattern is a map, and takes what the pattern names" do
      assert shapes_of(Module2, :param_named) ==
               tree_set([{:as_map, @param_0}, @struct_1_named])
    end

    test "variable taken from a param is a part of the param" do
      assert shapes_of(Module2, :param_pattern) == @part_of_param_0
    end

    test "rebound variable" do
      assert shapes_of(Module2, :rebound) ==
               tree_set([{:tuple, [tree_set([:prim]), tree_set([@struct_1])]}])
    end

    test "try with catch" do
      mfa = {Module2, :try_catch, 0}

      assert shapes_of(Module2, :try_catch) == tree_set([{:reach, mfa}, {:atom, :ok}])
    end

    test "try with else gives the else clauses' value instead of the body's" do
      assert shapes_of(Module2, :try_else) ==
               tree_set([{:tuple, [tree_set([@struct_1])]}, {:atom, :rescued}])
    end

    test "try with rescue of a module" do
      fields = rest_fields(top({Module2, :try_rescue, 0}))

      assert shapes_of(Module2, :try_rescue) ==
               tree_set([{:atom, :ok}, {:struct, ArgumentError, fields}])
    end

    test "try with a bare rescue: the rescued exception is a struct holding anything" do
      mfa = {Module2, :try_rescue_bare, 0}

      assert shapes_of(Module2, :try_rescue_bare) ==
               tree_set([{:as_map, tree_set([{:reach, mfa}])}, {:atom, :ok}])
    end

    test "variable no binding in the clause knows is the function's top" do
      var = IR.for_code("value", %Context{})
      clause = %IR.FunctionClause{params: [], guards: [], body: %IR.Block{expressions: [var]}}
      mfa = {Module2, :param, 1}

      assert shapes_tree(var, clause, mfa, flow()) == top(mfa)
    end

    test "with and its else clauses" do
      assert shapes_of(Module2, :with_else) ==
               tree_set([{:tuple, [@part_of_param_0]}, {:list, @part_of_param_0}])
    end

    test "with clause expression variable takes what the clause's pattern names" do
      assert shapes_of(Module2, :with_named) == tree_set([{:param, 0}, @struct_1_named])
    end

    test "with without else gives an unmatched value too" do
      assert shapes_of(Module2, :with_no_else) ==
               tree_set([{:tuple, [@part_of_param_0]}, {:param, 0}])
    end
  end

  test "start/2" do
    ir_plt = PLT.start()
    module_info_plt = PLT.start()

    assert %{ir_plt: ^ir_plt, module_info_plt: ^module_info_plt, summaries: %PLT{} = summaries} =
             start(ir_plt, module_info_plt)

    assert PLT.size(summaries) == 0
  end

  test "stop/1" do
    %{summaries: %PLT{pid: pid}} = flow = flow()

    assert stop(flow) == :ok
    refute Process.alive?(pid)
  end

  describe "start/3" do
    test "caps summaries at 32 KiB by default" do
      assert flow().max_summary_size == 32_768
    end

    test "takes another cap" do
      flow = start(PLT.start(), module_info_plt_fixture(), max_summary_size: 100)

      assert flow.max_summary_size == 100
    end

    test "starts a PLT for the module checks" do
      assert %PLT{} = flow().module_atoms
    end

    test "starts a PLT for the rules' caches" do
      assert %PLT{} = flow().rule_cache
    end

    test "asks the built-in rules modules by default" do
      assert flow().rules == Rules.built_in()
    end

    test "keeps the rules modules given" do
      flow = start(PLT.start(), module_info_plt_fixture(), rules: [Rules1])

      assert flow.rules == [Rules1]
    end
  end

  describe "summary/2" do
    test "a function a rules module answers is not followed" do
      flow = start(PLT.start(), module_info_plt_fixture(), rules: [Rules1])

      assert summary_tree({Module25, :calls_ruled, 0}, flow) == tree_set([@struct_1_stored])
      assert summary_of(Module25, :calls_ruled, 0) == tree_set([:prim])
    end

    test "a rule shape is resolved once its arguments are known" do
      flow = start(PLT.start(), module_info_plt_fixture(), rules: [Rules1])

      assert summary_tree({Module25, :calls_structs_of, 0}, flow) == tree_set([@struct_1_named])
    end

    test "a rule shape waits while its arguments are not known" do
      flow = start(PLT.start(), module_info_plt_fixture(), rules: [Rules1])

      assert summary_tree({Module25, :structs_of, 1}, flow) ==
               tree_set([{:rule, Rules1, :structs, [@param_0]}])
    end

    test "a rule shape answers for what its arguments show and waits for the rest" do
      flow = start(PLT.start(), module_info_plt_fixture(), rules: [Rules1])
      rule = {:rule, Rules1, :structs, [tree_set([{:atom, Struct1}, {:param, 0}])]}

      assert summary_tree({Module25, :structs_of_mixed, 2}, flow) ==
               tree_set([@struct_1_named, rule])
    end

    test "a set nested too deep becomes a bag of its leaves, with the same types" do
      flow = flow()
      summary = summary({Module9, :deep, 0}, flow)
      leaves = tree_set([@struct_1_named, :prim])
      level_3 = tree_set([{:tuple, [tree_set([{:bag, leaves}])]}])
      level_2 = tree_set([{:tuple, [level_3]}])

      assert to_tree(summary, flow) == tree_set([{:tuple, [level_2]}])
      assert types(summary, flow).structs == MapSet.new([Struct1])
    end

    test "a set with too many alternatives becomes a bag of them" do
      # The bag holds the 33 atoms, which a stored answer turns into one primitive.
      assert summary_of(Module9, :wide, 0) ==
               tree_set([{:list, tree_set([{:bag, tree_set([:prim])}])}])
    end

    test "call on each module of a list param is made once the list is known" do
      call = {:dyn, tree_set([{:contents, @param_0}]), :build, 0, []}

      assert summary_of(Module8, :call_each, 1) == tree_set([{:list, tree_set([call])}])

      assert summary_of(Module8, :calls_modules, 0) ==
               tree_set([{:list, tree_set([@struct_1_stored])}])
    end

    test "Elixir functions that build on the structural models" do
      for {function, structs} <- [
            enum_map: [Struct1],
            enum_reduce: [Struct1, Struct2],
            keyword_get: [Struct1],
            map_get: [Struct1],
            map_put: [Struct1]
          ] do
        flow = flow()
        summary = summary({Module8, function, 0}, flow)

        assert types(summary, flow).structs == MapSet.new(structs)
      end
    end

    test "a value put in the session stays in the server struct" do
      flow = flow()
      summary = summary({Module8, :session_put, 1}, flow)

      assert Struct1 in types(summary, flow).structs
    end

    test "Kernel.struct/2 on a module" do
      flow = flow()
      summary = summary({Module6, :kernel_struct, 0}, flow)

      assert Struct1 in types(summary, flow).structs
      refute PLT.member?(flow.summaries, {ArgumentError, :exception, 1})
    end

    test "Kernel.struct/2 on a module passed as an argument" do
      flow = flow()
      summary = summary({Module6, :calls_build_struct, 0}, flow)

      assert Struct1 in types(summary, flow).structs
    end

    test "model of a function returning a primitive" do
      assert summary_of(Module7, :count, 1) == tree_set([:prim])
      assert summary_of(Module7, :inspects, 0) == tree_set([:prim])
      assert summary_of(Module7, :to_string_of, 1) == tree_set([:prim])
    end

    test "binary with values interpolated" do
      assert summary_of(Module7, :interpolates, 1) == tree_set([:prim])
    end

    test "a part of a primitive is a primitive" do
      assert summary_of(Module7, :first_part, 1) == tree_set([:prim])
    end

    test "a primitive in a tuple doesn't keep a pattern from matching the tuple" do
      assert summary_of(Module7, :pairs_with_parts, 1) == tree_set([@struct_1_stored])
    end

    test "model of a function that never returns" do
      assert summary_of(Module7, :raises, 0) == tree_set()
    end

    test "a branch that raises gives nothing" do
      assert summary_of(Module7, :raises_or_struct, 1) == tree_set([@struct_1_stored])
    end

    test "apply/2 with the argument list written out" do
      assert summary_of(Module6, :apply_fun, 0) == tree_set([@struct_1_stored])
    end

    test "apply/3 with a function name known only at runtime gives everything it is given" do
      # A bag holds leaves (see widening): the empty argument list holds none.
      args = tree_set([{:atom, Module3}, {:param, 0}])

      assert summary_of(Module6, :apply_variable_name, 1) == tree_set([{:bag, args}])
    end

    test "apply/3 with the function name and the argument list written out" do
      fields = %{field: tree_set([@struct_2_stored])}

      assert summary_of(Module6, :apply_written, 0) == tree_set([{:struct, Struct1, fields}])
    end

    test "call on a module in a variable" do
      assert summary_of(Module6, :on_literal_module, 0) == tree_set([@struct_1_stored])
    end

    test "call on a param is made once the param is known" do
      assert summary_of(Module6, :on_param, 1) == tree_set([{:dyn, @param_0, :build, 0, []}])
    end

    test "call on a module passed as an argument" do
      assert summary_of(Module6, :calls_on_param, 0) == tree_set([@struct_1_stored])
    end

    test "dot on a struct gives what the field holds" do
      assert summary_of(Module6, :field, 0) == tree_set([@struct_2_stored])
    end

    test "dot on a param is made once the param is known" do
      assert summary_of(Module6, :field_of_param, 1) == tree_set([{:dot, @param_0, :field}])
    end

    test "dot on a struct passed as an argument gives the field, not the struct" do
      assert summary_of(Module6, :calls_field_of_param, 0) == tree_set([@struct_2_stored])
    end

    test "a field of a struct literal holds only that field's value" do
      assert summary_of(Module24, :literal_field, 0) == tree_set([:prim])
    end

    test "a key of a map literal holds only that key's value" do
      assert summary_of(Module24, :map_key, 0) == tree_set([:prim])
    end

    test "a map literal's atom keys are its fields, not values" do
      fields = %{item: tree_set([@struct_1_stored]), title: tree_set([:prim])}

      assert summary_of(Module24, :map_literal, 0) == tree_set([{:map, fields}])
    end

    test "a field read of maps merged holds the field, not the other map's fields" do
      assert summary_of(Module24, :either, 1) == tree_set([:prim])
    end

    test "a field read holds what the pairs with keys other than atoms hold" do
      assert summary_of(Module24, :mixed_keys, 0) == tree_set([:prim, @struct_1_stored])
    end

    test "a field of a struct built from a value keeps the types in the value" do
      flow = flow()
      summary = summary({Module24, :built_field, 1}, flow)

      pair = {:tuple, [tree_set([{:atom, :name}]), tree_set([@struct_1])]}
      list = {:list, tree_set([pair])}
      arg = ShapeSet.from_tree([list], flow.store)

      applied = apply_summary(summary, [arg], flow)

      assert Struct1 in types(applied, flow).structs
    end

    test "__struct__ dot on a struct gives its module" do
      assert summary_of(Module6, :struct_module, 0) == tree_set([{:atom, Struct1}])
    end

    test "dot on a module passed as an argument calls its zero-arity function" do
      assert summary_of(Module6, :dot_on_param, 1) ==
               tree_set([{:dot, @param_0, :__struct__}])

      assert summary_of(Module6, :calls_dot_on_param, 0) == tree_set([@struct_1_stored])
    end

    test "protocol function gives everything it is given" do
      module_info_plt =
        PLT.put(PLT.start(), Enumerable, %{protocol?: true, protocol_functions: [count: 1]})

      flow = start(PLT.start(), module_info_plt)

      assert summary_tree({Enumerable, :count, 1}, flow) == tree_set([{:bag, @param_0}])
    end

    test "anonymous function" do
      summary = summary_of(Module5, :closure, 0)

      assert [{:fun, {{Module5, :closure, 0}, _hash}, returned}] = summary

      assert returned == tree_set([@struct_1_stored])
    end

    test "an anonymous function is the same on every pass" do
      assert summary_of(Module5, :closure, 0) == summary_of(Module5, :closure, 0)
    end

    test "call of an anonymous function" do
      assert summary_of(Module5, :calls_closure, 0) == tree_set([@struct_1_stored])
    end

    test "call of an anonymous function with an argument" do
      assert summary_of(Module5, :closure_arg, 0) ==
               tree_set([
                 {:tuple, [tree_set([{:atom, :ok}]), tree_set([@struct_1_stored])]}
               ])
    end

    test "anonymous function with two clauses" do
      assert summary_of(Module5, :closure_clauses, 1) ==
               tree_set([@struct_1_stored, @struct_2_stored])
    end

    test "anonymous function reading a variable of its function" do
      assert summary_of(Module5, :closure_free_variable, 0) == tree_set([@struct_1_stored])
    end

    test "anonymous function returning its function's param" do
      summary = summary_of(Module5, :closure_of_param, 1)

      assert [{:fun, _ref, returned}] = summary
      assert returned == @param_0
    end

    test "one of two functions given itself is called a bounded number of times" do
      flow = flow()
      summary = summary({Module16, :encode, 2}, flow)

      assert {:param, 0} in to_tree(summary, flow)
      assert types(summary, flow).structs == MapSet.new([Struct1])
    end

    test "call of an anonymous function a call returned" do
      assert summary_of(Module5, :calls_closure_of_param, 0) == tree_set([@struct_1_stored])
    end

    test "anonymous function's param shadowing its function's" do
      assert summary_of(Module5, :closure_shadowing_param, 1) ==
               tree_set([
                 {:tuple, [@param_0, tree_set([{:tuple, [tree_set([@struct_1_stored])]}])]}
               ])
    end

    test "capture of a local function" do
      assert summary_of(Module5, :capture_local, 0) ==
               tree_set([
                 {:tuple, [tree_set([{:atom, :ok}]), tree_set([@struct_1_stored])]}
               ])
    end

    test "capture of a remote function" do
      assert summary_of(Module5, :capture_remote, 0) == tree_set([@struct_1_stored])
    end

    test "call of a param is made once the param is known" do
      assert summary_of(Module5, :higher_order, 1) ==
               tree_set([{:call, @param_0, [tree_set([@struct_1_stored])]}])
    end

    test "anonymous function given to a function that calls it" do
      assert summary_of(Module5, :calls_higher_order, 0) ==
               tree_set([
                 {:tuple, [tree_set([@struct_1_stored]), tree_set([@struct_2_stored])]}
               ])
    end

    test "recursive function returning an anonymous function settles" do
      summary = summary_of(Module5, :recursive_closure, 1)

      assert [{:fun, _ref, returned}] = summary
      assert returned == tree_set([@struct_1_stored])
    end

    test "function building a struct" do
      assert summary_of(Module3, :build, 0) == tree_set([@struct_1_stored])
    end

    test "function building a struct from its param" do
      fields = %{field: @param_0}

      assert summary_of(Module3, :build_from, 1) == tree_set([{:struct, Struct1, fields}])
    end

    test "call of a local function" do
      assert summary_of(Module3, :calls_build, 0) == tree_set([@struct_1_stored])
    end

    test "call puts its arguments in the callee's summary" do
      fields = %{field: tree_set([@struct_2_stored])}

      assert summary_of(Module3, :calls_build_from, 0) ==
               tree_set([{:struct, Struct1, fields}])
    end

    test "call of a modelled Erlang function" do
      assert summary_of(Module3, :calls_erlang, 1) == @param_0
    end

    test "call of a remote function" do
      assert summary_of(Module3, :calls_remote, 0) == tree_set([@struct_1_stored])
    end

    test "call whose value a pattern takes apart" do
      assert summary_of(Module3, :calls_wrap, 0) == tree_set([@struct_1_stored])
    end

    test "an argument the callee's value doesn't hold is not followed" do
      flow = flow()

      assert summary_tree({Module3, :calls_ignores, 0}, flow) == tree_set([:prim])
      refute PLT.member?(flow.summaries, {Module3, :build, 0})
    end

    test "a call whose value is dropped is not followed" do
      flow = flow()

      assert summary_tree({Module3, :drops_result, 0}, flow) == tree_set([:prim])
      refute PLT.member?(flow.summaries, {Module3, :build, 0})
    end

    test "Erlang function without a model gives everything it is given" do
      params = tree_set([{:param, 0}, {:param, 1}, {:param, 2}])

      assert summary_of(:lists, :zipwith, 3) == tree_set([{:bag, params}])
    end

    test "function its module doesn't define" do
      assert summary_of(Module3, :no_such_function, 0) == tree_set([{:bag, tree_set()}])
    end

    test "is kept in the analysis, with the summaries of the functions it calls" do
      flow = flow()
      summary = summary({Module3, :calls_build, 0}, flow)

      assert PLT.get(flow.summaries, {Module3, :calls_build, 0}) == {:ok, summary}

      assert {:ok, build} = PLT.get(flow.summaries, {Module3, :build, 0})
      assert to_tree(build, flow) == tree_set([@struct_1_stored])
    end

    test "param" do
      assert summary_of(Module3, :identity, 1) == @param_0
    end

    test "recursive function" do
      assert summary_of(Module3, :recursive, 1) == tree_set([@struct_1_stored])
    end

    test "recursive function whose answer is found on a later pass" do
      assert summary_of(Module4, :direct, 1) == tree_set([@struct_1_stored])
    end

    test "recursive function passing its param on" do
      assert summary_of(Module4, :join, 2) == tree_set([{:param, 1}, :prim])
    end

    test "a caller of a recursive function gets its final answer, and both are kept" do
      flow = flow()

      assert summary_tree({Module4, :calls_direct, 0}, flow) == tree_set([@struct_1_stored])

      assert {:ok, direct} = PLT.get(flow.summaries, {Module4, :direct, 1})
      assert to_tree(direct, flow) == tree_set([@struct_1_stored])

      assert PLT.member?(flow.summaries, {Module4, :calls_direct, 0})
    end

    test "mutually recursive functions" do
      assert summary_of(Module4, :mutual_a, 1) == tree_set([:prim, @struct_2_stored])
    end

    test "a loop inside a loop is read again until neither changes" do
      flow = flow()
      summary = summary({Module15, :outer, 2}, flow)

      assert types(summary, flow).structs == MapSet.new([Struct1])
    end

    test "a loop of functions is evaluated a bounded number of times" do
      flow = flow()
      count = count_code_summaries(fn -> summary({Module15, :ring_a, 1}, flow) end)

      # 4 functions, each evaluated once per sweep of the work list while the answers change.
      assert count <= 20
    end

    test "every function a run solves is kept" do
      flow = flow()
      summary({Module4, :mutual_a, 1}, flow)

      assert PLT.member?(flow.summaries, {Module4, :mutual_a, 1})
      assert PLT.member?(flow.summaries, {Module4, :mutual_b, 1})
    end

    test "a recursive function whose answer keeps growing settles" do
      flow = flow()
      summary = summary({Module4, :growing, 1}, flow)

      # Three levels of tuples, then a bag of the leaves of what is deeper.
      leaves = {:bag, tree_set([:prim, @struct_1_named])}
      level_3 = {:tuple, [tree_set([leaves])]}
      level_2 = {:tuple, [tree_set([level_3, @struct_1_stored])]}
      level_1 = {:tuple, [tree_set([level_2, @struct_1_stored])]}

      assert to_tree(summary, flow) == tree_set([level_1, @struct_1_stored])
      assert types(summary, flow) == types_fixture([], [], [Struct1])
    end

    test "a chain of calls deeper than 64 functions is followed to its end" do
      assert summary_of(Module18, :chain_0, 1) == tree_set([@struct_1_stored])
    end

    test "calls on a module passed in, nested by recursion, settle once flattened" do
      flow = flow()
      summary = summary({Module18, :wrapped, 2}, flow)

      assert [{:bag, leaves}] = to_tree(summary, flow)
      assert {:param, 0} in leaves
      assert types(summary, flow) == types_fixture([], [], [])
    end

    test "an answer that keeps changing ends as the function's top" do
      assert summary_of(Module18, :stepped, 2) == top({Module18, :stepped, 2})
    end

    test "a function evaluated many times, its answer not changing, keeps its answer" do
      flow = flow()
      summary({Module18, :pairs, 1}, flow)

      # steady is evaluated again on every change of a pair, more than 16 times; its answer holds.
      assert {:ok, steady} = PLT.get(flow.summaries, {Module18, :steady, 1})
      assert to_tree(steady, flow) == tree_set([@struct_1_stored])
    end

    test "a call of a param nested too deep dissolves into the function and its arguments" do
      leaves = tree_set([{:bag, tree_set([:prim, {:param, 0}])}])
      level_3 = tree_set([{:tuple, [leaves]}])
      level_2 = tree_set([{:tuple, [level_3]}])

      assert summary_of(Module9, :deep_call, 1) == tree_set([{:tuple, [level_2]}])
    end

    test "a chain of steps into a param becomes the param or anything inside it" do
      assert summary_of(Module19, :nested, 1) == tree_set([{:param, 0}, {:part, @param_0}])
    end

    test "a single step into a param stays" do
      assert summary_of(Module19, :single, 1) == tree_set([{:contents, @param_0}])
    end

    test "a field of a param stays" do
      assert summary_of(Module19, :field, 1) == tree_set([{:dot, @param_0, :title}])
    end

    test "a field of a value matched as a map or struct is the value or anything inside it" do
      assert summary_of(Module20, :read_field, 1) ==
               tree_set([{:param, 0}, {:part, @param_0}])
    end

    test "reads of several fields of a value matched as a map are one shape" do
      assert summary_of(Module20, :read_fields, 1) ==
               tree_set([{:list, tree_set([{:param, 0}, {:part, @param_0}])}])
    end

    test "the __struct__ field of a value matched as a struct stays a field read" do
      assert summary_of(Module20, :read_struct, 1) ==
               tree_set([
                 {:atom, Struct1},
                 {:dot, tree_set([{:as_map, @param_0}]), :__struct__}
               ])
    end

    test "a stored answer turns an atom that is not a module into a primitive" do
      assert summary_of(Module19, :bare, 0) == tree_set([:prim])
    end

    test "a tuple's first element keeps its atoms" do
      assert summary_of(Module19, :tagged, 0) ==
               tree_set([{:tuple, [tree_set([{:atom, :ok}]), tree_set([:prim])]}])
    end

    test "a module atom stays" do
      assert summary_of(Module19, :module, 0) == tree_set([{:atom, Struct1}])
      assert summary_of(Module19, :erlang_module, 0) == tree_set([{:atom, :lists}])
    end

    test "whether an atom is a module is kept in the analysis" do
      flow = flow()
      summary({Module19, :bare, 0}, flow)

      assert PLT.get(flow.module_atoms, :done) == {:ok, false}
    end

    test "an updated struct keeps its struct type" do
      for function <- [:deleted, :merged, :put, :updated] do
        flow = flow()
        summary = summary({Module20, function, 0}, flow)

        assert types(summary, flow).structs == MapSet.new([Struct1]),
               "#{function}: #{inspect(summary)}"
      end
    end

    # nested/0 builds its value with no call, so no call's bound applies; the summary's bound does.
    test "a summary built without a call, larger than the cap, is a bag of its leaves" do
      mfa = {Module21, :nested, 0}
      struct = tree_set([@struct_1_stored])
      structs = tree_set([{:tuple, List.duplicate(struct, 4)}])
      value = tree_set([{:tuple, List.duplicate(structs, 4)}])

      flow =
        start(PLT.start(), module_info_plt_fixture(), max_summary_size: graph_bytes(value) - 1)

      assert summary_tree(mfa, flow) == tree_set([{:bag, tree_set([:prim, @struct_1_named])}])
    end

    # Measured as a tree, the value is 1,000 copies of the struct, far over the cap; the store holds
    # the struct's set once, so the value fits and keeps its structure.
    test "a value holding one set a thousand times fits the cap" do
      struct = tree_set([@struct_1_stored])

      assert summary_tree({Module21, :calls_thousand, 0}, flow()) ==
               tree_set([{:tuple, List.duplicate(struct, 1_000)}])
    end

    test "a summary larger than the cap is a bag of its leaves" do
      mfa = {Module17, :repeat, 1}
      value = summary_tree(mfa, flow())

      flow =
        start(PLT.start(), module_info_plt_fixture(), max_summary_size: graph_bytes(value) - 1)

      assert value == tree_set([{:tuple, List.duplicate(@param_0, 4)}])
      assert summary_tree(mfa, flow) == tree_set([{:bag, @param_0}])
    end

    test "a summary whose leaves are larger than the cap is the function's top" do
      flow = start(PLT.start(), module_info_plt_fixture(), max_summary_size: 1)

      assert summary_tree({Module3, :recursive, 1}, flow) == top({Module3, :recursive, 1})
    end

    test "function with two clauses" do
      assert summary_of(Module3, :two_clauses, 1) ==
               tree_set([@struct_1_stored, @struct_2_stored])
    end

    test "function returning its param in a tuple" do
      assert summary_of(Module3, :wrap, 1) ==
               tree_set([{:tuple, [tree_set([{:atom, :ok}]), @param_0]}])
    end
  end

  describe "to_tree/2" do
    test "writes the nested sets out, sorted by content" do
      flow = flow()
      inner = ShapeSet.new([{:atom, :b}, {:atom, :a}], flow.store)
      set = ShapeSet.new([{:tuple, [inner, inner]}, :prim], flow.store)

      assert to_tree(set, flow) ==
               [:prim, {:tuple, [[{:atom, :a}, {:atom, :b}], [{:atom, :a}, {:atom, :b}]]}]
    end
  end

  describe "top/1" do
    test "function with params" do
      mfa = {Module2, :param, 1}

      assert top(mfa) == tree_set([{:reach, mfa}, {:param, 0}])
    end

    test "function with no params" do
      mfa = {Module1, :atom, 0}

      assert top(mfa) == tree_set([{:reach, mfa}])
    end
  end

  describe "types/2" do
    test "a rule shape holds the types its arguments show" do
      rule = {:rule, Rules1, :structs, [tree_set([{:atom, Struct1}, {:param, 0}])]}

      assert types_of([rule]) == types_fixture([Struct1], [], [Struct1])
    end

    test "struct" do
      assert types_of([@struct_1]) == types_fixture([], [], [Struct1])
    end

    test "a map's atom keys, a module among them" do
      assert types_of([{:map, %{Module1 => tree_set([:prim])}}]) ==
               types_fixture([Module1], [], [])
    end

    test "struct in a struct's fields" do
      struct = {:struct, Struct1, %{field: tree_set([@struct_2])}}

      assert types_of([struct]) == types_fixture([], [], [Struct1, Struct2])
    end

    test "module atom of a struct module" do
      assert types_of([{:atom, Struct1}]) == types_fixture([Struct1], [], [Struct1])
    end

    test "module atom of a module that defines no struct" do
      assert types_of([{:atom, Module1}]) == types_fixture([Module1], [], [])
    end

    test "atom that is no module the module info PLT knows" do
      assert types_of([{:atom, :ok}]) == types_fixture([], [], [])
    end

    test "reach" do
      mfa = {Module3, :build, 0}

      assert types_of([{:reach, mfa}]) == types_fixture([], [mfa], [])
    end

    test "param, anonymous function's argument and primitive hold nothing" do
      assert types_of([{:param, 0}, {:arg, make_ref(), 0}, :prim]) == types_fixture([], [], [])
    end

    test "tuple, list, map and bag hold what is inside them" do
      shapes = [
        {:tuple, [tree_set([@struct_1])]},
        {:list, tree_set([{:atom, Module1}])},
        {:map, %{a: tree_set([@struct_2])}},
        {:bag, tree_set([{:reach, {Module3, :build, 0}}])}
      ]

      assert types_of(shapes) ==
               types_fixture([Module1], [{Module3, :build, 0}], [Struct1, Struct2])
    end

    test "anonymous function holds what it returns" do
      assert types_of([{:fun, make_ref(), tree_set([@struct_1])}]) ==
               types_fixture([], [], [Struct1])
    end

    test "call not made holds its function and its arguments" do
      shapes = [{:call, tree_set([@struct_1]), [tree_set([@struct_2])]}]

      assert types_of(shapes) == types_fixture([], [], [Struct1, Struct2])
    end

    test "dynamic call not made holds its module and its arguments" do
      shapes = [{:dyn, tree_set([{:atom, Module1}]), :build, 1, [tree_set([@struct_2])]}]

      assert types_of(shapes) == types_fixture([Module1], [], [Struct2])
    end
  end

  # The tree of the given tree nested under three one-element tuples.
  defp under_three_tuples(tree) do
    Enum.reduce(1..3, tree, fn _level, inner -> tree_set([{:tuple, [inner]}]) end)
  end
end
