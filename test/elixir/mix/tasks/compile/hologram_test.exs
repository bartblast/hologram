defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: false
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Tracer
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module3
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module5

  @lib_assets_dir Path.join(Reflection.root_dir(), "assets")
  @lib_package_json_path Path.join(@lib_assets_dir, "package.json")

  @test_dir Path.join([
              Reflection.tmp_dir(),
              "tests",
              "mix",
              "tasks",
              "compile.hologram",
              "run_1"
            ])

  @assets_dir Path.join(@test_dir, "assets")
  @build_dir Path.join(@test_dir, "build")
  @static_dir Path.join(@test_dir, "static")
  @tmp_dir Path.join(@test_dir, "tmp")

  @compiler_lock_file_name Reflection.compiler_lock_file_name()
  @lock_path Path.join(@build_dir, @compiler_lock_file_name)

  @compile_fixtures_dir Path.join([@fixtures_dir, "mix", "tasks", "compile", "hologram"])

  # A function's JavaScript is produced by one call of this, however it is reached.
  @encode_function_mfa {Hologram.Compiler.Encoder, :encode_elixir_function, 6}

  @num_pages Enum.count(Reflection.list_pages())

  # A page whose template holds a link to another page, and that page.
  @linked_page Hologram.Test.Fixtures.Page.Module2
  @linking_page Hologram.Test.Fixtures.Page.Module5

  # A module of the test build that no page and no runtime function reaches.
  @unreached_module Hologram.Test.Fixtures.Compiler.CallGraph.Module9

  # The cache's state with the kept module infos as a map, nil while they are untrusted (no editable
  # modules kept), as the tests read them.
  defp cache_state do
    state = Cache.get()
    module_infos = if state.editable_modules, do: PLT.get_all(state.module_info_plt)

    Map.put(state, :module_infos, module_infos)
  end

  # How many times the function is called, in any process, while the given function runs.
  defp count_calls(mfa, fun) do
    :erlang.trace_pattern(mfa, true, [:call_count])

    try do
      fun.()
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)
      count
    after
      :erlang.trace_pattern(mfa, false, [:call_count])
    end
  end

  # How many times the compile state dump is written while the given function runs: each write goes
  # through a private function of the cache, whose local calls are counted.
  defp count_compile_state_writes(fun) do
    mfa = {Cache, :write_compile_state, 2}
    :erlang.trace_pattern(mfa, true, [:local, :call_count])

    try do
      fun.()
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)
      count
    after
      :erlang.trace_pattern(mfa, false, [:local, :call_count])
    end
  end

  # How many times the call graph and the module info PLT are dumped while the given function runs.
  # PLT.dump/2 also writes the page digest PLT, once before the batches and once after each, through
  # a private function whose local calls are counted and taken off.
  defp count_dumps(fun) do
    counted = [
      {CallGraph, :dump, 2, [:call_count]},
      {PLT, :dump, 2, [:call_count]},
      {Mix.Tasks.Compile.Hologram, :dump_page_digest_plt, 2, [:local, :call_count]}
    ]

    Enum.each(counted, fn {module, function, arity, flags} ->
      :erlang.trace_pattern({module, function, arity}, true, flags)
    end)

    try do
      fun.()

      [call_graph_dumps, plt_dumps, page_digest_dumps] =
        Enum.map(counted, fn {module, function, arity, _flags} ->
          {:call_count, count} = :erlang.trace_info({module, function, arity}, :call_count)
          count
        end)

      [call_graph_dumps, plt_dumps - page_digest_dumps]
    after
      Enum.each(counted, fn {module, function, arity, flags} ->
        :erlang.trace_pattern({module, function, arity}, false, flags)
      end)
    end
  end

  # How many kept pages reach the given module, as their states record it.
  defp count_pages_reaching(module) do
    cache_state().pages_plt
    |> PLT.get_all()
    |> Enum.count(fn {_page_module, page_state} -> MapSet.member?(page_state.modules, module) end)
  end

  defp count_plt_processes do
    Enum.count(Process.list(), fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} -> Keyword.get(dict, :"$initial_call") == {PLT, :init, 1}
        nil -> false
      end
    end)
  end

  # How many templates are validated while the given function runs: each goes through a private
  # function once, whose local calls are counted.
  defp count_validated_templates(fun) do
    mfa = {Compiler, :validate_module_prop_usages, 2}
    :erlang.trace_pattern(mfa, true, [:local, :call_count])

    try do
      fun.()
      {:call_count, count} = :erlang.trace_info(mfa, :call_count)
      count
    after
      :erlang.trace_pattern(mfa, false, [:local, :call_count])
    end
  end

  # Fakes an edit of the module in the kept state: the compiler reports it, so its beam is read, and
  # the digest read differs from the kept one.
  defp fake_edit(module) do
    %{dumped_at: dumped_at, editable_modules: editable_modules, module_infos: module_infos} =
      cache_state()

    report_compiled(module)
    edited_info = %{module_infos[module] | digest: "edited"}
    put_kept_module_infos(%{module_infos | module => edited_info}, dumped_at, editable_modules)
  end

  # A module the kept runtime carries whose beam a save can rewrite, since only such a beam is
  # rechecked, so that a fake edit of it is seen.
  # Fakes an edit of the module since the dumps were written, as a new VM sees one: the module info
  # dump gets a digest the beam does not have and an mtime the beam does not have, so the scan reads
  # the beam again and finds a digest that differs from the dumped one.
  defp fake_edit_in_dump(module, opts) do
    dump_path = Path.join(opts[:build_dir], Reflection.module_info_plt_dump_file_name())
    module_infos = load_module_info_items(opts)
    info = module_infos[module]
    edited_info = %{info | digest: "edited", mtime: info.mtime - 100}

    plt = PLT.start(items: Map.to_list(%{module_infos | module => edited_info}))
    PLT.dump(plt, dump_path)
    PLT.stop(plt)
  end

  defp find_editable_runtime_module do
    %{editable_modules: editable_modules, module_infos: module_infos, runtime: runtime} =
      cache_state()

    Enum.find_value(runtime.mfas, fn {module, _function, _arity} ->
      if MapSet.member?(editable_modules, module) and Map.has_key?(module_infos, module),
        do: module
    end)
  end

  # Forgets what the last compile kept, in the VM and on disk: what the first compile in a fresh
  # checkout finds. Cache.reset/0 alone is what the first compile in a new VM finds, the compile
  # state dump next to the call graph dump.
  defp forget_kept_state(opts) do
    Cache.reset()

    opts[:build_dir]
    |> Path.join(Reflection.compile_state_dump_file_name())
    |> File.rm()

    :ok
  end

  defp generate_old_bundle(name, opts) do
    opts[:static_dir]
    |> Path.join("#{name}.js")
    |> File.write!(name)
  end

  # Telemetry handler that tracks how many compilations are inside the critical
  # section at once, recording the running maximum. Public because telemetry
  # warns when a handler is captured as a local or anonymous function.
  @spec handle_compiler_telemetry(
          :telemetry.event_name(),
          :telemetry.event_measurements(),
          :telemetry.event_metadata(),
          Agent.agent()
        ) :: :ok
  def handle_compiler_telemetry(event_name, measurements, metadata, tracker)

  def handle_compiler_telemetry([:hologram, :compiler, :start], _measurements, _metadata, tracker) do
    Agent.update(tracker, fn %{current: current, max: max_seen} ->
      new_current = current + 1
      %{current: new_current, max: max(max_seen, new_current)}
    end)
  end

  def handle_compiler_telemetry([:hologram, :compiler, :stop], _measurements, _metadata, tracker) do
    Agent.update(tracker, fn state -> %{state | current: state.current - 1} end)
  end

  defp load_compile_state_dump(opts) do
    dump_path = Path.join(opts[:build_dir], Reflection.compile_state_dump_file_name())
    assert File.exists?(dump_path)

    dump_path
    |> File.read!()
    |> SerializationUtils.deserialize(true)
  end

  defp load_module_info_items(opts) do
    dump_path = Path.join(opts[:build_dir], Reflection.module_info_plt_dump_file_name())
    assert File.exists?(dump_path)

    plt = PLT.start()
    PLT.load(plt, dump_path)
    PLT.get_all(plt)
  end

  defp load_page_digest_items(opts) do
    dump_path = Path.join(opts[:build_dir], Reflection.page_digest_plt_dump_file_name())
    assert File.exists?(dump_path)

    plt = PLT.start()
    PLT.load(plt, dump_path)
    PLT.get_all(plt)
  end

  # Replaces the kept module infos with the given ones and marks them as the before picture.
  defp put_kept_module_infos(module_infos, dumped_at, editable_modules) do
    %{module_info_plt: module_info_plt} = Cache.get()

    module_info_plt
    |> PLT.reset()
    |> PLT.put(Map.to_list(module_infos))

    Cache.put_module_infos(dumped_at, editable_modules)
  end

  # Makes the first kept pages by name pending, so that a run rebuilds them with no edit, and
  # returns them.
  defp put_pending_kept_pages(count) do
    %{pages_plt: pages_plt} = cache_state()

    page_modules =
      pages_plt
      |> PLT.keys()
      |> Enum.sort()
      |> Enum.take(count)

    assert length(page_modules) == count

    Cache.put_pending_pages(page_modules)

    MapSet.new(page_modules)
  end

  # A function that records each value it is called with, and one that returns them in call order.
  defp record_calls do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    record = fn value -> Agent.update(agent, &[value | &1]) end
    recorded = fn -> Agent.get(agent, &Enum.reverse/1) end

    {record, recorded}
  end

  # What the compiler tracer records when the module is compiled: the bytes its beam holds.
  defp report_compiled(module) do
    Tracer.trace({:on_module, File.read!(:code.which(module)), :none}, %Macro.Env{module: module})
  end

  defp setup_empty_assets_and_build_dirs(opts) do
    assets_dir = setup_empty_assets_dir()
    build_dir = setup_empty_build_dir()

    opts
    |> Keyword.put(:assets_dir, assets_dir)
    |> Keyword.put(:build_dir, build_dir)
  end

  defp setup_empty_assets_dir do
    assets_dir = Path.join(@test_dir, "assets_empty")
    clean_dir(assets_dir)

    test_package_json_path = Path.join(assets_dir, "package.json")
    FileUtils.cp_p!(@lib_package_json_path, test_package_json_path)

    assets_dir
  end

  defp setup_empty_build_dir do
    build_dir = Path.join(@test_dir, "build_empty")
    clean_dir(build_dir)

    build_dir
  end

  defp test_build_artifacts(opts) do
    test_call_graph(opts)
    test_dirs(opts)
    test_js_deps(opts)
    test_module_info_plt(opts)
    test_page_bundles(opts)
    test_page_digest_plt(opts)
    test_runtime_bundle(opts)
  end

  # Takes the module out of the kept call graph, its reach and the IR PLT, as a compile whose diff
  # removed it would, while its beam stays: the next compile that walks to it builds it again.
  defp take_out_of_graph(module) do
    %{call_graph: kept_call_graph, ir_plt: ir_plt, module_infos: module_infos} = cache_state()

    module_info_plt = PLT.start(items: Map.to_list(module_infos))
    call_graph = %{kept_call_graph | module_info_plt: module_info_plt}
    diff = %{added_modules: [], edited_modules: [], removed_modules: [module]}

    CallGraph.patch(call_graph, ir_plt, diff)
    assert CallGraph.build_reach(call_graph, diff, fn _modules -> :ok end) == []
    PLT.delete(ir_plt, module)

    refute module in CallGraph.modules(call_graph)
  end

  defp test_call_graph(opts) do
    call_graph_dump_path = Path.join(opts[:build_dir], Reflection.call_graph_dump_file_name())
    assert File.exists?(call_graph_dump_path)

    call_graph = CallGraph.start()
    assert CallGraph.load(call_graph, call_graph_dump_path) == :ok

    # The graph holds the modules the pages reach, and not the rest.
    assert Module1 in CallGraph.modules(call_graph)
    refute @unreached_module in CallGraph.modules(call_graph)

    assert CallGraph.has_vertex?(call_graph, Module2)

    # Erlang MFA edges are added during compilation
    assert CallGraph.has_edge?(call_graph, {:binary, :match, 2}, {:binary, :match, 3})

    # Dynamic dispatch edges are added during compilation
    assert CallGraph.has_edge?(call_graph, {Date, :new, 4}, {Calendar.ISO, :valid_date?, 3})
  end

  defp test_dirs(opts) do
    assert File.exists?(opts[:build_dir])
    assert File.exists?(opts[:static_dir])
    assert File.exists?(opts[:tmp_dir])
  end

  defp test_js_deps(opts) do
    assert opts[:assets_dir]
           |> Path.join("node_modules")
           |> File.exists?()
  end

  defp test_module_info_plt(opts) do
    module_info_items = load_module_info_items(opts)

    assert map_size(module_info_items) > 1_000

    assert %{digest: digest, page?: true, component?: false} = module_info_items[Module1]
    assert is_integer(digest)
  end

  defp test_old_build_static_artifacts_cleanup(opts) do
    refute opts[:static_dir]
           |> Path.join("old_bundle_1.js")
           |> File.exists?()

    refute opts[:static_dir]
           |> Path.join("old_bundle_2.js")
           |> File.exists?()
  end

  defp test_page_bundles(opts) do
    num_page_bundles =
      opts[:static_dir]
      |> Path.join("page-*-????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_bundles == @num_pages

    num_page_source_maps =
      opts[:static_dir]
      |> Path.join("page-*-????????.js.map")
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_source_maps == @num_pages
  end

  defp test_page_digest_plt(opts) do
    page_digest_plt_dump_path =
      Path.join(opts[:build_dir], Reflection.page_digest_plt_dump_file_name())

    assert File.exists?(page_digest_plt_dump_path)

    page_digest_plt = PLT.start()
    PLT.load(page_digest_plt, page_digest_plt_dump_path)
    page_digest_items = PLT.get_all(page_digest_plt)

    assert map_size(page_digest_items) == @num_pages

    assert page_digest_items[Module1] =~ ~r/^[A-Z2-7]{8}$/
  end

  defp test_runtime_bundle(opts) do
    num_runtime_bundles =
      opts[:static_dir]
      |> Path.join("runtime-????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_bundles == 1

    num_runtime_source_maps =
      opts[:static_dir]
      |> Path.join("runtime-????????.js.map")
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_source_maps == 1
  end

  # Helper function to wait for lock file to appear and return its content
  # Appends a comment to one of this file's fixtures while the function runs, and restores it after:
  # the file's content moves, its meaning does not.
  defp with_edited_fixture(file_name, fun) do
    path = Path.join(@compile_fixtures_dir, file_name)
    content = File.read!(path)
    File.write!(path, content <> "\n// edited\n")

    try do
      fun.()
    after
      File.write!(path, content)
    end
  end

  defp wait_for_lock_file(lock_path, timeout_ms, end_time \\ nil) do
    end_time = end_time || System.system_time(:millisecond) + timeout_ms

    if System.system_time(:millisecond) > end_time do
      flunk("Lock file did not appear within timeout")
    end

    if File.exists?(lock_path) do
      case File.read(lock_path) do
        {:ok, content} ->
          content

        {:error, _reason} ->
          Process.sleep(10)
          wait_for_lock_file(lock_path, timeout_ms, end_time)
      end
    else
      Process.sleep(10)
      wait_for_lock_file(lock_path, timeout_ms, end_time)
    end
  end

  setup_all do
    original_hologram_start_flag = System.get_env("HOLOGRAM_START")
    System.put_env("HOLOGRAM_START", "1")

    on_exit(fn ->
      Cache.reset()

      if original_hologram_start_flag do
        System.put_env("HOLOGRAM_START", original_hologram_start_flag)
      else
        System.delete_env("HOLOGRAM_START")
      end
    end)

    clean_dir(@test_dir)
    File.mkdir!(@assets_dir)
    File.mkdir!(@build_dir)

    test_node_modules_path = Path.join(@assets_dir, "node_modules")

    opts = [
      assets_dir: @assets_dir,
      build_dir: @build_dir,
      esbuild_bin_path: Path.join([test_node_modules_path, ".bin", "esbuild"]),
      js_dir: Path.join(@lib_assets_dir, "js"),
      node_modules_path: test_node_modules_path,
      static_dir: @static_dir,
      tmp_dir: @tmp_dir
    ]

    test_package_json_path = Path.join(@assets_dir, "package.json")
    FileUtils.cp_p!(@lib_package_json_path, test_package_json_path)

    Compiler.install_js_deps(@assets_dir, @build_dir)

    [opts: opts]
  end

  setup do
    File.rm(@lock_path)

    clean_dir(@static_dir)
    clean_dir(@tmp_dir)
  end

  describe "compiler skipping" do
    setup do
      on_exit(fn -> System.put_env("HOLOGRAM_START", "1") end)
    end

    test "skips compilation when HOLOGRAM_START env var is not set", %{opts: opts} do
      System.delete_env("HOLOGRAM_START")

      assert run(opts) == :noop
    end

    test "skips compilation for language server builds", %{opts: opts} do
      ls_opts = Keyword.put(opts, :build_dir, Path.join(opts[:build_dir], ".expert"))

      assert run(ls_opts) == :noop
    end

    test "runs compilation when HOLOGRAM_START env var is set to 1", %{opts: opts} do
      System.put_env("HOLOGRAM_START", "1")

      assert run(opts) == :ok
    end
  end

  test "compilation artifacts", %{opts: initial_opts} do
    opts = setup_empty_assets_and_build_dirs(initial_opts)

    # Test case 1: when there are no previous build artifacts
    run(opts)
    test_build_artifacts(opts)

    first_run_module_info = load_module_info_items(opts)[Module1]

    # Test case 2: when there are previous build artifacts
    generate_old_bundle("old_bundle_1", opts)
    generate_old_bundle("old_bundle_2", opts)
    run(opts)
    test_build_artifacts(opts)
    test_old_build_static_artifacts_cleanup(opts)

    # Reused or re-read, an untouched module keeps its entry across runs
    assert load_module_info_items(opts)[Module1] == first_run_module_info
  end

  describe "kept compile state" do
    setup %{opts: opts} do
      # Reset on the way out too: a test here can leave faked entries in the cache that nothing
      # rereads, since the modules they are for are not reported as compiled.
      on_exit(&Cache.reset/0)
      forget_kept_state(opts)
    end

    test "the second run keeps what the first run built", %{opts: opts} do
      run(opts)
      %{call_graph: call_graph, ir_plt: ir_plt, module_infos: module_infos} = cache_state()

      assert module_infos == load_module_info_items(opts)

      run(opts)

      assert %{call_graph: ^call_graph, ir_plt: ^ir_plt, module_infos: module_infos} =
               cache_state()

      assert module_infos == load_module_info_items(opts)
    end

    test "keeps the modules whose beams a save can rewrite", %{opts: opts} do
      run(opts)

      editable_modules = cache_state().editable_modules

      assert editable_modules ==
               MapSet.new(Reflection.list_editable_beams(), fn {module, _beam_path} -> module end)

      assert MapSet.member?(editable_modules, Module1)
    end

    test "holds the IR of the pages and the modules they reach, and not of the rest", %{
      opts: opts
    } do
      run(opts)

      ir_modules = PLT.keys(cache_state().ir_plt)

      assert Module1 in ir_modules
      assert Module2 in ir_modules
      refute @unreached_module in ir_modules
    end

    test "an edited module gets its IR rebuilt", %{opts: opts} do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        ir_plt: ir_plt,
        module_infos: module_infos
      } = cache_state()

      PLT.put(ir_plt, Module1, :stale)

      # An edit is compiled, so the compiler reports the module and its beam is read.
      report_compiled(Module1)
      edited_info = %{module_infos[Module1] | digest: "edited"}

      put_kept_module_infos(
        %{module_infos | Module1 => edited_info},
        dumped_at,
        editable_modules
      )

      run(opts)

      assert {:ok, %IR.ModuleDefinition{module: %IR.AtomType{value: Module1}}} =
               PLT.get(ir_plt, Module1)
    end

    test "a run with no changes builds no IR and loads no call graph", %{opts: opts} do
      run(opts)

      counted_mfas = [{IR, :for_module, 2}, {CallGraph, :load, 2}]

      # Call counts are kept per function for every process, so the run's tasks are counted too.
      Enum.each(counted_mfas, &:erlang.trace_pattern(&1, true, [:call_count]))

      try do
        run(opts)

        Enum.each(counted_mfas, fn mfa ->
          assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
        end)
      after
        Enum.each(counted_mfas, &:erlang.trace_pattern(&1, false, [:call_count]))
      end
    end

    test "a run with no changes reads no module against the whole code path", %{opts: opts} do
      run(opts)

      full_scan_mfa = {Compiler, :build_module_info_plt!, 3}
      warm_scan_mfa = {Compiler, :patch_module_info_plt!, 5}

      Enum.each([full_scan_mfa, warm_scan_mfa], &:erlang.trace_pattern(&1, true, [:call_count]))

      try do
        run(opts)

        assert :erlang.trace_info(full_scan_mfa, :call_count) == {:call_count, 0}
        assert :erlang.trace_info(warm_scan_mfa, :call_count) == {:call_count, 1}
      after
        Enum.each(
          [full_scan_mfa, warm_scan_mfa],
          &:erlang.trace_pattern(&1, false, [:call_count])
        )
      end
    end

    test "a removed module loses its IR entry, its encodings and its call graph vertices", %{
      opts: opts
    } do
      run(opts)

      %{
        call_graph: call_graph,
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        ir_plt: ir_plt,
        module_infos: module_infos
      } = cache_state()

      removed_vertex = {:removed_module, :fun, 0}

      PLT.put(ir_plt, :removed_module, :ir)
      PLT.put(cache_state().encode_plt, {:removed_module, :fun, 0}, "js")
      CallGraph.add_vertex(call_graph, removed_vertex)
      assert CallGraph.has_vertex?(call_graph, removed_vertex)

      module_infos
      |> Map.put(:removed_module, %{digest: "removed"})
      |> put_kept_module_infos(dumped_at, MapSet.put(editable_modules, :removed_module))

      run(opts)

      assert PLT.get(ir_plt, :removed_module) == :error
      refute CallGraph.has_vertex?(call_graph, removed_vertex)
      assert PLT.get(cache_state().encode_plt, {:removed_module, :fun, 0}) == :error
    end

    test "copies the kept entries of the modules outside the editable applications", %{
      opts: opts
    } do
      run(opts)

      %{dumped_at: dumped_at, editable_modules: editable_modules, module_infos: module_infos} =
        cache_state()

      # A library's beam is not rewritten while the VM runs, so its kept entry is taken as it is:
      # the mtime faked here would make a check of the beam read it, and no page is rebuilt for it.
      kept_info = %{module_infos[Enum] | digest: "kept", mtime: 0}
      put_kept_module_infos(%{module_infos | Enum => kept_info}, dumped_at, editable_modules)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().module_infos[Enum] == kept_info
    end

    test "picks up a module added to an editable application", %{opts: opts} do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        ir_plt: ir_plt,
        module_infos: module_infos
      } = cache_state()

      # The state of a compile that ran before the module existed.
      PLT.delete(ir_plt, Module1)

      module_infos
      |> Map.delete(Module1)
      |> put_kept_module_infos(dumped_at, editable_modules)

      run(opts)

      assert cache_state().module_infos[Module1] == module_infos[Module1]
      assert {:ok, %IR.ModuleDefinition{}} = PLT.get(ir_plt, Module1)
    end

    test "copies the kept entry of an editable module the compiler did not report", %{
      opts: opts
    } do
      run(opts)

      %{dumped_at: dumped_at, editable_modules: editable_modules, module_infos: module_infos} =
        cache_state()

      # The mtime faked here would make a check of the beam read it, so a kept digest shows that
      # the beam was not checked, and no page is rebuilt for it.
      kept_info = %{module_infos[Module2] | digest: "kept", mtime: 0}
      put_kept_module_infos(%{module_infos | Module2 => kept_info}, dumped_at, editable_modules)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().module_infos[Module2] == kept_info
    end

    test "a run with no changes checks only the beams of the protocols", %{opts: opts} do
      run(opts)

      %{editable_modules: editable_modules, module_infos: module_infos} = cache_state()

      num_editable_protocols =
        Enum.count(editable_modules, fn module -> module_infos[module].protocol? end)

      # The function a beam is checked against its entry through, which is private, so its local
      # calls are counted.
      mfa = {Compiler, :reusable_module_info, 4}
      :erlang.trace_pattern(mfa, true, [:local, :call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, num_editable_protocols}
      after
        :erlang.trace_pattern(mfa, false, [:local, :call_count])
      end

      assert num_editable_protocols > 0
    end

    test "a run into a fresh build dir dumps the call graph of what the pages reach", %{
      opts: opts
    } do
      run(opts)

      fresh_build_dir_opts = Keyword.put(opts, :build_dir, setup_empty_build_dir())
      run(fresh_build_dir_opts)

      test_call_graph(fresh_build_dir_opts)
    end

    test "a run into an empty build dir holds only the reached modules in the graph", %{
      opts: opts
    } do
      Cache.reset()
      run(Keyword.put(opts, :build_dir, setup_empty_build_dir()))

      %{call_graph: call_graph, module_infos: module_infos} = cache_state()
      graph_modules = CallGraph.modules(call_graph)

      assert Module1 in graph_modules
      assert Module2 in graph_modules
      refute @unreached_module in graph_modules
      refute CallGraph.has_vertex?(call_graph, {@unreached_module, :my_fun_1, 0})
      assert MapSet.size(graph_modules) < map_size(module_infos)
    end

    test "a run with no changes does not walk the graph", %{opts: opts} do
      run(opts)

      Code.ensure_loaded!(CallGraph)

      assert count_calls({CallGraph, :build_reach, 3}, fn -> run(opts) end) == 0
    end

    test "an edit of a module the graph does not hold builds no IR", %{opts: opts} do
      run(opts)

      assert @unreached_module in cache_state().editable_modules

      fake_edit(@unreached_module)

      Code.ensure_loaded!(IR)
      count = count_calls({IR, :for_module, 2}, fn -> run(opts) end)

      # The edit was seen: the digest read from the beam replaced the faked one.
      assert cache_state().module_infos[@unreached_module].digest != "edited"

      assert count == 0
      refute PLT.member?(cache_state().ir_plt, @unreached_module)
      refute @unreached_module in CallGraph.modules(cache_state().call_graph)
    end

    test "an edit that starts reaching a module builds it", %{opts: opts} do
      run(opts)

      take_out_of_graph(Module2)
      fake_edit(Module1)

      run(opts)

      %{call_graph: call_graph, ir_plt: ir_plt} = cache_state()

      assert Module2 in CallGraph.modules(call_graph)
      assert CallGraph.has_vertex?(call_graph, {Module2, :template, 0})
      assert PLT.member?(ir_plt, Module2)
    end

    test "a run with no changes rebuilds no page", %{opts: opts} do
      run(opts)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      test_page_bundles(opts)
    end

    test "a page an earlier run left pending is rebuilt with no edit", %{opts: opts} do
      run(opts)

      Cache.put_pending_pages([Module1])

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().pending_pages == MapSet.new()
      test_page_bundles(opts)
    end

    test "a page rebuilt with no edit encodes no function again", %{opts: opts} do
      run(opts)
      put_pending_kept_pages(1)

      assert count_calls(@encode_function_mfa, fn -> run(opts) end) == 0
      test_page_bundles(opts)
    end

    test "an edited module's functions are encoded again, fewer than from scratch", %{opts: opts} do
      run(opts)

      fake_edit(Module2)
      kept_count = count_calls(@encode_function_mfa, fn -> run(opts) end)

      fake_edit(Module2)
      %{encode_plt: encode_plt} = cache_state()
      PLT.reset(encode_plt)
      scratch_count = count_calls(@encode_function_mfa, fn -> run(opts) end)

      assert kept_count > 0
      assert kept_count < scratch_count
      test_page_bundles(opts)
    end

    test "a removed module loses its encodings", %{opts: opts} do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        encode_plt: encode_plt,
        module_infos: module_infos
      } = cache_state()

      PLT.put(encode_plt, {:removed_module, :fun, 0}, "js")

      module_infos
      |> Map.put(:removed_module, %{digest: "removed"})
      |> put_kept_module_infos(dumped_at, MapSet.put(editable_modules, :removed_module))

      run(opts)

      assert PLT.get(encode_plt, {:removed_module, :fun, 0}) == :error
    end

    test "changed async MFAs empty the kept encodings", %{opts: opts} do
      run(opts)

      %{encode_plt: encode_plt, encoding_inputs: encoding_inputs} = cache_state()
      async_mfas = MapSet.put(encoding_inputs.async_mfas, {Module1, :fun_1, 0})
      Cache.put_encoding_inputs(%{encoding_inputs | async_mfas: async_mfas})

      # The async MFAs are walked again only when the graph changes, so the page is edited. The
      # marker belongs to a module the edit does not touch and the compile keeps, so only emptying
      # the whole PLT drops it.
      fake_edit(Module1)
      PLT.put(encode_plt, {Module2, :marker, 0}, "marker")

      run(opts)

      assert PLT.get(encode_plt, {Module2, :marker, 0}) == :error
    end

    test "a changed client stacktraces setting empties the kept encodings", %{opts: opts} do
      run(opts)
      put_pending_kept_pages(1)

      %{encoding_inputs: encoding_inputs} = cache_state()
      stacktraces? = not encoding_inputs.client_stacktraces?
      Cache.put_encoding_inputs(%{encoding_inputs | client_stacktraces?: stacktraces?})

      assert count_calls(@encode_function_mfa, fn -> run(opts) end) > 0
    end

    test "keeps what the encodings were made with", %{opts: opts} do
      run(opts)

      assert %{async_mfas: %MapSet{}, client_stacktraces?: stacktraces?} =
               cache_state().encoding_inputs

      assert stacktraces? == Hologram.client_stacktraces?()
    end

    test "keeps the encodings of the modules whose IR it keeps, no others", %{opts: opts} do
      run(opts)

      %{encode_plt: encode_plt, ir_plt: ir_plt} = cache_state()

      # As an earlier compile would have left them, had a page reached the module then: a module's
      # functions are encoded only from its IR.
      PLT.put(ir_plt, @unreached_module, :ir)
      PLT.put(encode_plt, {@unreached_module, :fun_1, 0}, "js")

      run(opts)

      assert PLT.get(encode_plt, {@unreached_module, :fun_1, 0}) == :error

      encoded_modules =
        encode_plt
        |> PLT.keys()
        |> MapSet.new(fn {module, _function, _arity} -> module end)

      assert MapSet.size(encoded_modules) > 0
      assert MapSet.subset?(encoded_modules, MapSet.new(PLT.keys(ir_plt)))
    end

    test "a pending page that no longer exists is forgotten", %{opts: opts} do
      run(opts)

      Cache.put_pending_pages([@unreached_module])

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().pending_pages == MapSet.new()
    end

    test "asks for the pages to build in batches", %{opts: opts} do
      run(opts)

      affected_pages = put_pending_kept_pages(3)
      num_affected_pages = MapSet.size(affected_pages)

      {record_remaining, recorded_remaining} = record_calls()
      {record_built, recorded_built} = record_calls()

      next_batch = fn remaining_pages, _links ->
        record_remaining.(remaining_pages)
        [Enum.min(remaining_pages)]
      end

      # The page digest dump is read as each batch is reported, to see that it names every page.
      bundles_built = fn built ->
        record_built.({built, map_size(load_page_digest_items(opts))})
      end

      run(Keyword.merge(opts, bundles_built: bundles_built, next_batch: next_batch))

      remaining = recorded_remaining.()

      assert hd(remaining) == affected_pages
      assert Enum.map(remaining, &MapSet.size/1) == Enum.to_list(num_affected_pages..1//-1)

      built = recorded_built.()

      assert MapSet.new(built, fn {[page_module], _num_digests} -> page_module end) ==
               affected_pages

      assert Enum.all?(built, fn {_built, num_digests} -> num_digests == @num_pages end)

      assert cache_state().pending_pages == MapSet.new()
      test_page_bundles(opts)
    end

    test "stopping leaves the pages not built pending, with the bundles they had", %{opts: opts} do
      run(opts)

      old_digests = load_page_digest_items(opts)

      %{pages_plt: pages_plt} = cache_state()
      old_pages = PLT.get_all(pages_plt)

      affected_pages = put_pending_kept_pages(3)

      built_page = Enum.min(affected_pages)
      not_built_pages = MapSet.delete(affected_pages, built_page)

      next_batch = fn remaining_pages, _links ->
        if remaining_pages == affected_pages, do: [built_page], else: :stop
      end

      run(Keyword.put(opts, :next_batch, next_batch))

      assert cache_state().pending_pages == not_built_pages

      assert Enum.all?(not_built_pages, fn page_module ->
               File.exists?(old_pages[page_module].bundle_info.static_bundle_path)
             end)

      new_digests = load_page_digest_items(opts)

      assert map_size(new_digests) == @num_pages

      assert Map.take(new_digests, Enum.to_list(not_built_pages)) ==
               Map.take(old_digests, Enum.to_list(not_built_pages))

      test_page_bundles(opts)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) ==
                 {:call_count, MapSet.size(not_built_pages)}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().pending_pages == MapSet.new()
    end

    test "the runtime is built with the first batch", %{opts: opts} do
      run(opts)

      runtime_module = find_editable_runtime_module()
      fake_edit(runtime_module)
      Cache.put_pending_pages([Module1])

      {record_built, recorded_built} = record_calls()

      next_batch = fn remaining_pages, _links -> [Enum.min(remaining_pages)] end

      # Whether the runtime is kept and its bundle on disk when a batch is reported.
      bundles_built = fn built ->
        runtime = cache_state().runtime

        record_built.(
          {built, runtime != nil and File.exists?(runtime.bundle_info.static_bundle_path)}
        )
      end

      run(Keyword.merge(opts, bundles_built: bundles_built, next_batch: next_batch))

      assert [{[:runtime, _first_page], true} | rest] = recorded_built.()
      refute Enum.any?(rest, fn {built, _runtime_on_disk?} -> :runtime in built end)

      test_runtime_bundle(opts)
    end

    test "the runtime is built alone when the first answer is to stop", %{opts: opts} do
      run(opts)

      runtime_module = find_editable_runtime_module()
      fake_edit(runtime_module)
      Cache.put_pending_pages([Module1])

      {record_built, recorded_built} = record_calls()

      run(
        Keyword.merge(opts,
          bundles_built: record_built,
          next_batch: fn _remaining_pages, _links -> :stop end
        )
      )

      assert recorded_built.() == [[:runtime]]
      assert MapSet.member?(cache_state().pending_pages, Module1)
      test_runtime_bundle(opts)
    end

    test "the page links name the pages each page links to", %{opts: opts} do
      run(opts)

      Cache.put_pending_pages([Module1])

      {record_links, recorded_links} = record_calls()

      next_batch = fn remaining_pages, links ->
        record_links.(links)
        MapSet.to_list(remaining_pages)
      end

      run(Keyword.put(opts, :next_batch, next_batch))

      assert [links] = recorded_links.()
      assert map_size(links) == @num_pages
      assert MapSet.member?(links[@linking_page], @linked_page)
      refute MapSet.member?(links[@linking_page], @linking_page)
    end

    test "a page to rebuild links to the pages its kept state names", %{opts: opts} do
      run(opts)

      Cache.put_pending_pages([@linking_page])

      {record_links, recorded_links} = record_calls()

      next_batch = fn remaining_pages, links ->
        record_links.(links)
        MapSet.to_list(remaining_pages)
      end

      run(Keyword.put(opts, :next_batch, next_batch))

      assert [links] = recorded_links.()
      assert MapSet.member?(links[@linking_page], @linked_page)
    end

    test "a page no compile has built links to the pages its listing names", %{opts: opts} do
      run(opts)

      forget_kept_state(opts)

      {record_links, recorded_links} = record_calls()

      next_batch = fn remaining_pages, links ->
        record_links.(links)
        MapSet.to_list(remaining_pages)
      end

      run(Keyword.put(opts, :next_batch, next_batch))

      assert [links] = recorded_links.()
      assert map_size(links) == @num_pages
      assert MapSet.member?(links[@linking_page], @linked_page)
    end

    test "a run into an empty build dir builds each module's IR once", %{opts: opts} do
      Cache.reset()
      fresh_build_dir_opts = Keyword.put(opts, :build_dir, setup_empty_build_dir())

      Code.ensure_loaded!(IR)
      count = count_calls({IR, :for_module, 2}, fn -> run(fresh_build_dir_opts) end)

      # Fewer than the modules it knows: the IR of the modules nothing reaches is never built.
      assert count < map_size(load_module_info_items(fresh_build_dir_opts))
      test_page_bundles(fresh_build_dir_opts)
    end

    test "lists a page's MFAs when its batch is built", %{opts: opts} do
      run(opts)
      put_pending_kept_pages(3)

      mfa = {CallGraph, :list_page_mfas, 4}
      {record_count, recorded_counts} = record_calls()

      # The pages listed so far, read as each batch is asked for.
      next_batch = fn remaining_pages, _links ->
        {:call_count, count} = :erlang.trace_info(mfa, :call_count)
        record_count.(count)
        [Enum.min(remaining_pages)]
      end

      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(Keyword.put(opts, :next_batch, next_batch))
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert recorded_counts.() == [0, 1, 2]
      test_page_bundles(opts)
    end

    test "stopping lists no MFAs of the pages left pending", %{opts: opts} do
      run(opts)
      affected_pages = put_pending_kept_pages(3)

      next_batch = fn remaining_pages, _links ->
        if remaining_pages == affected_pages, do: [Enum.min(remaining_pages)], else: :stop
      end

      count =
        count_calls({CallGraph, :list_page_mfas, 4}, fn ->
          run(Keyword.put(opts, :next_batch, next_batch))
        end)

      assert count == 1
    end

    test "shares the graph with the batches once", %{opts: opts} do
      run(opts)
      put_pending_kept_pages(3)

      next_batch = fn remaining_pages, _links -> [Enum.min(remaining_pages)] end

      count =
        count_calls({CallGraph, :with_shared_graph, 2}, fn ->
          run(Keyword.put(opts, :next_batch, next_batch))
        end)

      assert count == 1
    end

    test "a run with nothing to rebuild shares no graph", %{opts: opts} do
      run(opts)

      assert count_calls({CallGraph, :with_shared_graph, 2}, fn -> run(opts) end) == 0
    end

    test "a run with no page states lists each page once", %{opts: opts} do
      run(opts)
      forget_kept_state(opts)

      assert count_calls({CallGraph, :list_page_mfas, 4}, fn -> run(opts) end) == @num_pages
      test_page_bundles(opts)
    end

    test "an empty batch is refused", %{opts: opts} do
      run(opts)

      Cache.put_pending_pages([Module1])

      assert_raise ArgumentError, ~r/non-empty list of pages or :stop/, fn ->
        run(Keyword.put(opts, :next_batch, fn _remaining_pages, _links -> [] end))
      end
    end

    test "a batch holding a page not left to build is refused", %{opts: opts} do
      run(opts)

      Cache.put_pending_pages([Module1])

      assert_raise ArgumentError, ~r/not left to build/, fn ->
        run(Keyword.put(opts, :next_batch, fn _remaining_pages, _links -> [@linked_page] end))
      end
    end

    test "a pending page whose kept bundle is gone is not named in the page digest dump", %{
      opts: opts
    } do
      run(opts)

      [page_module] =
        1
        |> put_pending_kept_pages()
        |> MapSet.to_list()

      %{pages_plt: pages_plt} = cache_state()
      {:ok, page_state} = PLT.get(pages_plt, page_module)
      File.rm!(page_state.bundle_info.static_bundle_path)

      run(Keyword.put(opts, :next_batch, fn _remaining_pages, _links -> :stop end))

      page_digests = load_page_digest_items(opts)

      refute Map.has_key?(page_digests, page_module)
    end

    test "a pending page whose kept source map is gone is not named in the page digest dump", %{
      opts: opts
    } do
      run(opts)

      [page_module] =
        1
        |> put_pending_kept_pages()
        |> MapSet.to_list()

      %{pages_plt: pages_plt} = cache_state()
      {:ok, page_state} = PLT.get(pages_plt, page_module)
      File.rm!(page_state.bundle_info.static_source_map_path)

      run(Keyword.put(opts, :next_batch, fn _remaining_pages, _links -> :stop end))

      page_digests = load_page_digest_items(opts)

      refute Map.has_key?(page_digests, page_module)
    end

    test "a batch callback that exits leaves no lock behind", %{opts: opts} do
      run(opts)

      put_pending_kept_pages(1)

      # What a live reload pass whose scheduler went away gets from its next_batch callback.
      next_batch = fn _remaining_pages, _links -> exit(:noproc) end

      assert catch_exit(run(Keyword.put(opts, :next_batch, next_batch))) == :noproc
      refute File.exists?(@lock_path)
    end

    test "rebuilds the pages reaching an edited module, with a full compile's result", %{
      opts: opts
    } do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        module_infos: module_infos,
        pages_plt: pages_plt
      } = cache_state()

      pages_reaching_module_2 =
        pages_plt
        |> PLT.get_all()
        |> Enum.count(fn {_page_module, page_state} ->
          MapSet.member?(page_state.modules, Module2)
        end)

      # An edit is compiled, so the compiler reports the module and its beam is read.
      report_compiled(Module2)
      edited_info = %{module_infos[Module2] | digest: "edited"}

      put_kept_module_infos(
        %{module_infos | Module2 => edited_info},
        dumped_at,
        editable_modules
      )

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, pages_reaching_module_2}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert pages_reaching_module_2 < @num_pages
      partial_digests = load_page_digest_items(opts)

      forget_kept_state(opts)
      run(opts)

      assert load_page_digest_items(opts) == partial_digests
      test_page_bundles(opts)
    end

    test "keeps the bundle inputs", %{opts: opts} do
      run(opts)

      %{bundle_inputs: bundle_inputs, module_info_plt: module_info_plt} = cache_state()

      assert bundle_inputs == Compiler.build_bundle_inputs(module_info_plt, opts)
    end

    test "a run with unchanged bundle inputs builds no bundle", %{opts: opts} do
      run(opts)

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == 0
      test_page_bundles(opts)
    end

    test "rebuilds every page and the runtime when the client stack traces setting changed", %{
      opts: opts
    } do
      on_exit(fn -> Application.delete_env(:hologram, :client_stacktraces) end)
      run(opts)

      Application.put_env(:hologram, :client_stacktraces, not Hologram.client_stacktraces?())

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == @num_pages + 1
      assert cache_state().bundle_inputs.client_stacktraces? == Hologram.client_stacktraces?()
      test_page_bundles(opts)
      test_runtime_bundle(opts)
    end

    test "dumps the compile state with the bundles it built", %{opts: opts} do
      run(opts)

      {1, compile_state} = load_compile_state_dump(opts)
      state = cache_state()

      assert compile_state.pages == PLT.get_all(state.pages_plt)
      assert map_size(compile_state.pages) == @num_pages
      assert compile_state.runtime == state.runtime
      assert compile_state.runtime != nil
      assert compile_state.pending_pages == MapSet.new()
      assert compile_state.app_versions == state.app_versions
      assert compile_state.bundle_inputs == state.bundle_inputs
      assert compile_state.encoding_inputs == state.encoding_inputs
      assert compile_state.module_metadata == state.module_metadata
      assert compile_state.template_modules == state.template_modules
    end

    test "dumps the pages a stopped run left pending", %{opts: opts} do
      run(opts)
      pending_pages = put_pending_kept_pages(2)

      run(Keyword.put(opts, :next_batch, fn _remaining_pages, _links -> :stop end))

      {1, compile_state} = load_compile_state_dump(opts)
      assert compile_state.pending_pages == pending_pages
    end

    test "a run that changes nothing writes no compile state", %{opts: opts} do
      run(opts)

      assert count_compile_state_writes(fn -> run(opts) end) == 0
    end

    test "a run that rebuilds a page writes the compile state before and after its batches", %{
      opts: opts
    } do
      run(opts)
      fake_edit(Module2)

      assert count_compile_state_writes(fn -> run(opts) end) == 2
    end

    test "a new VM with nothing changed bundles nothing", %{opts: opts} do
      run(opts)
      page_digests = load_page_digest_items(opts)
      Cache.reset()

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == 0
      assert load_page_digest_items(opts) == page_digests
      test_page_bundles(opts)
      test_runtime_bundle(opts)
    end

    test "a new VM with nothing changed builds no IR", %{opts: opts} do
      run(opts)
      Cache.reset()

      Code.ensure_loaded!(IR)

      assert count_calls({IR, :for_module, 2}, fn -> run(opts) end) == 0
    end

    test "a new VM with nothing changed writes no dump", %{opts: opts} do
      run(opts)
      Cache.reset()

      assert count_compile_state_writes(fn ->
               assert count_dumps(fn -> run(opts) end) == [0, 0]
             end) == 0
    end

    test "a new VM whose call graph dump is gone writes both dumps", %{opts: opts} do
      run(opts)

      opts[:build_dir]
      |> Path.join(Reflection.call_graph_dump_file_name())
      |> File.rm!()

      Cache.reset()

      assert count_dumps(fn -> run(opts) end) == [1, 1]
    end

    test "a new VM whose module infos changed writes the module info dump", %{opts: opts} do
      run(opts)
      fake_edit_in_dump(Module2, opts)
      Cache.reset()

      assert count_dumps(fn -> run(opts) end) == [1, 1]
      assert load_module_info_items(opts)[Module2].digest != "edited"
    end

    test "a new VM with nothing changed encodes nothing", %{opts: opts} do
      run(opts)
      Cache.reset()

      assert count_calls(@encode_function_mfa, fn -> run(opts) end) == 0
    end

    test "a new VM with nothing changed lists no page and clones no graph", %{opts: opts} do
      run(opts)
      Cache.reset()

      mfas = [
        {CallGraph, :clone, 2},
        {CallGraph, :list_page_mfas, 4},
        {CallGraph, :list_runtime_mfas, 2}
      ]

      Enum.each(mfas, &:erlang.trace_pattern(&1, true, [:call_count]))

      try do
        run(opts)

        assert Enum.map(mfas, &:erlang.trace_info(&1, :call_count)) == [
                 {:call_count, 0},
                 {:call_count, 0},
                 {:call_count, 0}
               ]
      after
        Enum.each(mfas, &:erlang.trace_pattern(&1, false, [:call_count]))
      end
    end

    test "a new VM with nothing changed validates no template", %{opts: opts} do
      run(opts)
      Cache.reset()

      assert count_validated_templates(fn -> run(opts) end) == 0
    end

    test "a new VM with nothing changed keeps the runtime state and every page state it loaded",
         %{
           opts: opts
         } do
      run(opts)
      %{runtime: runtime} = cache_state()
      Cache.reset()

      mfas = [{Cache, :put_page, 3}, {Cache, :put_runtime, 1}]
      Enum.each(mfas, &:erlang.trace_pattern(&1, true, [:call_count]))

      try do
        run(opts)

        assert Enum.map(mfas, &:erlang.trace_info(&1, :call_count)) == [
                 {:call_count, 0},
                 {:call_count, 0}
               ]
      after
        Enum.each(mfas, &:erlang.trace_pattern(&1, false, [:call_count]))
      end

      %{pages_plt: pages_plt, runtime: kept_runtime} = cache_state()

      assert kept_runtime == runtime
      assert length(PLT.keys(pages_plt)) == @num_pages
    end

    test "a new VM rebuilds the pages reaching a module edited since the dumps", %{opts: opts} do
      run(opts)
      pages_reaching_module_2 = count_pages_reaching(Module2)
      fake_edit_in_dump(Module2, opts)
      Cache.reset()

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == pages_reaching_module_2
      assert pages_reaching_module_2 < @num_pages
      test_page_bundles(opts)
    end

    test "a new VM rebuilds the pages an earlier run left pending", %{opts: opts} do
      run(opts)
      pages_reaching_module_2 = count_pages_reaching(Module2)
      fake_edit_in_dump(Module2, opts)
      Cache.reset()
      run(Keyword.put(opts, :next_batch, fn _remaining_pages, _links -> :stop end))
      Cache.reset()

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == pages_reaching_module_2
      test_page_bundles(opts)
    end

    test "a new VM whose bundle inputs differ rebuilds every page and the runtime", %{
      opts: opts
    } do
      on_exit(fn -> Application.delete_env(:hologram, :client_stacktraces) end)
      run(opts)
      Cache.reset()

      Application.put_env(:hologram, :client_stacktraces, not Hologram.client_stacktraces?())

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == @num_pages + 1
      test_page_bundles(opts)
    end

    test "a compile state dump of another version is not loaded", %{opts: opts} do
      run(opts)
      dump_path = Path.join(opts[:build_dir], Reflection.compile_state_dump_file_name())
      File.write!(dump_path, SerializationUtils.serialize({0, %{}}))
      Cache.reset()

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == @num_pages + 1
      assert {1, _compile_state} = load_compile_state_dump(opts)
    end

    test "a compile state dump without a call graph dump is not loaded", %{opts: opts} do
      run(opts)

      opts[:build_dir]
      |> Path.join(Reflection.call_graph_dump_file_name())
      |> File.rm!()

      Cache.reset()

      assert count_calls({Compiler, :bundle, 4}, fn -> run(opts) end) == @num_pages + 1
      test_page_bundles(opts)
    end

    test "rebuilds the page reaching a module whose imported JavaScript changed", %{opts: opts} do
      run(opts)
      {record_built, recorded_built} = record_calls()

      with_edited_fixture("js_fixture.mjs", fn ->
        run(Keyword.put(opts, :bundles_built, record_built))
      end)

      assert recorded_built.() == [[Module3]]
      test_page_bundles(opts)
    end

    test "a new VM rebuilds the page reaching a module whose imported JavaScript changed", %{
      opts: opts
    } do
      run(opts)
      Cache.reset()
      {record_built, recorded_built} = record_calls()

      with_edited_fixture("js_fixture.mjs", fn ->
        run(Keyword.put(opts, :bundles_built, record_built))
      end)

      assert recorded_built.() == [[Module3]]
      test_page_bundles(opts)
    end

    test "rebuilds the page again once an edit of its imported JavaScript is undone", %{
      opts: opts
    } do
      run(opts)
      with_edited_fixture("js_fixture.mjs", fn -> run(opts) end)
      {record_built, recorded_built} = record_calls()

      run(Keyword.put(opts, :bundles_built, record_built))

      assert recorded_built.() == [[Module3]]
    end

    test "rebuilds the runtime alone when imported JavaScript it registers changed", %{
      opts: opts
    } do
      run(opts)
      assert MapSet.member?(cache_state().runtime.js_binding_modules, Module5)
      {record_built, recorded_built} = record_calls()

      with_edited_fixture("runtime_js_fixture.mjs", fn ->
        run(Keyword.put(opts, :bundles_built, record_built))
      end)

      assert recorded_built.() == [[:runtime]]
      test_runtime_bundle(opts)
    end

    test "a new VM rebuilds the runtime alone when imported JavaScript it registers changed", %{
      opts: opts
    } do
      run(opts)
      Cache.reset()
      {record_built, recorded_built} = record_calls()

      with_edited_fixture("runtime_js_fixture.mjs", fn ->
        run(Keyword.put(opts, :bundles_built, record_built))
      end)

      assert recorded_built.() == [[:runtime]]
      test_runtime_bundle(opts)
    end

    test "keeps the imported JavaScript digests", %{opts: opts} do
      run(opts)

      %{js_import_digests: js_import_digests, module_info_plt: module_info_plt} = cache_state()
      {1, compile_state} = load_compile_state_dump(opts)

      assert js_import_digests == Compiler.build_js_import_digests(module_info_plt)
      assert Map.has_key?(js_import_digests, Path.join(@compile_fixtures_dir, "js_fixture.mjs"))
      assert compile_state.js_import_digests == js_import_digests
    end

    test "rebuilds the runtime alone when the client config it sets changed", %{opts: opts} do
      on_exit(fn -> Application.delete_env(:hologram, :client_error_overlay) end)
      run(opts)

      Application.put_env(:hologram, :client_error_overlay, not Hologram.client_error_overlay?())
      {record_built, recorded_built} = record_calls()

      run(Keyword.put(opts, :bundles_built, record_built))

      assert recorded_built.() == [[:runtime]]
      test_runtime_bundle(opts)
    end

    test "a new VM rebuilds the runtime alone when the client config it sets changed", %{
      opts: opts
    } do
      on_exit(fn -> Application.delete_env(:hologram, :client_error_overlay) end)
      run(opts)
      Cache.reset()

      Application.put_env(:hologram, :client_error_overlay, not Hologram.client_error_overlay?())
      {record_built, recorded_built} = record_calls()

      run(Keyword.put(opts, :bundles_built, record_built))

      assert recorded_built.() == [[:runtime]]
      test_runtime_bundle(opts)
    end

    test "keeps the client config the runtime bundle was built with", %{opts: opts} do
      run(opts)

      assert cache_state().runtime.client_config == Compiler.client_config()
    end

    test "keeps the bundles of the pages it doesn't rebuild", %{opts: opts} do
      run(opts)

      kept_bundle_paths =
        cache_state().pages_plt
        |> PLT.get_all()
        |> Enum.reject(fn {_page_module, page_state} ->
          MapSet.member?(page_state.modules, Module2)
        end)
        |> Enum.map(fn {_page_module, page_state} ->
          page_state.bundle_info.static_bundle_path
        end)

      %{dumped_at: dumped_at, editable_modules: editable_modules, module_infos: module_infos} =
        cache_state()

      report_compiled(Module2)
      edited_info = %{module_infos[Module2] | digest: "edited"}

      put_kept_module_infos(
        %{module_infos | Module2 => edited_info},
        dumped_at,
        editable_modules
      )

      run(opts)

      assert kept_bundle_paths != []
      assert Enum.all?(kept_bundle_paths, &File.exists?/1)
      test_page_bundles(opts)
    end

    test "rebuilds a page whose kept bundle is gone", %{opts: opts} do
      run(opts)

      {:ok, page_state} = PLT.get(cache_state().pages_plt, Module1)
      File.rm!(page_state.bundle_info.static_bundle_path)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert File.exists?(page_state.bundle_info.static_bundle_path)
      test_page_bundles(opts)
    end

    test "forgets the state and the bundle of a page that no longer exists", %{opts: opts} do
      run(opts)

      digest = "AAAAAAAA"
      bundle_path = Path.join(opts[:static_dir], "page-gone_page-#{digest}.js")
      source_map_path = bundle_path <> ".map"
      File.write!(bundle_path, "bundle")
      File.write!(source_map_path, "map")

      Cache.put_page(
        :gone_page,
        %{
          bundle_info: %{
            bundle_name: "page",
            digest: digest,
            entry_name: :gone_page,
            js_inputs: %{},
            static_bundle_path: bundle_path,
            static_source_map_path: source_map_path
          },
          modules: MapSet.new()
        },
        []
      )

      run(opts)

      assert PLT.get(cache_state().pages_plt, :gone_page) == :error
      refute File.exists?(bundle_path)
      refute File.exists?(source_map_path)
    end

    test "rebundles the runtime when a module it carries was edited", %{opts: opts} do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        module_infos: module_infos,
        runtime: runtime
      } = cache_state()

      # Only a beam a save can rewrite is rechecked, so the fake edit must be of such a module.
      runtime_module =
        Enum.find_value(runtime.mfas, fn {module, _function, _arity} ->
          if MapSet.member?(editable_modules, module) and Map.has_key?(module_infos, module),
            do: module
        end)

      report_compiled(runtime_module)
      edited_info = %{module_infos[runtime_module] | digest: "edited"}

      put_kept_module_infos(
        %{module_infos | runtime_module => edited_info},
        dumped_at,
        editable_modules
      )

      # The edit is faked in the kept infos, so the beam and with it the rebuilt bundle are
      # byte-identical and keep their digest; what the test asserts is that the bundle was built.
      mfa = {Compiler, :create_runtime_entry_file, 6}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().runtime.mfas == runtime.mfas
      test_runtime_bundle(opts)
    end

    test "rebundles the runtime when its bundle is gone", %{opts: opts} do
      run(opts)

      runtime = cache_state().runtime
      File.rm!(runtime.bundle_info.static_bundle_path)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert File.exists?(cache_state().runtime.bundle_info.static_bundle_path)
      test_runtime_bundle(opts)
    end

    test "rebundles the runtime when its source map is gone", %{opts: opts} do
      run(opts)

      runtime = cache_state().runtime
      File.rm!(runtime.bundle_info.static_source_map_path)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      test_runtime_bundle(opts)
    end

    test "a run into a fresh static dir rebuilds every bundle", %{opts: opts} do
      run(opts)

      fresh_static_dir = Path.join(@test_dir, "static_fresh")
      clean_dir(fresh_static_dir)
      fresh_static_dir_opts = Keyword.put(opts, :static_dir, fresh_static_dir)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(fresh_static_dir_opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, @num_pages + 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      test_page_bundles(fresh_static_dir_opts)
      test_runtime_bundle(fresh_static_dir_opts)
    end

    test "a run with no changes does not rebuild the app versions", %{opts: opts} do
      run(opts)

      mfa = {Compiler, :build_app_versions, 1}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end
    end

    test "an edit of another application's module rebuilds the app versions", %{opts: opts} do
      run(opts)

      %{
        app_versions: app_versions,
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        module_infos: module_infos
      } = cache_state()

      # Only a beam a save can rewrite is rechecked, and of those the consolidated protocols belong
      # to other applications.
      other_app_module =
        Enum.find_value(module_infos, fn {module, _info} ->
          if MapSet.member?(editable_modules, module) and
               Application.get_application(module) not in [:hologram, nil],
             do: module
        end)

      edited_info = %{module_infos[other_app_module] | digest: "edited", mtime: 0}

      put_kept_module_infos(
        %{module_infos | other_app_module => edited_info},
        dumped_at,
        editable_modules
      )

      mfa = {Compiler, :build_app_versions, 1}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().app_versions == app_versions
    end

    test "a run whose walk builds a module rebuilds the app versions", %{opts: opts} do
      run(opts)

      take_out_of_graph(Module2)
      fake_edit(Module1)

      assert count_calls({Compiler, :build_app_versions, 1}, fn -> run(opts) end) == 1
    end

    test "the kept app versions are the ones a full compile finds", %{opts: opts} do
      run(opts)
      run(opts)
      warm_app_versions = cache_state().app_versions

      forget_kept_state(opts)
      run(opts)

      assert warm_app_versions == cache_state().app_versions
      assert warm_app_versions != []
    end

    test "a run with no changes walks no async MFAs", %{opts: opts} do
      run(opts)

      assert count_calls({CallGraph, :list_async_mfas, 1}, fn -> run(opts) end) == 0
    end

    test "an edit of a module the graph does not hold walks no async MFAs", %{opts: opts} do
      run(opts)

      fake_edit(@unreached_module)

      assert count_calls({CallGraph, :list_async_mfas, 1}, fn -> run(opts) end) == 0
    end

    test "an edit of a page walks the async MFAs again", %{opts: opts} do
      run(opts)

      fake_edit(Module1)

      assert count_calls({CallGraph, :list_async_mfas, 1}, fn -> run(opts) end) == 1
    end

    test "the kept async MFAs are the ones a walk finds", %{opts: opts} do
      run(opts)
      run(opts)

      %{call_graph: call_graph, encoding_inputs: encoding_inputs} = cache_state()

      assert encoding_inputs.async_mfas == CallGraph.list_async_mfas(call_graph)
    end

    test "a run with no changes lists no runtime MFAs", %{opts: opts} do
      run(opts)

      assert count_calls({CallGraph, :list_runtime_mfas, 2}, fn -> run(opts) end) == 0
    end

    test "an edit of a module the graph does not hold lists no runtime MFAs", %{opts: opts} do
      run(opts)

      fake_edit(@unreached_module)

      assert count_calls({CallGraph, :list_runtime_mfas, 2}, fn -> run(opts) end) == 0
    end

    test "an edit of a page lists the runtime MFAs again", %{opts: opts} do
      run(opts)

      fake_edit(Module1)

      assert count_calls({CallGraph, :list_runtime_mfas, 2}, fn -> run(opts) end) == 1
    end

    test "the kept runtime MFAs are the ones a walk finds", %{opts: opts} do
      run(opts)
      run(opts)

      %{call_graph: kept_call_graph, module_infos: module_infos, runtime: runtime} = cache_state()

      module_info_plt = PLT.start(items: Map.to_list(module_infos))
      kept_call_graph_with_infos = %{kept_call_graph | module_info_plt: module_info_plt}

      # The runtime is listed on a copy of the graph without the manually ported MFAs.
      call_graph =
        kept_call_graph_with_infos
        |> CallGraph.clone()
        |> CallGraph.remove_manually_ported_mfas()

      pages = Compiler.list_pages(module_info_plt)

      assert runtime.mfas == CallGraph.list_runtime_mfas(call_graph, pages)

      CallGraph.stop(call_graph)
      PLT.stop(module_info_plt)
    end

    test "a run with no changes copies no call graph", %{opts: opts} do
      run(opts)

      assert count_calls({CallGraph, :clone, 2}, fn -> run(opts) end) == 0
    end

    test "an edit of a module the graph does not hold copies no call graph", %{opts: opts} do
      run(opts)

      fake_edit(@unreached_module)

      assert count_calls({CallGraph, :clone, 2}, fn -> run(opts) end) == 0
    end

    test "a run that rebuilds a pending page copies the call graph once", %{opts: opts} do
      run(opts)

      pending_pages = put_pending_kept_pages(1)
      [page_module] = MapSet.to_list(pending_pages)

      {record_built, recorded_built} = record_calls()

      count =
        count_calls({CallGraph, :clone, 2}, fn ->
          run(Keyword.put(opts, :bundles_built, record_built))
        end)

      assert count == 1
      assert recorded_built.() == [[page_module]]
    end

    test "an edit of a page copies the call graph once", %{opts: opts} do
      run(opts)

      fake_edit(Module1)

      assert count_calls({CallGraph, :clone, 2}, fn -> run(opts) end) == 1
    end

    test "a run with no changes validates no template", %{opts: opts} do
      run(opts)

      assert count_validated_templates(fn -> run(opts) end) == 0
    end

    test "an edit of a module no template uses validates no template", %{opts: opts} do
      run(opts)

      refute Enum.any?(cache_state().template_modules, fn {_templatable, used_modules} ->
               MapSet.member?(used_modules, @unreached_module)
             end)

      fake_edit(@unreached_module)

      assert count_validated_templates(fn -> run(opts) end) == 0
    end

    test "an edit of a page validates the page and the templates that use it", %{opts: opts} do
      run(opts)

      num_users =
        Enum.count(cache_state().template_modules, fn {_templatable, used_modules} ->
          MapSet.member?(used_modules, Module1)
        end)

      fake_edit(Module1)

      assert count_validated_templates(fn -> run(opts) end) == 1 + num_users
    end

    test "an edit of a component validates it and the templates that use it", %{opts: opts} do
      run(opts)

      %{editable_modules: editable_modules, template_modules: template_modules} = cache_state()

      # A component some template uses, whose beam a save can rewrite.
      component_module =
        template_modules
        |> Enum.flat_map(fn {_templatable, used_modules} -> MapSet.to_list(used_modules) end)
        |> Enum.find(fn module ->
          Map.has_key?(template_modules, module) and MapSet.member?(editable_modules, module)
        end)

      num_users =
        Enum.count(template_modules, fn {_templatable, used_modules} ->
          MapSet.member?(used_modules, component_module)
        end)

      fake_edit(component_module)

      assert num_users > 0
      assert count_validated_templates(fn -> run(opts) end) == 1 + num_users
    end

    test "the kept template modules are the ones a full validation finds", %{opts: opts} do
      run(opts)
      fake_edit(Module1)
      run(opts)

      %{module_infos: module_infos, template_modules: template_modules} = cache_state()

      module_info_plt = PLT.start(items: Map.to_list(module_infos))

      templatable_modules =
        Compiler.list_pages(module_info_plt) ++ Compiler.list_components(module_info_plt)

      # The kept IR PLT holds no IR of a component no page reaches, so the full validation builds
      # its own.
      ir_plt = PLT.start()
      Compiler.build_missing_ir!(ir_plt, templatable_modules)

      assert template_modules == Compiler.validate_prop_usages(templatable_modules, ir_plt)

      PLT.stop(ir_plt)
      PLT.stop(module_info_plt)
    end

    test "keeps no IR of a component no page reaches", %{opts: opts} do
      run(opts)

      %{ir_plt: ir_plt, pages_plt: pages_plt, runtime: runtime, module_infos: module_infos} =
        cache_state()

      module_info_plt = PLT.start(items: Map.to_list(module_infos))
      components = Compiler.list_components(module_info_plt)
      PLT.stop(module_info_plt)

      reached_modules =
        pages_plt
        |> PLT.get_all()
        |> Enum.reduce(MapSet.new(), fn {_page_module, page_state}, acc ->
          MapSet.union(acc, page_state.modules)
        end)
        |> MapSet.union(MapSet.new(runtime.mfas, fn {module, _function, _arity} -> module end))

      unreached_components = Enum.reject(components, &MapSet.member?(reached_modules, &1))
      # The test build compiles every fixture component, and most are rendered by no page.
      assert unreached_components != []
      refute Enum.any?(unreached_components, &PLT.member?(ir_plt, &1))
    end

    test "an edit of a component a page reaches keeps its IR", %{opts: opts} do
      run(opts)

      %{editable_modules: editable_modules, pages_plt: pages_plt, module_infos: module_infos} =
        cache_state()

      component_module =
        pages_plt
        |> PLT.get_all()
        |> Enum.flat_map(fn {_page_module, page_state} -> MapSet.to_list(page_state.modules) end)
        |> Enum.find(fn module ->
          MapSet.member?(editable_modules, module) and
            match?(%{component?: true}, module_infos[module])
        end)

      fake_edit(component_module)
      run(opts)

      assert PLT.member?(cache_state().ir_plt, component_module)
    end

    # The IR prune reads the IR PLT's keys and forget_removed_pages/2 the page states'; the encode
    # PLT's keys are not read, since the IR prune drops nothing and no module was removed.
    # One copy is left, the page digest PLT's, which PLT.dump/2 reads out to write it. The module
    # infos are neither copied into a PLT of the compile's nor out of one, for the diff or the cache.
    test "a kept page state holds no MFA list", %{opts: opts} do
      run(opts)

      %{page_mfas_plt: page_mfas_plt, pages_plt: pages_plt} = cache_state()
      page_states = PLT.get_all(pages_plt)

      assert map_size(page_states) > 0

      Enum.each(page_states, fn {page_module, page_state} ->
        assert Enum.sort(Map.keys(page_state)) == [:bundle_info, :modules]
        assert {:ok, [_mfa | _rest]} = PLT.get(page_mfas_plt, page_module)
      end)
    end

    test "a run with no changes copies no module info", %{opts: opts} do
      run(opts)

      assert count_calls({PLT, :get_all, 1}, fn -> run(opts) end) == 1
    end

    test "a run with no changes reads no key of the encode PLT", %{opts: opts} do
      run(opts)

      assert count_calls({PLT, :keys, 1}, fn -> run(opts) end) == 2
    end

    test "a run with no changes writes neither the call graph nor the module infos", %{
      opts: opts
    } do
      run(opts)

      module_info_dump_path =
        Path.join(opts[:build_dir], Reflection.module_info_plt_dump_file_name())

      stat_before = File.stat!(module_info_dump_path, time: :posix)

      assert count_dumps(fn -> run(opts) end) == [0, 0]

      stat_after = File.stat!(module_info_dump_path, time: :posix)
      assert {stat_after.mtime, stat_after.size} == {stat_before.mtime, stat_before.size}
    end

    test "an edit of a module no page reaches writes the module infos only", %{opts: opts} do
      run(opts)

      fake_edit(@unreached_module)

      assert count_dumps(fn -> run(opts) end) == [0, 1]
    end

    test "an edit of a page writes the call graph and the module infos", %{opts: opts} do
      run(opts)

      fake_edit(Module1)

      assert count_dumps(fn -> run(opts) end) == [1, 1]
    end

    test "a run with no changes writes both dumps when the module info dump was rewritten", %{
      opts: opts
    } do
      run(opts)

      module_info_dump_path =
        Path.join(opts[:build_dir], Reflection.module_info_plt_dump_file_name())

      File.touch!(module_info_dump_path, System.os_time(:second) - 10)

      assert count_dumps(fn -> run(opts) end) == [1, 1]
    end

    test "a run with no changes writes the call graph dump again when it is gone", %{opts: opts} do
      run(opts)

      call_graph_dump_path = Path.join(opts[:build_dir], Reflection.call_graph_dump_file_name())
      File.rm!(call_graph_dump_path)

      assert count_dumps(fn -> run(opts) end) == [1, 0]
      assert File.exists?(call_graph_dump_path)
    end

    test "a run after a reset starts from the build dir", %{opts: opts} do
      run(opts)
      Cache.reset()

      mfa = {CallGraph, :load, 2}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      %{call_graph: call_graph, module_infos: module_infos, pages_plt: pages_plt} = cache_state()

      # The page's state comes from the compile state dump.
      assert {:ok, %{bundle_info: %{}, modules: %MapSet{}}} = PLT.get(pages_plt, Module1)
      assert CallGraph.has_vertex?(call_graph, Module2)
      assert module_infos == load_module_info_items(opts)
    end

    test "reuses the kept module infos against the time the kept compile wrote", %{opts: opts} do
      run(opts)

      %{editable_modules: editable_modules, module_infos: module_infos} = cache_state()

      # A consolidated protocol, whose beam a new implementation rewrites without a compile, so it
      # is checked against its entry on every compile rather than taken from the compiler.
      protocol_info = module_infos[Enumerable]

      # The state of a compile that dumped in the same second as the beam was last written: its
      # entry cannot be reused, since a beam rewritten during that second matches on mtime and size
      # and still differs. A dump time read from disk can belong to a later compile by another VM,
      # which would make the guard trust the entry below and miss the edit it carries.
      put_kept_module_infos(
        %{module_infos | Enumerable => %{protocol_info | digest: "stale"}},
        protocol_info.mtime,
        editable_modules
      )

      dump_path = Path.join(opts[:build_dir], Reflection.module_info_plt_dump_file_name())
      File.touch!(dump_path, protocol_info.mtime + 100)

      run(opts)

      assert is_integer(cache_state().module_infos[Enumerable].digest)
    end

    test "a run that fails leaves the next one cold", %{opts: opts} do
      run(opts)

      # A directory where the call graph dump goes: the run patches the kept IR PLT and call graph
      # in place and only then raises, which is the shape of a compile that dies after changing
      # what the cache keeps. The page is edited, since a run that changes nothing writes no dump.
      blocked_dump_path = Path.join(opts[:build_dir], Reflection.call_graph_dump_file_name())
      File.rm!(blocked_dump_path)
      File.mkdir!(blocked_dump_path)
      on_exit(fn -> File.rmdir(blocked_dump_path) end)
      fake_edit(Module1)

      assert_raise File.Error, fn -> run(opts) end
      assert cache_state().module_infos == nil

      File.rmdir!(blocked_dump_path)

      run(opts)

      assert cache_state().module_infos == load_module_info_items(opts)
      test_call_graph(opts)
    end

    test "a run that fails while bundling leaves the next one warm, with its pages pending", %{
      opts: opts
    } do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        module_infos: module_infos,
        pages_plt: pages_plt
      } = cache_state()

      pages_reaching_module_2 =
        pages_plt
        |> PLT.get_all()
        |> Enum.filter(fn {_page_module, page_state} ->
          MapSet.member?(page_state.modules, Module2)
        end)
        |> MapSet.new(fn {page_module, _page_state} -> page_module end)

      report_compiled(Module2)
      edited_info = %{module_infos[Module2] | digest: "edited"}

      put_kept_module_infos(
        %{module_infos | Module2 => edited_info},
        dumped_at,
        editable_modules
      )

      missing_esbuild_path = Path.join(opts[:build_dir], "missing_esbuild")
      failing_opts = Keyword.put(opts, :esbuild_bin_path, missing_esbuild_path)

      assert_raise RuntimeError, ~r/executable not found/, fn -> run(failing_opts) end

      assert cache_state().module_infos == load_module_info_items(opts)
      assert cache_state().pending_pages == pages_reaching_module_2

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) ==
                 {:call_count, MapSet.size(pages_reaching_module_2)}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert MapSet.size(pages_reaching_module_2) > 0
      assert cache_state().pending_pages == MapSet.new()
      test_page_bundles(opts)
    end

    test "a run that fails while bundling leaves the next one rebuilding the runtime", %{
      opts: opts
    } do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        module_infos: module_infos,
        runtime: runtime
      } = cache_state()

      # Only a beam a save can rewrite is rechecked, so the fake edit must be of such a module.
      runtime_module =
        Enum.find_value(runtime.mfas, fn {module, _function, _arity} ->
          if MapSet.member?(editable_modules, module) and Map.has_key?(module_infos, module),
            do: module
        end)

      report_compiled(runtime_module)
      edited_info = %{module_infos[runtime_module] | digest: "edited"}

      put_kept_module_infos(
        %{module_infos | runtime_module => edited_info},
        dumped_at,
        editable_modules
      )

      missing_esbuild_path = Path.join(opts[:build_dir], "missing_esbuild")
      failing_opts = Keyword.put(opts, :esbuild_bin_path, missing_esbuild_path)

      assert_raise RuntimeError, ~r/executable not found/, fn -> run(failing_opts) end

      mfa = {Compiler, :create_runtime_entry_file, 6}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert cache_state().runtime.mfas == runtime.mfas
      test_runtime_bundle(opts)
    end

    test "a run whose build dir has no call graph dump rebuilds the graph", %{opts: opts} do
      run(opts)

      opts[:build_dir]
      |> Path.join(Reflection.call_graph_dump_file_name())
      |> File.rm!()

      Cache.reset()

      run(opts)

      test_call_graph(opts)
    end

    test "a run whose build dir holds a call graph dump of another version rebuilds the graph", %{
      opts: opts
    } do
      run(opts)

      # A dump as a Hologram from before the dump version wrote it: the bare graph.
      opts[:build_dir]
      |> Path.join(Reflection.call_graph_dump_file_name())
      |> File.write!(SerializationUtils.serialize(Digraph.new()))

      Cache.reset()

      run(opts)

      test_call_graph(opts)
      test_page_bundles(opts)
    end
  end

  describe "module metadata" do
    setup do
      # Reset on the way out too: a test here can leave a faked entry in the kept module infos.
      on_exit(fn ->
        Application.delete_env(:hologram, :client_stacktraces)
        Cache.reset()
      end)

      :ok
    end

    test "a page bundle registers the source file of its page", %{opts: initial_opts} do
      Application.put_env(:hologram, :client_stacktraces, true)
      opts = setup_empty_assets_and_build_dirs(initial_opts)

      run(opts)

      page_digest_plt = PLT.start()

      PLT.load(
        page_digest_plt,
        Path.join(opts[:build_dir], Reflection.page_digest_plt_dump_file_name())
      )

      bundle_path =
        Path.join(
          opts[:static_dir],
          "page-#{Reflection.module_name(Module1)}-#{PLT.get!(page_digest_plt, Module1)}.js"
        )

      bundle = File.read!(bundle_path)

      assert String.contains?(bundle, "registerModuleMetadata")

      assert String.contains?(
               bundle,
               "test/elixir/support/fixtures/mix/tasks/compile/hologram/module_1.ex"
             )
    end

    test "is built only when client stack traces are on", %{opts: initial_opts} do
      opts = setup_empty_assets_and_build_dirs(initial_opts)
      mfa = {Compiler, :build_module_metadata, 1}

      count_builds = fn stacktraces? ->
        Application.put_env(:hologram, :client_stacktraces, stacktraces?)
        :erlang.trace_pattern(mfa, true, [:call_count])

        try do
          run(opts)
          {:call_count, count} = :erlang.trace_info(mfa, :call_count)
          count
        after
          :erlang.trace_pattern(mfa, false, [:call_count])
        end
      end

      assert count_builds.(false) == 0
      assert count_builds.(true) == 1
    end

    test "a run with no changes builds no module metadata", %{opts: opts} do
      Application.put_env(:hologram, :client_stacktraces, true)
      forget_kept_state(opts)
      run(opts)

      assert count_calls({Compiler, :build_module_metadata, 1}, fn -> run(opts) end) == 0
    end

    test "the kept module metadata after an edit is the one a full build finds", %{opts: opts} do
      Application.put_env(:hologram, :client_stacktraces, true)
      forget_kept_state(opts)
      run(opts)
      fake_edit(Module1)
      run(opts)

      %{module_infos: module_infos, module_metadata: module_metadata} = cache_state()
      module_info_plt = PLT.start(items: Map.to_list(module_infos))

      assert module_metadata == Compiler.build_module_metadata(module_info_plt)

      PLT.stop(module_info_plt)
    end

    test "turning client stack traces off forgets the module metadata", %{opts: opts} do
      Application.put_env(:hologram, :client_stacktraces, true)
      forget_kept_state(opts)
      run(opts)

      assert cache_state().module_metadata != nil

      Application.put_env(:hologram, :client_stacktraces, false)
      run(opts)

      assert cache_state().module_metadata == nil
    end
  end

  test "stops the processes it spawns once compilation finishes", %{opts: initial_opts} do
    opts = setup_empty_assets_and_build_dirs(initial_opts)

    # The cache's own PLT lives on after the run, so it is started before the count.
    cache_state()

    before_count = count_plt_processes()
    run(opts)
    after_count = count_plt_processes()

    assert after_count == before_count
  end

  describe "compiler locking" do
    test "locking mechanism prevents concurrent compilation", %{opts: opts} do
      # The lock guards the actual compilation work, which emits
      # [:hologram, :compiler, :start] when it enters the critical section and
      # [:hologram, :compiler, :stop] when it leaves. By tracking how many
      # compilations are inside the critical section at any moment, we verify the
      # lock's core guarantee directly: at no point do two compilations overlap.
      # If the lock failed, two concurrent invocations would be inside the section
      # together and the observed maximum concurrency would be 2.
      {:ok, tracker} = Agent.start_link(fn -> %{current: 0, max: 0} end)

      handler_id = "compiler-lock-test"

      events = [
        [:hologram, :compiler, :start],
        [:hologram, :compiler, :stop]
      ]

      :telemetry.attach_many(handler_id, events, &__MODULE__.handle_compiler_telemetry/4, tracker)
      on_exit(fn -> :telemetry.detach(handler_id) end)

      1..3
      |> Enum.map(fn _i -> Task.async(fn -> run(opts) end) end)
      |> Task.await_many(:infinity)

      assert Agent.get(tracker, & &1.max) == 1
    end

    test "lock file is cleaned up after successful compilation", %{opts: opts} do
      refute File.exists?(@lock_path)

      run(opts)

      refute File.exists?(@lock_path)
    end

    test "lock file is cleaned up after compilation error", %{opts: initial_opts} do
      opts = setup_empty_assets_and_build_dirs(initial_opts)

      # Create an invalid package.json that will cause npm install to fail
      package_json_path = Path.join(opts[:assets_dir], "package.json")
      File.write!(package_json_path, "{ invalid json content")

      refute File.exists?(@lock_path)

      assert_raise RuntimeError, "npm install command failed", fn ->
        run(opts)
      end

      refute File.exists?(@lock_path)
    end

    test "lock dir (which is the build dir) is created if it doesn't exist", %{opts: initial_opts} do
      opts = setup_empty_assets_and_build_dirs(initial_opts)

      build_dir = opts[:build_dir]
      lock_path = Path.join(build_dir, @compiler_lock_file_name)

      FileUtils.rm_rf_with_retries!(build_dir, 5, 10)

      refute File.exists?(build_dir)

      run(opts)

      assert File.exists?(build_dir)

      refute File.exists?(lock_path)
    end

    test "stale lock file is automatically detected and removed", %{opts: opts} do
      # Create a stale lock file with a non-existent OS-level PID
      # Use a very high OS-level PID that's unlikely to exist
      # Default max PIDs are:
      # Linux = 32,768, see: https://stackoverflow.com/a/6294196/13040586
      # macOs = 99,998, see: https://apple.stackexchange.com/a/260798
      # Windows = 4,294,967,295, see: https://learn.microsoft.com/en-us/answers/questions/70930/maximum-value-of-process-id
      stale_os_pid = 32_768
      FileUtils.write_p!(@lock_path, "#{stale_os_pid}")

      assert File.exists?(@lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "valid lock file with running OS-level process is respected", %{opts: opts} do
      # Create a lock file with the current process PID (which is definitely running)
      current_os_pid = System.pid()
      FileUtils.write_p!(@lock_path, "#{current_os_pid}")

      assert File.exists?(@lock_path)

      # Start a task that will try to run compilation
      task =
        Task.async(fn ->
          start_time = System.system_time(:millisecond)
          run(opts)
          end_time = System.system_time(:millisecond)
          end_time - start_time
        end)

      # Remove the lock file after a short delay to simulate the "running" process finishing
      Process.sleep(2_000)
      File.rm!(@lock_path)

      # The task should eventually complete after waiting for the lock
      duration = Task.await(task, :infinity)

      # Should have waited at least 2 seconds (our sleep above)
      assert duration >= 2_000

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "empty lock file younger than the grace period is respected", %{opts: opts} do
      # An empty lock file is a lock in the middle of being acquired: the owner has
      # created it but hasn't written its OS-level PID yet. It must be waited on, not
      # removed, otherwise a lock that was just legitimately acquired is deleted and
      # two compilations run at once.
      FileUtils.write_p!(@lock_path, "")

      assert File.exists?(@lock_path)

      # Start a task that will try to run compilation
      task = Task.async(fn -> run(opts) end)

      # Long enough for the task to have run the stale-lock check at least twice
      # (it runs once on entry and then once per second while waiting).
      Process.sleep(2_000)

      # The planted lock is still there and still empty, i.e. the task is waiting for
      # it rather than having removed it and taken the lock for itself - a compilation
      # holding the lock would have replaced the content with its own OS-level PID.
      assert File.read!(@lock_path) == ""

      # Remove the lock file to simulate the acquiring process finishing
      File.rm!(@lock_path)

      # The task should eventually complete after waiting for the lock
      Task.await(task, :infinity)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "empty lock file older than the grace period is removed as abandoned", %{opts: opts} do
      # An empty lock file whose owner died between creating it and writing its
      # OS-level PID would never be filled or removed by anyone, so it is presumed
      # abandoned once it is older than the grace period. The mtime is backdated
      # instead of sleeping through the real wait.
      FileUtils.write_p!(@lock_path, "")

      # 6 seconds is one second past @abandoned_empty_lock_grace_period_s in
      # Mix.Tasks.Compile.Hologram, which the test file can't read.
      File.touch!(@lock_path, System.os_time(:second) - 6)

      assert File.exists?(@lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "lock file with invalid OS-level PID format is removed", %{opts: opts} do
      # Create a lock file with invalid OS-level PID format
      FileUtils.write_p!(@lock_path, "invalid_pid_format")

      assert File.exists?(@lock_path)

      run(opts)

      # Lock should be cleaned up after successful compilation
      refute File.exists?(@lock_path)
    end

    test "lock file contains current OS-level process PID during compilation", %{opts: opts} do
      # Start compilation in a background task
      compilation_task =
        Task.async(fn ->
          run(opts)
        end)

      # Wait for lock file to appear and read its content
      lock_content = wait_for_lock_file(@lock_path, 5_000)

      # Verify the OS-level PID format
      assert is_binary(lock_content)
      assert {parsed_os_pid, ""} = Integer.parse(lock_content)
      assert parsed_os_pid > 0

      # The OS-level PID should correspond to a running OS process
      assert SystemUtils.os_process_alive?(parsed_os_pid)

      # Clean up: kill the background compilation task
      Task.shutdown(compilation_task, :brutal_kill)
    end
  end
end
