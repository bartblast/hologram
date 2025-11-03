defmodule Hologram.FrameworkTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Framework
  alias Hologram.Reflection

  @tmp_dir Reflection.tmp_dir()

  setup_all do
    [result: elixir_stdlib_erlang_deps()]
  end

  describe "elixir_funs_info/2" do
    test "returns correct structure with status, progress, dependencies, and dependencies_count" do
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

      result = elixir_funs_info(test_dir)

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
        assert Map.has_key?(info, :dependencies)
        assert Map.has_key?(info, :dependencies_count)

        # Verify field types and constraints
        assert info.status in [:done, :in_progress, :todo, :deferred]
        assert is_integer(info.progress)
        assert info.progress >= 0 and info.progress <= 100
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
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      # Test all precedence scenarios:
      # - Kernel.hd/1: all deps done + deferred + in_progress -> should be :done (highest priority)
      # - Kernel.tl/1: unported + deferred + in_progress -> should be :deferred (2nd priority)
      # - Kernel.length/1: unported + in_progress -> should be :in_progress (3rd priority)
      # - Kernel.abs/1: unported -> should be :todo (lowest priority)
      result =
        elixir_funs_info(test_dir,
          deferred_elixir: [{Kernel, :hd, 1}, {Kernel, :tl, 1}],
          in_progress_erlang: [{:erlang, :hd, 1}, {:erlang, :tl, 1}, {:erlang, :length, 1}]
        )

      # :done takes precedence over everything (and progress should be 100%)
      assert result[{Kernel, :hd, 1}].status == :done
      assert result[{Kernel, :hd, 1}].progress == 100

      # :deferred takes precedence over :in_progress and :todo
      assert result[{Kernel, :tl, 1}].status == :deferred

      # :in_progress takes precedence over :todo
      assert result[{Kernel, :length, 1}].status == :in_progress

      # :todo is the default when none of the above apply (and progress should be 0%))
      assert result[{Kernel, :abs, 1}].status == :todo
      assert result[{Kernel, :abs, 1}].progress == 0
    end

    test "calculates 0% progress when no dependencies are ported" do
      deps_map = elixir_stdlib_erlang_deps()
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

      result = elixir_funs_info(test_dir)
      kernel_elem = result[{Kernel, :elem, 2}]

      assert kernel_elem.progress == 0
      assert kernel_elem.dependencies_count == 2
    end

    test "calculates 50% progress when half of dependencies are ported" do
      deps_map = elixir_stdlib_erlang_deps()
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

      result = elixir_funs_info(test_dir)
      kernel_elem = result[{Kernel, :elem, 2}]

      assert kernel_elem.progress == 50
      assert kernel_elem.dependencies_count == 2
    end

    test "calculates 100% progress when all dependencies are ported" do
      deps_map = elixir_stdlib_erlang_deps()
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

      result = elixir_funs_info(test_dir)
      kernel_elem = result[{Kernel, :elem, 2}]

      assert kernel_elem.progress == 100
      assert kernel_elem.dependencies_count == 2
    end

    test "includes all Elixir stdlib functions" do
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

      result = elixir_funs_info(test_dir)

      # Verify some known functions are present
      assert Map.has_key?(result, {Kernel, :hd, 1})
      assert Map.has_key?(result, {Kernel, :+, 2})
      assert Map.has_key?(result, {Atom, :to_string, 1})
      assert Map.has_key?(result, {String, :length, 1})
    end
  end

  describe "elixir_modules_info/2" do
    test "returns correct structure with group, status, progress, functions, and functions_count" do
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

      result = elixir_modules_info(test_dir)

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
        assert Map.has_key?(info, :functions_count)

        # Verify field types and constraints
        assert is_binary(info.group)
        assert info.status in [:done, :in_progress, :todo, :deferred]
        assert is_integer(info.progress)
        assert info.progress >= 0 and info.progress <= 100
        assert is_list(info.functions)
        assert is_integer(info.functions_count)
        assert info.functions_count >= 0

        # Verify functions_count matches functions list length
        assert info.functions_count == length(info.functions)

        # Verify each function is a {name, arity} tuple
        Enum.each(info.functions, fn fun_tuple ->
          assert match?(
                   {fun, arity} when is_atom(fun) and is_integer(arity) and arity >= 0,
                   fun_tuple
                 )
        end)
      end)
    end

    test "assigns correct group to each module" do
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

      result = elixir_modules_info(test_dir)

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

    test "calculates status with precedence: all functions done > deferred module > any function in_progress > todo" do
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
      };
      """

      test_dir
      |> Path.join("erlang.mjs")
      |> File.write!(erlang_content)

      # Test precedence:
      # - Atom: all functions done (all deps ported) -> should be :done (highest priority, even if deferred)
      # - Bitwise: explicitly deferred module -> should be :deferred (2nd priority)
      # - Base: any function in_progress -> should be :in_progress (Base depends on {:erlang, :==, 2})
      # - Function: default case -> should be :todo
      result =
        elixir_modules_info(test_dir,
          deferred_elixir_modules: [Atom, Bitwise],
          in_progress_erlang_funs: [{:erlang, :==, 2}]
        )

      # All functions done takes precedence over deferred (Atom has only 2 simple deps, both ported)
      assert result[Atom].status == :done

      # Module explicitly deferred (and not all functions done)
      assert result[Bitwise].status == :deferred

      # Any function in progress (Base depends on {:erlang, :==, 2})
      assert result[Base].status == :in_progress

      # Default case should be :todo (Function doesn't depend on {:erlang, :==, 2})
      assert result[Function].status == :todo
    end

    test "ensures progress is within 0-100 range" do
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

      result = elixir_modules_info(test_dir)

      Enum.each(result, fn {_module, info} ->
        assert info.progress >= 0 and info.progress <= 100
      end)
    end

    test "includes all Elixir stdlib modules" do
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

      result = elixir_modules_info(test_dir)

      # Verify a few key modules are present
      assert Map.has_key?(result, Kernel)
      assert Map.has_key?(result, Atom)
      assert Map.has_key?(result, Base)
      assert Map.has_key?(result, String)
    end

    test "functions list matches module.__info__(:functions)" do
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

      result = elixir_modules_info(test_dir)

      modules_to_check = [Kernel, Atom, Base, String]

      for module <- modules_to_check do
        expected_functions = module.__info__(:functions)
        actual_functions = result[module].functions

        assert Enum.sort(actual_functions) == Enum.sort(expected_functions),
               "Expected functions for #{module} to match __info__(:functions)"

        assert result[module].functions_count == length(expected_functions)
      end
    end
  end

  describe "elixir_overview_stats/2" do
    test "returns correct structure with all count fields and progress percentage" do
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

      result = elixir_overview_stats(test_dir)

      # Verify result structure
      assert is_map(result)
      assert Map.has_key?(result, :done_count)
      assert Map.has_key?(result, :in_progress_count)
      assert Map.has_key?(result, :deferred_count)
      assert Map.has_key?(result, :todo_count)
      assert Map.has_key?(result, :progress)

      # Verify field types and constraints
      assert is_integer(result.done_count)
      assert is_integer(result.in_progress_count)
      assert is_integer(result.deferred_count)
      assert is_integer(result.todo_count)
      assert is_integer(result.progress)

      assert result.done_count >= 0
      assert result.in_progress_count >= 0
      assert result.deferred_count >= 0
      assert result.todo_count >= 0
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

      result =
        elixir_overview_stats(test_dir,
          deferred_elixir_modules: [Bitwise],
          deferred_elixir_funs: [{Kernel, :+, 2}],
          in_progress_erlang_funs: [{:erlang, :==, 2}]
        )

      # Verify counts are accurate
      assert result.done_count > 0, "Expected at least one done function"
      assert result.in_progress_count > 0, "Expected at least one in_progress function"
      assert result.deferred_count == 1, "Expected at least one deferred function"
      assert result.todo_count > 0, "Expected at least one todo function"

      elixir_funs_info =
        elixir_funs_info(test_dir,
          deferred_elixir: [{Kernel, :+, 2}],
          in_progress_erlang: [{:erlang, :==, 2}]
        )

      elixir_funs_count = map_size(elixir_funs_info)

      total =
        result.done_count + result.in_progress_count + result.deferred_count + result.todo_count

      # Total should match the number of Elixir functions
      assert total == elixir_funs_count

      non_deferred_funs =
        Enum.filter(elixir_funs_info, fn {_mfa, info} -> info.status != :deferred end)

      total_fun_progress =
        Enum.reduce(non_deferred_funs, 0, fn {_mfa, info}, acc ->
          acc + info.progress
        end)

      expected_progress = round(total_fun_progress / length(non_deferred_funs))

      # Progress should be average of non-deferred function progresses      
      assert result.progress == expected_progress
    end
  end

  describe "elixir_stdlib_erlang_deps/0" do
    test "returns expected modules", %{result: result} do
      assert is_map(result)

      module_names = Map.keys(result)
      assert Kernel in module_names
      assert Atom in module_names
      assert Base in module_names
    end

    test "has correct two-level nested structure: modules -> functions -> Erlang MFAs",
         %{result: result} do
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

    test "includes all public functions from each module", %{result: result} do
      # Verify for Atom and Base modules
      for module <- [Atom, Base] do
        module_map = Map.get(result, module)
        expected_functions = module.__info__(:functions)

        assert Enum.count(expected_functions) > 0

        Enum.each(expected_functions, fn {fun, arity} ->
          assert Map.has_key?(module_map, {fun, arity}),
                 "Expected function #{fun}/#{arity} to be present in #{module} module map"

          erlang_mfas = Map.get(module_map, {fun, arity})
          assert is_list(erlang_mfas)
        end)
      end
    end

    test "all dependency MFAs are from Erlang modules only", %{result: result} do
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

    test "Kernel module has many functions", %{result: result} do
      kernel_module_map = Map.get(result, Kernel)

      # Kernel is a large module with many functions
      assert Enum.count(kernel_module_map) > 50
    end
  end

  describe "erlang_funs_info/2" do
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

      in_progress = [{:erlang, :-, 2}, {:erlang, :/, 2}]
      deferred = [{:erlang, :div, 2}]
      result = erlang_funs_info(test_dir, in_progress: in_progress, deferred: deferred)

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

    test "marks unported functions as :todo" do
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

      result = erlang_funs_info(test_dir)

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

      in_progress = [{:erlang, :+, 2}, {:erlang, :hd, 1}]
      result = erlang_funs_info(test_dir, in_progress: in_progress)

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

      deferred = [{:erlang, :+, 2}, {:erlang, :hd, 1}]
      result = erlang_funs_info(test_dir, deferred: deferred)

      assert result[{:erlang, :+, 2}].status == :deferred
      assert result[{:erlang, :hd, 1}].status == :deferred
    end

    test "marks ported functions as :done" do
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

      result = erlang_funs_info(test_dir, [])

      assert result[{:erlang, :+, 2}].status == :done
      assert result[{:erlang, :hd, 1}].status == :done
    end

    test "correctly aggregates dependents and counts them" do
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

      result = erlang_funs_info(test_dir, [])

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
      result =
        erlang_funs_info(test_dir,
          in_progress: [{:erlang, :hd, 1}, {:erlang, :+, 2}],
          deferred: [{:erlang, :hd, 1}, {:erlang, :+, 2}, {:erlang, :-, 2}]
        )

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
    test "returns correct structure with all count fields and progress percentage" do
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

      result = erlang_overview_stats(test_dir)

      # Verify result structure
      assert is_map(result)
      assert Map.has_key?(result, :done_count)
      assert Map.has_key?(result, :in_progress_count)
      assert Map.has_key?(result, :deferred_count)
      assert Map.has_key?(result, :todo_count)
      assert Map.has_key?(result, :progress)

      # Verify field types and constraints
      assert is_integer(result.done_count)
      assert is_integer(result.in_progress_count)
      assert is_integer(result.deferred_count)
      assert is_integer(result.todo_count)
      assert is_integer(result.progress)

      assert result.done_count >= 0
      assert result.in_progress_count >= 0
      assert result.deferred_count >= 0
      assert result.todo_count >= 0
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

      in_progress = [{:erlang, :+, 2}]
      deferred = [{:erlang, :div, 2}]
      result = erlang_overview_stats(test_dir, in_progress: in_progress, deferred: deferred)

      # Verify counts are accurate
      assert result.done_count > 0, "Expected at least one done function"
      assert result.in_progress_count == 1, "Expected exactly one in_progress function"
      assert result.deferred_count == 1, "Expected exactly one deferred function"
      assert result.todo_count > 0, "Expected at least one todo function"

      # Total should match the number of unique Erlang functions
      erlang_funs_count =
        erlang_funs_info(test_dir, in_progress: in_progress, deferred: deferred)
        |> Map.keys()
        |> length()

      total =
        result.done_count + result.in_progress_count + result.deferred_count + result.todo_count

      assert total == erlang_funs_count

      # Progress should only consider done, todo, and in_progress (excluding deferred)
      total_for_progress = result.done_count + result.todo_count + result.in_progress_count
      expected_progress = round(result.done_count * 100 / total_for_progress)
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
