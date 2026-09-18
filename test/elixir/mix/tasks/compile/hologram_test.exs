defmodule Mix.Tasks.Compile.HologramTest do
  use Hologram.Test.BasicCase, async: false
  import Mix.Tasks.Compile.Hologram

  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.IR
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module1
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module2

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

  @num_pages Enum.count(Reflection.list_pages())

  # A module of the test build that no page and no runtime function reaches.
  @unreached_module Hologram.Test.Fixtures.Compiler.CallGraph.Module9

  defp count_plt_processes do
    Enum.count(Process.list(), fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} -> Keyword.get(dict, :"$initial_call") == {PLT, :init, 1}
        nil -> false
      end
    end)
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

  defp test_call_graph(opts) do
    call_graph_dump_path = Path.join(opts[:build_dir], Reflection.call_graph_dump_file_name())
    assert File.exists?(call_graph_dump_path)

    call_graph = CallGraph.start()
    CallGraph.load(call_graph, call_graph_dump_path)

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
      |> Path.join("page-????????????????????????????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_page_bundles == @num_pages

    num_page_source_maps =
      opts[:static_dir]
      |> Path.join("page-????????????????????????????????.js.map")
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

    assert page_digest_items[Module1] =~ ~r/^[0-9a-f]{32}$/
  end

  defp test_runtime_bundle(opts) do
    num_runtime_bundles =
      opts[:static_dir]
      |> Path.join("runtime-????????????????????????????????.js")
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_bundles == 1

    num_runtime_source_maps =
      opts[:static_dir]
      |> Path.join("runtime-????????????????????????????????.js.map")
      |> Path.wildcard()
      |> Enum.count()

    assert num_runtime_source_maps == 1
  end

  # Helper function to wait for lock file to appear and return its content
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
    setup do
      Cache.reset()
    end

    test "the second run keeps what the first run built", %{opts: opts} do
      run(opts)
      %{call_graph: call_graph, ir_plt: ir_plt, module_infos: module_infos} = Cache.get()

      assert module_infos == load_module_info_items(opts)

      run(opts)

      assert %{call_graph: ^call_graph, ir_plt: ^ir_plt, module_infos: module_infos} =
               Cache.get()

      assert module_infos == load_module_info_items(opts)
    end

    test "keeps the modules whose beams a save can rewrite", %{opts: opts} do
      run(opts)

      editable_modules = Cache.get().editable_modules

      assert editable_modules ==
               MapSet.new(Reflection.list_editable_beams(), fn {module, _beam_path} -> module end)

      assert MapSet.member?(editable_modules, Module1)
    end

    test "holds the IR of the pages and the modules they reach, and not of the rest", %{
      opts: opts
    } do
      run(opts)

      ir_modules = PLT.keys(Cache.get().ir_plt)

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
      } = Cache.get()

      PLT.put(ir_plt, Module1, :stale)

      # An edit rewrites the beam, so the kept entry no longer matches its mtime and is not reused.
      edited_info = %{module_infos[Module1] | digest: "edited", mtime: 0}

      Cache.put_module_infos(
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
      warm_scan_mfa = {Compiler, :update_module_info_plt!, 5}

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

    test "a removed module loses its IR entry and its call graph vertices", %{opts: opts} do
      run(opts)

      %{
        call_graph: call_graph,
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        ir_plt: ir_plt,
        module_infos: module_infos
      } = Cache.get()

      removed_vertex = {:removed_module, :fun, 0}

      PLT.put(ir_plt, :removed_module, :ir)
      CallGraph.add_vertex(call_graph, removed_vertex)
      assert CallGraph.has_vertex?(call_graph, removed_vertex)

      module_infos
      |> Map.put(:removed_module, %{digest: "removed"})
      |> Cache.put_module_infos(dumped_at, MapSet.put(editable_modules, :removed_module))

      run(opts)

      assert PLT.get(ir_plt, :removed_module) == :error
      refute CallGraph.has_vertex?(call_graph, removed_vertex)
    end

    test "copies the kept entries of the modules outside the editable applications", %{
      opts: opts
    } do
      run(opts)

      %{dumped_at: dumped_at, editable_modules: editable_modules, module_infos: module_infos} =
        Cache.get()

      # A library's beam is not rewritten while the VM runs, so its kept entry is taken as it is:
      # the mtime faked here would make a check of the beam read it, and no page is rebuilt for it.
      kept_info = %{module_infos[Enum] | digest: "kept", mtime: 0}
      Cache.put_module_infos(%{module_infos | Enum => kept_info}, dumped_at, editable_modules)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 0}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert Cache.get().module_infos[Enum] == kept_info
    end

    test "picks up a module added to an editable application", %{opts: opts} do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        ir_plt: ir_plt,
        module_infos: module_infos
      } = Cache.get()

      # The state of a compile that ran before the module existed.
      PLT.delete(ir_plt, Module1)

      module_infos
      |> Map.delete(Module1)
      |> Cache.put_module_infos(dumped_at, editable_modules)

      run(opts)

      assert Cache.get().module_infos[Module1] == module_infos[Module1]
      assert {:ok, %IR.ModuleDefinition{}} = PLT.get(ir_plt, Module1)
    end

    test "a run into a fresh build dir dumps the whole call graph", %{opts: opts} do
      run(opts)

      fresh_build_dir_opts = Keyword.put(opts, :build_dir, setup_empty_build_dir())
      run(fresh_build_dir_opts)

      test_call_graph(fresh_build_dir_opts)
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

    test "rebuilds the pages reaching an edited module, with a full compile's result", %{
      opts: opts
    } do
      run(opts)

      %{
        dumped_at: dumped_at,
        editable_modules: editable_modules,
        module_infos: module_infos,
        pages_plt: pages_plt
      } = Cache.get()

      pages_reaching_module_2 =
        pages_plt
        |> PLT.get_all()
        |> Enum.count(fn {_page_module, page_state} ->
          MapSet.member?(page_state.modules, Module2)
        end)

      # An edit rewrites the beam, so the kept entry no longer matches its mtime and is not reused.
      edited_info = %{module_infos[Module2] | digest: "edited", mtime: 0}

      Cache.put_module_infos(
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

      Cache.reset()
      run(opts)

      assert load_page_digest_items(opts) == partial_digests
      test_page_bundles(opts)
    end

    test "keeps the bundles of the pages it doesn't rebuild", %{opts: opts} do
      run(opts)

      kept_bundle_paths =
        Cache.get().pages_plt
        |> PLT.get_all()
        |> Enum.reject(fn {_page_module, page_state} ->
          MapSet.member?(page_state.modules, Module2)
        end)
        |> Enum.map(fn {_page_module, page_state} ->
          page_state.bundle_info.static_bundle_path
        end)

      %{dumped_at: dumped_at, editable_modules: editable_modules, module_infos: module_infos} =
        Cache.get()

      edited_info = %{module_infos[Module2] | digest: "edited", mtime: 0}

      Cache.put_module_infos(
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

      {:ok, page_state} = PLT.get(Cache.get().pages_plt, Module1)
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

      digest = String.duplicate("a", 32)
      bundle_path = Path.join(opts[:static_dir], "page-#{digest}.js")
      source_map_path = bundle_path <> ".map"
      File.write!(bundle_path, "bundle")
      File.write!(source_map_path, "map")

      Cache.put_page(:gone_page, %{
        bundle_info: %{
          bundle_name: "page",
          digest: digest,
          entry_name: :gone_page,
          static_bundle_path: bundle_path,
          static_source_map_path: source_map_path
        },
        mfas: [],
        modules: MapSet.new()
      })

      run(opts)

      assert PLT.get(Cache.get().pages_plt, :gone_page) == :error
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
      } = Cache.get()

      # Only a beam a save can rewrite is rechecked, so the fake edit must be of such a module.
      runtime_module =
        Enum.find_value(runtime.mfas, fn {module, _function, _arity} ->
          if MapSet.member?(editable_modules, module) and Map.has_key?(module_infos, module),
            do: module
        end)

      edited_info = %{module_infos[runtime_module] | digest: "edited", mtime: 0}

      Cache.put_module_infos(
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

      assert Cache.get().runtime.mfas == runtime.mfas
      test_runtime_bundle(opts)
    end

    test "rebundles the runtime when its bundle is gone", %{opts: opts} do
      run(opts)

      runtime = Cache.get().runtime
      File.rm!(runtime.bundle_info.static_bundle_path)

      mfa = {Compiler, :bundle, 4}
      :erlang.trace_pattern(mfa, true, [:call_count])

      try do
        run(opts)

        assert :erlang.trace_info(mfa, :call_count) == {:call_count, 1}
      after
        :erlang.trace_pattern(mfa, false, [:call_count])
      end

      assert File.exists?(Cache.get().runtime.bundle_info.static_bundle_path)
      test_runtime_bundle(opts)
    end

    test "rebundles the runtime when its source map is gone", %{opts: opts} do
      run(opts)

      runtime = Cache.get().runtime
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
      } = Cache.get()

      # Only a beam a save can rewrite is rechecked, and of those the consolidated protocols belong
      # to other applications.
      other_app_module =
        Enum.find_value(module_infos, fn {module, _info} ->
          if MapSet.member?(editable_modules, module) and
               Application.get_application(module) not in [:hologram, nil],
             do: module
        end)

      edited_info = %{module_infos[other_app_module] | digest: "edited", mtime: 0}

      Cache.put_module_infos(
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

      assert Cache.get().app_versions == app_versions
    end

    test "the kept app versions are the ones a full compile finds", %{opts: opts} do
      run(opts)
      run(opts)
      warm_app_versions = Cache.get().app_versions

      Cache.reset()
      run(opts)

      assert warm_app_versions == Cache.get().app_versions
      assert warm_app_versions != []
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

      %{call_graph: call_graph, ir_plt: ir_plt, module_infos: module_infos} = Cache.get()

      assert {:ok, %IR.ModuleDefinition{}} = PLT.get(ir_plt, Module1)
      assert CallGraph.has_vertex?(call_graph, Module2)
      assert module_infos == load_module_info_items(opts)
    end

    test "reuses the kept module infos against the time the kept compile wrote", %{opts: opts} do
      run(opts)

      %{editable_modules: editable_modules, ir_plt: ir_plt, module_infos: module_infos} =
        Cache.get()

      module_1_info = module_infos[Module1]

      # The state of a compile that dumped in the same second as the beam was last written: its
      # entry cannot be reused, since a beam rewritten during that second matches on mtime and size
      # and still differs. A dump time read from disk can belong to a later compile by another VM,
      # which would make the guard trust the entry below and miss the edit it carries.
      Cache.put_module_infos(
        %{module_infos | Module1 => %{module_1_info | digest: "stale"}},
        module_1_info.mtime,
        editable_modules
      )

      dump_path = Path.join(opts[:build_dir], Reflection.module_info_plt_dump_file_name())
      File.touch!(dump_path, module_1_info.mtime + 100)

      run(opts)

      assert is_integer(Cache.get().module_infos[Module1].digest)
      assert {:ok, %IR.ModuleDefinition{}} = PLT.get(ir_plt, Module1)
    end

    test "a run that fails leaves the next one cold", %{opts: opts} do
      run(opts)

      # A directory where the call graph dump goes: the run patches the kept IR PLT and call graph
      # in place, bundles, and only then raises, which is the shape of a compile that dies after
      # changing what the cache keeps.
      blocked_dump_path = Path.join(opts[:build_dir], Reflection.call_graph_dump_file_name())
      File.rm!(blocked_dump_path)
      File.mkdir!(blocked_dump_path)

      assert_raise File.Error, fn -> run(opts) end
      assert Cache.get().module_infos == nil

      File.rmdir!(blocked_dump_path)

      run(opts)

      assert Cache.get().module_infos == load_module_info_items(opts)
      test_call_graph(opts)
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
  end

  describe "module metadata" do
    setup do
      on_exit(fn -> Application.delete_env(:hologram, :client_stacktraces) end)
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

      bundle_path = Path.join(opts[:static_dir], "page-#{PLT.get!(page_digest_plt, Module1)}.js")
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
  end

  test "stops the processes it spawns once compilation finishes", %{opts: initial_opts} do
    opts = setup_empty_assets_and_build_dirs(initial_opts)

    # The cache's own PLT lives on after the run, so it is started before the count.
    Cache.get()

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
