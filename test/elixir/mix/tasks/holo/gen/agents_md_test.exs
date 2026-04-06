defmodule Mix.Tasks.Holo.Gen.AgentsMdTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Hologram.Reflection
  alias Mix.Tasks.Holo.Gen.AgentsMd, as: Task

  setup do
    test_dir =
      Path.join([
        Reflection.tmp_dir(),
        "tests",
        "mix",
        "tasks",
        "holo",
        "gen",
        "agents_md"
      ])

    clean_dir(test_dir)

    source_path = Path.join(test_dir, "usage-rules.md")
    File.write!(source_path, "# Rules\n\n- Rule one\n")

    %{
      source_path: source_path,
      target_dir: test_dir,
      target_path: Path.join(test_dir, "AGENTS.md")
    }
  end

  test "run/1", %{
    source_path: source_path,
    target_dir: target_dir,
    target_path: target_path
  } do
    capture_io(fn ->
      Task.run(source_path: source_path, target_dir: target_dir)
    end)

    result =
      target_path
      |> File.read!()
      |> normalize_newlines()

    expected =
      normalize_newlines("""
      <!-- hologram-start -->
      ## Hologram

      - Rule one
      <!-- hologram-end -->
      """)

    assert result == expected
  end
end
