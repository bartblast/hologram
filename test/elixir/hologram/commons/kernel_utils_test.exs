defmodule Hologram.Commons.KernelUtilsTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Commons.KernelUtils

  test "inspect/1" do
    assert Kernel.inspect(%{x: 1, y: 2}) in ["%{x: 1, y: 2}", "%{y: 2, x: 1}"]
    assert KernelUtils.inspect(%{x: 1, y: 2}) == "%{x: 1, y: 2}"
  end
end
