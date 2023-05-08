defmodule Hologram.Template.BuilderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Template.Builder

  test "text node" do
    assert build([{:text, "abc"}]) == [{:text, "abc"}]
  end
end
