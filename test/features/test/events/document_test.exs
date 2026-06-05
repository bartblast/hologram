defmodule HologramFeatureTests.Events.DocumentTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.DocumentPage

  feature "handles a global event", %{session: session} do
    session
    |> visit(DocumentPage)
    |> send_keys([:control, "k"])
    |> assert_text(css("#shortcut_result"), "1")
  end

  feature "activates a conditionally rendered binding", %{session: session} do
    session
    |> visit(DocumentPage)
    # Before its branch renders, Escape must not dispatch. The handled shortcut is a happens-after
    # barrier: once it lands, the earlier Escape has been processed too, so a zero count is reliable.
    |> send_keys([:escape])
    |> send_keys([:control, "k"])
    |> assert_text(css("#shortcut_result"), "1")
    |> assert_text(css("#escape_result"), "0")
    # Rendering the gated <document> activates the escape binding.
    |> click(css("#toggle_listening"))
    |> send_keys([:escape])
    |> assert_text(css("#escape_result"), "1")
  end

  feature "deactivates a binding that is no longer rendered", %{session: session} do
    session
    |> visit(DocumentPage)
    # Render the gated <document>, then confirm Escape dispatches.
    |> click(css("#toggle_listening"))
    |> send_keys([:escape])
    |> assert_text(css("#escape_result"), "1")
    # Removing the gated <document> deactivates it. The shortcut barrier confirms the later Escape was
    # processed, so the unchanged escape count proves it did not dispatch.
    |> click(css("#toggle_listening"))
    |> send_keys([:escape])
    |> send_keys([:control, "k"])
    |> assert_text(css("#shortcut_result"), "1")
    |> assert_text(css("#escape_result"), "1")
  end
end
