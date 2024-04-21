defmodule Hologram.BenchmarksTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Benchmarks
  alias Hologram.Commons.PLT

  test "build_module_beam_path_plt/0" do
    assert %PLT{} = plt = build_module_beam_path_plt()
    assert PLT.get!(plt, Hologram.Benchmarks) == :code.which(Hologram.Benchmarks)
  end
end
