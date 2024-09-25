defmodule Mix.Tasks.Holo.Compiler.PageToMfaPathsTest do
  use Hologram.Test.BasicCase, async: true
  import ExUnit.CaptureIO
  alias Mix.Tasks.Holo.Compiler.PageToMfaPaths, as: Task

  test "run/1" do
    page_module_arg = "Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1"
    dest_mfa_arg = "{System, :normalize_time_unit, 1}"

    output =
      capture_io(fn ->
        assert Task.run([page_module_arg, dest_mfa_arg]) == :ok
      end)

    assert output == """

           {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :template, 0} -> {System, :normalize_time_unit, 1}
           [{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :template, 0}, {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :fun_1, 0}, {DateTime, :utc_now, 0}, {DateTime, :utc_now, 1}, {DateTime, :utc_now, 2}, {System, :os_time, 1}, {System, :normalize_time_unit, 1}]

           """
  end
end
