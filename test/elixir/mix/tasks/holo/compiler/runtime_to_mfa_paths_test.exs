defmodule Mix.Tasks.Holo.Compiler.RuntimeToMfaPathsTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.Holo.Compiler.RuntimeToMfaPaths, as: Task

  test "run/1" do
    output =
      fn -> Task.run(["{URI, :default_port, 1}"]) end
      |> capture_io()
      |> normalize_newlines()

    assert String.contains?(output, """
           {String.Chars, :to_string, 1} -> {URI, :default_port, 1}
           [{String.Chars, :to_string, 1}, {String.Chars.URI, :to_string, 1}, {URI, :default_port, 1}]
           """)
  end
end
