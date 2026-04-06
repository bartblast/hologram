defmodule Hologram.Generators.AIRules do
  @moduledoc false

  alias Hologram.Reflection

  @marker_start "<!-- hologram-start -->"
  @marker_end "<!-- hologram-end -->"

  @doc """
  Syncs an AI rules file (e.g. AGENTS.md, CLAUDE.md) with Hologram rules wrapped in markers.

  Options:
    * `:source_path` - path to the rules source file (defaults to deps/hologram/usage-rules.md)
    * `:target_dir` - target directory (defaults to current working directory)
  """
  @spec sync(String.t(), keyword()) :: :ok
  def sync(filename, opts \\ []) do
    source_path = Keyword.get(opts, :source_path, default_source_path())
    target_dir = Keyword.get(opts, :target_dir, Reflection.root_dir())
    content = File.read!(source_path)
    marked_content = build_marked_content(content)
    path = Path.join(target_dir, filename)

    if File.exists?(path) do
      update_file(path, filename, marked_content)
    else
      create_file(path, filename, marked_content)
    end

    :ok
  end

  defp append_marked_section(content, marked_content) do
    trimmed = String.trim_trailing(content)
    trimmed <> "\n\n" <> marked_content
  end

  defp build_marked_content(content) do
    stripped =
      content
      |> String.trim()
      |> strip_h1_heading()

    """
    #{@marker_start}
    ## Hologram

    #{stripped}
    #{@marker_end}
    """
  end

  defp create_file(path, filename, marked_content) do
    File.write!(path, marked_content)
    print("Created #{filename}")
  end

  defp default_source_path do
    Path.join(Reflection.root_dir(), "deps/hologram/usage-rules.md")
  end

  defp print(output) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(output)
  end

  defp replace_between_markers(content, marked_content) do
    pattern = ~r/#{Regex.escape(@marker_start)}.*?#{Regex.escape(@marker_end)}\r?\n?/s
    String.replace(content, pattern, marked_content)
  end

  defp strip_h1_heading(content) do
    String.replace(content, ~r/^# .+(\r?\n)*/, "")
  end

  defp update_file(path, filename, marked_content) do
    existing = File.read!(path)

    updated =
      if String.contains?(existing, @marker_start) and String.contains?(existing, @marker_end) do
        replace_between_markers(existing, marked_content)
      else
        append_marked_section(existing, marked_content)
      end

    File.write!(path, updated)
    print("Updated #{filename}")
  end
end
