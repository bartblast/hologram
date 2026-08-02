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

  # Raises an error whose message runs over several lines, the same way.
  defp raise_function_clause_error(session) do
    expected_msg =
      ~r/^no function clause matching in HologramFeatureTests\.ErrorOverlayPage\.only_tuple\/1/

    assert_client_error session, FunctionClauseError, expected_msg, fn ->
      session
      |> visit(ErrorOverlayPage)
      |> click(button("No matching clause"))
    end

    session
  end

  # Matches an element the overlay renders in the given tone, holding the given
  # text - which is what says a run of text was read the way it should be.
  defp toned(tone, text) do
    css(".hologram-error-overlay__tone-#{tone}", count: :any, text: text)
  end

  feature "renders the error the page raised", %{session: session} do
    session
    |> raise_error()
    |> assert_has(@overlay)
    |> assert_text(@overlay, "Runtime Error")
    |> assert_text(@overlay, "** (RuntimeError) overlaid error")
  end

  # The overlay shows what the console shows, stacktrace included, so every frame
  # the error came through is named in the page as well.
  feature "renders the stacktrace alongside the message", %{session: session} do
    page = inspect(ErrorOverlayPage)

    session
    |> raise_error()
    |> assert_text(@overlay, "#{page}.inner_fun/0")
    |> assert_text(@overlay, "#{page}.middle_fun/0")
    |> assert_text(@overlay, "#{page}.outer_fun/0")
    |> assert_text(@overlay, "#{page}.action/3")
  end

  feature "sets the message apart from the frames it came through", %{session: session} do
    session
    |> raise_error()
    |> assert_has(toned("banner", "** (RuntimeError) overlaid error"))
  end

  # A frame the page raised in is split, so where it happened reads apart from
  # what was running there.
  feature "sets a frame's source location apart from what was running", %{session: session} do
    session
    |> raise_error()
    |> assert_has(toned("meta", "error_overlay_page.ex:"))
    |> assert_has(toned("body", "#{inspect(ErrorOverlayPage)}.inner_fun/0"))
  end

  # A frame from outside the page reads in one tone throughout, so the page's own
  # frames stand out of the run rather than having to be found in it.
  feature "reads a frame from outside the page in one tone", %{session: session} do
    session
    |> raise_error()
    |> assert_has(toned("chrome", "(hologram "))
  end

  # A FunctionClauseError lists the arguments it was given, indenting them the
  # way a frame is indented. The listing is part of the message, so it has to
  # stay in the message rather than be read as the frames that follow it.
  feature "keeps a message running over several lines in one piece", %{session: session} do
    session
    |> raise_function_clause_error()
    |> assert_has(toned("banner", "The following arguments were given to"))
    |> assert_has(toned("banner", ":not_a_tuple"))
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
