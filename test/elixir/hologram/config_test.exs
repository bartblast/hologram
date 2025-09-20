defmodule Hologram.ConfigTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.Config

  describe "init/2" do
    test "hologram mode" do
      original_mode = Application.get_env(:hologram, :mode)

      on_exit(fn ->
        if original_mode do
          Application.put_env(:hologram, :mode, original_mode)
        else
          Application.delete_env(:hologram, :mode)
        end
      end)

      init(:test_app, :test_env)

      assert Application.get_env(:hologram, :mode) == :standalone
    end
  end
end
