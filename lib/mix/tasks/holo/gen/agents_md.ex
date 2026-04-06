defmodule Mix.Tasks.Holo.Gen.AgentsMd do
  @moduledoc """
  Syncs an AGENTS.md file with Hologram AI rules.

  The content is read from the `usage-rules.md` file shipped with the Hologram
  package and wrapped in `<!-- hologram-start -->` / `<!-- hologram-end -->` markers.

  If the target file already exists:
    - If markers are found, the content between them is replaced.
    - If no markers are found, the marked section is appended at the end.

  If the target file doesn't exist, it is created with the marked section.

      $ mix holo.gen.agents_md
  """

  use Mix.Task

  @doc false
  @impl Mix.Task
  def run(opts \\ []) do
    Hologram.Generators.AIRules.sync("AGENTS.md", opts)
  end
end
