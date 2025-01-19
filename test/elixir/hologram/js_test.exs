defmodule Hologram.JSTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.JS

  test "exec/1" do
    assert exec("console.log('Hello, world!');") == nil
  end
end
