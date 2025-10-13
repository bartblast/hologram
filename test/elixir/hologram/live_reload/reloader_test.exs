defmodule Hologram.LiveReload.ReloaderTest do
  use Hologram.Test.BasicCase, async: true

  # The recompile_hologram/1 function is a pure delegation to Mix.Tasks.Compile.Hologram.run/1
  # with no additional logic, so there's nothing meaningful to test here.
  # The actual compilation logic is tested in Mix.Tasks.Compile.HologramTest.
  # test "recompile_hologram/1"
end
