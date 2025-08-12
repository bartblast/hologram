defmodule Hologram.Commons.FileUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.FileUtils
  alias Hologram.Reflection

  describe "list_files_recursively/1" do
    @base_dir "test/elixir/support/fixtures/commons/file_utils/list_files_recursively"

    test "single path" do
      assert list_files_recursively(@base_dir) == [
               "#{@base_dir}/dir_1/dir_3/file_5.txt",
               "#{@base_dir}/dir_1/dir_3/file_6.txt",
               "#{@base_dir}/dir_1/file_3.txt",
               "#{@base_dir}/dir_1/file_4.txt",
               "#{@base_dir}/dir_2/file_7.txt",
               "#{@base_dir}/dir_2/file_8.txt",
               "#{@base_dir}/file_1.text",
               "#{@base_dir}/file_2.text"
             ]
    end

    test "multiple paths" do
      paths = [
        "#{@base_dir}/dir_1",
        "#{@base_dir}/dir_2"
      ]

      assert list_files_recursively(paths) == [
               "#{@base_dir}/dir_1/dir_3/file_5.txt",
               "#{@base_dir}/dir_1/dir_3/file_6.txt",
               "#{@base_dir}/dir_1/file_3.txt",
               "#{@base_dir}/dir_1/file_4.txt",
               "#{@base_dir}/dir_2/file_7.txt",
               "#{@base_dir}/dir_2/file_8.txt"
             ]
    end

    test "removes duplicates" do
      paths = [
        "#{@base_dir}/dir_1",
        "#{@base_dir}/dir_1/dir_3"
      ]

      assert list_files_recursively(paths) == [
               "#{@base_dir}/dir_1/dir_3/file_5.txt",
               "#{@base_dir}/dir_1/dir_3/file_6.txt",
               "#{@base_dir}/dir_1/file_3.txt",
               "#{@base_dir}/dir_1/file_4.txt"
             ]
    end

    test "invalid path" do
      assert_raise ArgumentError, ~s(Invalid path: "my/invalid/path"), fn ->
        list_files_recursively("my/invalid/path")
      end
    end
  end

  test "recreate_dir/1" do
    dir_path =
      Path.join([
        Reflection.tmp_dir(),
        "tests",
        "commons",
        "file_utils",
        "recreate_dir_1"
      ])

    clean_dir(dir_path)

    file_path_1 = Path.join(dir_path, "file_1.txt")
    File.write!(file_path_1, "file_1")

    file_path_2 = Path.join(dir_path, "file_2.txt")
    File.write!(file_path_2, "file_2")

    nested_dir_path_1 = Path.join(dir_path, "dir_1")
    File.mkdir!(nested_dir_path_1)

    file_path_3 = Path.join(nested_dir_path_1, "file_3.txt")
    File.write!(file_path_3, "file_3")

    nested_dir_path_2 = Path.join(dir_path, "dir_2")
    File.mkdir!(nested_dir_path_2)

    file_path_4 = Path.join(nested_dir_path_2, "file_4.txt")
    File.write!(file_path_4, "file_4")

    assert recreate_dir(dir_path) == :ok
    assert File.ls!(dir_path) == []
  end

  describe "rm_rf_with_retries!/3" do
    @base_dir Path.join([
                Reflection.tmp_dir(),
                "tests",
                "commons",
                "file_utils",
                "rm_rf_with_retries!_3"
              ])

    test "removes a regular file" do
      dir_path = Path.join(@base_dir, "file")
      clean_dir(dir_path)

      file_path = Path.join(dir_path, "file.txt")
      File.write!(file_path, "content")

      assert File.regular?(file_path)

      assert rm_rf_with_retries!(file_path, 5, 10) == :ok
      refute File.exists?(file_path)
    end

    test "removes an empty directory" do
      dir_path = Path.join(@base_dir, "empty_dir")
      clean_dir(dir_path)

      assert File.dir?(dir_path)

      assert rm_rf_with_retries!(dir_path, 5, 10) == :ok
      refute File.exists?(dir_path)
    end

    test "removes a non-empty directory" do
      dir_path = Path.join(@base_dir, "non_empty_dir")
      clean_dir(dir_path)

      nested_dir_path = Path.join(dir_path, "nested")
      File.mkdir!(nested_dir_path)

      nested_file_path = Path.join(nested_dir_path, "file.txt")
      File.write!(nested_file_path, "content")

      assert File.dir?(dir_path)
      assert File.regular?(nested_file_path)

      assert rm_rf_with_retries!(dir_path, 5, 10) == :ok
      refute File.exists?(dir_path)
    end

    test "succeeds if path does not exist" do
      path = Path.join(@base_dir, "nonexistent_path")
      refute File.exists?(path)

      assert rm_rf_with_retries!(path, 5, 10) == :ok
      refute File.exists?(path)
    end

    test "raises if cannot remove after retries due to permissions" do
      dir_path = Path.join(@base_dir, "protected_dir")
      clean_dir(dir_path)

      # Create a nested file so the directory is non-empty
      nested_file_path = Path.join(dir_path, "file.txt")
      File.write!(nested_file_path, "content")

      # On Windows, chmod may be a no-op; in that case, just assert no raise
      if match?({:win32, _name}, :os.type()) do
        assert rm_rf_with_retries!(dir_path, 5, 10) == :ok
      else
        # Remove write permission on the directory while keeping execute so listing works
        File.chmod!(dir_path, 0o555)

        assert_raise RuntimeError, "Failed to fully remove #{dir_path} after 5 attempts", fn ->
          rm_rf_with_retries!(dir_path, 5, 10)
        end

        # Cleanup: restore permissions for reliable removal
        if File.exists?(dir_path) do
          File.chmod!(dir_path, 0o755)
        end
      end
    end
  end
end
