defmodule Hologram.LiveReloadTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.LiveReload

  describe "assets_extensions/0" do
    test "returns a list of asset file extensions" do
      result = assets_extensions()

      assert is_list(result)
      assert ".css" in result
    end
  end
end
