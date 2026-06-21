defmodule Mix.Tasks.Holo.Compiler.PageToMfaPathsTest do
  use Hologram.Test.BasicCase, async: true
  import ExUnit.CaptureIO
  alias Mix.Tasks.Holo.Compiler.PageToMfaPaths, as: Task

  test "run/1" do
    page_module_arg = "Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1"

    dest_mfa_arg =
      "{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module3, :fun_3c, 0}"

    output =
      capture_io(fn ->
        assert Task.run([page_module_arg, dest_mfa_arg]) == :ok
      end)

    assert output == """

           {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :template, 0} -> {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module3, :fun_3c, 0}
           [{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :template, 0}, {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :fun_1a, 0}, {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module2, :fun_2b, 0}, {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module3, :fun_3c, 0}]

           """
  end
end
