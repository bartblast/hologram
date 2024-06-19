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
      Path.join([Reflection.tmp_dir(), "tests", "commons", "file_utils", "recreate_dir_1"])

    File.rm_rf!(dir_path)
    File.mkdir_p!(dir_path)

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
end
