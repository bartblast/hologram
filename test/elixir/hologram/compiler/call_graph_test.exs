# credo:disable-for-this-file Credo.Check.Design.DuplicatedCode
defmodule Hologram.Compiler.CallGraphTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.CallGraph

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Component
  alias Hologram.Realtime
  alias Hologram.Reflection

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module10
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module11
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module12
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module13
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module14
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module15
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module16
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module17
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module18
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module19
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module2
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module20
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module21
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module22
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module24
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module25
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module27
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module28
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module3
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module30
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module31
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module32
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module33
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module35
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module36
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module37
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module38
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module39
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module4
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module40
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module41
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module42
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module43
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module44
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module5
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module6
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module7
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module8
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module9
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Protocol1
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Struct1

  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module10, as: DataFlowPage
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module11, as: DataFlowComponent
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1, as: DroppedStruct
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2, as: StateStruct

  alias String.Chars.Hologram.Test.Fixtures.Compiler.CallGraph.Module12, as: StringCharsModule12

  @erlang_js_dir Path.join([Reflection.root_dir(), "assets", "js", "erlang"])

  @tmp_dir Reflection.tmp_dir()

  defp app_protocol_dispatch_types_with_analysis(graph) do
    module_info_plt = module_info_plt_fixture()

    app_protocol_dispatch_types(
      graph,
      Reflection.list_pages(),
      broadcast_caller_analysis(graph, module_info_plt),
      module_info_plt
    )
  end

  # The Erlang functions each ported module calls, taken from the "Deps" comment
  # every port carries under its End marker. The comment is what a port author
  # writes down, so it is the statement the edge table has to answer to.
  # Runs the function in a process of its own, traced with this one as the tracer (a process cannot
  # be its own tracer), checks that CallGraph.get_graph/1 was not called there, and returns its
  # result. A walk that copied the graph out would copy it in that process, not in the agent.
  defp call_without_copying_graph(fun) do
    test_pid = self()

    walker =
      spawn_link(fn ->
        receive do
          :run -> send(test_pid, {:result, fun.()})
        end

        # Kept alive until the tracing is turned off, which a dead process would refuse.
        receive do
          :stop -> :ok
        end
      end)

    :erlang.trace_pattern({CallGraph, :get_graph, 1}, true, [:local])
    :erlang.trace(walker, true, [:call])

    try do
      send(walker, :run)

      # A walk of the whole graph takes longer than the default wait.
      assert_receive {:result, result}, 30_000

      # Trace messages arrive asynchronously, so this waits rather than reading the mailbox as it is.
      refute_receive {:trace, ^walker, :call, {CallGraph, :get_graph, _args}}, 200

      result
    after
      :erlang.trace(walker, false, [:call])
      :erlang.trace_pattern({CallGraph, :get_graph, 1}, false, [:local])
      send(walker, :stop)
    end
  end

  # A data flow context on the fixture app's module info PLT.
  defp data_flow_fixture, do: DataFlow.start(PLT.start(), module_info_plt_fixture())

  # The graph of a page of the data flow fixtures: its init/3 builds DroppedStruct and drops it, and
  # puts StateStruct in the state.
  defp data_flow_page_graph do
    [module_info_plt: module_info_plt_fixture()]
    |> start()
    |> build(IR.for_module(DataFlowPage))
    |> build(IR.for_module(DataFlowComponent))
    |> get_graph()
  end

  defp list_declared_erlang_deps do
    [@erlang_js_dir, "*.mjs"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.flat_map(fn file_path ->
      basename = Path.basename(file_path, ".mjs")

      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      module = String.to_atom(basename)

      file_path
      |> File.read!()
      |> String.split("\n")
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(&parse_declared_erlang_deps(&1, module))
    end)
  end

  defp list_page_mfas_with_analysis(call_graph, page_module) do
    call_graph
    |> CallGraph.get_graph()
    |> list_page_mfas(page_module, PLT.start(), CallGraph.module_info_plt(call_graph))
  end

  defp list_page_mfas_with_gate(call_graph, page_module, gate) do
    call_graph
    |> CallGraph.get_graph()
    |> list_page_mfas(page_module, PLT.start(), CallGraph.module_info_plt(call_graph), gate: gate)
  end

  # The module info PLT of the fixture app, started once per test run in setup_all (whose
  # process lives for the whole module, so the linked PLT does too) and kept here for the
  # tests that take no context: the call graph functions answer module questions from it
  # instead of loading modules.
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

  defp narrow_diff_fixture(added_modules, edited_modules, removed_modules) do
    %{
      added_modules: added_modules,
      edited_modules: edited_modules,
      removed_modules: removed_modules
    }
  end

  defp page_entry_mfas(page_module, layout_module) do
    [
      {page_module, :__layout_module__, 0},
      {page_module, :__layout_props__, 0},
      {page_module, :__params__, 0},
      {page_module, :__route__, 0},
      {page_module, :action, 3},
      {page_module, :template, 0},
      {layout_module, :__props__, 0},
      {layout_module, :action, 3},
      {layout_module, :template, 0}
    ]
  end

  # An End marker paired with the Deps comment under it, yielding one
  # {source, target} per Erlang dependency. Dependencies on Elixir modules are
  # named without a leading colon and are carried by a different table.
  defp parse_declared_erlang_deps([end_line, deps_line], module) do
    with [_match, fun, arity] <- Regex.run(~r{//\s*End\s+(\S+)/(\d+)\s*$}, end_line),
         [_match, deps] <- Regex.run(~r{//\s*Deps:\s*\[(.*)\]\s*$}, deps_line) do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      source = {module, String.to_atom(fun), String.to_integer(arity)}

      deps
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, ":"))
      |> Enum.map(&{source, parse_erlang_mfa(&1)})
    else
      _no_match -> []
    end
  end

  # A name the comment holds may have no edge naming it yet, which is what the
  # test reports - so the atoms are made rather than looked up, or a stale
  # declaration would raise here instead of showing up in the diff.
  # credo:disable-for-lines:5 Credo.Check.Warning.UnsafeToAtom
  defp parse_erlang_mfa(dep) do
    [_match, module, fun, arity] = Regex.run(~r{^:(\w+)\.(\S+)/(\d+)$}, dep)

    {String.to_atom(module), String.to_atom(fun), String.to_integer(arity)}
  end

  # Builds the given modules into the call graph, from reach_ir/2.
  defp reach_build(call_graph, modules, built_modules) do
    Enum.each(built_modules, &build(call_graph, reach_ir(modules, &1)))
  end

  defp reach_callee_ir({module, function, arity}) do
    %IR.RemoteFunctionCall{
      module: %IR.AtomType{value: module},
      function: function,
      args: List.duplicate(%IR.IntegerType{value: 0}, arity)
    }
  end

  defp reach_callee_ir(module), do: %IR.AtomType{value: module}

  # A call graph built the way the compile task builds one into an empty build dir: the roots (the
  # pages and the broadcast callers) first, then the walk. Returns the call graph and the modules
  # the walk built.
  defp reach_cold(modules, roots) do
    call_graph = start(module_info_plt: reach_module_info_plt(modules))
    reach_build(call_graph, modules, roots)

    built_modules =
      build_reach(
        call_graph,
        narrow_diff_fixture(roots, [], []),
        &reach_build(call_graph, modules, &1)
      )

    {call_graph, built_modules}
  end

  # The graph every module of the given ones builds, which the walk's graph must answer every
  # listing the same as.
  defp reach_full(modules) do
    call_graph = start(module_info_plt: reach_module_info_plt(modules))
    reach_build(call_graph, modules, Map.keys(modules))
    call_graph
  end

  # The IR of a module of reach_modules/0: a function definition per given function, whose body
  # calls the given functions and names the given modules.
  defp reach_ir(modules, module) do
    {_info, functions} = Map.fetch!(modules, module)

    function_defs =
      Enum.map(functions, fn {name, arity, callees} ->
        %IR.FunctionDefinition{
          name: name,
          arity: arity,
          visibility: :public,
          clause: %IR.FunctionClause{
            params: [],
            guards: [],
            body: %IR.Block{expressions: Enum.map(callees, &reach_callee_ir/1)}
          }
        }
      end)

    %IR.ModuleDefinition{
      module: %IR.AtomType{value: module},
      body: %IR.Block{expressions: function_defs}
    }
  end

  defp reach_module_info_plt(modules) do
    Enum.reduce(modules, PLT.start(), fn {module, {info, _functions}}, plt ->
      PLT.put(plt, module, info)
    end)
  end

  # A small app for the walk: a page whose template calls a protocol function and creates a TypeA
  # struct, and whose init/3 names a component and a plain module; the protocol's implementations for
  # TypeA (reached) and TypeB (not reached); a broadcast caller with one broadcasting function and one
  # that doesn't broadcast; and modules only the unwalked code reaches.
  defp reach_modules do
    %{
      ReachTest.Caller =>
        {%{broadcast_caller?: true},
         [
           {:notify, 0, [{Realtime, :broadcast_action, 2}, {ReachTest.CallerHelper, :fun, 0}]},
           {:other, 0, [{ReachTest.Unreached, :fun, 0}]}
         ]},
      ReachTest.CallerHelper => {%{}, [{:fun, 0, []}]},
      ReachTest.ImplHelper => {%{}, [{:fun, 0, []}]},
      ReachTest.Late => {%{}, [{:fun, 0, []}]},
      ReachTest.Layout => {%{component?: true}, [{:template, 0, []}]},
      ReachTest.Named =>
        {%{component?: true}, [{:template, 0, [{ReachTest.NamedHelper, :fun, 0}]}]},
      ReachTest.NamedHelper => {%{}, [{:fun, 0, []}]},
      ReachTest.Page =>
        {%{page?: true, layout_module: ReachTest.Layout},
         [
           {:init, 3, [{ReachTest.Server, :load, 0}]},
           {:template, 0, [{ReachTest.Proto, :fun, 1}, {ReachTest.TypeA, :__struct__, 0}]}
         ]},
      ReachTest.Plain => {%{}, [{:fun, 0, [{ReachTest.Unreached, :fun, 0}]}]},
      ReachTest.Proto => {%{protocol?: true, protocol_functions: [fun: 1]}, [{:fun, 1, []}]},
      ReachTest.Proto.TypeA =>
        {%{
           protocol_implementation?: true,
           implementation_for: ReachTest.TypeA,
           implemented_protocol: ReachTest.Proto
         }, [{:__impl__, 1, []}, {:fun, 1, [{ReachTest.ImplHelper, :fun, 0}]}]},
      ReachTest.Proto.TypeB =>
        {%{
           protocol_implementation?: true,
           implementation_for: ReachTest.TypeB,
           implemented_protocol: ReachTest.Proto
         }, [{:__impl__, 1, []}, {:fun, 1, [{ReachTest.Unreached, :fun, 0}]}]},
      ReachTest.Server => {%{}, [{:load, 0, [ReachTest.Named, ReachTest.Plain]}]},
      ReachTest.TypeA => {%{struct?: true}, [{:__struct__, 0, []}]},
      ReachTest.TypeB => {%{struct?: true}, [{:__struct__, 0, []}]},
      ReachTest.Unreached => {%{}, [{:fun, 0, []}]}
    }
  end

  defp reach_state(%{pid: pid}), do: Agent.get(pid, & &1.reach)

  setup_all do
    module_info_plt = module_info_plt_fixture()
    ir_plt = Compiler.build_ir_plt()
    full_call_graph = Compiler.build_call_graph(ir_plt, module_info_plt)
    runtime_mfas = CallGraph.list_runtime_mfas(full_call_graph, Reflection.list_pages())

    [
      full_call_graph: full_call_graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      runtime_mfas: runtime_mfas
    ]
  end

  setup %{module_info_plt: module_info_plt} do
    [empty_call_graph: start(module_info_plt: module_info_plt)]
  end

  test "add_edge/3", %{empty_call_graph: call_graph} do
    result = add_edge(call_graph, :vertex_1, :vertex_2)
    assert result == call_graph

    graph = get_graph(call_graph)
    assert Digraph.edges(graph) == [{:vertex_1, :vertex_2}]
  end

  test "add_edges/2", %{empty_call_graph: call_graph} do
    edges = [{:a, :b}, {:c, :d}]
    result = add_edges(call_graph, edges)

    assert result == call_graph

    graph = get_graph(call_graph)
    assert Digraph.sorted_edges(graph) == edges
  end

  describe "add_non_discoverable_edges/1" do
    test "adds @erlang_mfa_edges to the call graph", %{empty_call_graph: call_graph} do
      add_non_discoverable_edges(call_graph)

      assert has_edge?(call_graph, {:binary, :match, 2}, {:binary, :match, 3})
    end

    test "adds @dynamic_dispatch_edges to the call graph", %{empty_call_graph: call_graph} do
      add_non_discoverable_edges(call_graph)

      assert has_edge?(call_graph, {Date, :new, 4}, {Calendar.ISO, :valid_date?, 3})
    end
  end

  test "add_vertex/2", %{empty_call_graph: call_graph} do
    result = add_vertex(call_graph, :vertex_3)
    assert result == call_graph

    graph = get_graph(call_graph)
    assert Digraph.vertices(graph) == [:vertex_3]
  end

  describe "app_protocol_dispatch_types/4" do
    test "includes types reachable from page client code" do
      graph = Digraph.add_edge(Digraph.new(), {Module2, :template, 0}, Struct1)

      assert Struct1 in app_protocol_dispatch_types_with_analysis(graph)
    end

    test "includes types created in server-executed code of pages" do
      graph = Digraph.add_edge(Digraph.new(), {Module2, :init, 3}, Struct1)

      assert Struct1 in app_protocol_dispatch_types_with_analysis(graph)
    end

    test "includes types created in server-executed code of components used by pages" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :template, 0}, {Module4, :template, 0})
        |> Digraph.add_edge({Module4, :init, 3}, Struct1)

      assert Struct1 in app_protocol_dispatch_types_with_analysis(graph)
    end

    test "includes types reachable from broadcast callers" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> Digraph.add_edge({Module13, :my_fun, 0}, Struct1)

      assert Struct1 in app_protocol_dispatch_types_with_analysis(graph)
    end

    test "includes types created in server-executed code of broadcast-referenced components" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> Digraph.add_edge({Module13, :my_fun, 0}, Module4)
        |> Digraph.add_edge({Module4, :command, 3}, Struct1)

      assert Struct1 in app_protocol_dispatch_types_with_analysis(graph)
    end

    test "returns only built-in types for a graph without app type references" do
      graph = Digraph.add_edge(Digraph.new(), {Module13, :my_fun, 0}, {Module5, :my_fun, 0})

      assert app_protocol_dispatch_types_with_analysis(graph) ==
               protocol_dispatch_types([], module_info_plt_fixture())
    end
  end

  describe "broadcast_caller_analysis/2" do
    test "includes struct types reachable from broadcast_action callers" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Realtime, :broadcast_action, 2})
        |> Digraph.add_edge({Module5, :my_fun, 0}, Struct1)
        |> Digraph.add_edge({Module6, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> Digraph.add_edge({Module6, :my_fun, 0}, {Module7, :my_fun, 0})
        |> Digraph.add_edge({Module7, :my_fun, 0}, Module12)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert Struct1 in result.dispatch_types
      assert Module12 in result.dispatch_types
    end

    test "includes struct types reachable from broadcast_action_except callers" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Realtime, :broadcast_action_except, 3})
        |> Digraph.add_edge({Module5, :my_fun, 0}, Struct1)
        |> Digraph.add_edge({Module6, :my_fun, 0}, {Realtime, :broadcast_action_except, 4})
        |> Digraph.add_edge({Module6, :my_fun, 0}, Module12)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert Struct1 in result.dispatch_types
      assert Module12 in result.dispatch_types
    end

    test "collects component modules referenced in broadcast caller code" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Realtime, :broadcast_action, 2})
        |> Digraph.add_edge({Module5, :my_fun, 0}, Module15)
        |> Digraph.add_edge({Module6, :my_fun, 0}, {Realtime, :broadcast_action_except, 3})
        |> Digraph.add_edge({Module6, :my_fun, 0}, Module4)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert Enum.sort(result.referenced_components) == [Module15, Module4]
    end

    test "collects component modules referenced in code that queues a broadcast" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :command, 3}, {Component, :put_broadcast, 3})
        |> Digraph.add_edge({Module5, :command, 3}, Module15)
        |> Digraph.add_edge({Module6, :command, 3}, {Component, :put_broadcast, 4})
        |> Digraph.add_edge({Module6, :command, 3}, Module4)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert Enum.sort(result.referenced_components) == [Module15, Module4]
    end

    test "collects component modules referenced in code that queues a broadcast with exclusions" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :command, 3}, {Component, :put_broadcast_except, 4})
        |> Digraph.add_edge({Module5, :command, 3}, Module15)
        |> Digraph.add_edge({Module6, :command, 3}, {Component, :put_broadcast_except, 5})
        |> Digraph.add_edge({Module6, :command, 3}, Module4)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert Enum.sort(result.referenced_components) == [Module15, Module4]
    end

    test "doesn't collect non-component modules referenced in broadcast caller code" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Realtime, :broadcast_action, 2})
        |> Digraph.add_edge({Module5, :my_fun, 0}, Module12)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert result.referenced_components == []
    end

    test "doesn't collect page modules referenced in broadcast caller code" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Realtime, :broadcast_action, 2})
        |> Digraph.add_edge({Module5, :my_fun, 0}, Module14)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert result.referenced_components == []
    end

    test "returns only built-in types and no components when there are no broadcast callers" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, Struct1)
        |> Digraph.add_edge({Module5, :my_fun, 0}, Module15)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      assert result.dispatch_types == protocol_dispatch_types([], module_info_plt_fixture())
      assert result.referenced_components == []
    end

    test "doesn't traverse through protocol function vertices" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Protocol1, :my_fun, 1})
        |> Digraph.add_edge({Protocol1, :my_fun, 1}, Struct1)
        |> Digraph.add_edge({Protocol1, :my_fun, 1}, Module15)

      result = broadcast_caller_analysis(graph, module_info_plt_fixture())

      refute Struct1 in result.dispatch_types
      refute Module15 in result.referenced_components
    end

    test "knows a protocol function from the PLT function list without calling the protocol" do
      protocol = Hologram.Test.Fixtures.Compiler.CallGraph.NoSuchProtocol

      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> Digraph.add_edge({Module5, :my_fun, 0}, {protocol, :my_fun, 1})
        |> Digraph.add_edge({protocol, :my_fun, 1}, Struct1)

      without_entry = broadcast_caller_analysis(graph, module_info_plt_fixture())
      assert Struct1 in without_entry.dispatch_types

      module_info_plt = PLT.clone(module_info_plt_fixture())

      PLT.put(module_info_plt, protocol, %{
        protocol?: true,
        protocol_functions: [my_fun: 1]
      })

      with_entry = broadcast_caller_analysis(graph, module_info_plt)
      refute Struct1 in with_entry.dispatch_types
    end
  end

  describe "build/3" do
    test "adds no module edges for a module absent from the module infos" do
      call_graph = start()
      ir = IR.for_module(Module14)

      build(call_graph, ir)

      refute has_edge?(call_graph, Module14, {Module14, :__route__, 0})
      refute has_edge?(call_graph, Module14, {Module14, :__params__, 0})
    end

    test "adds the module edges for a module present in the module infos", %{
      empty_call_graph: call_graph
    } do
      ir = IR.for_module(Module14)

      build(call_graph, ir)

      assert has_edge?(call_graph, Module14, {Module14, :__route__, 0})
      assert has_edge?(call_graph, Module14, {Module14, :__params__, 0})
    end

    test "atom type IR, which is not an alias", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: :abc}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type IR, which as an alias of a non-existing module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Aaa.Bbb}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Aaa.Bbb, :vertex_1]
      assert edges(call_graph) == [{:vertex_1, Aaa.Bbb}]
    end

    test "atom type IR, which is an alias of an existing non-templatable module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, :vertex_1]
      assert edges(call_graph) == [{:vertex_1, Module1}]
    end

    test "atom type IR, which is an alias of a page module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module2}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module2, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module2}]
    end

    test "atom type IR, which is an alias of a layout module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module3}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module3, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module3}]
    end

    test "atom type IR, which is an alias of a component module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module4}
      result = build(call_graph, ir, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module4, :vertex_1]
      assert sorted_edges(call_graph) == [{:vertex_1, Module4}]
    end

    test "atom type IR in __impl__/1 of a protocol implementation module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, {String.Chars.URI, :__impl__, 1})

      assert result == call_graph
      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type IR in __protocol__/1 of a protocol module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, {String.Chars, :__protocol__, 1})

      assert result == call_graph
      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type IR in impl_for/1 of a protocol module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, {String.Chars, :impl_for, 1})

      assert result == call_graph
      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type IR in impl_for!/1 of a protocol module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, {String.Chars, :impl_for!, 1})

      assert result == call_graph
      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type IR in struct_impl_for/1 of a protocol module", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      result = build(call_graph, ir, {String.Chars, :struct_impl_for, 1})

      assert result == call_graph
      assert vertices(call_graph) == []
      assert edges(call_graph) == []
    end

    test "atom type IR in __impl__/1 of a module that is not a protocol implementation", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      from_vertex = {Module5, :__impl__, 1}
      result = build(call_graph, ir, from_vertex)

      assert result == call_graph
      assert sorted_vertices(call_graph) == [Module1, from_vertex]
      assert sorted_edges(call_graph) == [{from_vertex, Module1}]
    end

    test "atom type IR in a protocol function that is not generated dispatch metadata", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.AtomType{value: Module1}
      from_vertex = {String.Chars, :to_string, 1}
      result = build(call_graph, ir, from_vertex)

      assert result == call_graph
      assert sorted_vertices(call_graph) == [Module1, from_vertex]
      assert sorted_edges(call_graph) == [{from_vertex, Module1}]
    end

    test "atom type IR in impl_for/1 of a non-protocol module", %{empty_call_graph: call_graph} do
      ir = %IR.AtomType{value: Module1}
      from_vertex = {Module5, :impl_for, 1}
      result = build(call_graph, ir, from_vertex)

      assert result == call_graph
      assert sorted_vertices(call_graph) == [Module1, from_vertex]
      assert sorted_edges(call_graph) == [{from_vertex, Module1}]
    end

    test "function definition IR, with outbound vertices", %{empty_call_graph: call_graph} do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
          guards: [%IR.AtomType{value: Module5}],
          body: %IR.Block{
            expressions: [
              %IR.AtomType{value: Module6},
              %IR.AtomType{value: Module7}
            ]
          }
        }
      }

      result = build(call_graph, ir, Module1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               Module6,
               Module7,
               {Module1, :my_fun, 2}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun, 2}, Module5},
               {{Module1, :my_fun, 2}, Module6},
               {{Module1, :my_fun, 2}, Module7}
             ]
    end

    test "function definition IR, without outbound vertices", %{empty_call_graph: call_graph} do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 2,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :x}, %IR.Variable{name: :y}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.AtomType{value: :ok}
            ]
          }
        }
      }

      result = build(call_graph, ir, Module1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [{Module1, :my_fun, 2}]
      assert sorted_edges(call_graph) == []
    end

    test "function definition IR, with a dynamic call", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.FunctionDefinition{
        name: :my_fun,
        arity: 1,
        visibility: :public,
        clause: %IR.FunctionClause{
          params: [%IR.Variable{name: :module, version: 0}],
          guards: [],
          body: %IR.Block{
            expressions: [
              %IR.RemoteFunctionCall{
                module: %IR.Variable{name: :module, version: 0},
                function: :__changeset__,
                args: []
              }
            ]
          }
        }
      }

      build(call_graph, ir, Module1)

      site = {:dynamic_call, {Module1, :my_fun, 1}, :__changeset__, 0, {:param, 0}}

      assert sorted_vertices(call_graph) == [{Module1, :my_fun, 1}, site]
      assert sorted_edges(call_graph) == [{{Module1, :my_fun, 1}, site}]
    end

    test "list", %{empty_call_graph: call_graph} do
      list = [%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}]
      result = build(call_graph, list, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5}
             ]
    end

    test "local function call IR", %{empty_call_graph: call_graph} do
      ir = %IR.LocalFunctionCall{
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module5},
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7}
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module5,
               Module6,
               Module7,
               {Module1, :my_fun_1, 4},
               {Module1, :my_fun_2, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module5},
               {{Module1, :my_fun_1, 4}, Module6},
               {{Module1, :my_fun_1, 4}, Module7},
               {{Module1, :my_fun_1, 4}, {Module1, :my_fun_2, 3}}
             ]
    end

    test "map", %{empty_call_graph: call_graph} do
      map = %{
        %IR.AtomType{value: Module1} => %IR.AtomType{value: Module5},
        %IR.AtomType{value: Module6} => %IR.AtomType{value: Module7}
      }

      result = build(call_graph, map, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, Module6, Module7, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5},
               {:vertex_1, Module6},
               {:vertex_1, Module7}
             ]
    end

    test "module definition IR, regular module", %{empty_call_graph: call_graph} do
      ir = %IR.ModuleDefinition{
        module: %IR.AtomType{value: Module1},
        body: %IR.Block{
          expressions: [
            %IR.AtomType{value: Module5},
            %IR.AtomType{value: Module6}
          ]
        }
      }

      result = build(call_graph, ir)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module1,
               Module5,
               Module6
             ]

      assert sorted_edges(call_graph) == [
               {Module1, Module5},
               {Module1, Module6}
             ]
    end

    test "module definition IR, page module adds page-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_2_ir = IR.for_module(Module2)
      result = build(call_graph, module_2_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module2, :__params__, 0})
      assert has_vertex?(call_graph, {Module2, :__route__, 0})

      assert has_edge?(call_graph, Module2, {Module2, :__params__, 0})
      assert has_edge?(call_graph, Module2, {Module2, :__route__, 0})
    end

    test "module definition IR, component module adds component-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_4_ir = IR.for_module(Module4)
      result = build(call_graph, module_4_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module4, :__props__, 0})
      assert has_vertex?(call_graph, {Module4, :action, 3})
      assert has_vertex?(call_graph, {Module4, :init, 2})
      assert has_vertex?(call_graph, {Module4, :template, 0})

      assert has_edge?(call_graph, Module4, {Module4, :__props__, 0})
      assert has_edge?(call_graph, Module4, {Module4, :action, 3})
      assert has_edge?(call_graph, Module4, {Module4, :init, 2})
      assert has_edge?(call_graph, Module4, {Module4, :template, 0})
    end

    test "module definition IR, struct module adds struct-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_25_ir = IR.for_module(Module25)
      result = build(call_graph, module_25_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module25, :__struct__, 0})
      assert has_vertex?(call_graph, {Module25, :__struct__, 1})

      assert has_edge?(call_graph, Module25, {Module25, :__struct__, 0})
      assert has_edge?(call_graph, Module25, {Module25, :__struct__, 1})
    end

    test "module definition IR, Ecto schema module adds Ecto schema-specific edges", %{
      empty_call_graph: call_graph
    } do
      module_21_ir = IR.for_module(Module21)
      result = build(call_graph, module_21_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {Module21, :__changeset__, 0})
      assert has_vertex?(call_graph, {Module21, :__schema__, 1})
      assert has_vertex?(call_graph, {Module21, :__schema__, 2})

      assert has_edge?(call_graph, Module21, {Module21, :__changeset__, 0})
      assert has_edge?(call_graph, Module21, {Module21, :__schema__, 1})
      assert has_edge?(call_graph, Module21, {Module21, :__schema__, 2})
    end

    test "module definition IR, exception module adds exception-specific edges", %{
      empty_call_graph: call_graph
    } do
      argument_error_ir = IR.for_module(ArgumentError)
      result = build(call_graph, argument_error_ir)

      assert result == call_graph

      assert has_vertex?(call_graph, {ArgumentError, :message, 1})
      assert has_edge?(call_graph, ArgumentError, {ArgumentError, :message, 1})
    end

    test "module definition IR, protocol module adds protocol-specific edges", %{
      empty_call_graph: call_graph
    } do
      string_chars_ir = IR.for_module(String.Chars)
      result = build(call_graph, string_chars_ir)

      assert result == call_graph

      from_vertex = {String.Chars, :to_string, 1}

      assert has_edge?(call_graph, from_vertex, {String.Chars.Atom, :__impl__, 1})
      assert has_edge?(call_graph, from_vertex, {String.Chars.Atom, :to_string, 1})

      assert has_edge?(
               call_graph,
               from_vertex,
               {StringCharsModule12, :__impl__, 1}
             )

      assert has_edge?(
               call_graph,
               from_vertex,
               {StringCharsModule12, :to_string, 1}
             )
    end

    test "module definition IR, protocol module takes its function list from the PLT" do
      {:ok, info} = PLT.get(module_info_plt_fixture(), String.Chars)

      module_info_plt = PLT.clone(module_info_plt_fixture())

      PLT.put(module_info_plt, String.Chars, %{
        info
        | protocol_functions: [fake_fun: 7]
      })

      call_graph = start(module_info_plt: module_info_plt)
      build(call_graph, IR.for_module(String.Chars))

      assert has_edge?(
               call_graph,
               {String.Chars, :fake_fun, 7},
               {String.Chars.Atom, :__impl__, 1}
             )

      refute has_edge?(
               call_graph,
               {String.Chars, :to_string, 1},
               {String.Chars.Atom, :__impl__, 1}
             )
    end

    test "module definition IR, protocol module takes its implementations from the PLT" do
      impl = Hologram.Test.Fixtures.Compiler.CallGraph.NoSuchImpl
      module_info_plt = PLT.clone(module_info_plt_fixture())

      PLT.put(module_info_plt, impl, %{
        protocol_implementation?: true,
        implementation_for: Integer,
        implemented_protocol: String.Chars
      })

      call_graph = start(module_info_plt: module_info_plt)
      build(call_graph, IR.for_module(String.Chars))

      assert has_edge?(call_graph, {String.Chars, :to_string, 1}, {impl, :__impl__, 1})
      assert has_edge?(call_graph, {String.Chars, :to_string, 1}, {impl, :to_string, 1})
    end

    test "module definition IR, protocol module skips an implementation the PLT does not hold" do
      module_info_plt = PLT.clone(module_info_plt_fixture())
      PLT.delete(module_info_plt, StringCharsModule12)

      call_graph = start(module_info_plt: module_info_plt)
      build(call_graph, IR.for_module(String.Chars))

      refute has_edge?(
               call_graph,
               {String.Chars, :to_string, 1},
               {StringCharsModule12, :__impl__, 1}
             )

      assert has_edge?(
               call_graph,
               {String.Chars, :to_string, 1},
               {String.Chars.Atom, :__impl__, 1}
             )
    end

    test "remote function call IR, module field as an atom", %{empty_call_graph: call_graph} do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Module5},
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7},
          %IR.AtomType{value: Module8}
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               Module7,
               Module8,
               {Module1, :my_fun_1, 4},
               {Module5, :my_fun_2, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module6},
               {{Module1, :my_fun_1, 4}, Module7},
               {{Module1, :my_fun_1, 4}, Module8},
               {{Module1, :my_fun_1, 4}, {Module5, :my_fun_2, 3}}
             ]
    end

    test "remote function call IR, module field is a variable", %{empty_call_graph: call_graph} do
      ir = %IR.RemoteFunctionCall{
        module: %IR.Variable{name: :my_var},
        function: :my_fun_2,
        args: [
          %IR.AtomType{value: Module6},
          %IR.AtomType{value: Module7},
          %IR.AtomType{value: Module8}
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module6,
               Module7,
               Module8,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module6},
               {{Module1, :my_fun_1, 4}, Module7},
               {{Module1, :my_fun_1, 4}, Module8}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
    test "remote function call using Kernel.apply/3, module and function fields are both atoms",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.AtomType{value: DateTime},
          %IR.AtomType{value: :utc_now},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {DateTime, :utc_now, 1},
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO},
               {{Module1, :my_fun_1, 4}, {DateTime, :utc_now, 1}}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
    test "remote function call using Kernel.apply/3, module field is an atom, function field is not an atom",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.AtomType{value: DateTime},
          %IR.Variable{name: :my_fun},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               DateTime,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO},
               {{Module1, :my_fun_1, 4}, DateTime}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
    test "remote function call using Kernel.apply/3, module field is not an atom, function field is an atom",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.Variable{name: :module},
          %IR.AtomType{value: :utc_now},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO}
             ]
    end

    # :erlang.apply/3 is not added to the call graph because the encoder
    # translates it to Interpreter.callNamedFunction() instead of Erlang["apply/3"]().
    test "remote function call using Kernel.apply/3, neither module nor function field is an atom",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :apply,
        args: [
          %IR.Variable{name: :module},
          %IR.Variable{name: :my_fun},
          %IR.ListType{
            data: [%IR.AtomType{value: Calendar.ISO}]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Calendar.ISO,
               {Module1, :my_fun_1, 4}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Calendar.ISO}
             ]
    end

    test "remote function call using :erlang.error/3, error_info with module key", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :error,
        args: [
          %IR.AtomType{value: :badarg},
          %IR.ListType{data: [%IR.AtomType{value: :a}]},
          %IR.ListType{
            data: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error_info},
                  %IR.MapType{
                    data: [{%IR.AtomType{value: :module}, %IR.AtomType{value: Module2}}]
                  }
                ]
              }
            ]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module2,
               {Module1, :my_fun_1, 4},
               {Module2, :format_error, 2},
               {:erlang, :error, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module2},
               {{Module1, :my_fun_1, 4}, {Module2, :format_error, 2}},
               {{Module1, :my_fun_1, 4}, {:erlang, :error, 3}}
             ]
    end

    test "remote function call using :erlang.error/3, error_info with module and function keys",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :error,
        args: [
          %IR.AtomType{value: :badarg},
          %IR.ListType{data: [%IR.AtomType{value: :a}]},
          %IR.ListType{
            data: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error_info},
                  %IR.MapType{
                    data: [
                      {%IR.AtomType{value: :module}, %IR.AtomType{value: Module2}},
                      {%IR.AtomType{value: :function}, %IR.AtomType{value: :my_format_error}}
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               Module2,
               {Module1, :my_fun_1, 4},
               {Module2, :my_format_error, 2},
               {:erlang, :error, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, Module2},
               {{Module1, :my_fun_1, 4}, {Module2, :my_format_error, 2}},
               {{Module1, :my_fun_1, 4}, {:erlang, :error, 3}}
             ]
    end

    test "remote function call using :erlang.error/3, error_info without module key defaults to the enclosing module",
         %{
           empty_call_graph: call_graph
         } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :error,
        args: [
          %IR.AtomType{value: :badarg},
          %IR.ListType{data: [%IR.AtomType{value: :a}]},
          %IR.ListType{
            data: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error_info},
                  %IR.MapType{data: []}
                ]
              }
            ]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :format_error, 2},
               {Module1, :my_fun_1, 4},
               {:erlang, :error, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, {Module1, :format_error, 2}},
               {{Module1, :my_fun_1, 4}, {:erlang, :error, 3}}
             ]
    end

    test "remote function call using :erlang.error/3, error_info with a dynamic module value", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :error,
        args: [
          %IR.AtomType{value: :badarg},
          %IR.ListType{data: [%IR.AtomType{value: :a}]},
          %IR.ListType{
            data: [
              %IR.TupleType{
                data: [
                  %IR.AtomType{value: :error_info},
                  %IR.MapType{
                    data: [{%IR.AtomType{value: :module}, %IR.Variable{name: :module}}]
                  }
                ]
              }
            ]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun_1, 4},
               {:erlang, :error, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, {:erlang, :error, 3}}
             ]
    end

    test "remote function call using :erlang.error/3, options without error_info", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :error,
        args: [
          %IR.AtomType{value: :badarg},
          %IR.ListType{data: [%IR.AtomType{value: :a}]},
          %IR.ListType{
            data: [
              %IR.TupleType{
                data: [%IR.AtomType{value: :other_option}, %IR.AtomType{value: :abc}]
              }
            ]
          }
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun_1, 4},
               {:erlang, :error, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, {:erlang, :error, 3}}
             ]
    end

    test "remote function call using :erlang.error/3, dynamic options", %{
      empty_call_graph: call_graph
    } do
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: :erlang},
        function: :error,
        args: [
          %IR.AtomType{value: :badarg},
          %IR.ListType{data: [%IR.AtomType{value: :a}]},
          %IR.Variable{name: :options}
        ]
      }

      result = build(call_graph, ir, {Module1, :my_fun_1, 4})

      assert result == call_graph

      assert sorted_vertices(call_graph) == [
               {Module1, :my_fun_1, 4},
               {:erlang, :error, 3}
             ]

      assert sorted_edges(call_graph) == [
               {{Module1, :my_fun_1, 4}, {:erlang, :error, 3}}
             ]
    end

    test "tuple", %{empty_call_graph: call_graph} do
      tuple = {%IR.AtomType{value: Module1}, %IR.AtomType{value: Module5}}
      result = build(call_graph, tuple, :vertex_1)

      assert result == call_graph

      assert sorted_vertices(call_graph) == [Module1, Module5, :vertex_1]

      assert sorted_edges(call_graph) == [
               {:vertex_1, Module1},
               {:vertex_1, Module5}
             ]
    end
  end

  test "build_for_module/3", %{empty_call_graph: call_graph} do
    ir = %IR.ModuleDefinition{
      module: %IR.AtomType{value: Module11},
      body: %IR.Block{
        expressions: [
          %IR.AtomType{value: Module5},
          %IR.AtomType{value: Module6}
        ]
      }
    }

    ir_plt = PLT.start(items: [{Module11, ir}])

    assert build_for_module(call_graph, ir_plt, Module11) == call_graph

    assert sorted_vertices(call_graph) == [
             Module11,
             Module5,
             Module6,
             {Module11, :__params__, 0},
             {Module11, :__route__, 0}
           ]

    assert sorted_edges(call_graph) == [
             {Module11, Module5},
             {Module11, Module6},
             {Module11, {Module11, :__params__, 0}},
             {Module11, {Module11, :__route__, 0}}
           ]
  end

  describe "build_reach/3" do
    test "the walk's graph lists every fixture page and the runtime as the full graph does", %{
      full_call_graph: full_call_graph,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      runtime_mfas: full_runtime_mfas
    } do
      pages = Reflection.list_pages()
      broadcast_callers = PLT.keys(module_info_plt, %{broadcast_caller?: true})
      roots = Enum.uniq(pages ++ broadcast_callers)

      call_graph = start(module_info_plt: module_info_plt)
      Enum.each(roots, &build_for_module(call_graph, ir_plt, &1))
      add_non_discoverable_edges(call_graph)

      build_reach(call_graph, narrow_diff_fixture(roots, [], []), fn modules ->
        Enum.each(modules, &build_for_module(call_graph, ir_plt, &1))
      end)

      assert list_runtime_mfas(call_graph, pages) == full_runtime_mfas

      graph = get_graph(call_graph)
      full_graph = get_graph(full_call_graph)

      for page <- pages do
        assert list_page_mfas(graph, page, PLT.start(), module_info_plt) ==
                 list_page_mfas(full_graph, page, PLT.start(), module_info_plt)
      end

      reached_modules = modules(call_graph)
      all_modules = modules(full_call_graph)

      assert MapSet.size(reached_modules) < MapSet.size(all_modules)
    end

    test "the walk's graph lists the page and the runtime as the full graph does" do
      modules = reach_modules()
      {call_graph, _built_modules} = reach_cold(modules, [ReachTest.Page, ReachTest.Caller])
      full_call_graph = reach_full(modules)
      module_info_plt = call_graph.module_info_plt

      assert list_page_mfas(get_graph(call_graph), ReachTest.Page, PLT.start(), module_info_plt) ==
               list_page_mfas(
                 get_graph(full_call_graph),
                 ReachTest.Page,
                 PLT.start(),
                 module_info_plt
               )

      assert list_runtime_mfas(call_graph, [ReachTest.Page]) ==
               list_runtime_mfas(full_call_graph, [ReachTest.Page])
    end

    test "builds what the pages, their server callbacks and the broadcast callers reach" do
      {call_graph, built_modules} =
        reach_cold(reach_modules(), [ReachTest.Page, ReachTest.Caller])

      assert Enum.sort(built_modules) ==
               Enum.sort([
                 ReachTest.CallerHelper,
                 ReachTest.ImplHelper,
                 ReachTest.Layout,
                 ReachTest.Named,
                 ReachTest.NamedHelper,
                 ReachTest.Proto,
                 ReachTest.Proto.TypeA,
                 ReachTest.Server,
                 ReachTest.TypeA
               ])

      assert modules(call_graph) ==
               MapSet.new([ReachTest.Caller, ReachTest.Page | built_modules])
    end

    test "doesn't build an implementation whose type is not reached" do
      {call_graph, _built_modules} =
        reach_cold(reach_modules(), [ReachTest.Page, ReachTest.Caller])

      refute ReachTest.Proto.TypeB in modules(call_graph)
    end

    test "doesn't build a plain module named only as a value" do
      {call_graph, _built_modules} =
        reach_cold(reach_modules(), [ReachTest.Page, ReachTest.Caller])

      refute ReachTest.Plain in modules(call_graph)
      refute ReachTest.Unreached in modules(call_graph)
    end

    test "builds nothing on a walk with an empty diff" do
      modules = reach_modules()
      {call_graph, _built_modules} = reach_cold(modules, [ReachTest.Page, ReachTest.Caller])
      reach = reach_state(call_graph)

      diff = narrow_diff_fixture([], [], [])

      assert build_reach(call_graph, diff, &reach_build(call_graph, modules, &1)) == []
      assert reach_state(call_graph) == reach
    end

    test "an edited module is walked again from its reached functions" do
      modules = reach_modules()
      {call_graph, _built_modules} = reach_cold(modules, [ReachTest.Page, ReachTest.Caller])

      edited_modules =
        Map.put(
          modules,
          ReachTest.Server,
          {%{}, [{:load, 0, [ReachTest.Named, ReachTest.Plain, {ReachTest.Late, :fun, 0}]}]}
        )

      ir_plt = PLT.put(PLT.start(), ReachTest.Server, reach_ir(edited_modules, ReachTest.Server))
      diff = narrow_diff_fixture([], [ReachTest.Server], [])
      patch(call_graph, ir_plt, diff)

      assert build_reach(call_graph, diff, &reach_build(call_graph, edited_modules, &1)) ==
               [ReachTest.Late]

      {cold_call_graph, _built_modules} =
        reach_cold(edited_modules, [ReachTest.Page, ReachTest.Caller])

      cold_modules = modules(cold_call_graph)
      warm_modules = modules(call_graph)

      assert MapSet.subset?(cold_modules, warm_modules)

      assert MapSet.subset?(
               reach_state(cold_call_graph).reached_vertices,
               reach_state(call_graph).reached_vertices
             )
    end

    test "an added page is walked from its entries" do
      modules =
        Map.put(
          reach_modules(),
          ReachTest.Page2,
          {%{page?: true, layout_module: ReachTest.Layout},
           [{:template, 0, [{ReachTest.Late, :fun, 0}]}]}
        )

      {call_graph, _built_modules} = reach_cold(modules, [ReachTest.Page, ReachTest.Caller])

      PLT.put(call_graph.module_info_plt, ReachTest.Page2, elem(modules[ReachTest.Page2], 0))
      ir_plt = PLT.put(PLT.start(), ReachTest.Page2, reach_ir(modules, ReachTest.Page2))
      diff = narrow_diff_fixture([ReachTest.Page2], [], [])
      patch(call_graph, ir_plt, diff)

      assert build_reach(call_graph, diff, &reach_build(call_graph, modules, &1)) ==
               [ReachTest.Late]
    end

    test "an added implementation of a reached type is walked from its protocol's reached functions" do
      modules = reach_modules()
      {impl_info, _functions} = modules[ReachTest.Proto.TypeA]
      modules_before = Map.delete(modules, ReachTest.Proto.TypeA)

      {call_graph, built_modules} =
        reach_cold(modules_before, [ReachTest.Page, ReachTest.Caller])

      refute ReachTest.ImplHelper in built_modules

      PLT.put(call_graph.module_info_plt, ReachTest.Proto.TypeA, impl_info)

      ir_plt =
        PLT.put(PLT.start(), ReachTest.Proto.TypeA, reach_ir(modules, ReachTest.Proto.TypeA))

      diff = narrow_diff_fixture([ReachTest.Proto.TypeA], [], [])
      patch(call_graph, ir_plt, diff)

      assert build_reach(call_graph, diff, &reach_build(call_graph, modules, &1)) ==
               [ReachTest.ImplHelper]
    end

    test "a removed module's reached functions are forgotten" do
      modules = reach_modules()
      {call_graph, _built_modules} = reach_cold(modules, [ReachTest.Page, ReachTest.Caller])

      assert {ReachTest.NamedHelper, :fun, 0} in reach_state(call_graph).reached_vertices

      diff = narrow_diff_fixture([], [], [ReachTest.NamedHelper])
      patch(call_graph, PLT.start(), diff)

      assert build_reach(call_graph, diff, &reach_build(call_graph, modules, &1)) == []
      refute {ReachTest.NamedHelper, :fun, 0} in reach_state(call_graph).reached_vertices
    end

    test "the reach survives a dump and a load" do
      modules = reach_modules()
      {call_graph, _built_modules} = reach_cold(modules, [ReachTest.Page, ReachTest.Caller])

      dump_dir = Path.join([@tmp_dir, "tests", "compiler", "call_graph", "build_reach_3"])
      clean_dir(dump_dir)
      dump_path = Path.join(dump_dir, Reflection.call_graph_dump_file_name())
      dump(call_graph, dump_path)

      loaded_call_graph = start(module_info_plt: call_graph.module_info_plt)
      assert load(loaded_call_graph, dump_path) == :ok
      assert reach_state(loaded_call_graph) == reach_state(call_graph)

      diff = narrow_diff_fixture([], [], [])

      assert build_reach(loaded_call_graph, diff, &reach_build(loaded_call_graph, modules, &1)) ==
               []
    end
  end

  test "clone/1", %{full_call_graph: call_graph} do
    call_graph = %{call_graph | module_info_plt: PLT.start()}

    assert %CallGraph{} = call_graph_clone = clone(call_graph)
    assert call_graph_clone.module_info_plt == call_graph.module_info_plt

    refute call_graph_clone == call_graph
    assert get_graph(call_graph_clone) == get_graph(call_graph)
    assert modules(call_graph_clone) == modules(call_graph)
    assert Module9 in modules(call_graph_clone)
  end

  describe "dump/2" do
    setup do
      dump_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "compiler",
          "call_graph",
          "dump_2",
          "nested_a",
          "nested_b"
        ])

      clean_dir(dump_dir)

      [dump_path: Path.join(dump_dir, Reflection.call_graph_dump_file_name())]
    end

    test "writes the graph, its modules and its reach, tagged with the dump version", %{
      dump_path: dump_path,
      empty_call_graph: call_graph
    } do
      graph =
        call_graph
        |> add_edge(:vertex_1, :vertex_2)
        |> get_graph()

      assert dump(call_graph, dump_path) == call_graph

      deserialized_state =
        dump_path
        |> File.read!()
        |> SerializationUtils.deserialize()

      assert {1, %{graph: ^graph, modules: modules, reach: reach}} = deserialized_state
      assert modules == MapSet.new()
      assert reach == reach_state(call_graph)
    end

    test "writes the modules built into the graph", %{
      dump_path: dump_path,
      empty_call_graph: call_graph
    } do
      call_graph
      |> build(IR.for_module(Module9))
      |> dump(dump_path)

      {1, %{modules: modules}} =
        dump_path
        |> File.read!()
        |> SerializationUtils.deserialize()

      assert modules == MapSet.new([Module9])
    end

    test "replaces an earlier dump and leaves no temporary file", %{
      dump_path: dump_path,
      empty_call_graph: call_graph
    } do
      File.write!(dump_path, "earlier dump")

      dump(call_graph, dump_path)

      assert dump_path
             |> Path.dirname()
             |> File.ls!() == [Path.basename(dump_path)]

      assert {1, _state} =
               dump_path
               |> File.read!()
               |> SerializationUtils.deserialize()
    end
  end

  test "edges/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    result = edges(call_graph)

    assert Enum.count(result) == 2
    assert {:vertex_2, :vertex_3} in result
    assert {:vertex_4, :vertex_5} in result
  end

  describe "erlang_mfa_edges/0" do
    test "returns the calls between manually ported Erlang functions" do
      result = erlang_mfa_edges()

      assert is_list(result)
      assert {{:binary, :match, 2}, {:binary, :match, 3}} in result
      assert {{:erlang, :"=<", 2}, {:erlang, :==, 2}} in result
    end

    # Ported functions are JavaScript, so no IR analysis finds the calls between
    # them - each port names its callees in a "Deps" comment and the table above
    # carries the same calls as edges. The two are written by hand and apart, so
    # this holds them to each other: an edge the comments don't name pulls dead
    # code into every bundle reaching its source, and a comment no edge names
    # leaves the callee out of the bundle, which the caller only finds at runtime.
    test "names exactly what the ported Erlang functions declare" do
      declared_deps = list_declared_erlang_deps()

      undeclared_deps =
        Enum.reject(erlang_mfa_edges(), fn {source, target} ->
          {source, target} in declared_deps
        end)

      missing_deps =
        Enum.reject(declared_deps, fn {source, target} ->
          {source, target} in erlang_mfa_edges()
        end)

      assert undeclared_deps == []
      assert missing_deps == []
    end
  end

  test "get_graph/1", %{empty_call_graph: call_graph} do
    assert %Digraph{} = get_graph(call_graph)
  end

  describe "has_edge?/3" do
    test "has the given edge", %{empty_call_graph: call_graph} do
      add_edge(call_graph, :vertex_1, :vertex_2)
      assert has_edge?(call_graph, :vertex_1, :vertex_2)
    end

    test "doesn't have the given edge", %{empty_call_graph: call_graph} do
      refute has_edge?(call_graph, :vertex_1, :vertex_2)
    end
  end

  describe "has_vertex?/2" do
    test "has the given vertex", %{empty_call_graph: call_graph} do
      add_vertex(call_graph, :vertex)
      assert has_vertex?(call_graph, :vertex)
    end

    test "doesn't have the given vertex", %{empty_call_graph: call_graph} do
      refute has_vertex?(call_graph, :vertex)
    end
  end

  describe "list_async_mfas/1" do
    test "returns empty set when Task.await/1 is not in the graph" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {MyModule, :helper, 1})
        |> list_async_mfas()

      assert result == MapSet.new()
    end

    test "returns MFAs that directly call Task.await/1" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {Task, :await, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{MyModule, :action, 3}, {Task, :await, 1}])
    end

    test "returns MFAs that transitively call Task.await/1" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {MyModule, :fetch_data, 1})
        |> add_edge({MyModule, :fetch_data, 1}, {Task, :await, 1})
        |> list_async_mfas()

      assert result ==
               MapSet.new([
                 {MyModule, :action, 3},
                 {MyModule, :fetch_data, 1},
                 {Task, :await, 1}
               ])
    end

    test "excludes MFAs that do not reach Task.await/1" do
      result =
        start()
        |> add_edge({MyModule, :action, 3}, {Task, :await, 1})
        |> add_edge({OtherModule, :action, 3}, {OtherModule, :sync_helper, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{MyModule, :action, 3}, {Task, :await, 1}])
    end

    test "excludes module vertices (non-MFA)" do
      result =
        start()
        |> add_edge(MyModule, {MyModule, :action, 3})
        |> add_edge({MyModule, :action, 3}, {Task, :await, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{MyModule, :action, 3}, {Task, :await, 1}])
    end

    test "does not mark MFAs as async when they only reach Task.await/1 through a module vertex" do
      result =
        start()
        |> add_edge({MyModule, :my_fun, 1}, OtherModule)
        |> add_edge(OtherModule, {OtherModule, :fetch_data, 1})
        |> add_edge({OtherModule, :fetch_data, 1}, {Task, :await, 1})
        |> list_async_mfas()

      assert result == MapSet.new([{OtherModule, :fetch_data, 1}, {Task, :await, 1}])
    end

    test "does not copy the graph out of the agent" do
      call_graph = add_edge(start(), {MyModule, :action, 3}, {Task, :await, 1})

      async_mfas = call_without_copying_graph(fn -> list_async_mfas(call_graph) end)

      assert async_mfas == MapSet.new([{MyModule, :action, 3}, {Task, :await, 1}])
    end
  end

  describe "list_page_entry_mfas/2" do
    test "with the module info PLT of the app" do
      assert list_page_entry_mfas(Module19, module_info_plt_fixture()) ==
               page_entry_mfas(Module19, Module20)
    end

    test "reads the layout from the PLT without calling the page" do
      page_module = Hologram.Test.Fixtures.Compiler.CallGraph.NoSuchPage
      module_info_plt = PLT.put(PLT.start(), page_module, %{layout_module: Module20})

      assert list_page_entry_mfas(page_module, module_info_plt) ==
               page_entry_mfas(page_module, Module20)
    end

    test "calls the page when the PLT has no entry for it" do
      assert list_page_entry_mfas(Module19, PLT.start()) == page_entry_mfas(Module19, Module20)
    end

    test "calls the page when there is no PLT" do
      assert list_page_entry_mfas(Module19, nil) == page_entry_mfas(Module19, Module20)
    end
  end

  describe "list_modules_reaching/2" do
    setup %{empty_call_graph: call_graph} do
      call_graph
      |> add_edge({:module_1, :fun_a, 0}, {:module_2, :fun_b, 0})
      |> add_edge({:module_2, :fun_b, 0}, {:module_3, :fun_c, 0})
      |> add_edge({:module_4, :fun_d, 0}, :module_3)
      |> add_edge({:module_5, :fun_e, 0}, {:module_6, :fun_f, 0})
      # A page calling a protocol, the protocol dispatching to one implementation, and an ordinary
      # caller of that implementation.
      |> add_edge({:page_module, :template, 0}, {String.Chars, :to_string, 1})
      |> add_edge({String.Chars, :to_string, 1}, {StringCharsModule12, :to_string, 1})
      |> add_edge({:caller_module, :fun_g, 0}, {StringCharsModule12, :to_string, 1})

      :ok
    end

    test "returns the modules reaching the given modules, the given modules included", %{
      empty_call_graph: call_graph
    } do
      assert list_modules_reaching(call_graph, [:module_3]) ==
               MapSet.new([:module_1, :module_2, :module_3, :module_4])
    end

    test "includes a given module that has no vertices", %{empty_call_graph: call_graph} do
      assert list_modules_reaching(call_graph, [:module_3, :module_7]) ==
               MapSet.new([:module_1, :module_2, :module_3, :module_4, :module_7])
    end

    test "given no module, returns the empty set", %{empty_call_graph: call_graph} do
      assert list_modules_reaching(call_graph, []) == MapSet.new()
    end

    test "given no module, does not read the graph" do
      # A read of a stopped call graph exits, so the call returns only if it reads nothing.
      call_graph = CallGraph.start()
      CallGraph.stop(call_graph)

      assert list_modules_reaching(call_graph, []) == MapSet.new()
    end

    test "does not copy the graph out of the agent", %{empty_call_graph: call_graph} do
      reaching_modules =
        call_without_copying_graph(fn -> list_modules_reaching(call_graph, [:module_3]) end)

      assert reaching_modules == MapSet.new([:module_1, :module_2, :module_3, :module_4])
    end

    test "doesn't follow outgoing edges", %{empty_call_graph: call_graph} do
      assert list_modules_reaching(call_graph, [:module_2]) ==
               MapSet.new([:module_1, :module_2])
    end

    test "stops at a protocol's dispatch function", %{empty_call_graph: call_graph} do
      reaching_modules = list_modules_reaching(call_graph, [StringCharsModule12])

      assert MapSet.member?(reaching_modules, StringCharsModule12)
      refute MapSet.member?(reaching_modules, String.Chars)
      refute MapSet.member?(reaching_modules, :page_module)
    end

    test "follows a non-dispatch caller of the same module", %{empty_call_graph: call_graph} do
      reaching_modules = list_modules_reaching(call_graph, [StringCharsModule12])

      assert MapSet.member?(reaching_modules, :caller_module)
    end

    test "empty modules list", %{empty_call_graph: call_graph} do
      assert list_modules_reaching(call_graph, []) == MapSet.new()
    end
  end

  describe "list_page_mfas/5" do
    setup %{full_call_graph: full_call_graph, runtime_mfas: runtime_mfas} do
      page_module_22_mfas =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> list_page_mfas_with_analysis(Module22)

      [page_module_22_mfas: page_module_22_mfas]
    end

    test "includes action/3, template/0 and other MFAs that should be included", %{
      module_info_plt: module_info_plt
    } do
      module_14_ir = IR.for_module(Module14)
      module_15_ir = IR.for_module(Module15)
      module_16_ir = IR.for_module(Module16)

      call_graph = start(module_info_plt: module_info_plt)

      result =
        call_graph
        |> build(module_14_ir)
        |> build(module_15_ir)
        |> build(module_16_ir)
        |> list_page_mfas_with_analysis(Module14)

      assert result == [
               {Enum, :reverse, 1},
               {Enum, :to_list, 1},
               {Module14, :__layout_module__, 0},
               {Module14, :__layout_props__, 0},
               {Module14, :__params__, 0},
               {Module14, :__route__, 0},
               {Module14, :action, 3},
               {Module14, :template, 0},
               {Module15, :__props__, 0},
               {Module15, :action, 3},
               {Module15, :init, 2},
               {Module15, :template, 0},
               {Module16, :my_fun_16a, 2},
               {Kernel, :inspect, 1},
               {:erlang, :hd, 1}
             ]
    end

    test "excludes Hex MFAs" do
      module_17_ir = IR.for_module(Module17)

      call_graph = start(module_info_plt: module_info_plt_fixture())
      build(call_graph, module_17_ir)
      add_edge(call_graph, {Module17, :action, 3}, {Hex, :start, 2})
      add_edge(call_graph, {Module17, :action, 3}, {Hex, :version, 0})

      result = list_page_mfas_with_analysis(call_graph, Module17)

      assert {Module18, :my_fun_18, 2} in result

      refute {Hex, :start, 2} in result
      refute {Hex, :version, 0} in result
    end

    test "excludes Hex.* MFAs" do
      module_17_ir = IR.for_module(Module17)

      call_graph = start(module_info_plt: module_info_plt_fixture())
      build(call_graph, module_17_ir)
      add_edge(call_graph, {Module17, :action, 3}, {Hex.API, :request, 4})
      add_edge(call_graph, {Module17, :action, 3}, {Hex.Registry.Server, :versions, 2})

      result = list_page_mfas_with_analysis(call_graph, Module17)

      assert {Module18, :my_fun_18, 2} in result

      refute {Hex.API, :request, 4} in result
      refute {Hex.Registry.Server, :versions, 2} in result
    end

    test "excludes Hex implementations for Inspect and String.Chars protocols" do
      module_17_ir = IR.for_module(Module17)

      call_graph = start(module_info_plt: module_info_plt_fixture())
      build(call_graph, module_17_ir)

      result = list_page_mfas_with_analysis(call_graph, Module17)

      assert {Module18, :my_fun_18, 2} in result

      assert {Inspect.Integer, :__impl__, 1} in result
      assert {Inspect.Integer, :inspect, 2} in result

      refute {Inspect.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {Inspect.Hex.Solver.PackageRange, :inspect, 2} in result

      assert {String.Chars.Integer, :__impl__, 1} in result
      assert {String.Chars.Integer, :to_string, 1} in result

      refute {String.Chars.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {String.Chars.Hex.Solver.PackageRange, :to_string, 1} in result
    end

    test "excludes protocol implementations whose concrete type is not reachable", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> list_page_mfas_with_analysis(Module17)

      refute {StringCharsModule12, :__impl__, 1} in result
      refute {StringCharsModule12, :to_string, 1} in result
    end

    test "includes protocol implementations whose concrete type is reachable", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> add_edge({Module17, :template, 0}, {Module12, :__struct__, 1})
        |> list_page_mfas_with_analysis(Module17)

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "reads an implementation target from the PLT without calling the implementation", %{
      full_call_graph: full_call_graph
    } do
      impl = Hologram.Test.Fixtures.Compiler.CallGraph.NoSuchImpl

      module_info_plt = PLT.clone(module_info_plt_fixture())

      PLT.put(module_info_plt, impl, %{
        protocol_implementation?: true,
        implementation_for: Module12
      })

      call_graph = %{CallGraph.clone(full_call_graph) | module_info_plt: module_info_plt}

      result =
        call_graph
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> add_edge({String.Chars, :to_string, 1}, {impl, :__impl__, 1})
        |> add_edge({String.Chars, :to_string, 1}, {impl, :to_string, 1})
        |> add_edge({Module17, :template, 0}, {Module12, :__struct__, 1})
        |> list_page_mfas_with_analysis(Module17)

      assert {impl, :__impl__, 1} in result
      assert {impl, :to_string, 1} in result
    end

    test "includes protocol implementations whose type is created only in server init", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> add_edge({Module17, :init, 3}, Module12)
        |> list_page_mfas_with_analysis(Module17)

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "includes protocol implementations whose type is created only in commands", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> add_edge({Module17, :command, 3}, Module12)
        |> list_page_mfas_with_analysis(Module17)

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "includes protocol implementations unlocked transitively by server-created types", %{
      full_call_graph: full_call_graph
    } do
      struct_1_impl = Module.safe_concat(Protocol1, Struct1)

      # Struct1 is created only in server init, its Protocol1 implementation code
      # creates Module12, and Module12's String.Chars implementation must follow
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, {Protocol1, :my_fun, 1})
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> add_edge({Module17, :init, 3}, Struct1)
        |> add_edge({struct_1_impl, :my_fun, 1}, Module12)
        |> list_page_mfas_with_analysis(Module17)

      assert {struct_1_impl, :__impl__, 1} in result
      assert {struct_1_impl, :my_fun, 1} in result

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "excludes MFAs reachable only from server-executed code", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :init, 3}, {Module13, :my_fun, 0})
        |> add_edge({Module17, :command, 3}, {Module13, :my_fun, 0})
        |> list_page_mfas_with_analysis(Module17)

      refute {Module13, :my_fun, 0} in result
    end

    test "includes client MFAs of a component referenced only in server init", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :init, 3}, Module15)
        |> list_page_mfas_with_analysis(Module17)

      assert {Module15, :__props__, 0} in result
      assert {Module15, :action, 3} in result
      assert {Module15, :init, 2} in result
      assert {Module15, :template, 0} in result
    end

    test "includes client MFAs of a component referenced only in commands", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :command, 3}, Module15)
        |> list_page_mfas_with_analysis(Module17)

      assert {Module15, :__props__, 0} in result
      assert {Module15, :action, 3} in result
      assert {Module15, :init, 2} in result
      assert {Module15, :template, 0} in result
    end

    test "excludes client MFAs of a page module referenced only in server code", %{
      full_call_graph: full_call_graph
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :init, 3}, Module14)
        |> add_edge({Module17, :command, 3}, Module14)
        |> list_page_mfas_with_analysis(Module17)

      refute {Module14, :action, 3} in result
      refute {Module14, :template, 0} in result
    end

    test "includes client MFAs of a component referenced in a server-referenced component's own server callbacks",
         %{full_call_graph: full_call_graph} do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :init, 3}, Module15)
        |> add_edge({Module15, :command, 3}, Module4)
        |> list_page_mfas_with_analysis(Module17)

      assert {Module4, :__props__, 0} in result
      assert {Module4, :action, 3} in result
      assert {Module4, :init, 2} in result
      assert {Module4, :template, 0} in result
    end

    test "includes protocol implementations whose type is created in a server-referenced component's server code",
         %{full_call_graph: full_call_graph} do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> add_edge({Module17, :init, 3}, Module15)
        |> add_edge({Module15, :init, 3}, Module12)
        |> list_page_mfas_with_analysis(Module17)

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "treats components reached from a server-referenced component's client code as templatables",
         %{full_call_graph: full_call_graph} do
      # Module17's server init references Module15, whose template statically renders
      # Module4, whose own server init creates Module12 - so Module12's String.Chars
      # implementation must follow
      result =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, {String.Chars, :to_string, 1})
        |> add_edge({Module17, :init, 3}, Module15)
        |> add_edge({Module15, :template, 0}, Module4)
        |> add_edge({Module4, :init, 3}, Module12)
        |> list_page_mfas_with_analysis(Module17)

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "includes reflection MFAs reachable from server inits of components used by the page", %{
      page_module_22_mfas: result
    } do
      assert {Module24, :__changeset__, 0} in result
      assert {Module24, :__schema__, 1} in result
      assert {Module24, :__schema__, 2} in result

      assert {Module25, :__struct__, 0} in result
      assert {Module25, :__struct__, 1} in result

      assert {Module27, :__changeset__, 0} in result
      assert {Module27, :__schema__, 1} in result
      assert {Module27, :__schema__, 2} in result

      assert {Module28, :__struct__, 0} in result
      assert {Module28, :__struct__, 1} in result

      assert {Module30, :__changeset__, 0} in result
      assert {Module30, :__schema__, 1} in result
      assert {Module30, :__schema__, 2} in result

      assert {Module31, :__struct__, 0} in result
      assert {Module31, :__struct__, 1} in result

      assert {Module32, :__changeset__, 0} in result
      assert {Module32, :__schema__, 1} in result
      assert {Module32, :__schema__, 2} in result

      assert {Module33, :__struct__, 0} in result
      assert {Module33, :__struct__, 1} in result

      assert {Module35, :__changeset__, 0} in result
      assert {Module35, :__schema__, 1} in result
      assert {Module35, :__schema__, 2} in result

      assert {Module36, :__struct__, 0} in result
      assert {Module36, :__struct__, 1} in result

      assert {Module37, :__struct__, 0} in result
      assert {Module37, :__struct__, 1} in result
    end

    test "removes duplicate reflection MFAs reachable from server inits of components used by the page",
         %{page_module_22_mfas: result} do
      assert Enum.count(result, &(&1 == {Module32, :__changeset__, 0})) == 1
      assert Enum.count(result, &(&1 == {Module32, :__schema__, 1})) == 1
      assert Enum.count(result, &(&1 == {Module32, :__schema__, 2})) == 1

      assert Enum.count(result, &(&1 == {Module37, :__struct__, 0})) == 1
      assert Enum.count(result, &(&1 == {Module37, :__struct__, 1})) == 1
    end

    test "results are deduped", %{page_module_22_mfas: result} do
      assert result == Enum.uniq(result)
    end

    test "results are sorted", %{page_module_22_mfas: result} do
      assert result == Enum.sort(result)
    end

    test "computes and keeps the analyses of the templatables the PLT does not hold", %{
      module_info_plt: module_info_plt
    } do
      call_graph =
        [module_info_plt: module_info_plt]
        |> start()
        |> build(IR.for_module(Module14))
        |> build(IR.for_module(Module15))
        |> build(IR.for_module(Module16))

      graph = CallGraph.get_graph(call_graph)
      analyses = PLT.start()

      list_page_mfas(graph, Module14, analyses, module_info_plt)

      expected =
        server_callback_analysis_by_templatable(graph, [Module14, Module15], module_info_plt)

      assert PLT.get(analyses, Module14) == {:ok, expected[Module14]}
      assert PLT.get(analyses, Module15) == {:ok, expected[Module15]}
    end

    test "reads a kept analysis instead of computing one", %{module_info_plt: module_info_plt} do
      call_graph =
        [module_info_plt: module_info_plt]
        |> start()
        |> build(IR.for_module(Module14))
        |> build(IR.for_module(Module15))
        |> build(IR.for_module(Module16))

      # No walk of Module14's server callbacks finds this component, so its client MFAs are listed
      # only when the kept analysis is read.
      kept_analysis = %{
        dispatch_types: MapSet.new(),
        server_referenced_components: [Module38]
      }

      analyses = PLT.start(items: [{Module14, kept_analysis}])

      result =
        call_graph
        |> build(IR.for_module(Module38))
        |> CallGraph.get_graph()
        |> list_page_mfas(Module14, analyses, module_info_plt)

      assert {Module38, :template, 0} in result
    end

    test "lists the reflection functions of the types the page reaches, when no gate is given", %{
      page_module_22_mfas: result
    } do
      # Module25 is a struct put into state by the page's init/3, Module21 an Ecto schema no
      # templatable of the page reaches.
      assert {Module25, :__struct__, 0} in result
      assert {Module25, :__struct__, 1} in result

      refute {Module21, :__changeset__, 0} in result
      refute {Module21, :__struct__, 0} in result
    end

    test "lists the reflection functions of the types created in command/3", %{
      full_call_graph: full_call_graph,
      runtime_mfas: runtime_mfas
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> add_edge({Module22, :command, 3}, Module21)
        |> list_page_mfas_with_analysis(Module22)

      assert {Module21, :__changeset__, 0} in result
      assert {Module21, :__schema__, 1} in result
      assert {Module21, :__schema__, 2} in result
      assert {Module21, :__struct__, 0} in result
      assert {Module21, :__struct__, 1} in result
    end

    test "lists no reflection functions for the built-in types", %{page_module_22_mfas: result} do
      refute {Map, :__struct__, 0} in result
      refute {Atom, :__struct__, 0} in result
    end

    test "lists no reflection functions the gate closes", %{
      full_call_graph: full_call_graph,
      runtime_mfas: runtime_mfas
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> list_page_mfas_with_gate(Module43, %{
          ir_plt: PLT.start(),
          runtime: %{exposed: %{}, open: MapSet.new(), page_callers: %{}}
        })

      refute {Module24, :__changeset__, 0} in result
      refute {Module24, :__schema__, 1} in result
      refute {Module24, :__schema__, 2} in result
      refute {Module24, :__struct__, 0} in result
      refute {Module25, :__struct__, 0} in result
      refute {Module25, :__struct__, 1} in result
    end

    test "lists the reflection functions the page's client code opens", %{
      full_call_graph: full_call_graph,
      runtime_mfas: runtime_mfas
    } do
      # Module44's action calls __changeset__/0 on a module it does not name; the types come from
      # the inits of the page (Module24, Module25) and of its layout (Module32, Module33).
      result =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> list_page_mfas_with_gate(Module44, %{
          ir_plt: PLT.start(),
          runtime: %{exposed: %{}, open: MapSet.new(), page_callers: %{}}
        })

      assert {Module24, :__changeset__, 0} in result
      assert {Module32, :__changeset__, 0} in result

      refute {Module24, :__schema__, 1} in result
      refute {Module24, :__struct__, 0} in result
      refute {Module25, :__struct__, 0} in result
      refute {Module33, :__struct__, 0} in result
    end

    test "lists the reflection functions the runtime opens", %{
      full_call_graph: full_call_graph,
      runtime_mfas: runtime_mfas
    } do
      result =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> list_page_mfas_with_gate(Module43, %{
          ir_plt: PLT.start(),
          runtime: %{exposed: %{}, open: MapSet.new([{:__struct__, 0}]), page_callers: %{}}
        })

      assert {Module24, :__struct__, 0} in result
      assert {Module25, :__struct__, 0} in result

      refute {Module24, :__changeset__, 0} in result
      refute {Module25, :__struct__, 1} in result
    end
  end

  test "list_runtime_entry_mfas/0" do
    result = list_runtime_entry_mfas()

    assert {:erlang, :error, 1} in result
    assert {String.Chars, :to_string, 1} in result

    assert {Hologram.Router.Helpers, :page_path, 1} in result

    assert {:re, :import, 1} in result

    refute {:unicode, :characters_to_binary, 1} in result
    refute {Hologram.Router.Helpers, :asset_path, 1} in result
  end

  describe "list_runtime_mfas/2" do
    setup %{full_call_graph: call_graph} do
      [runtime_mfas: list_runtime_mfas(call_graph, Reflection.list_pages())]
    end

    test "includes MFAs that are reachable by Elixir functions used by the runtime", %{
      runtime_mfas: result
    } do
      assert {Enum, :into, 2} in result
      assert {Enum, :into_protocol, 2} in result
      assert {:lists, :foldl, 3} in result

      assert {Enum, :to_list, 1} in result
      assert {Enum, :reverse, 1} in result
      assert {:lists, :reverse, 1} in result
    end

    test "excludes MFAs with non-existing modules", %{full_call_graph: call_graph} do
      call_graph_clone = CallGraph.clone(call_graph)

      call_graph_clone
      |> add_edge({Enum, :into, 2}, {Calendar.ISO, :dummy_function_1, 1})
      |> add_edge({Enum, :into, 2}, {NonExistingModuleFixture, :dummy_function_2, 2})
      |> add_edge({Enum, :into, 2}, {:maps, :dummy_function_3, 3})
      |> add_edge({Enum, :into, 2}, {:non_existing_module_fixture, :dummy_function_4, 4})

      result = list_runtime_mfas(call_graph_clone, Reflection.list_pages())

      assert {Calendar.ISO, :dummy_function_1, 1} in result
      refute {NonExistingModuleFixture, :dummy_function_2, 2} in result
      assert {:maps, :dummy_function_3, 3} in result
      refute {:non_existing_module_fixture, :dummy_function_4, 4} in result
    end

    test "excludes Hex MFAs", %{full_call_graph: call_graph} do
      call_graph_clone = CallGraph.clone(call_graph)

      call_graph_clone
      |> add_edge({Enum, :into, 2}, {Hex, :start, 2})
      |> add_edge({Enum, :into, 2}, {Hex, :version, 0})

      result = list_runtime_mfas(call_graph_clone, Reflection.list_pages())

      assert {Enum, :into, 2} in result

      refute {Hex, :start, 2} in result
      refute {Hex, :version, 0} in result
    end

    test "excludes Hex.* MFAs", %{full_call_graph: call_graph} do
      call_graph_clone = CallGraph.clone(call_graph)

      call_graph_clone
      |> add_edge({Enum, :into, 2}, {Hex.API, :request, 4})
      |> add_edge({Enum, :into, 2}, {Hex.Registry.Server, :versions, 2})

      result = list_runtime_mfas(call_graph_clone, Reflection.list_pages())

      assert {Enum, :into, 2} in result

      refute {Hex.API, :request, 4} in result
      refute {Hex.Registry.Server, :versions, 2} in result
    end

    test "excludes Hex implementations for Inspect and String.Chars protocols", %{
      runtime_mfas: result
    } do
      assert {Inspect.Integer, :__impl__, 1} in result
      assert {Inspect.Integer, :inspect, 2} in result

      refute {Inspect.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {Inspect.Hex.Solver.PackageRange, :inspect, 2} in result

      assert {String.Chars.Integer, :__impl__, 1} in result
      assert {String.Chars.Integer, :to_string, 1} in result

      refute {String.Chars.Hex.Solver.PackageRange, :__impl__, 1} in result
      refute {String.Chars.Hex.Solver.PackageRange, :to_string, 1} in result
    end

    test "excludes protocol implementations whose concrete type is not runtime reachable", %{
      runtime_mfas: result
    } do
      refute {StringCharsModule12, :__impl__, 1} in result
      refute {StringCharsModule12, :to_string, 1} in result
    end

    test "includes protocol dispatch helpers used by generic protocol functions", %{
      runtime_mfas: result
    } do
      assert {String.Chars, :to_string, 1} in result
      assert {String.Chars, :impl_for, 1} in result
      assert {String.Chars, :impl_for!, 1} in result
      assert {String.Chars, :struct_impl_for, 1} in result
      assert {Protocol.UndefinedError, :exception, 1} in result
    end

    test "includes protocol implementations whose type is used only by a page", %{
      full_call_graph: call_graph
    } do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :template, 0}, Module12)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "includes protocol implementations whose type is created only in a page's server init",
         %{
           full_call_graph: call_graph
         } do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module17, :init, 3}, Module12)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "includes protocol implementations whose type is reachable from broadcast callers", %{
      full_call_graph: call_graph
    } do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> add_edge({Module13, :my_fun, 0}, Module12)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result

      refute {Module13, :my_fun, 0} in result
    end

    test "includes client MFAs of a component referenced only in broadcast caller code", %{
      full_call_graph: call_graph
    } do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> add_edge({Module13, :my_fun, 0}, Module38)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {Module38, :__props__, 0} in result
      assert {Module38, :action, 3} in result
      assert {Module38, :init, 2} in result
      assert {Module38, :template, 0} in result

      refute {Module13, :my_fun, 0} in result
    end

    test "includes client MFAs of a component referenced only in code that queues a broadcast", %{
      full_call_graph: call_graph
    } do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module38, :command, 3}, {Component, :put_broadcast, 4})
        |> add_edge({Module38, :command, 3}, Module39)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {Module39, :__props__, 0} in result
      assert {Module39, :action, 3} in result
      assert {Module39, :init, 2} in result
      assert {Module39, :template, 0} in result

      refute {Module38, :command, 3} in result
    end

    test "excludes client MFAs of a page module referenced only in broadcast caller code", %{
      full_call_graph: call_graph
    } do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> add_edge({Module13, :my_fun, 0}, Module14)
        |> list_runtime_mfas(Reflection.list_pages())

      refute {Module14, :action, 3} in result
      refute {Module14, :template, 0} in result
    end

    test "includes protocol implementations whose type is created in a broadcast-referenced component's server code",
         %{full_call_graph: call_graph} do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> add_edge({Module13, :my_fun, 0}, Module38)
        |> add_edge({Module38, :command, 3}, Module12)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result

      refute {Module38, :command, 3} in result
    end

    test "includes client MFAs of a component referenced in a broadcast-referenced component's own server callbacks",
         %{full_call_graph: call_graph} do
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> add_edge({Module13, :my_fun, 0}, Module38)
        |> add_edge({Module38, :command, 3}, Module39)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {Module39, :__props__, 0} in result
      assert {Module39, :action, 3} in result
      assert {Module39, :init, 2} in result
      assert {Module39, :template, 0} in result
    end

    test "collects components through a referenced component's client code already at analysis time",
         %{full_call_graph: call_graph} do
      # Module13 broadcasts and references Module38, whose template statically renders
      # Module39, whose own server command creates Module12. The broadcast caller
      # traversal crosses static client code, so Module39 is collected by the analysis
      # itself and Module12's String.Chars implementation must follow.
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> add_edge({Module13, :my_fun, 0}, Module38)
        |> add_edge({Module38, :template, 0}, Module39)
        |> add_edge({Module39, :command, 3}, Module12)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "treats components reached from a broadcast-chained component's client code as templatables",
         %{full_call_graph: call_graph} do
      # Module13 broadcasts and references Module38, whose server command references
      # Module39 (fixpoint hop), whose template statically renders Module40, whose own
      # server command creates Module12 - so Module12's String.Chars implementation
      # must follow
      result =
        call_graph
        |> CallGraph.clone()
        |> add_edge({Module13, :my_fun, 0}, {Realtime, :broadcast_action, 3})
        |> add_edge({Module13, :my_fun, 0}, Module38)
        |> add_edge({Module38, :command, 3}, Module39)
        |> add_edge({Module39, :template, 0}, Module40)
        |> add_edge({Module40, :command, 3}, Module12)
        |> list_runtime_mfas(Reflection.list_pages())

      assert {Module40, :template, 0} in result

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    # Guards the type-bounded implementation inclusion in both directions: missing
    # built-in type implementations would break rendering of primitives on every page,
    # while any extra entry means implementations of unreachable types (and their
    # dependency subtrees) are getting pulled into the runtime bundle again.
    test "includes exactly the built-in type implementations of String.Chars", %{
      runtime_mfas: result
    } do
      string_chars_impls =
        result
        |> Enum.map(fn {module, _function, _arity} -> module end)
        |> Enum.uniq()
        |> Enum.filter(&(Reflection.protocol_implementation(&1) == String.Chars))
        |> Enum.sort()

      assert string_chars_impls == [
               String.Chars.Atom,
               String.Chars.BitString,
               String.Chars.Float,
               String.Chars.Integer,
               String.Chars.List
             ]
    end

    test "results are deduped", %{runtime_mfas: result} do
      assert result == Enum.uniq(result)
    end

    test "results are sorted", %{runtime_mfas: result} do
      assert result == Enum.sort(result)
    end

    # The analyses PLT is started from the agent, since the walk runs there, and is linked to it
    # while it runs, so a PLT left running would stay among the agent's links.
    test "stops the analyses PLT it starts", %{full_call_graph: call_graph} do
      {:links, links_before} = Process.info(call_graph.pid, :links)

      list_runtime_mfas(call_graph, Reflection.list_pages())

      {:links, links_after} = Process.info(call_graph.pid, :links)

      assert MapSet.new(links_after) == MapSet.new(links_before)
    end

    test "does not copy the graph out of the agent", %{
      full_call_graph: call_graph,
      runtime_mfas: runtime_mfas
    } do
      walked_mfas =
        call_without_copying_graph(fn ->
          list_runtime_mfas(call_graph, Reflection.list_pages())
        end)

      assert walked_mfas == runtime_mfas
    end
  end

  describe "load/2" do
    setup do
      dump_dir = Path.join([@tmp_dir, "tests", "compiler", "call_graph", "load_2"])
      clean_dir(dump_dir)

      [dump_path: Path.join(dump_dir, Reflection.call_graph_dump_file_name())]
    end

    test "loads the graph and the modules of a dump of this version", %{
      dump_path: dump_path,
      empty_call_graph: call_graph
    } do
      call_graph
      |> add_edge(:vertex_1, :vertex_2)
      |> build(IR.for_module(Module9))
      |> dump(dump_path)

      call_graph_2 = start()

      assert load(call_graph_2, dump_path) == :ok
      assert get_graph(call_graph_2) == get_graph(call_graph)
      assert modules(call_graph_2) == MapSet.new([Module9])
    end

    test "does not load a dump of another version", %{dump_path: dump_path} do
      graph = Digraph.add_edge(Digraph.new(), :vertex_1, :vertex_2)
      state = %{graph: graph, modules: MapSet.new([Module9])}
      File.write!(dump_path, SerializationUtils.serialize({0, state}))

      call_graph = start()

      assert load(call_graph, dump_path) == :error
      assert get_graph(call_graph) == Digraph.new()
      assert modules(call_graph) == MapSet.new()
    end

    test "does not load a dump written before the dump version existed", %{dump_path: dump_path} do
      graph = Digraph.add_edge(Digraph.new(), :vertex_1, :vertex_2)
      File.write!(dump_path, SerializationUtils.serialize(graph))

      call_graph = start()

      assert load(call_graph, dump_path) == :error
      assert get_graph(call_graph) == Digraph.new()
    end
  end

  test "manually_ported_elixir_mfas/0" do
    result = manually_ported_elixir_mfas()

    assert is_list(result)
    assert {Kernel, :inspect, 1} in result
    assert {String, :upcase, 1} in result
  end

  test "module_vertices/2", %{empty_call_graph: call_graph} do
    ir = IR.for_module(Module13)

    call_graph
    |> add_vertex({:module_1, :fun_a, 1})
    |> add_vertex({:module_3, :fun_b, 2})
    |> build(ir)
    |> add_vertex(:module_4)

    assert module_vertices(call_graph, Module13) == [
             {Module13, :fun_b, 2},
             {Module13, :fun_d, 4},
             {Module13, :fun_e, 2}
           ]
  end

  test "module_vertices/2 includes the dynamic calls of the module's functions", %{
    empty_call_graph: call_graph
  } do
    build(call_graph, IR.for_module(Module42))

    result =
      call_graph
      |> module_vertices(Module42)
      |> Enum.sort()

    assert result == [
             {Module42, :my_fun, 1},
             {:dynamic_call, {Module42, :my_fun, 1}, :__changeset__, 0, {:param, 0}}
           ]
  end

  test "module_info_plt/1" do
    module_info_plt = PLT.start()

    assert module_info_plt(start(module_info_plt: module_info_plt)) == module_info_plt
    assert module_info_plt(start()) == nil
  end

  describe "modules/1" do
    test "empty at first", %{empty_call_graph: call_graph} do
      assert modules(call_graph) == MapSet.new()
    end

    test "lists the modules whose definitions were built", %{empty_call_graph: call_graph} do
      call_graph
      |> build(IR.for_module(Module9))
      |> build(IR.for_module(Module10))

      assert modules(call_graph) == MapSet.new([Module9, Module10])
    end

    test "leaves out a module only named by a call", %{empty_call_graph: call_graph} do
      build(call_graph, IR.for_module(Module14))

      assert has_vertex?(call_graph, {Module16, :my_fun_16a, 2})
      refute Module16 in modules(call_graph)
    end
  end

  describe "narrow_diff/2" do
    setup do
      module_info_plt =
        PLT.start()
        |> PLT.put(NarrowDiff.Page, %{page?: true})
        |> PLT.put(NarrowDiff.Caller, %{broadcast_caller?: true})
        |> PLT.put(NarrowDiff.HeldImpl, %{
          protocol_implementation?: true,
          implemented_protocol: NarrowDiff.HeldProtocol
        })
        |> PLT.put(NarrowDiff.OtherImpl, %{
          protocol_implementation?: true,
          implemented_protocol: NarrowDiff.OtherProtocol
        })
        |> PLT.put(NarrowDiff.Held, %{})
        |> PLT.put(NarrowDiff.Other, %{})

      call_graph =
        start(
          modules: MapSet.new([NarrowDiff.Held, NarrowDiff.HeldProtocol]),
          module_info_plt: module_info_plt
        )

      [call_graph: call_graph]
    end

    test "keeps every removed module", %{call_graph: call_graph} do
      diff = narrow_diff_fixture([], [], [NarrowDiff.Held, NarrowDiff.Other])

      assert narrow_diff(call_graph, diff) == diff
    end

    test "keeps an edited module the graph holds", %{call_graph: call_graph} do
      diff = narrow_diff_fixture([], [NarrowDiff.Held], [])

      assert narrow_diff(call_graph, diff) == diff
    end

    test "drops an edited module the graph does not hold", %{call_graph: call_graph} do
      diff = narrow_diff_fixture([], [NarrowDiff.Other], [])

      assert narrow_diff(call_graph, diff) == narrow_diff_fixture([], [], [])
    end

    test "drops an added module outside the reach", %{call_graph: call_graph} do
      diff = narrow_diff_fixture([NarrowDiff.Other], [], [])

      assert narrow_diff(call_graph, diff) == narrow_diff_fixture([], [], [])
    end

    test "keeps an added or edited page", %{call_graph: call_graph} do
      diff = narrow_diff_fixture([NarrowDiff.Page], [NarrowDiff.Page], [])

      assert narrow_diff(call_graph, diff) == diff
    end

    test "keeps an added or edited broadcast caller", %{call_graph: call_graph} do
      diff = narrow_diff_fixture([NarrowDiff.Caller], [NarrowDiff.Caller], [])

      assert narrow_diff(call_graph, diff) == diff
    end

    test "keeps an added or edited implementation of a protocol the graph holds", %{
      call_graph: call_graph
    } do
      diff = narrow_diff_fixture([NarrowDiff.HeldImpl], [NarrowDiff.HeldImpl], [])

      assert narrow_diff(call_graph, diff) == diff
    end

    test "drops an implementation of a protocol the graph does not hold", %{
      call_graph: call_graph
    } do
      diff = narrow_diff_fixture([NarrowDiff.OtherImpl], [NarrowDiff.OtherImpl], [])

      assert narrow_diff(call_graph, diff) == narrow_diff_fixture([], [], [])
    end

    test "keeps the order of the given lists", %{call_graph: call_graph} do
      diff =
        narrow_diff_fixture(
          [NarrowDiff.Page, NarrowDiff.Other, NarrowDiff.Caller],
          [NarrowDiff.HeldImpl, NarrowDiff.Other, NarrowDiff.Held],
          []
        )

      assert narrow_diff(call_graph, diff) ==
               narrow_diff_fixture(
                 [NarrowDiff.Page, NarrowDiff.Caller],
                 [NarrowDiff.HeldImpl, NarrowDiff.Held],
                 []
               )
    end
  end

  describe "patch/3" do
    test "adds modules", %{empty_call_graph: call_graph_1} do
      module_9_ir = IR.for_module(Module9)
      module_10_ir = IR.for_module(Module10)

      ir_plt =
        PLT.start()
        |> PLT.put(Module9, module_9_ir)
        |> PLT.put(Module10, module_10_ir)

      call_graph_2 =
        start()
        |> build(module_9_ir)
        |> build(module_10_ir)

      diff = %{
        added_modules: [Module10, Module9],
        removed_modules: [],
        edited_modules: []
      }

      patch(call_graph_1, ir_plt, diff)

      assert get_graph(call_graph_1) == get_graph(call_graph_2)
    end

    test "removes modules", %{empty_call_graph: call_graph} do
      call_graph
      |> add_edge({:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b})
      |> add_edge({:module_2, :fun_c, :arity_c}, {:module_3, :fun_d, :arity_d})
      |> add_edge({:module_1, :fun_e, :arity_e}, {:module_3, :fun_f, :arity_f})
      |> add_edge({:module_4, :fun_g, :arity_g}, :module_2)
      |> add_edge({:module_5, :fun_h, :arity_h}, :module_6)

      ir_plt = PLT.start()

      diff = %{
        added_modules: [],
        removed_modules: [:module_2, :module_3],
        edited_modules: []
      }

      patch(call_graph, ir_plt, diff)

      assert sorted_vertices(call_graph) == [
               :module_6,
               {:module_1, :fun_a, :arity_a},
               {:module_1, :fun_e, :arity_e},
               {:module_4, :fun_g, :arity_g},
               {:module_5, :fun_h, :arity_h}
             ]

      assert edges(call_graph) == [
               {{:module_5, :fun_h, :arity_h}, :module_6}
             ]
    end

    test "adds protocol dispatch edges when an added module is a protocol implementation", %{
      empty_call_graph: call_graph
    } do
      impl_module = StringCharsModule12
      impl_ir = IR.for_module(impl_module)
      from_vertex = {String.Chars, :to_string, 1}

      # Simulate a previous build that had String.Chars but not Module12:
      # manually add the protocol function vertex without the dispatch edge to Module12.
      add_vertex(call_graph, from_vertex)

      refute has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      refute has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})

      # Now patch with Module12 (which has defimpl String.Chars) as an added module
      ir_plt = PLT.put(PLT.start(), impl_module, impl_ir)

      diff = %{
        added_modules: [impl_module],
        removed_modules: [],
        edited_modules: []
      }

      patch(call_graph, ir_plt, diff)

      assert has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      assert has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})
    end

    test "reads an added implementation protocol from the PLT" do
      impl_module = StringCharsModule12
      {:ok, info} = PLT.get(module_info_plt_fixture(), impl_module)

      module_info_plt = PLT.clone(module_info_plt_fixture())

      PLT.put(module_info_plt, impl_module, %{
        info
        | implemented_protocol: Protocol1
      })

      call_graph = start(module_info_plt: module_info_plt)
      ir_plt = PLT.put(PLT.start(), impl_module, IR.for_module(impl_module))
      diff = %{added_modules: [impl_module], removed_modules: [], edited_modules: []}

      patch(call_graph, ir_plt, diff)

      # The dispatch edges refreshed are those of the protocol the PLT names.
      assert has_edge?(call_graph, {Protocol1, :my_fun, 1}, {Protocol1.Integer, :__impl__, 1})
      refute has_edge?(call_graph, {String.Chars, :to_string, 1}, {impl_module, :__impl__, 1})
    end

    test "adds protocol dispatch edges when an edited module is a protocol implementation", %{
      empty_call_graph: call_graph
    } do
      impl_module = StringCharsModule12
      impl_ir = IR.for_module(impl_module)
      from_vertex = {String.Chars, :to_string, 1}

      # Simulate a previous build: the protocol function vertex exists and the
      # implementation module was already built (has its own internal edges).
      call_graph
      |> add_vertex(from_vertex)
      |> build(impl_ir)

      # The impl's internal edges exist, but there are no dispatch edges
      # from the protocol to the implementation.
      assert has_vertex?(call_graph, {impl_module, :to_string, 1})
      refute has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      refute has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})

      ir_plt = PLT.put(PLT.start(), impl_module, impl_ir)

      diff = %{
        added_modules: [],
        removed_modules: [],
        edited_modules: [impl_module]
      }

      patch(call_graph, ir_plt, diff)

      assert has_edge?(call_graph, from_vertex, {impl_module, :__impl__, 1})
      assert has_edge?(call_graph, from_vertex, {impl_module, :to_string, 1})
    end

    test "adds protocol dispatch edges when a protocol and its implementation are added together",
         %{empty_call_graph: call_graph} do
      ir_plt =
        PLT.start(
          items: [
            {Protocol1, IR.for_module(Protocol1)},
            {Protocol1.Integer, IR.for_module(Protocol1.Integer)}
          ]
        )

      diff = %{
        added_modules: [Protocol1, Protocol1.Integer],
        removed_modules: [],
        edited_modules: []
      }

      patch(call_graph, ir_plt, diff)

      assert has_edge?(call_graph, {Protocol1, :my_fun, 1}, {Protocol1.Integer, :__impl__, 1})
      assert has_edge?(call_graph, {Protocol1, :my_fun, 1}, {Protocol1.Integer, :my_fun, 1})
    end

    test "updates modules", %{empty_call_graph: call_graph} do
      module_9_ir = IR.for_module(Module9)
      module_10_ir = IR.for_module(Module10)

      ir_plt =
        PLT.start()
        |> PLT.put(Module9, module_9_ir)
        |> PLT.put(Module10, module_10_ir)

      call_graph
      |> add_edge({:module_3, :fun_c, :arity_c}, Module9)
      |> add_edge({:module_1, :fun_a, :arity_a}, {Module9, :my_fun_1, 0})
      |> add_edge({:module_2, :fun_b, :arity_b}, {Module9, :my_fun_2, 0})
      |> add_edge({:module_1, :fun_d, :arity_d}, Module9)
      |> add_edge({Module9, :my_fun_3, 2}, {:module_4, :fun_e, :arity_e})
      |> add_edge({Module10, :my_fun_4, 2}, {:module_5, :fun_f, :arity_f})

      diff = %{
        added_modules: [],
        removed_modules: [],
        edited_modules: [Module9, Module10]
      }

      patch(call_graph, ir_plt, diff)

      assert sorted_vertices(call_graph) == [
               Module9,
               {Module10, :my_fun_3, 0},
               {Module10, :my_fun_4, 0},
               {Module9, :my_fun_1, 0},
               {Module9, :my_fun_2, 0},
               {:module_1, :fun_a, :arity_a},
               {:module_1, :fun_d, :arity_d},
               {:module_2, :fun_b, :arity_b},
               {:module_3, :fun_c, :arity_c},
               {:module_4, :fun_e, :arity_e},
               {:module_5, :fun_f, :arity_f}
             ]

      assert sorted_edges(call_graph) == [
               {{Module10, :my_fun_3, 0}, {Module10, :my_fun_4, 0}},
               {{Module9, :my_fun_1, 0}, {Module9, :my_fun_2, 0}},
               {{:module_1, :fun_a, :arity_a}, {Module9, :my_fun_1, 0}},
               {{:module_1, :fun_d, :arity_d}, Module9},
               {{:module_2, :fun_b, :arity_b}, {Module9, :my_fun_2, 0}},
               {{:module_3, :fun_c, :arity_c}, Module9}
             ]
    end

    test "forgets a removed module", %{empty_call_graph: call_graph} do
      call_graph
      |> build(IR.for_module(Module9))
      |> build(IR.for_module(Module10))

      diff = %{added_modules: [], removed_modules: [Module9], edited_modules: []}
      patch(call_graph, PLT.start(), diff)

      assert modules(call_graph) == MapSet.new([Module10])
    end

    test "keeps an edited module", %{empty_call_graph: call_graph} do
      module_9_ir = IR.for_module(Module9)
      ir_plt = PLT.put(PLT.start(), Module9, module_9_ir)

      build(call_graph, module_9_ir)

      diff = %{added_modules: [], removed_modules: [], edited_modules: [Module9]}
      patch(call_graph, ir_plt, diff)

      assert modules(call_graph) == MapSet.new([Module9])
    end

    test "records an added module", %{empty_call_graph: call_graph} do
      ir_plt = PLT.put(PLT.start(), Module9, IR.for_module(Module9))

      diff = %{added_modules: [Module9], removed_modules: [], edited_modules: []}
      patch(call_graph, ir_plt, diff)

      assert modules(call_graph) == MapSet.new([Module9])
    end

    test "patching again with the same diff gives the same graph", %{empty_call_graph: call_graph} do
      ir_plt =
        PLT.start()
        |> PLT.put(Module9, IR.for_module(Module9))
        |> PLT.put(Module10, IR.for_module(Module10))

      call_graph
      |> add_edge({:module_1, :fun_a, :arity_a}, {Module9, :my_fun_1, 0})
      |> add_edge({:module_2, :fun_b, :arity_b}, {Module9, :my_fun_2, 0})
      |> add_edge({:module_3, :fun_c, :arity_c}, {:module_2, :fun_b, :arity_b})
      |> add_edge({Module9, :my_fun_3, 2}, {:module_4, :fun_d, :arity_d})

      diff = %{
        added_modules: [Module10],
        removed_modules: [:module_2],
        edited_modules: [Module9]
      }

      patch(call_graph, ir_plt, diff)
      graph_after_first_patch = get_graph(call_graph)

      patch(call_graph, ir_plt, diff)

      assert get_graph(call_graph) == graph_after_first_patch
    end

    test "removes the dynamic calls of a removed module", %{empty_call_graph: call_graph} do
      build(call_graph, IR.for_module(Module42))

      diff = %{added_modules: [], removed_modules: [Module42], edited_modules: []}
      patch(call_graph, PLT.start(), diff)

      assert vertices(call_graph) == []
    end

    test "replaces the dynamic calls of an edited module", %{empty_call_graph: call_graph} do
      build(call_graph, IR.for_module(Module42))

      # The edit takes the dynamic call out: the module now defines Module9's functions.
      edited_ir = %{IR.for_module(Module9) | module: %IR.AtomType{value: Module42}}
      ir_plt = PLT.put(PLT.start(), Module42, edited_ir)

      diff = %{added_modules: [], removed_modules: [], edited_modules: [Module42]}
      patch(call_graph, ir_plt, diff)

      assert sorted_vertices(call_graph) == [
               {Module42, :my_fun_1, 0},
               {Module42, :my_fun_2, 0}
             ]
    end
  end

  describe "protocol_dispatch_dependency_vertices/3" do
    test "retains dispatch helpers of reached protocol functions", %{
      full_call_graph: call_graph
    } do
      graph = get_graph(call_graph)

      result =
        protocol_dispatch_dependency_vertices(
          graph,
          [{String.Chars, :to_string, 1}],
          module_info_plt_fixture()
        )

      assert {String.Chars, :impl_for, 1} in result
      assert {String.Chars, :impl_for!, 1} in result
      assert {String.Chars, :struct_impl_for, 1} in result
      assert {Protocol.UndefinedError, :exception, 1} in result
    end

    test "doesn't pull protocol implementations", %{full_call_graph: call_graph} do
      graph = get_graph(call_graph)

      result =
        protocol_dispatch_dependency_vertices(
          graph,
          [{String.Chars, :to_string, 1}],
          module_info_plt_fixture()
        )

      refute {StringCharsModule12, :to_string, 1} in result
      refute {String.Chars.URI, :to_string, 1} in result
    end

    test "returns empty list when no protocol function vertices are given", %{
      full_call_graph: call_graph
    } do
      graph = get_graph(call_graph)

      assert protocol_dispatch_dependency_vertices(
               graph,
               [{Module5, :my_fun, 0}],
               module_info_plt_fixture()
             ) == []
    end
  end

  describe "protocol_dispatch_types/2" do
    test "includes built-in protocol dispatch types" do
      assert protocol_dispatch_types([], module_info_plt_fixture()) ==
               MapSet.new([
                 Any,
                 Atom,
                 BitString,
                 Float,
                 Function,
                 Integer,
                 List,
                 Map,
                 PID,
                 Port,
                 Reference,
                 Tuple
               ])
    end

    test "includes struct modules among module vertices" do
      assert Struct1 in protocol_dispatch_types([Struct1], module_info_plt_fixture())
    end

    test "excludes non-struct modules among module vertices" do
      refute Module1 in protocol_dispatch_types([Module1], module_info_plt_fixture())
    end

    test "excludes non-alias atom vertices" do
      refute :abc in protocol_dispatch_types([:abc], module_info_plt_fixture())
    end

    test "includes modules of __struct__/0 MFAs" do
      assert Struct1 in protocol_dispatch_types(
               [{Struct1, :__struct__, 0}],
               module_info_plt_fixture()
             )
    end

    test "includes modules of __struct__/1 MFAs" do
      assert Struct1 in protocol_dispatch_types(
               [{Struct1, :__struct__, 1}],
               module_info_plt_fixture()
             )
    end

    test "excludes modules of MFAs other than __struct__/0 and __struct__/1" do
      refute Struct1 in protocol_dispatch_types(
               [{Struct1, :my_fun, 1}],
               module_info_plt_fixture()
             )
    end
  end

  describe "protocol_function_mfa?/2" do
    test "function its protocol defines" do
      assert protocol_function_mfa?({Protocol1, :my_fun, 1}, module_info_plt_fixture())
    end

    test "dispatch helper of a protocol" do
      refute protocol_function_mfa?({Protocol1, :impl_for, 1}, module_info_plt_fixture())
    end

    test "function of a module that is no protocol" do
      refute protocol_function_mfa?({Module5, :my_fun, 0}, module_info_plt_fixture())
    end

    test "module vertex" do
      refute protocol_function_mfa?(Protocol1, module_info_plt_fixture())
    end
  end

  test "put_graph", %{empty_call_graph: call_graph} do
    build(call_graph, IR.for_module(Module9))
    graph = Digraph.add_edge(Digraph.new(), :vertex_3, :vertex_4)

    assert put_graph(call_graph, graph) == call_graph
    assert get_graph(call_graph) == graph
    assert modules(call_graph) == MapSet.new([Module9])
  end

  describe "reachable_mfas/4" do
    test "drops MFAs of Elixir-named modules the module info PLT does not know and keeps Erlang ones" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module5, :my_fun, 0}, {Collectable.Atom, :into, 1})
        |> Digraph.add_edge({Module5, :my_fun, 0}, {:lists, :reverse, 1})

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      assert Enum.sort(result) == [{Module5, :my_fun, 0}, {:lists, :reverse, 1}]
    end

    test "drops every Elixir-named MFA without a module info PLT" do
      graph = Digraph.add_edge(Digraph.new(), {Module5, :my_fun, 0}, {:lists, :reverse, 1})

      assert reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), nil) == [
               {:lists, :reverse, 1}
             ]
    end

    test "includes implementations for built-in types when their protocol is reached", %{
      full_call_graph: full_call_graph
    } do
      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, {Protocol1, :my_fun, 1})
        |> get_graph()

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      assert {Protocol1, :my_fun, 1} in result
      assert {Protocol1.Integer, :__impl__, 1} in result
      assert {Protocol1.Integer, :my_fun, 1} in result
    end

    test "excludes implementations whose struct type is not reachable", %{
      full_call_graph: full_call_graph
    } do
      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, {Protocol1, :my_fun, 1})
        |> get_graph()

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      struct_1_impl = Module.safe_concat(Protocol1, Struct1)

      refute {struct_1_impl, :__impl__, 1} in result
      refute {struct_1_impl, :my_fun, 1} in result
    end

    test "includes implementations whose struct type is reachable", %{
      full_call_graph: full_call_graph
    } do
      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, {Protocol1, :my_fun, 1})
        |> add_edge({Module5, :my_fun, 0}, Struct1)
        |> get_graph()

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      struct_1_impl = Module.safe_concat(Protocol1, Struct1)

      assert {struct_1_impl, :__impl__, 1} in result
      assert {struct_1_impl, :my_fun, 1} in result
    end

    test "includes implementations whose struct type is in the extra types", %{
      full_call_graph: full_call_graph
    } do
      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, {Protocol1, :my_fun, 1})
        |> get_graph()

      extra_types = MapSet.new([Struct1])

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], extra_types, module_info_plt_fixture())

      struct_1_impl = Module.safe_concat(Protocol1, Struct1)

      assert {struct_1_impl, :__impl__, 1} in result
      assert {struct_1_impl, :my_fun, 1} in result
    end

    test "reaches fixpoint when implementation code makes further types reachable", %{
      full_call_graph: full_call_graph
    } do
      struct_1_impl = Module.safe_concat(Protocol1, Struct1)

      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, {Protocol1, :my_fun, 1})
        |> add_edge({Module5, :my_fun, 0}, {String.Chars, :to_string, 1})
        |> add_edge({Module5, :my_fun, 0}, Struct1)
        |> add_edge({struct_1_impl, :my_fun, 1}, Module12)
        |> get_graph()

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      assert {StringCharsModule12, :__impl__, 1} in result
      assert {StringCharsModule12, :to_string, 1} in result
    end

    test "includes an implementation reached both directly and via dispatch exactly once", %{
      full_call_graph: full_call_graph
    } do
      struct_1_impl = Module.safe_concat(Protocol1, Struct1)

      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, {Protocol1, :my_fun, 1})
        |> add_edge({Module5, :my_fun, 0}, {struct_1_impl, :my_fun, 1})
        |> add_edge({Module5, :my_fun, 0}, Struct1)
        |> get_graph()

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      assert Enum.count(result, &(&1 == {struct_1_impl, :my_fun, 1})) == 1
    end

    test "retains dispatch helper MFAs of reached protocols", %{
      full_call_graph: full_call_graph
    } do
      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, {String.Chars, :to_string, 1})
        |> get_graph()

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      assert {String.Chars, :impl_for, 1} in result
      assert {String.Chars, :impl_for!, 1} in result
      assert {String.Chars, :struct_impl_for, 1} in result
      assert {Protocol.UndefinedError, :exception, 1} in result
    end

    test "excludes module vertices from the result", %{full_call_graph: full_call_graph} do
      graph =
        full_call_graph
        |> CallGraph.clone()
        |> add_edge({Module5, :my_fun, 0}, Struct1)
        |> get_graph()

      result =
        reachable_mfas(graph, [{Module5, :my_fun, 0}], MapSet.new(), module_info_plt_fixture())

      refute Enum.any?(result, &is_atom/1)
    end
  end

  test "remote_incoming_edges/2", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge({:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b})
    |> add_edge({:module_3, :fun_c, :arity_c}, {:module_2, :fun_d, :arity_d})
    |> add_edge({:module_4, :fun_e, :arity_e}, :module_2)
    |> add_edge({:module_5, :fun_f, :arity_f}, :module_2)
    |> add_edge({:module_6, :fun_g, :arity_g}, {:module_7, :fun_h, :arity_h})
    |> add_edge({:module_8, :fun_i, :arity_i}, :module_9)

    result =
      call_graph
      |> remote_incoming_edges(:module_2)
      |> Enum.sort()

    assert result == [
             {{:module_1, :fun_a, :arity_a}, {:module_2, :fun_b, :arity_b}},
             {{:module_3, :fun_c, :arity_c}, {:module_2, :fun_d, :arity_d}},
             {{:module_4, :fun_e, :arity_e}, :module_2},
             {{:module_5, :fun_f, :arity_f}, :module_2}
           ]
  end

  describe "remove_manually_ported_mfas/1" do
    setup %{full_call_graph: call_graph} do
      call_graph_clone =
        call_graph
        |> CallGraph.clone()
        |> remove_manually_ported_mfas()

      [call_graph: call_graph_clone]
    end

    test "excludes Elixir functions which are ported manually", %{call_graph: call_graph} do
      refute CallGraph.has_vertex?(call_graph, {Kernel, :inspect, 1})
    end

    test "includes functions which are not ported manually", %{call_graph: call_graph} do
      assert CallGraph.has_vertex?(call_graph, {Kernel, :hd, 1})
    end
  end

  describe "remove_runtime_mfas!/2" do
    test "removes the runtime MFAs and keeps the rest", %{ir_plt: ir_plt} do
      call_graph = Compiler.build_call_graph(ir_plt)
      runtime_mfas = list_runtime_mfas(call_graph, Reflection.list_pages())

      CallGraph.add_edge(call_graph, :my_vertex_1, :my_vertex_2)

      CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

      assert CallGraph.has_edge?(call_graph, :my_vertex_1, :my_vertex_2)

      Enum.each(runtime_mfas, fn mfa ->
        refute CallGraph.has_vertex?(call_graph, mfa)
      end)
    end

    test "gives the graph removing the vertices gives", %{
      full_call_graph: full_call_graph,
      runtime_mfas: runtime_mfas
    } do
      expected =
        full_call_graph
        |> CallGraph.get_graph()
        |> Digraph.remove_vertices(runtime_mfas)

      result =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> CallGraph.get_graph()

      assert runtime_mfas != []
      assert result == expected
    end

    test "leaves no empty neighbour map", %{
      full_call_graph: full_call_graph,
      runtime_mfas: runtime_mfas
    } do
      graph =
        full_call_graph
        |> CallGraph.clone()
        |> remove_runtime_mfas!(runtime_mfas)
        |> CallGraph.get_graph()

      assert Enum.all?(graph.outgoing_edges, fn {_vertex, targets} -> map_size(targets) > 0 end)
      assert Enum.all?(graph.incoming_edges, fn {_vertex, sources} -> map_size(sources) > 0 end)
    end
  end

  test "remove_vertex/2", %{empty_call_graph: call_graph} do
    call_graph
    |> add_vertex(:vertex_1)
    |> add_vertex(:vertex_2)
    |> add_vertex(:vertex_3)
    |> add_edge(:vertex_1, :vertex_2)
    |> add_edge(:vertex_2, :vertex_3)
    |> add_edge(:vertex_3, :vertex_1)
    |> remove_vertex(:vertex_2)

    assert has_vertex?(call_graph, :vertex_1)
    refute has_vertex?(call_graph, :vertex_2)
    assert has_vertex?(call_graph, :vertex_3)

    refute has_edge?(call_graph, :vertex_1, :vertex_2)
    refute has_edge?(call_graph, :vertex_2, :vertex_3)
    assert has_edge?(call_graph, :vertex_3, :vertex_1)
  end

  test "remove_vertices/2", %{empty_call_graph: call_graph} do
    call_graph
    |> add_vertex(:vertex_1)
    |> add_vertex(:vertex_2)
    |> add_vertex(:vertex_3)
    |> add_vertex(:vertex_4)
    |> add_edge(:vertex_1, :vertex_2)
    |> add_edge(:vertex_2, :vertex_3)
    |> add_edge(:vertex_3, :vertex_4)
    |> add_edge(:vertex_4, :vertex_1)
    |> remove_vertices([:vertex_2, :vertex_3])

    assert has_vertex?(call_graph, :vertex_1)
    refute has_vertex?(call_graph, :vertex_2)
    refute has_vertex?(call_graph, :vertex_3)
    assert has_vertex?(call_graph, :vertex_4)

    refute has_edge?(call_graph, :vertex_1, :vertex_2)
    refute has_edge?(call_graph, :vertex_2, :vertex_3)
    refute has_edge?(call_graph, :vertex_3, :vertex_4)
    assert has_edge?(call_graph, :vertex_4, :vertex_1)
  end

  # How the runtime's dynamic calls are resolved is tested with Hologram.Compiler.DynamicCallGate.
  describe "runtime_dynamic_calls/3" do
    test "opens the reflection functions the runtime's functions call on unnamed modules", %{
      empty_call_graph: call_graph
    } do
      # No runtime function calls either function, so their parameters can hold anything.
      call_graph
      |> build(IR.for_module(Module42))
      |> add_edge(
        {:module_1, :fun_a, 1},
        {:dynamic_call, {:module_1, :fun_a, 1}, :__struct__, 1, :open}
      )
      |> add_edge(
        {:module_1, :fun_a, 1},
        {:dynamic_call, {:module_1, :fun_a, 1}, :__schema__, 2, {:param, 0}}
      )

      runtime_mfas = [{Module42, :my_fun, 1}, {:module_1, :fun_a, 1}]
      result = runtime_dynamic_calls(call_graph, runtime_mfas, PLT.start())

      assert result == %{
               exposed: %{},
               open: MapSet.new([{:__changeset__, 0}, {:__schema__, 2}, {:__struct__, 1}]),
               page_callers: %{}
             }
    end

    test "ignores the dynamic calls of functions outside the runtime", %{
      empty_call_graph: call_graph
    } do
      call_graph
      |> build(IR.for_module(Module42))
      |> add_vertex({:module_1, :fun_a, 1})

      assert runtime_dynamic_calls(call_graph, [{:module_1, :fun_a, 1}], PLT.start()) == %{
               exposed: %{},
               open: MapSet.new(),
               page_callers: %{}
             }
    end
  end

  describe "server_callback_analysis_by_templatable/4" do
    test "with a data flow context, a struct server code builds and drops is no dispatch type" do
      analysis =
        server_callback_analysis_by_templatable(
          data_flow_page_graph(),
          [DataFlowPage],
          module_info_plt_fixture(),
          data_flow_fixture()
        )

      refute DroppedStruct in analysis[DataFlowPage].dispatch_types
      assert StateStruct in analysis[DataFlowPage].dispatch_types
    end

    test "without a data flow context, a struct server code names is a dispatch type" do
      analysis =
        server_callback_analysis_by_templatable(
          data_flow_page_graph(),
          [DataFlowPage],
          module_info_plt_fixture()
        )

      assert DroppedStruct in analysis[DataFlowPage].dispatch_types
    end

    test "returns an entry for each given templatable" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :init, 3}, Struct1)
        |> Digraph.add_edge({Module4, :command, 3}, Module12)

      result =
        server_callback_analysis_by_templatable(
          graph,
          [Module2, Module4],
          module_info_plt_fixture()
        )

      analyzed_templatables =
        result
        |> Map.keys()
        |> Enum.sort()

      assert analyzed_templatables == [Module2, Module4]
    end

    test "harvests dispatch types from the templatable's own server entries only" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :init, 3}, Struct1)
        |> Digraph.add_edge({Module4, :command, 3}, Module12)

      result =
        server_callback_analysis_by_templatable(
          graph,
          [Module2, Module4],
          module_info_plt_fixture()
        )

      assert Struct1 in result[Module2].dispatch_types
      refute Module12 in result[Module2].dispatch_types

      assert Module12 in result[Module4].dispatch_types
      refute Struct1 in result[Module4].dispatch_types
    end

    test "collects component modules referenced in the templatable's own server callbacks" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :init, 3}, Module15)
        |> Digraph.add_edge({Module4, :command, 3}, Module3)

      result =
        server_callback_analysis_by_templatable(
          graph,
          [Module2, Module4],
          module_info_plt_fixture()
        )

      assert result[Module2].server_referenced_components == [Module15]
      assert result[Module4].server_referenced_components == [Module3]
    end

    test "doesn't collect non-component modules referenced in server callbacks" do
      graph = Digraph.add_edge(Digraph.new(), {Module2, :init, 3}, Module5)

      result =
        server_callback_analysis_by_templatable(graph, [Module2], module_info_plt_fixture())

      assert result[Module2].server_referenced_components == []
    end

    test "doesn't collect page modules referenced in server callbacks" do
      graph = Digraph.add_edge(Digraph.new(), {Module2, :init, 3}, Module14)

      result =
        server_callback_analysis_by_templatable(graph, [Module2], module_info_plt_fixture())

      assert result[Module2].server_referenced_components == []
    end

    test "doesn't collect component modules reachable only through protocol function vertices" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :init, 3}, {Protocol1, :my_fun, 1})
        |> Digraph.add_edge({Protocol1, :my_fun, 1}, Module15)

      result =
        server_callback_analysis_by_templatable(graph, [Module2], module_info_plt_fixture())

      assert result[Module2].server_referenced_components == []
    end
  end

  describe "server_protocol_dispatch_types/4" do
    test "with a data flow context, the types come from the data flow analyses" do
      types =
        server_protocol_dispatch_types(
          data_flow_page_graph(),
          [DataFlowPage],
          module_info_plt_fixture(),
          data_flow_fixture()
        )

      refute DroppedStruct in types
      assert StateStruct in types
    end

    test "without a data flow context, a struct server code names is a dispatch type" do
      types =
        server_protocol_dispatch_types(
          data_flow_page_graph(),
          [DataFlowPage],
          module_info_plt_fixture()
        )

      assert DroppedStruct in types
    end

    test "includes struct types reachable from init/3" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :init, 3}, {Module5, :my_fun, 0})
        |> Digraph.add_edge({Module5, :my_fun, 0}, Struct1)

      assert Struct1 in server_protocol_dispatch_types(
               graph,
               [Module2],
               module_info_plt_fixture()
             )
    end

    test "includes struct types reachable from command/3" do
      graph = Digraph.add_edge(Digraph.new(), {Module2, :command, 3}, {Struct1, :__struct__, 1})

      assert Struct1 in server_protocol_dispatch_types(
               graph,
               [Module2],
               module_info_plt_fixture()
             )
    end

    test "harvests types from all given templatables" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :init, 3}, Struct1)
        |> Digraph.add_edge({Module4, :command, 3}, Module12)

      result =
        server_protocol_dispatch_types(graph, [Module2, Module4], module_info_plt_fixture())

      assert Struct1 in result
      assert Module12 in result
    end

    test "returns only built-in types when init/3 and command/3 vertices don't exist" do
      graph = Digraph.add_edge(Digraph.new(), {Module5, :my_fun, 0}, Struct1)

      assert server_protocol_dispatch_types(graph, [Module2], module_info_plt_fixture()) ==
               protocol_dispatch_types([], module_info_plt_fixture())
    end

    test "doesn't traverse through protocol function vertices" do
      graph =
        Digraph.new()
        |> Digraph.add_edge({Module2, :init, 3}, {Protocol1, :my_fun, 1})
        |> Digraph.add_edge({Protocol1, :my_fun, 1}, Struct1)

      refute Struct1 in server_protocol_dispatch_types(
               graph,
               [Module2],
               module_info_plt_fixture()
             )
    end
  end

  test "sorted_edges/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    assert sorted_edges(call_graph) == [
             {:vertex_2, :vertex_3},
             {:vertex_4, :vertex_5}
           ]
  end

  test "sorted_vertices/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    assert sorted_vertices(call_graph) == [:vertex_1, :vertex_2, :vertex_3, :vertex_4, :vertex_5]
  end

  describe "start/1" do
    test "default graph opt" do
      assert %CallGraph{pid: pid} = call_graph = start()
      assert is_pid(pid)
      assert get_graph(call_graph) == Digraph.new()
    end

    test "graph opt specified" do
      graph = Digraph.add_vertex(Digraph.new(), :my_vertex)

      assert %CallGraph{pid: pid} = call_graph = start(graph: graph)
      assert is_pid(pid)
      assert get_graph(call_graph) == graph
    end

    test "default modules opt" do
      assert modules(start()) == MapSet.new()
    end

    test "modules opt specified" do
      modules = MapSet.new([Module9])

      assert modules(start(modules: modules)) == modules
    end

    test "default module_info_plt opt" do
      assert %CallGraph{module_info_plt: nil} = start()
    end

    test "module_info_plt opt specified" do
      module_info_plt = PLT.start()

      assert %CallGraph{module_info_plt: ^module_info_plt} =
               start(module_info_plt: module_info_plt)
    end
  end

  test "stop/1" do
    %{pid: pid} = call_graph = start()

    assert stop(call_graph) == :ok
    refute Process.alive?(pid)
  end

  describe "unbounded_reachable_mfas/2" do
    setup do
      # 1
      # ├─ {Module2, :f2, 2}
      # │  ├─ 4
      # │  │  ├─ {Module8, :f8, 8}
      # │  │  ├─ 9
      # │  ├─ {Module5, :f5, 5}
      # │  │  ├─ 10
      # │  │  ├─ 11
      # ├─ {Module3, :f3, 3}
      # │  ├─ 6
      # │  │  ├─ {Module11, :f12, 12}
      # │  │  ├─ 13
      # │  ├─ {Module7, :f7, 7}
      # │  │  ├─ 14
      # │  │  ├─ {Module15, :f15, 15}
      # |  |  |- {Collectable.Atom, :fca, 123}

      graph =
        Digraph.new()
        |> Digraph.add_edge(:vertex_1, {Module2, :f2, 2})
        |> Digraph.add_edge(:vertex_1, {Module3, :f3, 3})
        |> Digraph.add_edge({Module2, :f2, 2}, :vertex_4)
        |> Digraph.add_edge({Module2, :f2, 2}, {Module5, :f5, 5})
        |> Digraph.add_edge({Module3, :f3, 3}, :vertex_6)
        |> Digraph.add_edge({Module3, :f3, 3}, {Module7, :f7, 7})
        |> Digraph.add_edge(:vertex_4, {Module8, :f8, 8})
        |> Digraph.add_edge(:vertex_4, :vertex_9)
        |> Digraph.add_edge({Module5, :f5, 5}, :vertex_10)
        |> Digraph.add_edge({Module5, :f5, 5}, :vertex_11)
        |> Digraph.add_edge(:vertex_6, {Module11, :f12, 12})
        |> Digraph.add_edge(:vertex_6, :vertex_13)
        |> Digraph.add_edge({Module7, :f7, 7}, :vertex_14)
        |> Digraph.add_edge({Module7, :f7, 7}, {Module15, :f15, 15})
        |> Digraph.add_edge({Module7, :f7, 7}, {Collectable.Atom, :fca, 123})

      [graph: graph]
    end

    test "single MFA argument", %{graph: graph} do
      result = unbounded_reachable_mfas(graph, [{Module3, :f3, 3}])

      assert Enum.sort(result) == [
               {Module11, :f12, 12},
               {Module15, :f15, 15},
               {Module3, :f3, 3},
               {Module7, :f7, 7}
             ]
    end

    test "multiple MFAs argument", %{graph: graph} do
      result = unbounded_reachable_mfas(graph, [{Module5, :f5, 5}, {Module3, :f3, 3}])

      assert Enum.sort(result) == [
               {Module11, :f12, 12},
               {Module15, :f15, 15},
               {Module3, :f3, 3},
               {Module5, :f5, 5},
               {Module7, :f7, 7}
             ]
    end
  end

  test "vertices/1", %{empty_call_graph: call_graph} do
    call_graph
    |> add_edge(:vertex_4, :vertex_5)
    |> add_vertex(:vertex_1)
    |> add_edge(:vertex_2, :vertex_3)

    result = vertices(call_graph)

    assert Enum.count(result) == 5
    assert :vertex_1 in result
    assert :vertex_2 in result
    assert :vertex_3 in result
    assert :vertex_4 in result
    assert :vertex_5 in result
  end

  describe "vertex_module/1" do
    test "MFA" do
      assert vertex_module({Module1, :my_fun, 2}) == Module1
    end

    test "module" do
      assert vertex_module(Module1) == Module1
    end

    test "dynamic call" do
      site = {:dynamic_call, {Module1, :my_fun, 2}, :__struct__, 0, :open}

      assert vertex_module(site) == Module1
    end
  end

  describe "with_shared_graph/2" do
    # The shared key under which the given graph is stored, found by the graph, which each test
    # makes unique with a fresh reference vertex, so tests running meanwhile cannot be mistaken
    # for it.
    defp shared_graph_key(graph) do
      Enum.find_value(:persistent_term.get(), fn
        {{CallGraph, _ref} = key, ^graph} -> key
        _other -> nil
      end)
    end

    setup %{empty_call_graph: call_graph} do
      add_edge(call_graph, make_ref(), :vertex_1)

      :ok
    end

    test "the reader returns the graph at the time of the call", %{empty_call_graph: call_graph} do
      graph = get_graph(call_graph)

      assert with_shared_graph(call_graph, fn read_graph -> read_graph.() end) == graph
    end

    test "edits made after the call are not seen", %{empty_call_graph: call_graph} do
      graph = get_graph(call_graph)

      with_shared_graph(call_graph, fn read_graph ->
        add_edge(call_graph, :vertex_2, :vertex_3)

        assert read_graph.() == graph
        assert get_graph(call_graph) != graph
      end)
    end

    test "every process reads the same graph", %{empty_call_graph: call_graph} do
      with_shared_graph(call_graph, fn read_graph ->
        task = Task.async(fn -> read_graph.() end)

        assert Task.await(task) == read_graph.()
      end)
    end

    test "releases the graph when the function returns", %{empty_call_graph: call_graph} do
      graph = get_graph(call_graph)

      key =
        with_shared_graph(call_graph, fn _read_graph ->
          shared_graph_key(graph)
        end)

      assert {CallGraph, _ref} = key
      assert :persistent_term.get(key, :released) == :released
    end

    test "releases the graph when the function raises", %{empty_call_graph: call_graph} do
      graph = get_graph(call_graph)

      assert_raise RuntimeError, "boom", fn ->
        with_shared_graph(call_graph, fn _read_graph ->
          Process.put(:shared_graph_key, shared_graph_key(graph))
          raise "boom"
        end)
      end

      key = Process.get(:shared_graph_key)

      assert {CallGraph, _ref} = key
      assert :persistent_term.get(key, :released) == :released
    end

    test "returns what the function returns", %{empty_call_graph: call_graph} do
      assert with_shared_graph(call_graph, fn _read_graph -> :result end) == :result
    end
  end

  # Consistency tests verifying that the Elixir IR patterns
  # assumed by the call graph still hold. If these fail after an
  # Elixir upgrade, the corresponding call graph code needs updating.
  describe "Elixir IR pattern assumptions" do
    defp find_fun_defs(ir_plt, module, name, arity) do
      %IR.ModuleDefinition{body: %IR.Block{expressions: expressions}} =
        PLT.get!(ir_plt, module)

      Enum.filter(expressions, &match?(%IR.FunctionDefinition{name: ^name, arity: ^arity}, &1))
    end

    # EEP-54 formatter resolution assumption: a raise site passing a literal
    # error_info option compiles to a keyword list of tuples whose error_info
    # value is a map with literal atom keys and values.
    test ":erlang.error/3 with a literal error_info option compiles to the IR shape the formatter resolution matches" do
      code =
        ~s/:erlang.error(:badarg, [:a], error_info: %{module: MyFormatter, function: :my_format_error})/

      assert IR.for_code(code, %Context{}) == %IR.RemoteFunctionCall{
               line: 1,
               module: %IR.AtomType{value: :erlang},
               function: :error,
               args: [
                 %IR.AtomType{value: :badarg},
                 %IR.ListType{data: [%IR.AtomType{value: :a}]},
                 %IR.ListType{
                   data: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :error_info},
                         %IR.MapType{
                           data: [
                             {%IR.AtomType{value: :module}, %IR.AtomType{value: MyFormatter}},
                             {%IR.AtomType{value: :function},
                              %IR.AtomType{value: :my_format_error}}
                           ]
                         }
                       ]
                     }
                   ]
                 }
               ]
             }
    end

    # Dynamic dispatch assumption: Date.day_of_era/1 extracts calendar from the struct
    # and calls `calendar.day_of_era(year, month, day)`.
    #
    # Original source:
    #   def day_of_era(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.day_of_era(year, month, day)
    #   end
    test "Date.day_of_era/1 dynamically dispatches calendar.day_of_era/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :day_of_era, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :day_of_era,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.day_of_week/2 extracts calendar from the struct
    # and calls `calendar.day_of_week(year, month, day, starting_on)`.
    #
    # Original source:
    #   def day_of_week(%{calendar: calendar, year: year, month: month, day: day}, starting_on) do
    #     {day_of_week, _first, _last} = calendar.day_of_week(year, month, day, starting_on)
    #     day_of_week
    #   end
    test "Date.day_of_week/2 dynamically dispatches calendar.day_of_week/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :day_of_week, 2)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   },
                   _starting_on
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :day_of_week,
                         args: [_year_arg, _month_arg, _day_arg, _starting_on_arg]
                       }
                     },
                     _result
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.day_of_year/1 extracts calendar from the struct
    # and calls `calendar.day_of_year(year, month, day)`.
    #
    # Original source:
    #   def day_of_year(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.day_of_year(year, month, day)
    #   end
    test "Date.day_of_year/1 dynamically dispatches calendar.day_of_year/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :day_of_year, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :day_of_year,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.days_in_month/1 extracts calendar from the struct
    # and calls `calendar.days_in_month(year, month)`.
    #
    # Original source:
    #   def days_in_month(%{calendar: calendar, year: year, month: month}) do
    #     calendar.days_in_month(year, month)
    #   end
    test "Date.days_in_month/1 dynamically dispatches calendar.days_in_month/2",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :days_in_month, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :days_in_month,
                       args: [_year_arg, _month_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.leap_year?/1 extracts calendar from the struct
    # and calls `calendar.leap_year?(year)`.
    #
    # Original source:
    #   def leap_year?(%{calendar: calendar, year: year}) do
    #     calendar.leap_year?(year)
    #   end
    test "Date.leap_year?/1 dynamically dispatches calendar.leap_year?/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :leap_year?, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :leap_year?,
                       args: [_year_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.months_in_year/1 extracts calendar from the struct
    # and calls `calendar.months_in_year(year)`.
    #
    # Original source:
    #   def months_in_year(%{calendar: calendar, year: year}) do
    #     calendar.months_in_year(year)
    #   end
    test "Date.months_in_year/1 dynamically dispatches calendar.months_in_year/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :months_in_year, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :months_in_year,
                       args: [_year_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Default param assumption: Date.new/3 is the generated clause that fills in the
    # Calendar.ISO default and calls Date.new/4. The Calendar.ISO atom appears in the body
    # as data (not a dispatch target).
    #
    # Generated from: def new(year, month, day, calendar \\ Calendar.ISO)
    #
    # Expanded:
    #   def new(x0, x1, x2), do: new(x0, x1, x2, Calendar.ISO)
    test "Date.new/3 fills in Calendar.ISO default and calls Date.new/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :new, 3)

      # The clause and the call in its body point into Elixir's own source, so
      # their lines depend on the Elixir version - neutralize them before the
      # exact comparison.
      [call] = fun_def.clause.body.expressions
      body = %{fun_def.clause.body | expressions: [%{call | line: nil}]}
      fun_def = %{fun_def | clause: %{fun_def.clause | line: nil, body: body}}

      assert fun_def == %IR.FunctionDefinition{
               name: :new,
               arity: 3,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.Variable{name: :x0, version: 0},
                   %IR.Variable{name: :x1, version: 1},
                   %IR.Variable{name: :x2, version: 2}
                 ],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.LocalFunctionCall{
                       function: :new,
                       args: [
                         %IR.Variable{name: :x0, version: 0},
                         %IR.Variable{name: :x1, version: 1},
                         %IR.Variable{name: :x2, version: 2},
                         %IR.AtomType{value: Calendar.ISO}
                       ]
                     }
                   ]
                 },
                 blame: %{params: ["x0", "x1", "x2"], guards: []}
               }
             }
    end

    # Dynamic dispatch assumption: Date.new/4 has `calendar \\ Calendar.ISO` and calls
    # `calendar.valid_date?(year, month, day)` where calendar is a variable, not a literal
    # module atom. This call can't be discovered from static IR analysis, so we add a
    # manual edge in @dynamic_dispatch_edges.
    #
    # Original source:
    #   def new(year, month, day, calendar \\ Calendar.ISO) do
    #     if calendar.valid_date?(year, month, day) do
    #       {:ok, %Date{year: year, month: month, day: day, calendar: calendar}}
    #     else
    #       {:error, :invalid_date}
    #     end
    #   end
    test "Date.new/4 dynamically dispatches calendar.valid_date?/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :new, 4)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_year, _month, _day, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     %IR.Case{
                       condition: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :valid_date?,
                         args: [_year_arg, _month_arg, _day_arg]
                       }
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.quarter_of_year/1 extracts calendar from the struct
    # and calls `calendar.quarter_of_year(year, month, day)`.
    #
    # Original source:
    #   def quarter_of_year(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.quarter_of_year(year, month, day)
    #   end
    test "Date.quarter_of_year/1 dynamically dispatches calendar.quarter_of_year/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :quarter_of_year, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :quarter_of_year,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.shift/2 extracts calendar from the struct
    # and calls `calendar.shift_date(year, month, day, duration)`.
    # Date.shift/2 was added in Elixir 1.17.0.
    #
    # Original source:
    #   def shift(%{calendar: calendar} = date, duration) do
    #     %{year: year, month: month, day: day} = date
    #     {year, month, day} = calendar.shift_date(year, month, day, __duration__!(duration))
    #     %Date{calendar: calendar, year: year, month: month, day: day}
    #   end
    if Version.match?(System.version(), ">= 1.17.0") do
      test "Date.shift/2 dynamically dispatches calendar.shift_date/4",
           %{ir_plt: ir_plt} do
        assert [fun_def] = find_fun_defs(ir_plt, Date, :shift, 2)

        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   params: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                       }
                     },
                     _duration
                   ],
                   body: %IR.Block{
                     expressions: [
                       _destructure,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_date,
                           args: [_year, _month, _day, _duration_arg]
                         }
                       },
                       _result
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: Date.to_string/1 extracts calendar from the struct
    # and calls `calendar.date_to_string(year, month, day)`.
    #
    # Original source:
    #   def to_string(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.date_to_string(year, month, day)
    #   end
    test "Date.to_string/1 dynamically dispatches calendar.date_to_string/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :date_to_string,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Date.year_of_era/1 extracts calendar from the struct
    # and calls `calendar.year_of_era(year, month, day)`.
    #
    # Original source (Elixir >= 1.18):
    #   def year_of_era(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.year_of_era(year, month, day)
    #   end
    #
    # Original source (Elixir < 1.18):
    #   def year_of_era(%{calendar: calendar, year: year, month: month, day: day}) do
    #     if function_exported?(calendar, :year_of_era, 3) do
    #       calendar.year_of_era(year, month, day)
    #     else
    #       calendar.year_of_era(year)
    #     end
    #   end
    test "Date.year_of_era/1 dynamically dispatches calendar.year_of_era/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Date, :year_of_era, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ]
               }
             } = fun_def

      if Version.match?(System.version(), ">= 1.18.0") do
        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   body: %IR.Block{
                     expressions: [
                       %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :year_of_era,
                         args: [_year_arg, _month_arg, _day_arg]
                       }
                     ]
                   }
                 }
               } = fun_def
      else
        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   body: %IR.Block{
                     expressions: [
                       %IR.Case{
                         condition: %IR.RemoteFunctionCall{
                           function: :function_exported,
                           args: [
                             %IR.Variable{name: :calendar},
                             %IR.AtomType{value: :year_of_era},
                             %IR.IntegerType{value: 3}
                           ]
                         }
                       }
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: DateTime.from_gregorian_seconds/3 receives calendar
    # as a parameter (default Calendar.ISO) and calls
    # `calendar.naive_datetime_from_iso_days(iso_days)`.
    #
    # Original source:
    #   def from_gregorian_seconds(seconds, {microsecond, precision} \\ {0, 0},
    #         calendar \\ Calendar.ISO) when is_integer(seconds) do
    #     iso_days = Calendar.ISO.gregorian_seconds_to_iso_days(seconds, microsecond)
    #     {year, month, day, hour, minute, second, {microsecond, _}} =
    #       calendar.naive_datetime_from_iso_days(iso_days)
    #     ...
    #   end
    test "DateTime.from_gregorian_seconds/3 dynamically dispatches calendar.naive_datetime_from_iso_days/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, DateTime, :from_gregorian_seconds, 3)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_seconds, _microsecond, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     _iso_days_assignment,
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :naive_datetime_from_iso_days,
                         args: [_iso_days]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: DateTime.from_iso_days/4 (private) receives calendar
    # as a parameter and calls `calendar.naive_datetime_from_iso_days(iso_days)`.
    #
    # Original source:
    #   defp from_iso_days(iso_days, datetime, calendar, precision) do
    #     %{time_zone: time_zone, zone_abbr: zone_abbr, utc_offset: utc_offset,
    #       std_offset: std_offset} = datetime
    #     {year, month, day, hour, minute, second, {microsecond, _}} =
    #       calendar.naive_datetime_from_iso_days(iso_days)
    #     ...
    #   end
    test "DateTime.from_iso_days/4 dynamically dispatches calendar.naive_datetime_from_iso_days/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, DateTime, :from_iso_days, 4)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_iso_days, _datetime, %IR.Variable{name: :calendar}, _precision],
                 body: %IR.Block{
                   expressions: [
                     _datetime_destructure,
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :naive_datetime_from_iso_days,
                         args: [_iso_days_arg]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: DateTime.shift/3 extracts calendar from the struct and
    # calls `calendar.shift_naive_datetime(...)` (both clauses) and
    # `calendar.naive_datetime_to_iso_days(...)` (non-UTC clause).
    # DateTime.shift/3 was added in Elixir 1.17.0.
    #
    # Original source (UTC clause):
    #   def shift(%{calendar: calendar, time_zone: "Etc/UTC"} = datetime, duration, _) do
    #     ...
    #     {year, month, day, hour, minute, second, microsecond} =
    #       calendar.shift_naive_datetime(year, month, day, hour, minute, second,
    #         microsecond, __duration__!(duration))
    #     ...
    #   end
    #
    # Original source (non-UTC clause):
    #   def shift(%{calendar: calendar} = datetime, duration, time_zone_database) do
    #     ...
    #     {year, month, day, hour, minute, second, {_, precision} = microsecond} =
    #       calendar.shift_naive_datetime(...)
    #     result =
    #       calendar.naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond)
    #       |> ...
    #   end
    if Version.match?(System.version(), ">= 1.17.0") do
      test "DateTime.shift/3 dynamically dispatches calendar.shift_naive_datetime/8 and calendar.naive_datetime_to_iso_days/7",
           %{ir_plt: ir_plt} do
        fun_defs = find_fun_defs(ir_plt, DateTime, :shift, 3)
        assert [utc_clause, non_utc_clause] = fun_defs

        # UTC clause: calendar.shift_naive_datetime(...)
        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   body: %IR.Block{
                     expressions: [
                       _destructure,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_naive_datetime,
                           args: [
                             _year,
                             _month,
                             _day,
                             _hour,
                             _minute,
                             _second,
                             _microsecond,
                             _duration
                           ]
                         }
                       }
                       | _rest
                     ]
                   }
                 }
               } = utc_clause

        # Non-UTC clause: calendar.shift_naive_datetime(...) and
        # calendar.naive_datetime_to_iso_days(...) piped through apply_tz_offset
        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   body: %IR.Block{
                     expressions: [
                       _destructure2,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_naive_datetime,
                           args: [
                             _year2,
                             _month2,
                             _day2,
                             _hour2,
                             _minute2,
                             _second2,
                             _microsecond2,
                             _duration2
                           ]
                         }
                       },
                       %IR.MatchOperator{
                         right: %IR.LocalFunctionCall{
                           function: :shift_zone_for_iso_days_utc,
                           args: [
                             %IR.LocalFunctionCall{
                               function: :apply_tz_offset,
                               args: [
                                 %IR.RemoteFunctionCall{
                                   module: %IR.Variable{name: :calendar},
                                   function: :naive_datetime_to_iso_days,
                                   args: [
                                     _year3,
                                     _month3,
                                     _day3,
                                     _hour3,
                                     _minute3,
                                     _second3,
                                     _microsecond3
                                   ]
                                 },
                                 _offset
                               ]
                             }
                             | _shift_zone_args
                           ]
                         }
                       }
                       | _rest2
                     ]
                   }
                 }
               } = non_utc_clause
      end
    end

    # Dynamic dispatch assumption: DateTime.shift_by_offset/2 (private) extracts calendar
    # from the struct and calls `calendar.naive_datetime_from_iso_days(iso_days)`.
    #
    # Original source:
    #   defp shift_by_offset(%{calendar: calendar} = datetime, offset) do
    #     total_offset = datetime.utc_offset + datetime.std_offset
    #     datetime
    #     |> to_iso_days()
    #     |> Calendar.ISO.add_day_fraction_to_iso_days(offset - total_offset, 86400)
    #     |> calendar.naive_datetime_from_iso_days()
    #   end
    test "DateTime.shift_by_offset/2 dynamically dispatches calendar.naive_datetime_from_iso_days/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, DateTime, :shift_by_offset, 2)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MatchOperator{
                     left: %IR.MapType{
                       data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                     }
                   },
                   _offset
                 ],
                 body: %IR.Block{
                   expressions: [
                     _total_offset,
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :naive_datetime_from_iso_days,
                       args: [_iso_days]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: DateTime.shift_zone_for_iso_days_utc/5 (private) receives
    # calendar as a parameter and calls `calendar.naive_datetime_from_iso_days(iso_days)`
    # inside the :ok clause of a case on time_zone_db.time_zone_period_from_utc_iso_days/2.
    #
    # Original source:
    #   defp shift_zone_for_iso_days_utc(iso_days_utc, calendar, precision, time_zone, time_zone_db) do
    #     case time_zone_db.time_zone_period_from_utc_iso_days(iso_days_utc, time_zone) do
    #       {:ok, %{std_offset: std_offset, utc_offset: utc_offset, zone_abbr: zone_abbr}} ->
    #         {year, month, day, hour, minute, second, {microsecond_without_precision, _}} =
    #           iso_days_utc
    #           |> apply_tz_offset(-(utc_offset + std_offset))
    #           |> calendar.naive_datetime_from_iso_days()
    #         ...
    #     end
    #   end
    test "DateTime.shift_zone_for_iso_days_utc/5 dynamically dispatches calendar.naive_datetime_from_iso_days/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, DateTime, :shift_zone_for_iso_days_utc, 5)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   _iso_days_utc,
                   %IR.Variable{name: :calendar},
                   _precision,
                   _time_zone,
                   _time_zone_db
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.Case{
                       clauses: [
                         %IR.Clause{
                           body: %IR.Block{
                             expressions: [
                               %IR.MatchOperator{
                                 right: %IR.RemoteFunctionCall{
                                   module: %IR.Variable{name: :calendar},
                                   function: :naive_datetime_from_iso_days,
                                   args: [_iso_days_arg]
                                 }
                               }
                               | _rest
                             ]
                           }
                         }
                         | _other_clauses
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: DateTime.to_iso_days/1 (private) extracts calendar
    # from the struct and calls `calendar.naive_datetime_to_iso_days(year, month, day,
    # hour, minute, second, microsecond)`.
    #
    # Original source:
    #   defp to_iso_days(%{calendar: calendar, year: year, month: month, day: day,
    #          hour: hour, minute: minute, second: second, microsecond: microsecond}) do
    #     calendar.naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond)
    #   end
    test "DateTime.to_iso_days/1 dynamically dispatches calendar.naive_datetime_to_iso_days/7",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, DateTime, :to_iso_days, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day},
                       {%IR.AtomType{value: :hour}, _hour},
                       {%IR.AtomType{value: :minute}, _minute},
                       {%IR.AtomType{value: :second}, _second},
                       {%IR.AtomType{value: :microsecond}, _microsecond}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :naive_datetime_to_iso_days,
                       args: [
                         _year_arg,
                         _month_arg,
                         _day_arg,
                         _hour_arg,
                         _minute_arg,
                         _second_arg,
                         _microsecond_arg
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: DateTime.to_string/1 extracts calendar from the struct
    # and calls `calendar.datetime_to_string(year, month, day, hour, minute, second,
    # microsecond, time_zone, zone_abbr, utc_offset, std_offset)`.
    #
    # Original source:
    #   def to_string(%{calendar: calendar} = datetime) do
    #     %{year: year, month: month, day: day, hour: hour, minute: minute,
    #       second: second, microsecond: microsecond, time_zone: time_zone,
    #       zone_abbr: zone_abbr, utc_offset: utc_offset, std_offset: std_offset} = datetime
    #     calendar.datetime_to_string(year, month, day, hour, minute, second,
    #       microsecond, time_zone, zone_abbr, utc_offset, std_offset)
    #   end
    test "DateTime.to_string/1 dynamically dispatches calendar.datetime_to_string/11",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, DateTime, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MatchOperator{
                     left: %IR.MapType{
                       data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                     }
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     _destructure,
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :datetime_to_string,
                       args: [
                         _year,
                         _month,
                         _day,
                         _hour,
                         _minute,
                         _second,
                         _microsecond,
                         _time_zone,
                         _zone_abbr,
                         _utc_offset,
                         _std_offset
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Inspect.Date.inspect/2 extracts calendar from the struct
    # and calls `calendar.date_to_string(year, month, day)`. Calendar.ISO dates with normal
    # years reach this clause in all Elixir versions:
    # - Elixir >= 1.18: guard `when calendar != Calendar.ISO or year in -9999..9999`
    # - Elixir 1.17: guard `when year in -9999..9999`
    # - Elixir < 1.17: no guard (single clause handles all dates)
    #
    # Original source (Elixir >= 1.18):
    #   def inspect(%{calendar: calendar, year: year, month: month, day: day}, _)
    #       when calendar != Calendar.ISO or year in -9999..9999 do
    #     "~D[" <> calendar.date_to_string(year, month, day) <> suffix(calendar) <> "]"
    #   end
    #
    # Original source (Elixir 1.17):
    #   def inspect(%{calendar: calendar, year: year, month: month, day: day}, _)
    #       when year in -9999..9999 do
    #     "~D[" <> calendar.date_to_string(year, month, day) <> suffix(calendar) <> "]"
    #   end
    #
    # Original source (Elixir < 1.17):
    #   def inspect(%{calendar: calendar, year: year, month: month, day: day}, _) do
    #     "~D[" <> calendar.date_to_string(year, month, day) <> suffix(calendar) <> "]"
    #   end
    test "Inspect.Date.inspect/2 dynamically dispatches calendar.date_to_string/3",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Inspect.Date, :inspect, 2)
      assert [first_clause | _rest] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   },
                   _opts
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.BitstringType{
                       segments: [
                         _prefix,
                         %IR.BitstringSegment{
                           value: %IR.RemoteFunctionCall{
                             module: %IR.Variable{name: :calendar},
                             function: :date_to_string,
                             args: [_year_arg, _month_arg, _day_arg]
                           }
                         },
                         _suffix,
                         _closing
                       ]
                     }
                   ]
                 }
               }
             } = first_clause

      cond do
        Version.match?(System.version(), ">= 1.18.0") ->
          assert [
                   %IR.RemoteFunctionCall{
                     function: :orelse,
                     args: [
                       %IR.RemoteFunctionCall{
                         function: :"/=",
                         args: [%IR.Variable{name: :calendar}, %IR.AtomType{value: Calendar.ISO}]
                       },
                       _year_range_check
                     ]
                   }
                 ] = first_clause.clause.guards

        Version.match?(System.version(), ">= 1.17.0") ->
          assert [
                   %IR.RemoteFunctionCall{
                     function: :andalso,
                     args: [
                       %IR.RemoteFunctionCall{
                         function: :is_integer,
                         args: [%IR.Variable{name: :year}]
                       },
                       _year_range_check
                     ]
                   }
                 ] = first_clause.clause.guards

        true ->
          assert [] = first_clause.clause.guards
      end
    end

    # Dynamic dispatch assumption: Inspect.DateTime.inspect/2 destructures calendar from
    # the struct in the body and calls `calendar.datetime_to_string(year, month, day, hour,
    # minute, second, microsecond, time_zone, zone_abbr, utc_offset, std_offset)`.
    #
    # Original source:
    #   def inspect(datetime, _) do
    #     %{year: year, month: month, day: day, hour: hour, minute: minute,
    #       second: second, microsecond: microsecond, time_zone: time_zone,
    #       zone_abbr: zone_abbr, utc_offset: utc_offset, std_offset: std_offset,
    #       calendar: calendar} = datetime
    #     formatted = calendar.datetime_to_string(year, month, day, hour, minute,
    #       second, microsecond, time_zone, zone_abbr, utc_offset, std_offset)
    #     ...
    #   end
    test "Inspect.DateTime.inspect/2 dynamically dispatches calendar.datetime_to_string/11",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Inspect.DateTime, :inspect, 2)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :datetime}, _opts],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :year}, _year},
                           {%IR.AtomType{value: :month}, _month},
                           {%IR.AtomType{value: :day}, _day},
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond},
                           {%IR.AtomType{value: :time_zone}, _time_zone},
                           {%IR.AtomType{value: :zone_abbr}, _zone_abbr},
                           {%IR.AtomType{value: :utc_offset}, _utc_offset},
                           {%IR.AtomType{value: :std_offset}, _std_offset},
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                         ]
                       }
                     },
                     %IR.MatchOperator{
                       left: %IR.Variable{name: :formatted},
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :datetime_to_string,
                         args: [
                           _year_arg,
                           _month_arg,
                           _day_arg,
                           _hour_arg,
                           _minute_arg,
                           _second_arg,
                           _microsecond_arg,
                           _time_zone_arg,
                           _zone_abbr_arg,
                           _utc_offset_arg,
                           _std_offset_arg
                         ]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Inspect.NaiveDateTime.inspect/2 destructures calendar
    # from the struct in the body and calls `calendar.naive_datetime_to_string(...)`.
    # In Elixir >= 1.18 the call is guarded by `if calendar != Calendar.ISO or year in -9999..9999`;
    # in Elixir < 1.18 the call is unconditional. Calendar.ISO dates reach the dispatch in both.
    #
    # Original source (Elixir >= 1.18):
    #   def inspect(naive_datetime, _) do
    #     %{year: year, month: month, day: day, hour: hour, minute: minute,
    #       second: second, microsecond: microsecond, calendar: calendar} = naive_datetime
    #     if calendar != Calendar.ISO or year in -9999..9999 do
    #       formatted = calendar.naive_datetime_to_string(...)
    #       ...
    #
    # Original source (Elixir < 1.18):
    #   def inspect(naive_datetime, _) do
    #     %{...calendar: calendar} = naive_datetime
    #     formatted = calendar.naive_datetime_to_string(...)
    #     ...
    test "Inspect.NaiveDateTime.inspect/2 dynamically dispatches calendar.naive_datetime_to_string/7",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Inspect.NaiveDateTime, :inspect, 2)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :naive_datetime}, _opts],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :year}, _year},
                           {%IR.AtomType{value: :month}, _month},
                           {%IR.AtomType{value: :day}, _day},
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond},
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                         ]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def

      # The dispatch `formatted = calendar.naive_datetime_to_string(...)` is in different
      # IR locations:
      # - Elixir >= 1.18: inside `if` true branch (compiled to nested Case)
      # - Elixir < 1.18: directly in body as second expression
      dispatch_expressions =
        if Version.match?(System.version(), ">= 1.18.0") do
          [_destructure, %IR.Case{clauses: [_false_clause, true_clause]}] =
            fun_def.clause.body.expressions

          assert %IR.Clause{match: %IR.AtomType{value: true}} = true_clause
          true_clause.body.expressions
        else
          [_destructure | rest] = fun_def.clause.body.expressions
          rest
        end

      assert [
               %IR.MatchOperator{
                 left: %IR.Variable{name: :formatted},
                 right: %IR.RemoteFunctionCall{
                   module: %IR.Variable{name: :calendar},
                   function: :naive_datetime_to_string,
                   args: [
                     _year_arg,
                     _month_arg,
                     _day_arg,
                     _hour_arg,
                     _minute_arg,
                     _second_arg,
                     _microsecond_arg
                   ]
                 }
               }
               | _rest_exprs
             ] = dispatch_expressions
    end

    # Dynamic dispatch assumption: Inspect.Time.inspect/2 destructures calendar from the
    # struct in the body and calls `calendar.time_to_string(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def inspect(time, _) do
    #     %{hour: hour, minute: minute, second: second,
    #       microsecond: microsecond, calendar: calendar} = time
    #     "~T[" <> calendar.time_to_string(hour, minute, second, microsecond) <>
    #       suffix(calendar) <> "]"
    #   end
    test "Inspect.Time.inspect/2 dynamically dispatches calendar.time_to_string/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Inspect.Time, :inspect, 2)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :time}, _opts],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond},
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                         ]
                       }
                     },
                     %IR.BitstringType{
                       segments: [
                         _prefix,
                         %IR.BitstringSegment{
                           value: %IR.RemoteFunctionCall{
                             module: %IR.Variable{name: :calendar},
                             function: :time_to_string,
                             args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                           }
                         },
                         _suffix,
                         _closing
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.beginning_of_day/1 extracts calendar from
    # the struct and calls `calendar.iso_days_to_beginning_of_day(iso_days)`.
    #
    # Original source:
    #   def beginning_of_day(%{calendar: calendar, microsecond: {_, precision}} = naive_datetime) do
    #     naive_datetime
    #     |> to_iso_days()
    #     |> calendar.iso_days_to_beginning_of_day()
    #     |> from_iso_days(calendar, precision)
    #   end
    test "NaiveDateTime.beginning_of_day/1 dynamically dispatches calendar.iso_days_to_beginning_of_day/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :beginning_of_day, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MatchOperator{
                     left: %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                         {%IR.AtomType{value: :microsecond}, _microsecond}
                       ]
                     }
                   }
                 ]
               }
             } = fun_def

      # The pipe chain compiles to:
      # from_iso_days(calendar.iso_days_to_beginning_of_day(to_iso_days(ndt)), calendar, precision)
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [
                     %IR.LocalFunctionCall{
                       function: :from_iso_days,
                       args: [
                         %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :iso_days_to_beginning_of_day,
                           args: [_iso_days]
                         },
                         %IR.Variable{name: :calendar},
                         _precision
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.end_of_day/1 extracts calendar from
    # the struct and calls `calendar.iso_days_to_end_of_day(iso_days)`.
    #
    # Original source:
    #   def end_of_day(%{calendar: calendar, microsecond: {_, precision}} = naive_datetime) do
    #     end_of_day =
    #       naive_datetime
    #       |> to_iso_days()
    #       |> calendar.iso_days_to_end_of_day()
    #       |> from_iso_days(calendar, precision)
    #     ...
    #   end
    test "NaiveDateTime.end_of_day/1 dynamically dispatches calendar.iso_days_to_end_of_day/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :end_of_day, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MatchOperator{
                     left: %IR.MapType{
                       data: [
                         {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                         {%IR.AtomType{value: :microsecond}, _microsecond}
                       ]
                     }
                   }
                 ]
               }
             } = fun_def

      # The pipe chain compiles to:
      # from_iso_days(calendar.iso_days_to_end_of_day(to_iso_days(ndt)), calendar, precision)
      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.LocalFunctionCall{
                         function: :from_iso_days,
                         args: [
                           %IR.RemoteFunctionCall{
                             module: %IR.Variable{name: :calendar},
                             function: :iso_days_to_end_of_day,
                             args: [_iso_days]
                           },
                           %IR.Variable{name: :calendar},
                           _precision
                         ]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.from_iso_days/3 (private) receives calendar
    # as a parameter and calls `calendar.naive_datetime_from_iso_days(iso_days)`.
    #
    # Original source:
    #   defp from_iso_days(iso_days, calendar, precision) do
    #     {year, month, day, hour, minute, second, {microsecond, _}} =
    #       calendar.naive_datetime_from_iso_days(iso_days)
    #     ...
    #   end
    test "NaiveDateTime.from_iso_days/3 dynamically dispatches calendar.naive_datetime_from_iso_days/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :from_iso_days, 3)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_iso_days, %IR.Variable{name: :calendar}, _precision],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :naive_datetime_from_iso_days,
                         args: [_iso_days_arg]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.new/8 receives calendar as a parameter
    # (default Calendar.ISO) and calls both `calendar.valid_date?(year, month, day)` and
    # `calendar.valid_time?(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def new(year, month, day, hour, minute, second, microsecond, calendar) do
    #     cond do
    #       not calendar.valid_date?(year, month, day) -> {:error, :invalid_date}
    #       not calendar.valid_time?(hour, minute, second, microsecond) -> {:error, :invalid_time}
    #       true -> ...
    #     end
    #   end
    test "NaiveDateTime.new/8 dynamically dispatches calendar.valid_date?/3 and calendar.valid_time?/4",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, NaiveDateTime, :new, 8)
      assert [_clause_1, clause_2] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   _year,
                   _month,
                   _day,
                   _hour,
                   _minute,
                   _second,
                   _microsecond,
                   %IR.Variable{name: :calendar}
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.Cond{
                       clauses: [
                         %IR.CondClause{
                           condition: %IR.RemoteFunctionCall{
                             module: %IR.AtomType{value: :erlang},
                             function: :not,
                             args: [
                               %IR.RemoteFunctionCall{
                                 module: %IR.Variable{name: :calendar},
                                 function: :valid_date?,
                                 args: [_year_arg, _month_arg, _day_arg]
                               }
                             ]
                           }
                         },
                         %IR.CondClause{
                           condition: %IR.RemoteFunctionCall{
                             module: %IR.AtomType{value: :erlang},
                             function: :not,
                             args: [
                               %IR.RemoteFunctionCall{
                                 module: %IR.Variable{name: :calendar},
                                 function: :valid_time?,
                                 args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                               }
                             ]
                           }
                         },
                         _true_clause
                       ]
                     }
                   ]
                 }
               }
             } = clause_2
    end

    # Dynamic dispatch assumption: NaiveDateTime.shift/2 extracts calendar from the struct
    # and calls `calendar.shift_naive_datetime(year, month, day, hour, minute, second,
    # microsecond, duration)`. NaiveDateTime.shift/2 was added in Elixir 1.17.0.
    #
    # Original source:
    #   def shift(%{calendar: calendar} = naive_datetime, duration) do
    #     %{year: year, month: month, day: day, hour: hour, minute: minute,
    #       second: second, microsecond: microsecond} = naive_datetime
    #     {year, month, day, hour, minute, second, microsecond} =
    #       calendar.shift_naive_datetime(year, month, day, hour, minute, second,
    #         microsecond, __duration__!(duration))
    #     ...
    #   end
    if Version.match?(System.version(), ">= 1.17.0") do
      test "NaiveDateTime.shift/2 dynamically dispatches calendar.shift_naive_datetime/8",
           %{ir_plt: ir_plt} do
        assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :shift, 2)

        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   params: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                       }
                     },
                     _duration
                   ],
                   body: %IR.Block{
                     expressions: [
                       _destructure,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_naive_datetime,
                           args: [
                             _year,
                             _month,
                             _day,
                             _hour,
                             _minute,
                             _second,
                             _microsecond,
                             _duration_arg
                           ]
                         }
                       }
                       | _rest
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: NaiveDateTime.to_gregorian_seconds/1 extracts calendar
    # from the struct and calls `calendar.naive_datetime_to_iso_days(year, month, day,
    # hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def to_gregorian_seconds(%{calendar: calendar, year: year, month: month, day: day,
    #         hour: hour, minute: minute, second: second,
    #         microsecond: {microsecond, precision}} = _naive_datetime) do
    #     {days, day_fraction} =
    #       calendar.naive_datetime_to_iso_days(year, month, day, hour, minute, second,
    #         {microsecond, precision})
    #     ...
    #   end
    #
    # Elixir 1.20 added the `= _naive_datetime` binding to the head, so the map pattern is
    # wrapped in a match; earlier versions expose the bare map pattern as the parameter.
    test "NaiveDateTime.to_gregorian_seconds/1 dynamically dispatches calendar.naive_datetime_to_iso_days/7",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :to_gregorian_seconds, 1)

      map_param =
        case fun_def.clause.params do
          [%IR.MatchOperator{left: %IR.MapType{} = map}] -> map
          [%IR.MapType{} = map] -> map
        end

      assert %IR.MapType{
               data: [
                 {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                 {%IR.AtomType{value: :year}, _year},
                 {%IR.AtomType{value: :month}, _month},
                 {%IR.AtomType{value: :day}, _day},
                 {%IR.AtomType{value: :hour}, _hour},
                 {%IR.AtomType{value: :minute}, _minute},
                 {%IR.AtomType{value: :second}, _second},
                 {%IR.AtomType{value: :microsecond}, _microsecond}
               ]
             } = map_param

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :naive_datetime_to_iso_days,
                         args: [
                           _year_arg,
                           _month_arg,
                           _day_arg,
                           _hour_arg,
                           _minute_arg,
                           _second_arg,
                           _microsecond_arg
                         ]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.to_iso_days/1 (private) extracts calendar
    # from the struct and calls `calendar.naive_datetime_to_iso_days(year, month, day,
    # hour, minute, second, microsecond)`.
    #
    # Original source:
    #   defp to_iso_days(%{calendar: calendar, year: year, month: month, day: day,
    #          hour: hour, minute: minute, second: second, microsecond: microsecond}) do
    #     calendar.naive_datetime_to_iso_days(year, month, day, hour, minute, second, microsecond)
    #   end
    # credo:disable-for-lines:32 Credo.Check.Design.DuplicatedCode
    test "NaiveDateTime.to_iso_days/1 dynamically dispatches calendar.naive_datetime_to_iso_days/7",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :to_iso_days, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day},
                       {%IR.AtomType{value: :hour}, _hour},
                       {%IR.AtomType{value: :minute}, _minute},
                       {%IR.AtomType{value: :second}, _second},
                       {%IR.AtomType{value: :microsecond}, _microsecond}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :naive_datetime_to_iso_days,
                       args: [
                         _year_arg,
                         _month_arg,
                         _day_arg,
                         _hour_arg,
                         _minute_arg,
                         _second_arg,
                         _microsecond_arg
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: NaiveDateTime.to_string/1 extracts calendar from the
    # struct and calls `calendar.naive_datetime_to_string(year, month, day, hour, minute,
    # second, microsecond)`.
    #
    # Original source:
    #   def to_string(%{calendar: calendar} = naive_datetime) do
    #     %{year: year, month: month, day: day, hour: hour, minute: minute,
    #       second: second, microsecond: microsecond} = naive_datetime
    #     calendar.naive_datetime_to_string(year, month, day, hour, minute, second, microsecond)
    #   end
    test "NaiveDateTime.to_string/1 dynamically dispatches calendar.naive_datetime_to_string/7",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, NaiveDateTime, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MatchOperator{
                     left: %IR.MapType{
                       data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                     }
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     _destructure,
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :naive_datetime_to_string,
                       args: [
                         _year,
                         _month,
                         _day,
                         _hour,
                         _minute,
                         _second,
                         _microsecond
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: String.Chars.Date.to_string/1 extracts calendar from
    # the struct and calls `calendar.date_to_string(year, month, day)`.
    #
    # Original source:
    #   def to_string(%{calendar: calendar, year: year, month: month, day: day}) do
    #     calendar.date_to_string(year, month, day)
    #   end
    test "String.Chars.Date.to_string/1 dynamically dispatches calendar.date_to_string/3",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, String.Chars.Date, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                       {%IR.AtomType{value: :year}, _year},
                       {%IR.AtomType{value: :month}, _month},
                       {%IR.AtomType{value: :day}, _day}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :date_to_string,
                       args: [_year_arg, _month_arg, _day_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: String.Chars.DateTime.to_string/1 destructures calendar
    # from the struct in the body and calls `calendar.datetime_to_string(year, month, day,
    # hour, minute, second, microsecond, time_zone, zone_abbr, utc_offset, std_offset)`.
    #
    # Original source:
    #   def to_string(datetime) do
    #     %{calendar: calendar, year: year, month: month, day: day, hour: hour,
    #       minute: minute, second: second, microsecond: microsecond, time_zone: time_zone,
    #       zone_abbr: zone_abbr, utc_offset: utc_offset, std_offset: std_offset} = datetime
    #     calendar.datetime_to_string(year, month, day, hour, minute, second,
    #       microsecond, time_zone, zone_abbr, utc_offset, std_offset)
    #   end
    test "String.Chars.DateTime.to_string/1 dynamically dispatches calendar.datetime_to_string/11",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, String.Chars.DateTime, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :datetime}],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                           {%IR.AtomType{value: :year}, _year},
                           {%IR.AtomType{value: :month}, _month},
                           {%IR.AtomType{value: :day}, _day},
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond},
                           {%IR.AtomType{value: :time_zone}, _time_zone},
                           {%IR.AtomType{value: :zone_abbr}, _zone_abbr},
                           {%IR.AtomType{value: :utc_offset}, _utc_offset},
                           {%IR.AtomType{value: :std_offset}, _std_offset}
                         ]
                       }
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :datetime_to_string,
                       args: [
                         _year_arg,
                         _month_arg,
                         _day_arg,
                         _hour_arg,
                         _minute_arg,
                         _second_arg,
                         _microsecond_arg,
                         _time_zone_arg,
                         _zone_abbr_arg,
                         _utc_offset_arg,
                         _std_offset_arg
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: String.Chars.NaiveDateTime.to_string/1 destructures
    # calendar from the struct in the body and calls
    # `calendar.naive_datetime_to_string(year, month, day, hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def to_string(naive_datetime) do
    #     %{calendar: calendar, year: year, month: month, day: day, hour: hour,
    #       minute: minute, second: second, microsecond: microsecond} = naive_datetime
    #     calendar.naive_datetime_to_string(year, month, day, hour, minute, second, microsecond)
    #   end
    test "String.Chars.NaiveDateTime.to_string/1 dynamically dispatches calendar.naive_datetime_to_string/7",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, String.Chars.NaiveDateTime, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :naive_datetime}],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}},
                           {%IR.AtomType{value: :year}, _year},
                           {%IR.AtomType{value: :month}, _month},
                           {%IR.AtomType{value: :day}, _day},
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond}
                         ]
                       }
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :naive_datetime_to_string,
                       args: [
                         _year_arg,
                         _month_arg,
                         _day_arg,
                         _hour_arg,
                         _minute_arg,
                         _second_arg,
                         _microsecond_arg
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: String.Chars.Time.to_string/1 destructures calendar
    # from the struct in the body and calls
    # `calendar.time_to_string(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def to_string(time) do
    #     %{hour: hour, minute: minute, second: second,
    #       microsecond: microsecond, calendar: calendar} = time
    #     calendar.time_to_string(hour, minute, second, microsecond)
    #   end
    test "String.Chars.Time.to_string/1 dynamically dispatches calendar.time_to_string/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, String.Chars.Time, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :time}],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [
                           {%IR.AtomType{value: :hour}, _hour},
                           {%IR.AtomType{value: :minute}, _minute},
                           {%IR.AtomType{value: :second}, _second},
                           {%IR.AtomType{value: :microsecond}, _microsecond},
                           {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                         ]
                       }
                     },
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :time_to_string,
                       args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Time.convert/2 receives calendar as a parameter and
    # calls `calendar.time_from_day_fraction(day_fraction)`.
    #
    # Original source:
    #   def convert(%{microsecond: {_, precision}} = time, calendar) do
    #     {hour, minute, second, {microsecond, _}} =
    #       time
    #       |> to_day_fraction()
    #       |> calendar.time_from_day_fraction()
    #     ...
    #   end
    test "Time.convert/2 dynamically dispatches calendar.time_from_day_fraction/1",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Time, :convert, 2)
      assert [_clause_1, clause_2] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_time, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :time_from_day_fraction,
                         args: [_day_fraction]
                       }
                     },
                     _struct_assignment,
                     _ok_tuple
                   ]
                 }
               }
             } = clause_2
    end

    # Dynamic dispatch assumption: Time.from_seconds_after_midnight/3 receives calendar
    # as a parameter (default Calendar.ISO) and calls
    # `calendar.time_from_day_fraction({seconds_in_day, @seconds_per_day})`.
    #
    # Original source:
    #   def from_seconds_after_midnight(seconds, microsecond \\ {0, 0}, calendar \\ Calendar.ISO)
    #       when is_integer(seconds) do
    #     seconds_in_day = Integer.mod(seconds, @seconds_per_day)
    #     {hour, minute, second, {_, _}} =
    #       calendar.time_from_day_fraction({seconds_in_day, @seconds_per_day})
    #     ...
    #   end
    test "Time.from_seconds_after_midnight/3 dynamically dispatches calendar.time_from_day_fraction/1",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Time, :from_seconds_after_midnight, 3)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_seconds, _microsecond, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     _seconds_in_day,
                     %IR.MatchOperator{
                       right: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :time_from_day_fraction,
                         args: [_day_fraction]
                       }
                     }
                     | _rest
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Time.new/5 receives calendar as a parameter
    # (default Calendar.ISO) and calls `calendar.valid_time?(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def new(hour, minute, second, {microsecond, precision}, calendar)
    #       when is_integer(hour) and ... do
    #     case calendar.valid_time?(hour, minute, second, {microsecond, precision}) do
    #       ...
    #     end
    #   end
    test "Time.new/5 dynamically dispatches calendar.valid_time?/4",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Time, :new, 5)
      assert [_clause_1, clause_2] = fun_defs

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [_hour, _minute, _second, _microsecond, %IR.Variable{name: :calendar}],
                 body: %IR.Block{
                   expressions: [
                     %IR.Case{
                       condition: %IR.RemoteFunctionCall{
                         module: %IR.Variable{name: :calendar},
                         function: :valid_time?,
                         args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                       }
                     }
                   ]
                 }
               }
             } = clause_2
    end

    # Dynamic dispatch assumption: Time.shift/2 extracts calendar from the struct
    # and calls `calendar.shift_time(hour, minute, second, microsecond, duration)`.
    # Time.shift/2 was added in Elixir 1.17.0.
    #
    # Original source:
    #   def shift(%{calendar: calendar} = time, duration) do
    #     %{hour: hour, minute: minute, second: second, microsecond: microsecond} = time
    #     {hour, minute, second, microsecond} =
    #       calendar.shift_time(hour, minute, second, microsecond, __duration__!(duration))
    #     ...
    #   end
    if Version.match?(System.version(), ">= 1.17.0") do
      test "Time.shift/2 dynamically dispatches calendar.shift_time/5",
           %{ir_plt: ir_plt} do
        assert [fun_def] = find_fun_defs(ir_plt, Time, :shift, 2)

        assert %IR.FunctionDefinition{
                 clause: %IR.FunctionClause{
                   params: [
                     %IR.MatchOperator{
                       left: %IR.MapType{
                         data: [{%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}]
                       }
                     },
                     _duration
                   ],
                   body: %IR.Block{
                     expressions: [
                       _destructure,
                       %IR.MatchOperator{
                         right: %IR.RemoteFunctionCall{
                           module: %IR.Variable{name: :calendar},
                           function: :shift_time,
                           args: [_hour, _minute, _second, _microsecond, _duration_arg]
                         }
                       }
                       | _rest
                     ]
                   }
                 }
               } = fun_def
      end
    end

    # Dynamic dispatch assumption: Time.to_day_fraction/1 (private) extracts calendar
    # from the struct and calls `calendar.time_to_day_fraction(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   defp to_day_fraction(%{hour: hour, minute: minute, second: second,
    #          microsecond: {_, _} = microsecond, calendar: calendar}) do
    #     calendar.time_to_day_fraction(hour, minute, second, microsecond)
    #   end
    test "Time.to_day_fraction/1 dynamically dispatches calendar.time_to_day_fraction/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Time, :to_day_fraction, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :hour}, _hour},
                       {%IR.AtomType{value: :minute}, _minute},
                       {%IR.AtomType{value: :second}, _second},
                       {%IR.AtomType{value: :microsecond}, _microsecond},
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :time_to_day_fraction,
                       args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Dynamic dispatch assumption: Time.to_string/1 extracts calendar from the struct
    # and calls `calendar.time_to_string(hour, minute, second, microsecond)`.
    #
    # Original source:
    #   def to_string(%{hour: hour, minute: minute, second: second,
    #         microsecond: microsecond, calendar: calendar}) do
    #     calendar.time_to_string(hour, minute, second, microsecond)
    #   end
    test "Time.to_string/1 dynamically dispatches calendar.time_to_string/4",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Time, :to_string, 1)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :hour}, _hour},
                       {%IR.AtomType{value: :minute}, _minute},
                       {%IR.AtomType{value: :second}, _second},
                       {%IR.AtomType{value: :microsecond}, _microsecond},
                       {%IR.AtomType{value: :calendar}, %IR.Variable{name: :calendar}}
                     ]
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.Variable{name: :calendar},
                       function: :time_to_string,
                       args: [_hour_arg, _minute_arg, _second_arg, _microsecond_arg]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Original source:
    #   defimpl Protocol1, for: Integer do
    #     def my_fun(_data), do: :ok
    #   end
    #
    # Expanded (Elixir >= 1.16):
    #   def __impl__(:for), do: Integer
    #   def __impl__(:protocol), do: Protocol1
    #
    # Expanded (Elixir < 1.16):
    #   def __impl__(:for), do: Integer
    #   def __impl__(:protocol), do: Protocol1
    #   def __impl__(:target), do: Protocol1.Integer
    test "__impl__/1 clauses have 'for' and 'protocol' module atoms in body",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1.Integer, :__impl__, 1)

      {for_clause, protocol_clause} =
        if Version.match?(System.version(), ">= 1.16.0") do
          assert [for_clause, protocol_clause] = fun_defs
          {for_clause, protocol_clause}
        else
          assert [target_clause, for_clause, protocol_clause] = fun_defs

          assert target_clause == %IR.FunctionDefinition{
                   name: :__impl__,
                   arity: 1,
                   visibility: :public,
                   clause: %IR.FunctionClause{
                     params: [%IR.AtomType{value: :target}],
                     guards: [],
                     body: %IR.Block{
                       expressions: [%IR.AtomType{value: Protocol1.Integer}]
                     },
                     line: 2,
                     blame: %{params: [":target"], guards: []}
                   }
                 }

          {for_clause, protocol_clause}
        end

      assert for_clause == %IR.FunctionDefinition{
               name: :__impl__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :for}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: Integer}]
                 },
                 line: 2,
                 blame: %{params: [":for"], guards: []}
               }
             }

      assert protocol_clause == %IR.FunctionDefinition{
               name: :__impl__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :protocol}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: Protocol1}]
                 },
                 line: 2,
                 blame: %{params: [":protocol"], guards: []}
               }
             }
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (after consolidation):
    #   def __protocol__(:module), do: Protocol1
    #   def __protocol__(:functions), do: [my_fun: 1]
    #   def __protocol__(:consolidated?), do: true
    #   def __protocol__(:impls), do: {:consolidated, [Struct1, Integer]}
    test "__protocol__/1 clauses have module atoms in body (protocol module and implementations)",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1, :__protocol__, 1)

      assert [module_clause, functions_clause, consolidated_clause, impls_clause] = fun_defs

      assert module_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :module}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: Protocol1}]
                 },
                 line: 2,
                 blame: %{params: [":module"], guards: []}
               }
             }

      assert functions_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :functions}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.ListType{
                       data: [
                         %IR.TupleType{
                           data: [
                             %IR.AtomType{value: :my_fun},
                             %IR.IntegerType{value: 1}
                           ]
                         }
                       ]
                     }
                   ]
                 },
                 line: 2,
                 blame: %{params: [":functions"], guards: []}
               }
             }

      assert consolidated_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :consolidated?}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: true}]
                 },
                 line: 2,
                 blame: %{params: [":consolidated?"], guards: []}
               }
             }

      assert impls_clause == %IR.FunctionDefinition{
               name: :__protocol__,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: :impls}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.TupleType{
                       data: [
                         %IR.AtomType{value: :consolidated},
                         %IR.ListType{
                           data: [
                             %IR.AtomType{value: Struct1},
                             %IR.AtomType{value: Integer}
                           ]
                         }
                       ]
                     }
                   ]
                 },
                 line: 2,
                 blame: %{params: [":impls"], guards: []}
               }
             }
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (after consolidation):
    #   def impl_for(%{__struct__: x}) when is_atom(x), do: struct_impl_for(x)
    #   def impl_for(x) when is_integer(x), do: Protocol1.Integer
    #   def impl_for(_), do: nil
    test "impl_for/1 clauses have module atoms in body and struct dispatch calls struct_impl_for/1",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1, :impl_for, 1)

      assert [struct_clause, integer_clause, catch_all_clause] = fun_defs

      # credo:disable-for-next-line Credo.Check.Design.DuplicatedCode
      assert struct_clause == %IR.FunctionDefinition{
               name: :impl_for,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [
                   %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :__struct__}, %IR.Variable{name: :x, version: -1}}
                     ]
                   }
                 ],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_atom,
                     args: [%IR.Variable{name: :x, version: -1}],
                     line: 2
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.LocalFunctionCall{
                       function: :struct_impl_for,
                       args: [%IR.Variable{name: :x, version: -1}],
                       line: 2
                     }
                   ]
                 },
                 line: 2
               }
             }

      assert integer_clause == %IR.FunctionDefinition{
               name: :impl_for,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :x, version: -1}],
                 guards: [
                   %IR.RemoteFunctionCall{
                     module: %IR.AtomType{value: :erlang},
                     function: :is_integer,
                     args: [%IR.Variable{name: :x, version: -1}],
                     line: 2
                   }
                 ],
                 body: %IR.Block{
                   expressions: [
                     %IR.AtomType{value: Protocol1.Integer}
                   ]
                 },
                 line: 2
               }
             }

      assert catch_all_clause == %IR.FunctionDefinition{
               name: :impl_for,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.MatchPlaceholder{}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: nil}]
                 },
                 line: 2
               }
             }
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (Elixir >= 1.18):
    #   def impl_for!(data) do
    #     case impl_for(data) do
    #       x when x == false or x == nil ->
    #         :erlang.error(Protocol.UndefinedError.exception(
    #           protocol: Protocol1, value: data, description: ""))
    #       x -> x
    #     end
    #   end
    #
    # Expanded (Elixir < 1.18):
    #   def impl_for!(data) do
    #     case impl_for(data) do
    #       x when x == false or x == nil ->
    #         :erlang.error(Protocol.UndefinedError.exception(
    #           protocol: Protocol1, value: data))
    #       x -> x
    #     end
    #   end
    test "impl_for!/1 body calls impl_for/1 and has protocol module atom in error path",
         %{ir_plt: ir_plt} do
      assert [clause] = find_fun_defs(ir_plt, Protocol1, :impl_for!, 1)

      exception_keyword_data =
        if Version.match?(System.version(), ">= 1.18.0") do
          [
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :protocol},
                %IR.AtomType{value: Protocol1}
              ]
            },
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :value},
                %IR.Variable{name: :data, version: 0}
              ]
            },
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :description},
                %IR.StringType{value: ""}
              ]
            }
          ]
        else
          [
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :protocol},
                %IR.AtomType{value: Protocol1}
              ]
            },
            %IR.TupleType{
              data: [
                %IR.AtomType{value: :value},
                %IR.Variable{name: :data, version: 0}
              ]
            }
          ]
        end

      assert clause == %IR.FunctionDefinition{
               name: :impl_for!,
               arity: 1,
               visibility: :public,
               clause: %IR.FunctionClause{
                 params: [%IR.Variable{name: :data, version: 0}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.Case{
                       line: 2,
                       condition: %IR.LocalFunctionCall{
                         function: :impl_for,
                         args: [%IR.Variable{name: :data, version: 0}],
                         line: 2
                       },
                       clauses: [
                         %IR.Clause{
                           match: %IR.Variable{name: :x, version: 1},
                           guards: [
                             %IR.RemoteFunctionCall{
                               module: %IR.AtomType{value: :erlang},
                               function: :orelse,
                               args: [
                                 %IR.RemoteFunctionCall{
                                   module: %IR.AtomType{value: :erlang},
                                   function: :"=:=",
                                   args: [
                                     %IR.Variable{name: :x, version: 1},
                                     %IR.AtomType{value: false}
                                   ],
                                   line: 2
                                 },
                                 %IR.RemoteFunctionCall{
                                   module: %IR.AtomType{value: :erlang},
                                   function: :"=:=",
                                   args: [
                                     %IR.Variable{name: :x, version: 1},
                                     %IR.AtomType{value: nil}
                                   ],
                                   line: 2
                                 }
                               ],
                               line: 2
                             }
                           ],
                           body: %IR.Block{
                             expressions: [
                               %IR.RemoteFunctionCall{
                                 module: %IR.AtomType{value: :erlang},
                                 function: :error,
                                 args: [
                                   %IR.RemoteFunctionCall{
                                     module: %IR.AtomType{value: Protocol.UndefinedError},
                                     function: :exception,
                                     args: [
                                       %IR.ListType{data: exception_keyword_data}
                                     ],
                                     line: 2
                                   }
                                 ],
                                 line: 2
                               }
                             ]
                           }
                         },
                         %IR.Clause{
                           match: %IR.Variable{name: :x, version: 2},
                           guards: [],
                           body: %IR.Block{
                             expressions: [%IR.Variable{name: :x, version: 2}]
                           }
                         }
                       ]
                     }
                   ]
                 },
                 line: 2
               }
             }
    end

    # Kernel.raise with a compile-time-known exception module expands to
    # :erlang.error/1, without any error_info option, so no formatter edge
    # is derived from such raise sites.
    #
    # Original source:
    #   raise ArgumentError, "my message"
    test "raise with a known exception module expands to :erlang.error/1 without error_info",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Module41, :my_fun_1, 0)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :error,
                       args: [
                         %IR.RemoteFunctionCall{
                           module: %IR.AtomType{value: ArgumentError},
                           function: :exception,
                           args: [%IR.StringType{value: "my message"}]
                         }
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Kernel.raise with a message expands to :erlang.error/3 whose error_info
    # option names Exception as the format module, so the EEP-54 resolution
    # derives an Exception.format_error/2 formatter edge from such raise sites.
    #
    # Original source:
    #   raise "my message"
    test "raise with a message expands to :erlang.error/3 with the Exception formatter error_info",
         %{ir_plt: ir_plt} do
      assert [fun_def] = find_fun_defs(ir_plt, Module41, :my_fun_2, 0)

      assert %IR.FunctionDefinition{
               clause: %IR.FunctionClause{
                 body: %IR.Block{
                   expressions: [
                     %IR.RemoteFunctionCall{
                       module: %IR.AtomType{value: :erlang},
                       function: :error,
                       args: [
                         %IR.RemoteFunctionCall{
                           module: %IR.AtomType{value: RuntimeError},
                           function: :exception,
                           args: [%IR.StringType{value: "my message"}]
                         },
                         %IR.AtomType{value: :none},
                         %IR.ListType{
                           data: [
                             %IR.TupleType{
                               data: [
                                 %IR.AtomType{value: :error_info},
                                 %IR.MapType{
                                   data: [
                                     {%IR.AtomType{value: :module},
                                      %IR.AtomType{value: Exception}}
                                   ]
                                 }
                               ]
                             }
                           ]
                         }
                       ]
                     }
                   ]
                 }
               }
             } = fun_def
    end

    # Original source:
    #   defprotocol Protocol1 do
    #     def my_fun(data)
    #   end
    #
    # Expanded (after consolidation, one clause per struct + catch-all):
    #   defp struct_impl_for(Struct1), do: Protocol1.Struct1
    #   defp struct_impl_for(_), do: nil
    test "struct_impl_for/1 clauses have struct and implementation module atoms",
         %{ir_plt: ir_plt} do
      fun_defs = find_fun_defs(ir_plt, Protocol1, :struct_impl_for, 1)

      assert [struct_1_clause, catch_all_clause] = fun_defs

      assert struct_1_clause == %IR.FunctionDefinition{
               name: :struct_impl_for,
               arity: 1,
               visibility: :private,
               clause: %IR.FunctionClause{
                 params: [%IR.AtomType{value: Struct1}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [
                     %IR.AtomType{value: Module.safe_concat(Protocol1, Struct1)}
                   ]
                 },
                 line: 2,
                 blame: %{params: [inspect(Struct1)], guards: []}
               }
             }

      assert catch_all_clause == %IR.FunctionDefinition{
               name: :struct_impl_for,
               arity: 1,
               visibility: :private,
               clause: %IR.FunctionClause{
                 params: [%IR.MatchPlaceholder{}],
                 guards: [],
                 body: %IR.Block{
                   expressions: [%IR.AtomType{value: nil}]
                 },
                 line: 2,
                 # Consolidation gives the catch-all param a context that Macro
                 # walking rejects, so its clause head can't be rendered.
                 blame: nil
               }
             }
    end
  end
end
