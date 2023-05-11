defmodule Hologram.Commons.StringUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.StringUtils

  test "wrap/3" do
    assert wrap("ab", "cd", "ef") == "cdabef"
  end
end
