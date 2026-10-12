defmodule Hologram.LiveReload.ReportDataModelFailureTest do
  use Hologram.Test.BasicCase, async: false

  import ExUnit.CaptureLog
  import Hologram.LiveReload

  alias Hologram.LiveReload.Diagnostic

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")

    :ok
  end

  describe "report_data_model_failure/2" do
    test "broadcasts an exception's message as a compilation error" do
      message = """
      invalid data model:
        * relationship :author in MyApp.Note targets String, which is not an entity type module\
      """

      log =
        capture_log(fn ->
          error = %Hologram.CompileError{message: message}

          assert report_data_model_failure(:error, error) == :ok
        end)

      assert log =~ "Hologram: data model step failed: #{message}"

      assert_receive {:compilation_error, lines}
      assert lines == Diagnostic.to_lines(message)
    end

    test "broadcasts an exit as a compilation error" do
      capture_log(fn ->
        assert report_data_model_failure(:exit, :timeout) == :ok
      end)

      assert_receive {:compilation_error, lines}
      assert lines == Diagnostic.to_lines("** (exit) time out")
    end
  end
end
