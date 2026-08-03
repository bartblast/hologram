defmodule Hologram.LiveReload.DiagnosticTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureIO
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

    # Only what is worth finding carries weight, so a line this doesn't know is
    # shown as it was written rather than given weight it hasn't earned.
    test "reads a line in no known shape in the chrome tone" do
      assert to_lines("Compiling 1 file (.ex)") == [
               [%{tone: :chrome, text: "Compiling 1 file (.ex)"}]
             ]
    end

    test "reads a caret line in the chrome tone" do
      assert to_lines("    │     ^^^") == [[%{tone: :chrome, text: "    │     ^^^"}]]
    end

    test "reads a section rule in the chrome tone" do
      assert to_lines("== Compilation error in file lib/my_app.ex ==") == [
               [%{tone: :chrome, text: "== Compilation error in file lib/my_app.ex =="}]
             ]
    end

    # Split the way a stack frame is, so both reports tell where something is
    # apart from what was there in the same way.
    test "sets a location apart from what it points at" do
      assert to_lines("    └─ lib/my_app.ex:3:5: MyApp.bar/0") == [
               [
                 %{tone: :chrome, text: "    └─ "},
                 %{tone: :meta, text: "lib/my_app.ex:3:5: "},
                 %{tone: :body, text: "MyApp.bar/0"}
               ]
             ]
    end

    test "sets a location carrying no column apart from what it points at" do
      assert to_lines("    └─ lib/my_app.ex:3: MyApp.bar/0") == [
               [
                 %{tone: :chrome, text: "    └─ "},
                 %{tone: :meta, text: "lib/my_app.ex:3: "},
                 %{tone: :body, text: "MyApp.bar/0"}
               ]
             ]
    end

    test "reads a location naming nothing it points at as the location alone" do
      assert to_lines("    └─ nofile:8:8") == [
               [%{tone: :chrome, text: "    └─ "}, %{tone: :meta, text: "nofile:8:8"}]
             ]
    end

    # A diagnostic raised while compiling carries the stacktrace it was raised
    # through, which reads the way the client reads an uncaught error's frames.
    test "sets a stack frame's source location apart from what was running" do
      line = "    (hologram 0.10.1) lib/hologram/template.ex:40: Hologram.Template.build/1"

      assert to_lines(line) == [
               [
                 %{tone: :chrome, text: "    (hologram 0.10.1) "},
                 %{tone: :meta, text: "lib/hologram/template.ex:40: "},
                 %{tone: :body, text: "Hologram.Template.build/1"}
               ]
             ]
    end

    test "sets a stack frame expanding a macro apart the same way" do
      line = "    (hologram 0.10.1) expanding macro: Hologram.Template.sigil_HOLO/2"

      assert to_lines(line) == [
               [
                 %{tone: :chrome, text: "    (hologram 0.10.1) "},
                 %{tone: :meta, text: "expanding macro: "},
                 %{tone: :body, text: "Hologram.Template.sigil_HOLO/2"}
               ]
             ]
    end

    test "sets a source excerpt's gutter apart from its source" do
      assert to_lines("  3 │     foo()") == [
               [%{tone: :chrome, text: "  3 │ "}, %{tone: :body, text: "    foo()"}]
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
               [%{tone: :chrome}],
               [%{tone: :chrome}, %{tone: :body}],
               [%{tone: :chrome}],
               [%{tone: :chrome}],
               [%{tone: :chrome}, %{tone: :meta}, %{tone: :body}],
               [%{tone: :chrome, text: ""}]
             ] = to_lines(output)
    end
  end

  # The shapes to_lines/1 keys on are Elixir's, not Hologram's, so the cases
  # above only pin what the compiler is believed to print. These run a
  # diagnostic the compiler really produced through the same reading, so an
  # Elixir release that renders one differently fails here rather than going
  # unnoticed until somebody sees the overlay.
  describe "to_lines/1 on a diagnostic the compiler really produced" do
    setup do
      {_result, diagnostics} =
        Code.with_diagnostics(fn ->
          try do
            Code.compile_string(
              """
              defmodule Hologram.Test.Fixtures.LiveReload.Diagnostic.Module1 do
                def bar do
                  foo()
                end
              end
              """,
              "lib/my_app.ex"
            )
          rescue
            error -> error
          end
        end)

      output = capture_io(:stderr, fn -> Enum.each(diagnostics, &Code.print_diagnostic/1) end)

      [lines: to_lines(output)]
    end

    test "reads the header naming what went wrong in the banner tone", %{lines: lines} do
      assert [%{tone: :banner, text: text}] = hd(lines)

      trimmed = String.trim_leading(text)

      assert String.starts_with?(trimmed, "error:")
    end

    test "sets the location apart from what it points at", %{lines: lines} do
      location_line =
        Enum.find(lines, fn segments ->
          Enum.any?(segments, &String.contains?(&1.text, "└─"))
        end)

      assert [
               %{tone: :chrome, text: marker},
               %{tone: :meta, text: location},
               %{tone: :body, text: compiling}
             ] = location_line

      assert String.contains?(marker, "└─")
      assert String.starts_with?(location, "lib/my_app.ex:")
      assert compiling =~ ~r"\.\w+/\d+$"
    end

    test "gives no line weight it hasn't earned", %{lines: lines} do
      weighted =
        lines
        |> List.flatten()
        |> Enum.filter(&(&1.tone == :body))
        |> Enum.map(& &1.text)

      # Only what is worth finding carries weight. A shape this doesn't know
      # falls back to :chrome, so every run here was recognised on purpose - and
      # in this diagnostic that is what was being compiled, named as an MFA.
      assert weighted != []
      assert Enum.all?(weighted, &(&1 =~ ~r"\.\w+/\d+$"))
    end
  end
end
