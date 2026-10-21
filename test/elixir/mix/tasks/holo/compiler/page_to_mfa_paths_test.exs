defmodule Mix.Tasks.Holo.Compiler.PageToMfaPathsTest do
  # async: false - the task builds the call graph of the whole project, which takes a few
  # seconds alone. Run concurrently with the other compiler task tests and the async suite, the
  # builds contend for the runner's cores - on Windows CI they took up to 56 s, and sometimes ran
  # past the 60 s timeout.
  use Hologram.Test.BasicCase, async: false
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

    expected =
      normalize_newlines("""

      {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :template, 0} -> {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module3, :fun_3c, 0}
      [{Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :template, 0}, {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module1, :fun_1a, 0}, {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module2, :fun_2b, 0}, {Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageToMfaPaths.Module3, :fun_3c, 0}]

      """)

    assert output == expected
  end
end
