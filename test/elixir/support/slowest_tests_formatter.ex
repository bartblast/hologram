defmodule Hologram.Test.SlowestTestsFormatter do
  @moduledoc false

  # TODO: Remove this formatter, and its --formatter flags in the lib test step of
  # .github/workflows/ci.yml, once the Windows timeouts of the compiler Mix task tests
  # (ExRuntimeMfasTest, PageToMfaPathsTest) are diagnosed.
  #
  # Prints the slowest tests when the suite finishes, the way mix test --slowest does, without what
  # --slowest also turns on: trace mode, which runs one test module at a time. These tests time out
  # only when they share the runner with the rest of the async suite, so measuring them serially
  # would measure a run that never fails.

  use GenServer

  @count 15

  @impl GenServer
  def init(_opts), do: {:ok, []}

  @impl GenServer
  def handle_cast({:test_finished, %ExUnit.Test{} = test}, tests) do
    {:noreply, [test | tests]}
  end

  def handle_cast({:suite_finished, _times}, tests) do
    lines =
      tests
      |> Enum.sort_by(& &1.time, :desc)
      |> Enum.take(@count)
      |> Enum.map_join("\n", &describe/1)

    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts("\nTop #{@count} slowest tests, run with the suite's own concurrency:\n\n#{lines}")

    {:noreply, tests}
  end

  def handle_cast(_event, tests), do: {:noreply, tests}

  defp describe(%ExUnit.Test{module: module, name: name, tags: tags, time: time}) do
    location = "#{Path.relative_to_cwd(tags.file)}:#{tags.line}"

    "  * #{name} (#{inspect(module)}) (#{Float.round(time / 1000, 1)}ms) [#{location}]"
  end
end
