defmodule Mix.Tasks.Holo.Compiler.PageExFunSizesTest do
  # async: false - the task builds the call graph of the whole project, which takes a few
  # seconds alone. Run concurrently with the other compiler task tests and the async suite, the
  # builds contend for the runner's cores - on Windows CI they took up to 56 s, and sometimes ran
  # past the 60 s timeout.
  use Hologram.Test.BasicCase, async: false
  import ExUnit.CaptureIO
  alias Mix.Tasks.Holo.Compiler.PageExFunSizes, as: Task

  test "run/1" do
    arg = "Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module1"

    output =
      capture_io(fn ->
        assert Task.run([arg]) == :ok
      end)

    expected_pattern =
      normalize_newlines("""
      \[
        \{\{Hologram\.Test\.Fixtures\.Mix\.Tasks\.Holo\.Compiler\.PageExFunSizes\.Module1,
          :template, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.LayoutFixture, :template, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.Mix\.Tasks\.Holo\.Compiler\.PageExFunSizes\.Module1,
          :__route__, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.Mix\.Tasks\.Holo\.Compiler\.PageExFunSizes\.Module1,
          :__params__, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.Mix\.Tasks\.Holo\.Compiler\.PageExFunSizes\.Module1,
          :__layout_module__, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.LayoutFixture, :__props__, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.Mix\.Tasks\.Holo\.Compiler\.PageExFunSizes\.Module1,
          :__layout_props__, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.LayoutFixture, :init, 2\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.Mix\.Tasks\.Holo\.Compiler\.PageExFunSizes\.Module1,
          :fun_1, 0\}, [[:alnum:]]+\},
        \{\{Hologram\.Test\.Fixtures\.Mix\.Tasks\.Holo\.Compiler\.PageExFunSizes\.Module1,
          :fun_2, 0\}, [[:alnum:]]+\}
      \]
      """)

    assert output =~ Regex.compile!(expected_pattern)
  end

  # The page's init/3 puts an Ecto schema into state, and no client code calls a reflection
  # function on a module it does not name, so the page's bundle holds none of the schema's.
  test "run/1 lists no reflection function the page's bundle leaves out" do
    arg = "Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module2"

    output =
      capture_io(fn ->
        assert Task.run([arg]) == :ok
      end)

    assert output =~ "PageExFunSizes.Module2"
    refute output =~ "__changeset__"
    refute output =~ "__schema__"
  end
end
