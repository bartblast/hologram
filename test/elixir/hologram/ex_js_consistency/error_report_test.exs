defmodule Hologram.ExJsConsistency.ErrorReportTest do
  @moduledoc """
  IMPORTANT!
  The client reads an uncaught error's report by its shape, in
  assets/js/uncaught_error_overlay.mjs. That shape is Elixir's rather than
  Hologram's, so these pin the parts the client keys on - an Elixir release
  rendering a report differently fails here rather than going unnoticed until
  somebody sees the overlay.

  TODO: read the client's frames from the boxed stacktrace instead of from the
  rendered report, which would leave only the message needing to be read by
  shape.
  """
  use Hologram.Test.BasicCase, async: true

  @moduletag :consistency

  # IMPORTANT!
  # A copy of FRAME_START_REGEX in assets/js/uncaught_error_overlay.mjs - what
  # the client keys on to find where a report's message ends and its frames
  # begin. Always update both together, or this stops pinning what the client
  # actually reads.
  @frame_start_regex ~r/^ {4}(?:\([^)]*\) )?\S*\.\w+:(?:\d+:)? /

  def only_tuple({_first, _second}), do: :ok

  defp format(error, stacktrace) do
    {blamed, blamed_stacktrace} = Exception.blame(:error, error, stacktrace)

    Exception.format_banner(:error, blamed) <>
      "\n" <> Exception.format_stacktrace(blamed_stacktrace)
  end

  defp report(fun) do
    fun.()
  rescue
    error -> format(error, __STACKTRACE__)
  end

  describe "a raised error's report" do
    test "opens with the message, marked the way the client expects" do
      report = report(fn -> raise "my message" end)

      assert String.starts_with?(report, "** (RuntimeError) my message")
    end

    test "indents every frame by four spaces" do
      report = report(fn -> raise "my message" end)

      [_message | frames] = String.split(report, "\n", trim: true)

      assert frames != []
      assert Enum.all?(frames, &String.starts_with?(&1, "    "))
    end

    test "names the app a frame came from in parentheses before its location" do
      report = report(fn -> Enum.map(:not_enumerable, & &1) end)

      assert report =~ ~r/^ {4}\(elixir [\d.]+\) \S+\.ex:\d+: /m
    end
  end

  describe "a clause mismatch's report" do
    # The listing is part of the message and is indented the way a frame is, so
    # the client would take it for one if it read a frame as anything indented.
    # Read the way the client reads it, the listing has to land in the message.
    test "indents the arguments it lists without making them look like frames" do
      lines =
        fn -> only_tuple(wrap_term(:not_a_tuple)) end
        |> report()
        |> String.split("\n")

      first_frame_index = Enum.find_index(lines, &Regex.match?(@frame_start_regex, &1))
      message_lines = Enum.take(lines, first_frame_index)

      assert "    # 1" in message_lines
      assert "    :not_a_tuple" in message_lines
    end
  end
end
