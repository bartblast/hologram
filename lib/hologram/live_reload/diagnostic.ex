defmodule Hologram.LiveReload.Diagnostic do
  @moduledoc false

  # Every shape read below is Elixir's rather than Hologram's, so an Elixir
  # release rendering a diagnostic differently is read wrongly here. The tests
  # run a diagnostic the compiler really produced through this, so such a change
  # fails there rather than going unnoticed until somebody sees the overlay.
  #
  # TODO: when live reload compiles without Phoenix, the compiler's diagnostics
  # arrive as structs and none of this reading is needed - see the TODO in
  # Hologram.LiveReload.reload_code/1.

  @typedoc """
  A run of text and the tone it reads in.
  """
  @type segment :: %{tone: atom, text: String.t()}

  # The escape sequences the compiler colors its diagnostics with when ANSI is
  # enabled. They carry no meaning outside a terminal, and would otherwise be
  # shown as the characters they are made of.
  @ansi_escapes_regex ~r/\e\[[0-9;]*[a-zA-Z]/

  # IMPORTANT!
  # A stack frame is read the same way on the client, in
  # assets/js/uncaught_error_overlay.mjs - an error report and a compiler
  # diagnostic both carry frames, and the two overlays are meant to render one
  # alike. The rules differ because what surrounds a frame does: here every
  # frame names an app, whereas there a message can hold a colon of its own.
  # Always change both together, or the overlays drift apart.
  #
  # A stack frame, which the compiler prints below a diagnostic raised while
  # compiling, as in
  # "  (hologram 0.10.1) lib/hologram/template.ex:40: Hologram.Template.build/1".
  # The app it came from opens it, which is what tells a frame from the rest of
  # the output - the file it names is optional, since a frame expanding a macro
  # says that instead.
  @frame_regex ~r/^(\s*\([^)]*\)\s+)(\S[^:]*(?::\d+)*:\s+)?(.*)$/u

  # A location and what it points at, as in
  # "  └─ lib/my_app.ex:3:5: MyApp.bar/0" - the marker leading it, where in the
  # source, and what was being compiled there, which a location raised outside
  # any function doesn't name.
  @location_regex ~r/^(\s*└─\s*)(\S+:\s+)?(.*)$/u

  # The gutter a source excerpt opens with, holding the line number, as in
  # "  3 │     foo()".
  @source_excerpt_regex ~r/^(\s*\d+\s*│\s?)(.*)$/u

  @doc """
  Returns the compiler's output as lines, each a list of segments.

  IMPORTANT!
  Each tone names a class the overlay styles, in assets/js/error_overlay.mjs.
  A tone with no class there renders unstyled - always update both together.

  Every line reads in one of four tones:

    * `:banner` - what went wrong, as in `** (CompileError) ...`, `error: ...`
      and `warning: ...`
    * `:body` - the source the diagnostic points at
    * `:chrome` - the scaffolding holding the rest apart: line-number gutters,
      carets and section rules
    * `:meta` - where it points, as in `└─ lib/my_app.ex:3:5: MyApp.bar/0`

  A line matching none of them reads in `:chrome`, so output in a shape
  this doesn't know is still shown as it was written.
  """
  @spec to_lines(String.t()) :: [[segment]]
  def to_lines(output) do
    output
    |> strip_ansi_escapes()
    |> String.split("\n")
    |> Enum.map(&to_segments/1)
  end

  defp segment(tone, text), do: %{tone: tone, text: text}

  defp strip_ansi_escapes(text) do
    Regex.replace(@ansi_escapes_regex, text, "")
  end

  defp to_frame_segments(line) do
    case Regex.run(@frame_regex, line) do
      [_match, app, "", running] ->
        [segment(:chrome, app), segment(:body, running)]

      [_match, app, location, running] ->
        [segment(:chrome, app), segment(:meta, location), segment(:body, running)]

      _fallback ->
        [segment(:chrome, line)]
    end
  end

  # Split the way a stack frame is, so what was being compiled reads apart from
  # where it is - the same parts, told apart the same way.
  defp to_location_segments(line) do
    case Regex.run(@location_regex, line) do
      [_match, marker, "", location] ->
        [segment(:chrome, marker), segment(:meta, location)]

      [_match, marker, location, compiling] ->
        [segment(:chrome, marker), segment(:meta, location), segment(:body, compiling)]

      _fallback ->
        [segment(:meta, line)]
    end
  end

  defp to_segments(line) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, ["** (", "error:", "warning:"]) ->
        [segment(:banner, line)]

      String.starts_with?(trimmed, ["== ", "│"]) ->
        [segment(:chrome, line)]

      String.starts_with?(trimmed, "└─") ->
        to_location_segments(line)

      Regex.match?(@frame_regex, line) ->
        to_frame_segments(line)

      true ->
        to_source_excerpt_segments(line)
    end
  end

  defp to_source_excerpt_segments(line) do
    case Regex.run(@source_excerpt_regex, line) do
      [_match, gutter, source] -> [segment(:chrome, gutter), segment(:body, source)]
      nil -> [segment(:chrome, line)]
    end
  end
end
