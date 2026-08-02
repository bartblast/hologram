defmodule Hologram.LiveReload.DiagnosticTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.LiveReload.Diagnostic

  describe "to_lines/1" do
    test "reads a compilation error banner in the banner tone" do
      assert to_lines("** (CompileError) lib/my_app.ex: cannot compile module MyApp") == [
               [
                 %{
                   tone: :banner,
                   text: "** (CompileError) lib/my_app.ex: cannot compile module MyApp"
                 }
               ]
             ]
    end

    test "reads an error header in the banner tone" do
      assert to_lines("    error: undefined function foo/0") == [
               [%{tone: :banner, text: "    error: undefined function foo/0"}]
             ]
    end

    test "reads a warning header in the banner tone" do
      assert to_lines("    warning: variable \"x\" is unused") == [
               [%{tone: :banner, text: "    warning: variable \"x\" is unused"}]
             ]
    end

    test "reads a section rule in the dimmest tone" do
      assert to_lines("== Compilation error in file lib/my_app.ex ==") == [
               [%{tone: :dimmest, text: "== Compilation error in file lib/my_app.ex =="}]
             ]
    end

    test "reads a caret line in the dimmest tone" do
      assert to_lines("    │     ^^^") == [[%{tone: :dimmest, text: "    │     ^^^"}]]
    end

    test "reads a location in the dim tone" do
      assert to_lines("    └─ lib/my_app.ex:3:5: MyApp.bar/0") == [
               [%{tone: :dim, text: "    └─ lib/my_app.ex:3:5: MyApp.bar/0"}]
             ]
    end

    test "sets a source excerpt's gutter apart from its source" do
      assert to_lines("  3 │     foo()") == [
               [%{tone: :dimmest, text: "  3 │ "}, %{tone: :foreground, text: "    foo()"}]
             ]
    end

    test "reads a line in no known shape in the foreground tone" do
      assert to_lines("something else entirely") == [
               [%{tone: :foreground, text: "something else entirely"}]
             ]
    end

    test "removes the escape sequences the compiler colors its output with" do
      assert to_lines("\e[31m    error: undefined function foo/0\e[0m") == [
               [%{tone: :banner, text: "    error: undefined function foo/0"}]
             ]
    end

    test "returns one entry per line of output" do
      output = """
          error: undefined function foo/0
          │
        3 │     foo()
          │     ^^^
          │
          └─ lib/my_app.ex:3:5: MyApp.bar/0
      """

      assert [
               [%{tone: :banner}],
               [%{tone: :dimmest}],
               [%{tone: :dimmest}, %{tone: :foreground}],
               [%{tone: :dimmest}],
               [%{tone: :dimmest}],
               [%{tone: :dim}],
               [%{tone: :foreground, text: ""}]
             ] = to_lines(output)
    end
  end
end
