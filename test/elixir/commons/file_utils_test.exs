defmodule Hologram.Commons.FileUtilsTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Commons.FileUtils

  describe "list_files_recursively/1" do
    @base_path "test/elixir/fixtures/commons/file_utils/list_files_recursively"

    test "single path" do
      assert FileUtils.list_files_recursively(@base_path) == [
               "#{@base_path}/dir_1/dir_3/file_5.txt",
               "#{@base_path}/dir_1/dir_3/file_6.txt",
               "#{@base_path}/dir_1/file_3.txt",
               "#{@base_path}/dir_1/file_4.txt",
               "#{@base_path}/dir_2/file_7.txt",
               "#{@base_path}/dir_2/file_8.txt",
               "#{@base_path}/file_1.text",
               "#{@base_path}/file_2.text"
             ]
    end

    test "multiple paths" do
      paths = [
        "#{@base_path}/dir_1",
        "#{@base_path}/dir_2"
      ]

      assert FileUtils.list_files_recursively(paths) == [
               "#{@base_path}/dir_1/dir_3/file_5.txt",
               "#{@base_path}/dir_1/dir_3/file_6.txt",
               "#{@base_path}/dir_1/file_3.txt",
               "#{@base_path}/dir_1/file_4.txt",
               "#{@base_path}/dir_2/file_7.txt",
               "#{@base_path}/dir_2/file_8.txt"
             ]
    end

    test "removes duplicates" do
      paths = [
        "#{@base_path}/dir_1",
        "#{@base_path}/dir_1/dir_3"
      ]

      assert FileUtils.list_files_recursively(paths) == [
               "#{@base_path}/dir_1/dir_3/file_5.txt",
               "#{@base_path}/dir_1/dir_3/file_6.txt",
               "#{@base_path}/dir_1/file_3.txt",
               "#{@base_path}/dir_1/file_4.txt"
             ]
    end
  end
end
