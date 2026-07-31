defmodule HologramFeatureTests.ErrorOverlayTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ErrorOverlayPage

  @dismiss_button css("#hologram-uncaught-error-overlay button[aria-label='Dismiss']")
  @overlay css("#hologram-uncaught-error-overlay")

  # Raises an uncaught error in the page, consuming the JavaScript error it logs
  # so that later interactions don't fail on it, and returns the session.
  defp raise_error(session) do
    assert_client_error session, RuntimeError, "overlaid error", fn ->
      session
      |> visit(ErrorOverlayPage)
      |> click(button("Raise error"))
    end

    session
  end

  feature "renders the error the page raised", %{session: session} do
    session
    |> raise_error()
    |> assert_has(@overlay)
    |> assert_text(@overlay, "Runtime Error")
    |> assert_text(@overlay, "** (RuntimeError) overlaid error")
  end

  # The overlay shows what the console shows, stacktrace included, so the frame
  # the error was raised in is named in the page as well.
  feature "renders the stacktrace alongside the message", %{session: session} do
    session
    |> raise_error()
    |> assert_text(@overlay, "#{inspect(ErrorOverlayPage)}.action/3")
  end

  feature "dismisses on the dismiss button", %{session: session} do
    session
    |> raise_error()
    |> click(@dismiss_button)
    |> refute_has(@overlay)
  end

  feature "dismisses on Escape", %{session: session} do
    session
    |> raise_error()
    |> send_keys([:escape])
    |> refute_has(@overlay)
  end
end
