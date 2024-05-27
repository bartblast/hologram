defmodule Hologram.RuntimeSettingsTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.RuntimeSettings

  test "prefetch_page_action_name/0" do
    assert prefetch_page_action_name() == :__prefetch_page__
  end
end
