defmodule Hologram.BenchmarksTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Benchmarks

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Compiler

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
    test "100% added modules, 0% removed modules, 0% updated modules", %{
      module_digest_plt: module_digest_plt,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(100, 0)

      assert PLT.size(old_module_digest_plt) == 0
      assert PLT.size(new_module_digest_plt) == num_modules

      assert PLT.get_all(new_module_digest_plt) == PLT.get_all(module_digest_plt)
    end

    test "0% added modules, 100% removed modules, 0% updated modules", %{
      module_digest_plt: module_digest_plt,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(0, 100)

      assert PLT.size(old_module_digest_plt) == num_modules
      assert PLT.size(new_module_digest_plt) == 0

      assert PLT.get_all(old_module_digest_plt) == PLT.get_all(module_digest_plt)
    end

    test "0% added modules, 0% removed modules, 100% updated modules", %{
      module_digest_plt: module_digest_plt,
      modules: modules,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(0, 0)

      assert PLT.size(old_module_digest_plt) == num_modules
      assert PLT.size(new_module_digest_plt) == num_modules

      assert PLT.get_all(old_module_digest_plt) == PLT.get_all(module_digest_plt)

      Enum.each(modules, fn module ->
        assert PLT.get!(old_module_digest_plt, module) != PLT.get!(new_module_digest_plt, module)
      end)
    end

    test "20% added modules, 30% removed modules, 50% updated modules", %{
      modules: modules,
      num_modules: num_modules
    } do
      {old_module_digest_plt, new_module_digest_plt} = generate_module_digest_plts(20, 30)

      expected_num_added_modules = Integer.floor_div(20 * num_modules, 100)
      expected_num_removed_modules = Integer.floor_div(30 * num_modules, 100)

      expected_num_updated_modules =
        num_modules - expected_num_added_modules - expected_num_removed_modules

      assert PLT.size(old_module_digest_plt) == num_modules - expected_num_added_modules
      assert PLT.size(new_module_digest_plt) == num_modules - expected_num_removed_modules

      num_added_modules =
        Enum.reduce(modules, 0, fn module, acc ->
          case {PLT.get(old_module_digest_plt, module), PLT.get(new_module_digest_plt, module)} do
            {:error, {:ok, _digest}} -> acc + 1
            _fallback -> acc
          end
        end)

      assert num_added_modules == expected_num_added_modules

      num_removed_modules =
        Enum.reduce(modules, 0, fn module, acc ->
          case {PLT.get(old_module_digest_plt, module), PLT.get(new_module_digest_plt, module)} do
            {{:ok, _digest}, :error} -> acc + 1
            _fallback -> acc
          end
        end)

      assert num_removed_modules == expected_num_removed_modules

      num_updated_modules =
        Enum.reduce(modules, 0, fn module, acc ->
          case {PLT.get(old_module_digest_plt, module), PLT.get(new_module_digest_plt, module)} do
            {{:ok, digest}, {:ok, digest}} -> acc
            {{:ok, _digest_1}, {:ok, _digest_2}} -> acc + 1
            _fallback -> acc
          end
        end)

      assert num_updated_modules == expected_num_updated_modules
    end
  end
end
