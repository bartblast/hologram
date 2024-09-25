defmodule Mix.Tasks.Holo.Compiler.PageExFunSizesTest do
  use Hologram.Test.BasicCase, async: true
  import ExUnit.CaptureIO
  alias Mix.Tasks.Holo.Compiler.PageExFunSizes, as: Task

  test "run/1" do
    arg = "Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1"

    output =
      capture_io(fn ->
        assert Task.run([arg]) == :ok
      end)

    assert output === """
           [
             {{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1,
               :template, 0}, 853},
             {{Hologram.Test.Fixtures.LayoutFixture, :template, 0}, 634},
             {{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1,
               :__route__, 0}, 295},
             {{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1,
               :__layout_module__, 0}, 270},
             {{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1,
               :__params__, 0}, 246},
             {{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1,
               :__layout_props__, 0}, 226},
             {{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1,
               :fun_1, 0}, 216},
             {{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1,
               :fun_2, 0}, 216},
             {{Hologram.Test.Fixtures.LayoutFixture, :__props__, 0}, 212}
           ]
           """
  end
end
