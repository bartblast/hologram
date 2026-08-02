defmodule Hologram.ExJsConsistency.StacktraceTest do
  @moduledoc """
  IMPORTANT!
  Each Elixir test here has a related JavaScript test in
  test/javascript/interpreter_test.mjs (formatStacktrace() describe block).
  Always update both together.

  The client renders its own stacktraces rather than running the transpiled
  Exception.format_stacktrace/1 to do it, which costs milliseconds per frame.
  That makes the rendering a reproduction of Elixir's, so these render the same
  frames the way Elixir does and pin what it produces - an Elixir release that
  renders a frame differently fails here, next to the JavaScript that has to
  match it.

  The modules named below have no application, so no application prefix leaks
  into the shapes being pinned. The prefix has a test of its own.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  @file_path ~c"lib/my_module.ex"

  defp format(frames), do: Exception.format_stacktrace(frames)

  describe "format_stacktrace/1" do
    test "indents each frame and ends the line it is on" do
      frames = [
        {MyModule, :my_fun, 1, [file: @file_path, line: 11]},
        {MyModule, :my_other_fun, 2, [file: @file_path, line: 22]}
      ]

      assert format(frames) ==
               "    lib/my_module.ex:11: MyModule.my_fun/1\n" <>
                 "    lib/my_module.ex:22: MyModule.my_other_fun/2\n"
    end

    # The version is taken from the application rather than written out, since
    # the suite runs against more than one Elixir.
    test "names the application a module was compiled into" do
      {:ok, vsn} = :application.get_key(:elixir, :vsn)
      frames = [{Enum, :map, 2, [file: ~c"lib/enum.ex", line: 11]}]

      assert format(frames) ==
               "    (elixir #{vsn}) lib/enum.ex:11: Enum.map/2\n"
    end

    # An application carrying no version has no test here: every application the
    # server knows of carries one, and the shape only arises on the client, where
    # a bundle can hold a module whose application version it doesn't. The
    # JavaScript test covers it alone.

    test "names an Erlang module as the atom it is" do
      frames = [{:my_module, :my_fun, 2, [file: ~c"my_module.erl", line: 11]}]

      assert format(frames) == "    my_module.erl:11: :my_module.my_fun/2\n"
    end

    test "names the arguments a frame kept in place of its arity" do
      frames = [{MyModule, :my_fun, [:abc, 1], [file: @file_path, line: 11]}]

      assert format(frames) == "    lib/my_module.ex:11: MyModule.my_fun(:abc, 1)\n"
    end

    test "places a frame carrying a file but no line by its file alone" do
      frames = [{MyModule, :my_fun, 1, [file: @file_path]}]

      assert format(frames) == "    lib/my_module.ex: MyModule.my_fun/1\n"
    end

    test "places a frame carrying no location by what was running alone" do
      frames = [{MyModule, :my_fun, 1, []}]

      assert format(frames) == "    MyModule.my_fun/1\n"
    end

    test "names an anonymous function after the one it was defined in" do
      frames = [{MyModule, :"-my_fun/2-fun-0-", 1, [file: @file_path, line: 11]}]

      assert format(frames) ==
               "    lib/my_module.ex:11: anonymous fn/1 in MyModule.my_fun/2\n"
    end

    # Elixir generates names for more than anonymous functions, and only the
    # ones it generated for those name the function they came from.
    test "keeps a generated name that names no function it came from" do
      frames = [
        {MyModule, :"-map/2-lists^map/1-1-", 2, [file: @file_path, line: 11]}
      ]

      assert format(frames) ==
               ~S(    lib/my_module.ex:11: MyModule."-map/2-lists^map/1-1-"/2) <> "\n"
    end

    test "writes a function name that could not be written as it stands quoted" do
      frames = [{MyModule, :"my fun", 1, [file: @file_path, line: 11]}]

      assert format(frames) ==
               ~S(    lib/my_module.ex:11: MyModule."my fun"/1) <> "\n"
    end

    # The client decides this through Macro.inspect_atom/3, which the JavaScript
    # tests stand in for with a helper that quotes every name it is given - so
    # which names go unquoted is pinned here rather than there.
    test "writes an operator as it stands" do
      frames = [{:my_module, :+, 2, [file: ~c"my_module.erl", line: 11]}]

      assert format(frames) == "    my_module.erl:11: :my_module.+/2\n"
    end
  end
end
