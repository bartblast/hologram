defmodule HologramFeatureTests.StacktraceTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.StacktraceFixture
  alias HologramFeatureTests.StacktracePage

  @fixture_file ~s(~c"app/stacktrace_fixture.ex")
  @page_file ~s(~c"app/pages/stacktrace_page.ex")

  # The lines the pinned frames point at, in app/pages/stacktrace_page.ex and
  # app/stacktrace_fixture.ex.
  @anonymous_raise_line 42
  @anonymous_call_line 47
  @local_call_line 58
  @fixture_raise_line 3
  @remote_call_line 73

  # The raising frame reports the raise expression's line and carries the
  # error_info naming the exception formatter. Each caller frame below it
  # reports the line its call is made on - not the line its function starts at.
  feature "each frame points at the line its function has reached", %{session: session} do
    expected =
      "{:nested_calls_trace, [" <>
        "{#{inspect(StacktraceFixture)}, :raise_error, 1, " <>
        "[file: #{@fixture_file}, line: #{@fixture_raise_line}, error_info: %{module: Exception}]}, " <>
        "{#{inspect(StacktracePage)}, :local_fun, 1, " <>
        "[file: #{@page_file}, line: #{@remote_call_line}]}, " <>
        "{#{inspect(StacktracePage)}, :action, 3, " <>
        "[file: #{@page_file}, line: #{@local_call_line}]}]}"

    session
    |> visit(StacktracePage)
    |> click(button("Nested calls"))
    |> assert_text(css("#result"), expected)
  end

  # An anonymous function's frame is named after its enclosing definition, the
  # way the BEAM names it. The trailing fun counter is the client's own - the
  # server numbers every generated function in the module, which no message
  # depends on (see Hologram.Compiler.Encoder).
  feature "raise inside an anonymous function names its frame after the definition",
          %{session: session} do
    expected =
      "{:anonymous_function_trace, [" <>
        ~s({#{inspect(StacktracePage)}, :"-action/3-fun-0-", 1, ) <>
        "[file: #{@page_file}, line: #{@anonymous_raise_line}, error_info: %{module: Exception}]}, " <>
        "{#{inspect(StacktracePage)}, :action, 3, " <>
        "[file: #{@page_file}, line: #{@anonymous_call_line}]}]}"

    session
    |> visit(StacktracePage)
    |> click(button("Anonymous function"))
    |> assert_text(css("#result"), expected)
  end
end
