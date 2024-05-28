defmodule Hologram.RuntimeSettingsTest do
  use Hologram.Test.BasicCase, async: false
  import Hologram.RuntimeSettings

  test "navigate_to_prefetched_page_action_name/0" do
    assert navigate_to_prefetched_page_action_name() == :__navigate_to_prefetched_page__
  end

  test "prefetch_page_action_name/0" do
    assert prefetch_page_action_name() == :__prefetch_page__
  end
end
