defmodule Hologram.BenchmarksTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Benchmarks

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Reflection

  defp count_added_modules(modules, old_module_digest_plt, new_module_digest_plt) do
    Enum.reduce(modules, 0, fn module, acc ->
      case {PLT.get(old_module_digest_plt, module), PLT.get(new_module_digest_plt, module)} do
        {:error, {:ok, _digest}} -> acc + 1
        _fallback -> acc
      end
    end)
  end

  defp count_removed_modules(modules, old_module_digest_plt, new_module_digest_plt) do
    Enum.reduce(modules, 0, fn module, acc ->
      case {PLT.get(old_module_digest_plt, module), PLT.get(new_module_digest_plt, module)} do
        {{:ok, _digest}, :error} -> acc + 1
        _fallback -> acc
      end
    end)
  end

  defp count_untouched_modules(modules, old_module_digest_plt, new_module_digest_plt) do
    Enum.reduce(modules, 0, fn module, acc ->
      case {PLT.get(old_module_digest_plt, module), PLT.get(new_module_digest_plt, module)} do
        {{:ok, digest}, {:ok, digest}} -> acc + 1
        {{:ok, _digest_1}, {:ok, _digest_2}} -> acc
        _fallback -> acc
      end
    end)
  end

  defp count_updated_modules(modules, old_module_digest_plt, new_module_digest_plt) do
    Enum.reduce(modules, 0, fn module, acc ->
      case {PLT.get(old_module_digest_plt, module), PLT.get(new_module_digest_plt, module)} do
        {{:ok, digest}, {:ok, digest}} -> acc
        {{:ok, _digest_1}, {:ok, _digest_2}} -> acc + 1
        _fallback -> acc
      end
    end)
  end

  setup_all do
    modules = Reflection.list_elixir_modules()
    module_beam_path_plt = Compiler.build_module_beam_path_plt()

    [
      module_digest_plt: Compiler.build_module_digest_plt!(module_beam_path_plt),
      modules: modules,
      num_modules: Enum.count(modules)
    ]
  end

  describe "generate_module_digest_plts/2" do
    test "100% added modules, 0% removed modules, 0% updated modules, 0% untouched modules", %{
      module_digest_plt: module_digest_plt,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(1.0, 0.0, 0.0)

      assert PLT.size(old_module_digest_plt) == 0
      assert PLT.size(new_module_digest_plt) == num_modules

      assert PLT.get_all(new_module_digest_plt) == PLT.get_all(module_digest_plt)
    end

    test "0% added modules, 100% removed modules, 0% updated modules, 0% untouched modules", %{
      module_digest_plt: module_digest_plt,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(0.0, 1.0, 0.0)

      assert PLT.size(old_module_digest_plt) == num_modules
      assert PLT.size(new_module_digest_plt) == 0

      assert PLT.get_all(old_module_digest_plt) == PLT.get_all(module_digest_plt)
    end

    test "0% added modules, 0% removed modules, 100% updated modules, 0% untouched modules", %{
      module_digest_plt: module_digest_plt,
      modules: modules,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(0.0, 0.0, 1.0)

      assert PLT.size(old_module_digest_plt) == num_modules
      assert PLT.size(new_module_digest_plt) == num_modules

      assert PLT.get_all(old_module_digest_plt) == PLT.get_all(module_digest_plt)

      Enum.each(modules, fn module ->
        assert PLT.get!(old_module_digest_plt, module) != PLT.get!(new_module_digest_plt, module)
      end)
    end

    test "0% added modules, 0% removed modules, 0% updated modules, 100% untouched modules", %{
      module_digest_plt: module_digest_plt,
      modules: modules,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(0.0, 0.0, 0.0)

      assert PLT.size(old_module_digest_plt) == num_modules
      assert PLT.size(new_module_digest_plt) == num_modules

      assert PLT.get_all(old_module_digest_plt) == PLT.get_all(module_digest_plt)

      Enum.each(modules, fn module ->
        assert PLT.get!(old_module_digest_plt, module) == PLT.get!(new_module_digest_plt, module)
      end)
    end

    test "10% added modules, 20% removed modules, 30% updated modules, 40% untouched modules", %{
      modules: modules,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(0.1, 0.2, 0.3)

      expected_num_added_modules = trunc(0.1 * num_modules)
      expected_num_removed_modules = trunc(0.2 * num_modules)
      expected_num_updated_modules = trunc(0.3 * num_modules)

      expected_num_untouched_modules =
        num_modules - expected_num_added_modules - expected_num_removed_modules -
          expected_num_updated_modules

      assert PLT.size(old_module_digest_plt) == num_modules - expected_num_added_modules
      assert PLT.size(new_module_digest_plt) == num_modules - expected_num_removed_modules

      num_added_modules =
        count_added_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_added_modules == expected_num_added_modules

      num_removed_modules =
        count_removed_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_removed_modules == expected_num_removed_modules

      num_updated_modules =
        count_updated_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_updated_modules == expected_num_updated_modules

      num_untouched_modules =
        count_untouched_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_untouched_modules == expected_num_untouched_modules
    end

    test "literal number of modules", %{
      modules: modules,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(1, 2, 3)

      expected_num_added_modules = 1
      expected_num_removed_modules = 2
      expected_num_updated_modules = 3

      expected_num_untouched_modules = num_modules - 1 - 2 - 3

      assert PLT.size(old_module_digest_plt) == num_modules - expected_num_added_modules
      assert PLT.size(new_module_digest_plt) == num_modules - expected_num_removed_modules

      num_added_modules =
        count_added_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_added_modules == expected_num_added_modules

      num_removed_modules =
        count_removed_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_removed_modules == expected_num_removed_modules

      num_updated_modules =
        count_updated_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_updated_modules == expected_num_updated_modules

      num_untouched_modules =
        count_untouched_modules(modules, old_module_digest_plt, new_module_digest_plt)

      assert num_untouched_modules == expected_num_untouched_modules
    end

    test "sum of float args greater than 1.0" do
      assert {%PLT{}, %PLT{}} = generate_module_digest_plts(0.2, 0.3, 0.5)

      assert_raise ArgumentError,
                   "the sum of the arguments in case they are floats must be less than or equal to 1.0",
                   fn ->
                     generate_module_digest_plts(0.2, 0.3, 0.501)
                   end
    end

    test "first float arg less than 0.0" do
      expected_msg =
        "invalid arguments: added_modules_spec = -0.1, removed_modules_spec = 0.2, updated_modules_spec = 0.3"

      assert_raise ArgumentError, expected_msg, fn ->
        generate_module_digest_plts(-0.1, 0.2, 0.3)
      end
    end

    test "second float arg less than 0.0" do
      expected_msg =
        "invalid arguments: added_modules_spec = 0.1, removed_modules_spec = -0.2, updated_modules_spec = 0.3"

      assert_raise ArgumentError, expected_msg, fn ->
        generate_module_digest_plts(0.1, -0.2, 0.3)
      end
    end

    test "third float arg less than 0.0" do
      expected_msg =
        "invalid arguments: added_modules_spec = 0.1, removed_modules_spec = 0.2, updated_modules_spec = -0.3"

      assert_raise ArgumentError, expected_msg, fn ->
        generate_module_digest_plts(0.1, 0.2, -0.3)
      end
    end

    test "first integer arg less than 0" do
      expected_msg =
        "invalid arguments: added_modules_spec = -1, removed_modules_spec = 2, updated_modules_spec = 3"

      assert_raise ArgumentError, expected_msg, fn ->
        generate_module_digest_plts(-1, 2, 3)
      end
    end

    test "second integer arg less than 0" do
      expected_msg =
        "invalid arguments: added_modules_spec = 1, removed_modules_spec = -2, updated_modules_spec = 3"

      assert_raise ArgumentError, expected_msg, fn ->
        generate_module_digest_plts(1, -2, 3)
      end
    end

    test "third integer arg less than 0" do
      expected_msg =
        "invalid arguments: added_modules_spec = 1, removed_modules_spec = 2, updated_modules_spec = -3"

      assert_raise ArgumentError, expected_msg, fn ->
        generate_module_digest_plts(1, 2, -3)
      end
    end

    test "mixed type of arguments" do
      expected_msg =
        "invalid arguments: added_modules_spec = 1, removed_modules_spec = 2.0, updated_modules_spec = 3"

      assert_raise ArgumentError, expected_msg, fn ->
        generate_module_digest_plts(1, 2.0, 3)
      end
    end
  end
end
