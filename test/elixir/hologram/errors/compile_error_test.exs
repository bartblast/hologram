defmodule Hologram.CompileErrorTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.CompileError

  @file_path "lib/my_app/task_list.ex"

  defp absolute_file_path do
    Path.join(File.cwd!(), @file_path)
  end

  describe "message/1" do
    test "reads as the message alone when no location is carried" do
      error = %CompileError{message: "the query builds no window"}

      assert Exception.message(error) == "the query builds no window"
    end

    test "opens with the file when no line is carried" do
      error = %CompileError{message: "the query builds no window", file: absolute_file_path()}

      assert Exception.message(error) == "lib/my_app/task_list.ex: the query builds no window"
    end

    test "opens with the file and the line" do
      error = %CompileError{
        message: "the query builds no window",
        file: absolute_file_path(),
        line: 17
      }

      assert Exception.message(error) == "lib/my_app/task_list.ex:17: the query builds no window"
    end

    test "renders a frame whose file is unknown as the function alone" do
      error = %CompileError{
        message: "the query builds no window",
        stack: [{MyApp.TaskList, :entities_query, 1, [file: nil, line: 17]}]
      }

      expected_msg =
        normalize_newlines("""
        the query builds no window

            MyApp.TaskList.entities_query/1\
        """)

      assert Exception.message(error) == expected_msg
    end

    test "renders every frame's file relative to the project, as the opening does" do
      error = %CompileError{
        message: "the query builds no window",
        file: absolute_file_path(),
        line: 20,
        stack: [{MyApp.TaskList, :bounds, 0, [file: absolute_file_path(), line: 20]}]
      }

      expected_msg =
        normalize_newlines("""
        lib/my_app/task_list.ex:20: the query builds no window

            lib/my_app/task_list.ex:20: MyApp.TaskList.bounds/0\
        """)

      assert Exception.message(error) == expected_msg
    end

    test "closes with the path the error was reached through" do
      error = %CompileError{
        message: "the query builds no window",
        file: absolute_file_path(),
        line: 20,
        stack: [
          {MyApp.TaskList, :bounds, 0, [file: @file_path, line: 20]},
          {MyApp.TaskList, :entities_query, 1, [file: @file_path, line: 17]}
        ]
      }

      expected_msg =
        normalize_newlines("""
        lib/my_app/task_list.ex:20: the query builds no window

            lib/my_app/task_list.ex:20: MyApp.TaskList.bounds/0
            lib/my_app/task_list.ex:17: MyApp.TaskList.entities_query/1\
        """)

      assert Exception.message(error) == expected_msg
    end
  end
end
