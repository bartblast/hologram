defmodule Hologram.Compiler.Formatter do
  def append_line_break(output) do
    output <> "\n"
  end

  def maybe_append_new_line(output, "") do
    output
  end

  def maybe_append_new_line(output, str) do
    separator = if String.ends_with?(output, "\n"), do: "", else: "\n"
    output <> separator <> str
  end

  def maybe_append_new_section(output, "") do
    output
  end

  def maybe_append_new_section(output, str) do
    separator = if String.ends_with?(output, "\n\n"), do: "", else: "\n\n"
    output <> separator <> str
  end
end
