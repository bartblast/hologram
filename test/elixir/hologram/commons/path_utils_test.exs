defmodule Hologram.Commons.PathUtilsTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Commons.PathUtils

  test "path_separator/0" do
    result = path_separator()

    case :os.type() do
      {:unix, _name} ->
        assert result == "/"

      _fallback ->
        assert result == "\\"
    end
  end
end
