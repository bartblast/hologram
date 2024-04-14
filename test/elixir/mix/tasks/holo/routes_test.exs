defmodule Mix.Tasks.Holo.RoutesTest do
  use Hologram.Test.BasicCase, async: true
  import ExUnit.CaptureIO
  alias Mix.Tasks.Holo.Routes, as: Task

  test "run/1" do
    expected_header_output = """
    --------------------------------------------------------------------------------
    ROUTE / MODULE / SOURCE FILE
    --------------------------------------------------------------------------------\
    """

    expected_route_output = """
    --------------------------------------------------------------------------------
    /hologram-test-fixtures-mix-tasks-holo-routes-module1
    Hologram.Test.Fixtures.Mix.Tasks.Holo.Routes.Module1
    #{@fixtures_dir}/mix/tasks/holo/routes/module_1.ex
    --------------------------------------------------------------------------------\
    """

    output = capture_io(fn -> Task.run([]) end)

    assert String.contains?(output, expected_header_output)
    assert String.contains?(output, expected_route_output)
  end
end
