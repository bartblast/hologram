defmodule Hologram.FrameworkTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Framework
  alias Hologram.Reflection

  @macro_deps %{
    {Integer, :is_even, 1} => [
      {Bitwise, :&&&, 2},
      {Kernel, :==, 2},
      {Kernel, :and, 2},
      {Kernel, :is_integer, 1}
    ],
    {Kernel, :and, 2} => [
      {:erlang, :andalso, 2},
      {:erlang, :error, 1}
    ]
  }

  @tmp_dir Reflection.tmp_dir()

  setup_all do
    [elixir_stdlib_erlang_deps: elixir_stdlib_erlang_deps(@macro_deps)]
  end

  describe "elixir_funs_info/2" do
    setup do
      [
        opts: [
          deferred_elixir_funs: [],
          in_progress_erlang_funs: [],
          deferred_erlang_funs: [],
          macro_deps: @macro_deps
        ]
      ]
    end

    test "returns correct structure with status, progress, dependencies, and dependencies_count",
         %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_funs_info_2",
          "basic_structure"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = elixir_funs_info(test_dir, opts)

      assert is_map(result)
      refute Enum.empty?(result)

      # Check structure of each entry
      Enum.each(result, fn {elixir_mfa, info} ->
        # Verify MFA structure
        assert match?(
                 {module, fun, arity} when is_atom(module) and is_atom(fun) and is_integer(arity),
                 elixir_mfa
               )

        # Verify info map has all required fields
        assert is_map(info)
        assert Map.has_key?(info, :status)
        assert Map.has_key?(info, :progress)
        assert Map.has_key?(info, :method)
        assert Map.has_key?(info, :dependencies)
        assert Map.has_key?(info, :dependencies_count)

        # Verify field types and constraints
        assert info.status in [:done, :in_progress, :todo, :deferred]
        assert is_integer(info.progress)
        assert info.progress >= 0 and info.progress <= 100
        assert info.method in [:auto, :manual]
        assert is_list(info.dependencies)
        assert is_integer(info.dependencies_count)
        assert info.dependencies_count >= 0

        # Verify dependencies_count matches dependencies list length
        assert info.dependencies_count == length(info.dependencies)
      end)
    end

    test "calculates status with precedence: done > deferred > in_progress > todo" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_funs_info_2",
          "status_calculation"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []

        // Start +/2
        "+/2": (a, b) => a + b,
        // End +/2
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      # Test all precedence scenarios:
      # - Kernel.hd/1: all deps done + deferred + in_progress -> should be :done (highest priority)
      # - Kernel.tl/1: unported + deferred + in_progress -> should be :deferred (2nd priority)
      # - Kernel.length/1: unported + in_progress -> should be :in_progress (3rd priority)
      # - Kernel.elem/2: some deps done (+/2) but not all (element/2) -> should be :in_progress
      # - Kernel.abs/1: unported -> should be :todo (lowest priority)
      opts = [
        deferred_elixir_funs: [{Kernel, :hd, 1}, {Kernel, :tl, 1}],
        in_progress_erlang_funs: [{:erlang, :hd, 1}, {:erlang, :tl, 1}, {:erlang, :length, 1}],
        deferred_erlang_funs: [],
        macro_deps: @macro_deps
      ]

      result = elixir_funs_info(test_dir, opts)

      # :done takes precedence over everything (and progress should be 100%)
      assert result[{Kernel, :hd, 1}].status == :done
      assert result[{Kernel, :hd, 1}].progress == 100

      # :deferred takes precedence over :in_progress and :todo
      assert result[{Kernel, :tl, 1}].status == :deferred

      # :in_progress when any dep is :in_progress (none :done)
      assert result[{Kernel, :length, 1}].status == :in_progress

      # :in_progress when some (but not all) deps are :done (none :in_progress)
      assert result[{Kernel, :elem, 2}].status == :in_progress
      assert result[{Kernel, :elem, 2}].progress == 50

      # :todo is the default when none of the above apply (and progress should be 0%))
      assert result[{Kernel, :abs, 1}].status == :todo
      assert result[{Kernel, :abs, 1}].progress == 0
    end

    test "calculates 0% progress when no dependencies are ported", %{opts: opts} do
      deps_map = elixir_stdlib_erlang_deps(@macro_deps)
      assert deps_map[Kernel][{:elem, 2}] == [{:erlang, :+, 2}, {:erlang, :element, 2}]

      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_funs_info_2",
          "progress_0"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = elixir_funs_info(test_dir, opts)

      kernel_elem = result[{Kernel, :elem, 2}]
      assert kernel_elem.progress == 0
      assert kernel_elem.dependencies_count == 2
    end

    test "calculates 50% progress when half of dependencies are ported", %{opts: opts} do
      deps_map = elixir_stdlib_erlang_deps(@macro_deps)
      assert deps_map[Kernel][{:elem, 2}] == [{:erlang, :+, 2}, {:erlang, :element, 2}]

      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_funs_info_2",
          "progress_50"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start +/2
        "+/2": (a, b) => a + b,
        // End +/2
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = elixir_funs_info(test_dir, opts)

      kernel_elem = result[{Kernel, :elem, 2}]
      assert kernel_elem.progress == 50
      assert kernel_elem.dependencies_count == 2
    end

    test "calculates 100% progress when all dependencies are ported", %{opts: opts} do
      deps_map = elixir_stdlib_erlang_deps(@macro_deps)
      assert deps_map[Kernel][{:elem, 2}] == [{:erlang, :+, 2}, {:erlang, :element, 2}]

      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_funs_info_2",
          "progress_100"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start +/2
        "+/2": (a, b) => a + b,
        // End +/2
        // Deps: []

        // Start element/2
        "element/2": (n, tuple) => tuple[n - 1],
        // End element/2
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = elixir_funs_info(test_dir, opts)

      kernel_elem = result[{Kernel, :elem, 2}]
      assert kernel_elem.progress == 100
      assert kernel_elem.dependencies_count == 2
    end

    test "includes all Elixir stdlib functions and macros", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_funs_info_2",
          "all_functions"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = elixir_funs_info(test_dir, opts)

      # Verify some known functions are present
      assert Map.has_key?(result, {Kernel, :hd, 1})
      assert Map.has_key?(result, {Kernel, :+, 2})
      assert Map.has_key?(result, {Atom, :to_string, 1})
      assert Map.has_key?(result, {String, :length, 1})

      # Verify some known macros are present
      assert Map.has_key?(result, {Kernel, :def, 2})
      assert Map.has_key?(result, {Kernel, :if, 2})
      assert Map.has_key?(result, {Integer, :is_even, 1})
      assert Map.has_key?(result, {Record, :is_record, 1})
    end

    test "correctly identifies manual vs auto porting method", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_funs_info_2",
          "method_identification"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = elixir_funs_info(test_dir, opts)

      # Kernel.+/2 is auto-transpiled
      assert result[{Kernel, :+, 2}].method == :auto

      # String.downcase/2 is manually ported
      assert result[{String, :downcase, 2}].method == :manual
    end
  end

  describe "elixir_modules_info/2" do
    setup do
      [
        opts: [
          deferred_elixir_modules: [],
          deferred_elixir_funs: [],
          in_progress_erlang_funs: [],
          deferred_erlang_funs: [],
          macro_deps: @macro_deps
        ]
      ]
    end

    test "returns correct structure with group, status, progress, functions, all_fun_count, and status counts",
         %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_modules_info_2",
          "basic_structure"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = elixir_modules_info(test_dir, opts)

      assert is_map(result)
      refute Enum.empty?(result)

      # Check structure of each entry
      Enum.each(result, fn {module, info} ->
        # Verify module is an atom
        assert is_atom(module)

        # Verify info map has all required fields
        assert is_map(info)
        assert Map.has_key?(info, :group)
        assert Map.has_key?(info, :status)
        assert Map.has_key?(info, :progress)
        assert Map.has_key?(info, :functions)
        assert Map.has_key?(info, :all_fun_count)
        assert Map.has_key?(info, :done_fun_count)
        assert Map.has_key?(info, :in_progress_fun_count)
        assert Map.has_key?(info, :todo_fun_count)
        assert Map.has_key?(info, :deferred_fun_count)

        # Verify field types and constraints
        assert is_binary(info.group)
        assert info.status in [:done, :in_progress, :todo, :deferred]
        assert is_integer(info.progress)
        assert info.progress >= 0 and info.progress <= 100
        assert is_list(info.functions)
        assert is_integer(info.all_fun_count)
        assert info.all_fun_count >= 0
        assert is_integer(info.done_fun_count)
        assert info.done_fun_count >= 0
        assert is_integer(info.in_progress_fun_count)
        assert info.in_progress_fun_count >= 0
        assert is_integer(info.todo_fun_count)
        assert info.todo_fun_count >= 0
        assert is_integer(info.deferred_fun_count)
        assert info.deferred_fun_count >= 0

        # Verify all_fun_count matches functions list length
        assert info.all_fun_count == length(info.functions)

        # Verify sum of status counts equals all_fun_count
        total_counted =
          info.done_fun_count + info.in_progress_fun_count + info.todo_fun_count +
            info.deferred_fun_count

        assert total_counted == info.all_fun_count

        # Verify each function is a {name, arity} tuple
        Enum.each(info.functions, fn fun_tuple ->
          assert match?(
                   {fun, arity} when is_atom(fun) and is_integer(arity) and arity >= 0,
                   fun_tuple
                 )
        end)
      end)
    end

    test "assigns correct group to each module", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_modules_info_2",
          "module_groups"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = elixir_modules_info(test_dir, opts)

      # Verify specific modules are assigned to their correct groups
      assert result[Kernel].group == "Core"
      assert result[Atom].group == "Data Types"
      assert result[String].group == "Data Types"
      assert result[Enum].group == "Collections & Enumerables"
      assert result[List].group == "Collections & Enumerables"
      assert result[File].group == "IO & System"
      assert result[Calendar].group == "Calendar"
      assert result[Agent].group == "Processes & Applications"
      assert result[Enumerable].group == "Protocols"
      assert result[Code].group == "Code & Macros"
      assert result[ArgumentError].group == "Exceptions"
    end

    test "calculates status with precedence: done > deferred > in_progress > todo" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_modules_info_2",
          "status_calculation"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start atom_to_list/1
        "atom_to_list/1": (atom) => atom.toString().split(''),
        // End atom_to_list/1
        // Deps: []

        // Start atom_to_binary/1
        "atom_to_binary/1": (atom) => atom.toString(),
        // End atom_to_binary/1
        // Deps: []

        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      # Test precedence:
      # - Atom: all functions done (all deps ported) -> should be :done (highest priority, even if deferred)
      # - Bitwise: explicitly deferred module -> should be :deferred (2nd priority)
      # - Base: any function in_progress -> should be :in_progress (Base depends on {:erlang, :==, 2})
      # - Kernel: any function done (but not all) -> should be :in_progress (Kernel.hd/1 deps are ported)
      # - Port: default case -> should be :todo
      opts = [
        deferred_elixir_modules: [Atom, Bitwise],
        deferred_elixir_funs: [],
        in_progress_erlang_funs: [{:erlang, :==, 2}],
        deferred_erlang_funs: [],
        macro_deps: @macro_deps
      ]

      result = elixir_modules_info(test_dir, opts)

      # All functions done takes precedence over deferred (Atom has only 2 simple deps, both ported)
      assert result[Atom].status == :done

      # Module explicitly deferred (and not all functions done)
      assert result[Bitwise].status == :deferred

      # Any function in progress (Base depends on {:erlang, :==, 2})
      assert result[Base].status == :in_progress

      # Any function done (but not all) - Kernel.hd/1 has all deps done, but Kernel has many other functions
      assert result[Kernel].status == :in_progress

      # Default case should be :todo (Port doesn't depend on
      # {:erlang, :==, 2}, {:erlang, :atom_to_list, 1}, {:erlang, :atom_to_binary, 1}, or {:erlang, :hd, 1})
      assert result[Port].status == :todo
    end

    test "ensures progress is within 0-100 range", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_modules_info_2",
          "progress_calculation"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = elixir_modules_info(test_dir, opts)

      Enum.each(result, fn {_module, info} ->
        assert info.progress >= 0 and info.progress <= 100
      end)
    end

    test "includes all Elixir stdlib modules", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_modules_info_2",
          "all_modules"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = elixir_modules_info(test_dir, opts)

      # Verify a few key modules are present
      assert Map.has_key?(result, Kernel)
      assert Map.has_key?(result, Atom)
      assert Map.has_key?(result, Base)
      assert Map.has_key?(result, String)
    end

    test "functions list matches module.__info__(:functions) ++ module.__info__(:macros)", %{
      opts: opts
    } do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_modules_info_2",
          "functions_match"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = elixir_modules_info(test_dir, opts)

      modules_to_check = [Kernel, Atom, Base, String]

      for module <- modules_to_check do
        expected_functions = module.__info__(:functions)
        expected_macros = module.__info__(:macros)
        expected_all = expected_functions ++ expected_macros
        actual_functions = result[module].functions

        assert Enum.sort(actual_functions) == Enum.sort(expected_all),
               "Expected functions for #{module} to match __info__(:functions) ++ __info__(:macros)"

        assert result[module].all_fun_count == length(expected_all)
      end
    end

    test "functions list is sorted", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_modules_info_2",
          "functions_sorted"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = elixir_modules_info(test_dir, opts)

      for {module, info} <- result do
        assert info.functions == Enum.sort(info.functions),
               "Expected functions for #{module} to be sorted"
      end
    end
  end

  describe "elixir_overview_stats/2" do
    setup do
      [
        opts: [
          deferred_elixir_modules: [],
          deferred_elixir_funs: [],
          in_progress_erlang_funs: [],
          deferred_erlang_funs: [],
          macro_deps: @macro_deps
        ]
      ]
    end

    test "returns correct structure with all count fields and progress percentage", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_overview_stats_2",
          "basic_structure"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start atom_to_list/1
        "atom_to_list/1": (atom) => atom.toString().split(''),
        // End atom_to_list/1
        // Deps: []

        // Start atom_to_binary/1
        "atom_to_binary/1": (atom) => atom.toString(),
        // End atom_to_binary/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = elixir_overview_stats(test_dir, opts)

      # Verify result structure
      assert is_map(result)
      assert Map.has_key?(result, :done_fun_count)
      assert Map.has_key?(result, :in_progress_fun_count)
      assert Map.has_key?(result, :todo_fun_count)
      assert Map.has_key?(result, :deferred_fun_count)
      assert Map.has_key?(result, :done_module_count)
      assert Map.has_key?(result, :in_progress_module_count)
      assert Map.has_key?(result, :todo_module_count)
      assert Map.has_key?(result, :deferred_module_count)
      assert Map.has_key?(result, :progress)

      # Verify field types
      assert is_integer(result.done_fun_count)
      assert is_integer(result.in_progress_fun_count)
      assert is_integer(result.todo_fun_count)
      assert is_integer(result.deferred_fun_count)
      assert is_integer(result.done_module_count)
      assert is_integer(result.in_progress_module_count)
      assert is_integer(result.todo_module_count)
      assert is_integer(result.deferred_module_count)
      assert is_integer(result.progress)

      # Verify field constraints
      assert result.done_fun_count >= 0
      assert result.in_progress_fun_count >= 0
      assert result.todo_fun_count >= 0
      assert result.deferred_fun_count >= 0
      assert result.done_module_count >= 0
      assert result.in_progress_module_count >= 0
      assert result.todo_module_count >= 0
      assert result.deferred_module_count >= 0
      assert result.progress >= 0 and result.progress <= 100
    end

    test "aggregates counts correctly and calculates progress from average of non-deferred function progresses" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "elixir_overview_stats_2",
          "aggregation_and_progress"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start atom_to_list/1
        "atom_to_list/1": (atom) => atom.toString().split(''),
        // End atom_to_list/1
        // Deps: []

        // Start atom_to_binary/1
        "atom_to_binary/1": (atom) => atom.toString(),
        // End atom_to_binary/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      opts = [
        deferred_elixir_modules: [Bitwise],
        deferred_elixir_funs: [{Kernel, :+, 2}],
        in_progress_erlang_funs: [{:erlang, :==, 2}],
        deferred_erlang_funs: [],
        macro_deps: @macro_deps
      ]

      result = elixir_overview_stats(test_dir, opts)

      # Verify function counts are accurate
      assert result.done_fun_count > 0, "Expected at least one done function"
      assert result.in_progress_fun_count > 0, "Expected at least one in_progress function"
      assert result.todo_fun_count > 0, "Expected at least one todo function"
      assert result.deferred_fun_count == 1, "Expected exactly one deferred function"

      # Verify module counts are accurate
      assert result.done_module_count >= 0, "Expected zero or more done modules"
      assert result.in_progress_module_count > 0, "Expected at least one in_progress module"
      assert result.todo_module_count >= 0, "Expected zero or more todo modules"
      assert result.deferred_module_count == 1, "Expected exactly one deferred module (Bitwise)"

      elixir_funs_info = elixir_funs_info(test_dir, opts)
      elixir_modules_info = elixir_modules_info(test_dir, opts)

      elixir_fun_count = map_size(elixir_funs_info)
      elixir_module_count = map_size(elixir_modules_info)

      total_funs =
        result.done_fun_count + result.in_progress_fun_count + result.todo_fun_count +
          result.deferred_fun_count

      total_modules =
        result.done_module_count + result.in_progress_module_count + result.todo_module_count +
          result.deferred_module_count

      # Totals should match the number of Elixir functions and modules
      assert total_funs == elixir_fun_count
      assert total_modules == elixir_module_count

      non_deferred_funs =
        Enum.filter(elixir_funs_info, fn {_elixir_mfa, info} -> info.status != :deferred end)

      total_fun_progress =
        Enum.reduce(non_deferred_funs, 0, fn {_elixir_mfa, info}, acc ->
          acc + info.progress
        end)

      expected_progress = round(total_fun_progress / length(non_deferred_funs))

      # Progress should be average of non-deferred function progresses
      assert result.progress == expected_progress
    end
  end

  describe "elixir_stdlib_erlang_deps/0" do
    test "returns expected modules", %{elixir_stdlib_erlang_deps: result} do
      assert is_map(result)

      module_names = Map.keys(result)
      assert Kernel in module_names
      assert Atom in module_names
      assert Base in module_names
    end

    test "has correct two-level nested structure: modules -> functions -> Erlang MFAs",
         %{elixir_stdlib_erlang_deps: result} do
      # Level 1: Modules (atom keys)
      assert is_map(result)
      refute Enum.empty?(result)

      Enum.each(result, fn {module, module_map} ->
        assert is_atom(module)

        # Level 2: Functions ({name, arity} tuple keys)
        assert is_map(module_map)

        if module != Calendar.TimeZoneDatabase do
          refute Enum.empty?(module_map)
        end

        Enum.each(module_map, fn {function_key, erlang_mfas} ->
          # Function keys are {name, arity} tuples
          assert match?({fun, arity} when is_atom(fun) and is_integer(arity), function_key)
          {_fun, arity} = function_key
          assert arity >= 0

          # Values are lists of Erlang MFAs
          assert is_list(erlang_mfas)

          # Each Erlang MFA is a {module, fun, arity} tuple
          Enum.each(erlang_mfas, fn erlang_mfa ->
            assert match?(
                     {module, fun, arity}
                     when is_atom(module) and is_atom(fun) and is_integer(arity),
                     erlang_mfa
                   )
          end)
        end)
      end)
    end

    test "includes all public functions and macros from each module", %{
      elixir_stdlib_erlang_deps: result
    } do
      # Verify for Atom and Base modules
      for module <- [Atom, Base] do
        module_map = Map.get(result, module)
        expected_functions = module.__info__(:functions)
        expected_macros = module.__info__(:macros)
        expected_all = expected_functions ++ expected_macros

        assert Enum.count(expected_all) > 0

        Enum.each(expected_all, fn {fun, arity} ->
          assert Map.has_key?(module_map, {fun, arity}),
                 "Expected function/macro #{fun}/#{arity} to be present in #{module} module map"

          erlang_mfas = Map.get(module_map, {fun, arity})
          assert is_list(erlang_mfas)
        end)
      end
    end

    test "all dependency MFAs are from Erlang modules only", %{elixir_stdlib_erlang_deps: result} do
      Enum.each(result, fn {_module, module_map} ->
        Enum.each(module_map, fn {_function_key, erlang_mfas} ->
          Enum.each(erlang_mfas, fn {module, _fun, _arity} ->
            assert Reflection.erlang_module?(module),
                   "Expected #{inspect(module)} to be an Erlang module"

            refute Reflection.elixir_module?(module),
                   "Expected #{inspect(module)} not to be an Elixir module"

            # Erlang modules start with lowercase letters
            module_str = Atom.to_string(module)
            first_char = String.first(module_str)

            assert first_char >= "a" and first_char <= "z",
                   "Expected Erlang module #{inspect(module)} to start with lowercase letter"
          end)
        end)
      end)
    end

    test "Kernel module has many functions and macros", %{elixir_stdlib_erlang_deps: result} do
      kernel_module_map = Map.get(result, Kernel)

      # Kernel is a large module with many functions and macros
      assert Enum.count(kernel_module_map) > 100
    end

    test "injects macro dependencies into call graph", %{elixir_stdlib_erlang_deps: result} do
      # Test that Kernel.and/2 includes the directly specified Erlang dependencies
      kernel_and_deps = result[Kernel][{:and, 2}]
      assert {:erlang, :andalso, 2} in kernel_and_deps
      assert {:erlang, :error, 1} in kernel_and_deps

      # Test that Integer.is_even/1 includes transitive dependencies through Kernel.and/2
      integer_is_even_deps = result[Integer][{:is_even, 1}]
      assert {:erlang, :andalso, 2} in integer_is_even_deps
      assert {:erlang, :error, 1} in integer_is_even_deps
    end

    test "does not inject macro dependencies into call graph when macro_deps is empty" do
      result = elixir_stdlib_erlang_deps(%{})

      kernel_and_deps = result[Kernel][{:and, 2}]
      refute {:erlang, :andalso, 2} in kernel_and_deps
      refute {:erlang, :error, 1} in kernel_and_deps

      integer_is_even_deps = result[Integer][{:is_even, 1}]
      refute {:erlang, :andalso, 2} in integer_is_even_deps
      refute {:erlang, :error, 1} in integer_is_even_deps
    end
  end

  describe "elixir_stdlib_module_groups/0" do
    test "returns list of {group_name, modules} with correct types" do
      groups = elixir_stdlib_module_groups()

      assert is_list(groups)
      refute Enum.empty?(groups)

      Enum.each(groups, fn {group_name, modules} ->
        assert is_binary(group_name)
        assert is_list(modules)
        Enum.each(modules, &assert(is_atom(&1)))
      end)
    end

    test "includes known modules in expected groups" do
      groups = elixir_stdlib_module_groups()

      core =
        groups
        |> Enum.find(fn {name, _modules} -> name == "Core" end)
        |> elem(1)

      data_types =
        groups
        |> Enum.find(fn {name, _modules} -> name == "Data Types" end)
        |> elem(1)

      collections =
        groups
        |> Enum.find(fn {name, _modules} -> name == "Collections & Enumerables" end)
        |> elem(1)

      assert Kernel in core
      assert Atom in data_types
      assert Enum in collections
    end
  end

  describe "erlang_funs_info/2" do
    setup do
      [opts: [in_progress_erlang_funs: [], deferred_erlang_funs: [], macro_deps: @macro_deps]]
    end

    test "returns correct structure with status, dependents, and dependents_count" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_funs_info_2",
          "basic_structure"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
        
        // Start +/2
        "+/2": (a, b) => a + b,
        // End +/2
        // Deps: []
        
        // Start */2
        "*/2": (a, b) => a * b,
        // End */2
        // Deps: []
      };
      """

      lists_content = """
      const Erlang_Lists = {
        // Start reverse/1
        "reverse/1": (list) => list.reverse(),
        // End reverse/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      test_dir
      |> Path.join("lists.mjs")
      |> File.write!(lists_content)

      opts = [
        in_progress_erlang_funs: [{:erlang, :-, 2}, {:erlang, :/, 2}],
        deferred_erlang_funs: [{:erlang, :div, 2}],
        macro_deps: @macro_deps
      ]

      result = erlang_funs_info(test_dir, opts)

      assert is_map(result)
      refute Enum.empty?(result)

      # Verify we have examples of all four statuses
      statuses =
        result
        |> Map.values()
        |> Enum.map(& &1.status)
        |> Enum.uniq()
        |> Enum.sort()

      assert :done in statuses, "Expected at least one :done status"
      assert :in_progress in statuses, "Expected at least one :in_progress status"
      assert :todo in statuses, "Expected at least one :todo status"
      assert :deferred in statuses, "Expected at least one :deferred status"

      # Check that ALL entries have the correct structure
      Enum.each(result, fn {erlang_mfa, info} ->
        # Verify MFA structure
        assert match?(
                 {module, fun, arity} when is_atom(module) and is_atom(fun) and is_integer(arity),
                 erlang_mfa
               )

        # Verify info map structure
        assert is_map(info)
        assert Map.has_key?(info, :status)
        assert Map.has_key?(info, :dependents)
        assert Map.has_key?(info, :dependents_count)

        # Verify field types and constraints
        assert info.status in [:done, :in_progress, :todo, :deferred]
        assert is_list(info.dependents)
        assert is_integer(info.dependents_count)
        assert info.dependents_count >= 0

        # Verify dependents_count matches dependents list
        assert info.dependents_count == length(info.dependents)
      end)
    end

    test "marks unported functions as :todo", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_funs_info_2",
          "todo_functions"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = erlang_funs_info(test_dir, opts)

      assert result[{:erlang, :+, 2}].status == :todo
      assert result[{:erlang, :hd, 1}].status == :todo
    end

    test "marks functions in in_progress list as :in_progress" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_funs_info_2",
          "in_progress_functions"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      opts = [
        in_progress_erlang_funs: [{:erlang, :+, 2}, {:erlang, :hd, 1}],
        deferred_erlang_funs: [],
        macro_deps: @macro_deps
      ]

      result = erlang_funs_info(test_dir, opts)

      assert result[{:erlang, :+, 2}].status == :in_progress
      assert result[{:erlang, :hd, 1}].status == :in_progress
    end

    test "marks functions in deferred list as :deferred" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_funs_info_2",
          "deferred_functions"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      opts = [
        in_progress_erlang_funs: [],
        deferred_erlang_funs: [{:erlang, :+, 2}, {:erlang, :hd, 1}],
        macro_deps: @macro_deps
      ]

      result = erlang_funs_info(test_dir, opts)

      assert result[{:erlang, :+, 2}].status == :deferred
      assert result[{:erlang, :hd, 1}].status == :deferred
    end

    test "marks ported functions as :done", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_funs_info_2",
          "done_functions"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start +/2
        "+/2": (a, b) => a + b,
        // End +/2
        // Deps: []
                
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = erlang_funs_info(test_dir, opts)

      assert result[{:erlang, :+, 2}].status == :done
      assert result[{:erlang, :hd, 1}].status == :done
    end

    test "correctly aggregates dependents and counts them", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_funs_info_2",
          "dependents_aggregation"
        ])

      clean_dir(test_dir)

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!("const Erlang = {};")

      result = erlang_funs_info(test_dir, opts)

      Enum.each(result, fn {_erlang_mfa, info} ->
        # dependents_count should match the length of unique dependents
        assert info.dependents_count == length(info.dependents),
               "Expected dependents_count to equal length of dependents list"

        # All dependents should be valid Elixir MFAs
        Enum.each(info.dependents, fn dependent ->
          assert match?(
                   {module, fun, arity}
                   when is_atom(module) and is_atom(fun) and is_integer(arity),
                   dependent
                 ),
                 "Expected dependent to be a valid MFA tuple"
        end)

        # Dependents list should not have duplicates
        assert length(info.dependents) == length(Enum.uniq(info.dependents)),
               "Expected dependents list to contain only unique entries"
      end)
    end

    test "prioritizes status in correct order: done > in_progress > deferred > todo" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_funs_info_2",
          "status_priority"
        ])

      clean_dir(test_dir)

      # Port hd/1 to test that :done has highest priority
      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      # Test all precedence levels:
      # - hd/1 is ported AND in both in_progress and deferred -> should be :done
      # - +/2 is in both in_progress and deferred -> should be :in_progress
      # - -/2 is only in deferred -> should be :deferred
      # - //2 is in none of the lists -> should be :todo
      opts = [
        in_progress_erlang_funs: [{:erlang, :hd, 1}, {:erlang, :+, 2}],
        deferred_erlang_funs: [{:erlang, :hd, 1}, {:erlang, :+, 2}, {:erlang, :-, 2}],
        macro_deps: @macro_deps
      ]

      result = erlang_funs_info(test_dir, opts)

      # :done takes precedence over in_progress and deferred
      assert result[{:erlang, :hd, 1}].status == :done
      # :in_progress takes precedence over deferred
      assert result[{:erlang, :+, 2}].status == :in_progress
      # :deferred when not ported or in_progress
      assert result[{:erlang, :-, 2}].status == :deferred
      # :todo when not in any special category
      assert result[{:erlang, :/, 2}].status == :todo
    end
  end

  describe "erlang_overview_stats/2" do
    setup do
      [
        opts: [
          in_progress_erlang_funs: [],
          deferred_erlang_funs: [],
          macro_deps: @macro_deps
        ]
      ]
    end

    test "returns correct structure with all count fields and progress percentage", %{opts: opts} do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_overview_stats_2",
          "basic_structure"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = erlang_overview_stats(test_dir, opts)

      # Verify result structure
      assert is_map(result)
      assert Map.has_key?(result, :done_fun_count)
      assert Map.has_key?(result, :in_progress_fun_count)
      assert Map.has_key?(result, :todo_fun_count)
      assert Map.has_key?(result, :deferred_fun_count)
      assert Map.has_key?(result, :progress)

      # Verify field types and constraints
      assert is_integer(result.done_fun_count)
      assert is_integer(result.in_progress_fun_count)
      assert is_integer(result.deferred_fun_count)
      assert is_integer(result.todo_fun_count)
      assert is_integer(result.progress)

      assert result.done_fun_count >= 0
      assert result.in_progress_fun_count >= 0
      assert result.todo_fun_count >= 0
      assert result.deferred_fun_count >= 0
      assert result.progress >= 0 and result.progress <= 100
    end

    test "aggregates counts correctly and excludes deferred from progress calculation" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "erlang_overview_stats_2",
          "aggregation_and_progress"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start hd/1
        "hd/1": (list) => list[0],
        // End hd/1
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      opts = [
        in_progress_erlang_funs: [{:erlang, :+, 2}],
        deferred_erlang_funs: [{:erlang, :div, 2}],
        macro_deps: @macro_deps
      ]

      result = erlang_overview_stats(test_dir, opts)

      # Verify counts are accurate
      assert result.done_fun_count > 0, "Expected at least one done function"
      assert result.in_progress_fun_count == 1, "Expected exactly one in_progress function"
      assert result.todo_fun_count > 0, "Expected at least one todo function"
      assert result.deferred_fun_count == 1, "Expected exactly one deferred function"

      # Total should match the number of unique Erlang functions
      erlang_fun_count =
        test_dir
        |> erlang_funs_info(opts)
        |> Map.keys()
        |> length()

      total =
        result.done_fun_count + result.in_progress_fun_count + result.todo_fun_count +
          result.deferred_fun_count

      assert total == erlang_fun_count

      # Progress should only consider done, todo, and in_progress (excluding deferred)
      total_for_progress =
        result.done_fun_count + result.in_progress_fun_count + result.todo_fun_count

      expected_progress = round(result.done_fun_count * 100 / total_for_progress)
      assert result.progress == expected_progress
    end
  end

  describe "list_ported_erlang_funs/1" do
    test "handles multiple module files" do
      test_dir =
        Path.join([
          @tmp_dir,
          "tests",
          "framework",
          "list_ported_erlang_funs_1",
          "multiple_modules"
        ])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start div/2
        "div/2": (left, right) => {
          return left / right;
        },
        // End div/2
        // Deps: []
      };
      """

      lists_content = """
      const Erlang_Lists = {
        // Start flatten/1
        "flatten/1": (list) => {
          return list;
        },
        // End flatten/1
        // Deps: []

        // Start reverse/1
        "reverse/1": (list) => {
          return list.reverse();
        },
        // End reverse/1
        // Deps: []
      };
      """

      maps_content = """
      const Erlang_Maps = {
        // Start get/2
        "get/2": (key, map) => {
          return map[key];
        },
        // End get/2
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      test_dir
      |> Path.join("lists.mjs")
      |> File.write!(lists_content)

      test_dir
      |> Path.join("maps.mjs")
      |> File.write!(maps_content)

      result = list_ported_erlang_funs(test_dir)

      assert length(result) == 4
      assert {:erlang, :div, 2} in result
      assert {:lists, :flatten, 1} in result
      assert {:lists, :reverse, 1} in result
      assert {:maps, :get, 2} in result
    end

    test "handles special characters in function names" do
      test_dir =
        Path.join([@tmp_dir, "tests", "framework", "list_ported_erlang_funs_1", "special_chars"])

      clean_dir(test_dir)

      erlang_content = """
      const Erlang = {
        // Start ==/2
        "==/2": (left, right) => {
          return left == right;
        },
        // End ==/2
        // Deps: []

        // Start /=/2
        "/=/2": (left, right) => {
          return left != right;
        },
        // End /=/2
        // Deps: []

        // Start =:=/2
        "=:=/2": (left, right) => {
          return left === right;
        },
        // End =:=/2
        // Deps: []
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      result = list_ported_erlang_funs(test_dir)

      assert length(result) == 3
      assert {:erlang, :==, 2} in result
      assert {:erlang, :"/=", 2} in result
      assert {:erlang, :"=:=", 2} in result
    end

    test "returns empty list for files without ported functions" do
      test_dir =
        Path.join([@tmp_dir, "tests", "framework", "list_ported_erlang_funs_1", "no_functions"])

      clean_dir(test_dir)

      content = """
      const Erlang = {
        // This is just a comment
        // No actual function markers
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(content)

      result = list_ported_erlang_funs(test_dir)

      assert result == []
    end
  end
end
