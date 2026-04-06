defmodule Hologram.Generators.AIRulesTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO

  alias Hologram.Generators.AIRules
  alias Hologram.Reflection

  @expected_marked_content """
  <!-- hologram-start -->
  ## Hologram

  - Rule one
  - Rule two
  <!-- hologram-end -->
  """

  @filename "TEST.md"

  @marker_start "<!-- hologram-start -->"
  @marker_end "<!-- hologram-end -->"

  setup do
    test_dir =
      Path.join([
        Reflection.tmp_dir(),
        "tests",
        "generators",
        "ai_rules",
        "sync_2"
      ])

    clean_dir(test_dir)

    source_path = Path.join(test_dir, "usage-rules.md")

    File.write!(source_path, """
    # Test Rules

    - Rule one
    - Rule two
    """)

    %{
      source_path: source_path,
      target_dir: test_dir,
      target_path: Path.join(test_dir, @filename)
    }
  end

  describe "sync/2" do
    test "creates new file when it doesn't exist", %{
      source_path: source_path,
      target_dir: target_dir,
      target_path: target_path
    } do
      capture_io(fn ->
        AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
      end)

      assert File.read!(target_path) == @expected_marked_content
    end

    test "appends to existing file without markers", %{
      source_path: source_path,
      target_dir: target_dir,
      target_path: target_path
    } do
      File.write!(target_path, """
      # My Project

      Custom content.
      """)

      capture_io(fn ->
        AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
      end)

      expected = """
      # My Project

      Custom content.

      #{@marker_start}
      ## Hologram

      - Rule one
      - Rule two
      #{@marker_end}
      """

      assert File.read!(target_path) == expected
    end

    test "replaces content between existing markers", %{
      source_path: source_path,
      target_dir: target_dir,
      target_path: target_path
    } do
      File.write!(target_path, """
      before
      #{@marker_start}
      old content
      #{@marker_end}
      after
      """)

      capture_io(fn ->
        AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
      end)

      expected = """
      before
      #{@marker_start}
      ## Hologram

      - Rule one
      - Rule two
      #{@marker_end}
      after
      """

      assert File.read!(target_path) == expected
    end

    test "prints 'Created' for new files", %{
      source_path: source_path,
      target_dir: target_dir
    } do
      output =
        capture_io(fn ->
          AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
        end)

      assert output =~ "Created #{@filename}"
    end

    test "prints 'Updated' for existing files", %{
      source_path: source_path,
      target_dir: target_dir,
      target_path: target_path
    } do
      File.write!(target_path, "existing")

      output =
        capture_io(fn ->
          AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
        end)

      assert output =~ "Updated #{@filename}"
    end

    test "is idempotent when creating a new file", %{
      source_path: source_path,
      target_dir: target_dir,
      target_path: target_path
    } do
      capture_io(fn ->
        AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
      end)

      first_result = File.read!(target_path)

      capture_io(fn ->
        AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
      end)

      second_result = File.read!(target_path)

      assert first_result == second_result
    end

    test "is idempotent when appending to file without markers", %{
      source_path: source_path,
      target_dir: target_dir,
      target_path: target_path
    } do
      File.write!(target_path, """
      # My Project

      Custom content.
      """)

      capture_io(fn ->
        AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
      end)

      first_result = File.read!(target_path)

      capture_io(fn ->
        AIRules.sync(@filename, source_path: source_path, target_dir: target_dir)
      end)

      second_result = File.read!(target_path)

      assert first_result == second_result
    end
  end
end
