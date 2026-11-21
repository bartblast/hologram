defmodule HologramFeatureTests.Components.Mutations.Jobs do
  use Hologram.Component
  use Hologram.DB

  alias HologramFeatureTests.Jobs.HoldRun
  alias HologramFeatureTests.Jobs.KillRun
  alias HologramFeatureTests.Jobs.RestockItem

  # The jobs reach this list through the ordinary read path - a derived query over the rows the
  # sync stream keeps current - so a job the worker moved to done shows here without the page being fetched again.
  derived :jobs, [RestockItem], &jobs_query/0

  derived :killed_jobs, [KillRun], &killed_jobs_query/0

  derived :held_jobs, [HoldRun], &held_jobs_query/0

  def template do
    ~HOLO"""
    <p>
      Jobs: <strong id="jobs"><code>{Enum.map_join(@jobs, ",", &"#{&1.amount}:#{&1.status}")}</code></strong>
    </p>
    <p>
      Killed jobs: <strong id="killed_jobs"><code>{Enum.map_join(@killed_jobs, ",", &"#{&1.label}:#{&1.status}")}</code></strong>
    </p>
    <p>
      Held jobs: <strong id="held_jobs"><code>{Enum.map_join(@held_jobs, ",", &"#{&1.label}:#{&1.status}")}</code></strong>
    </p>
    """
  end

  defp jobs_query do
    sort(RestockItem, amount)
  end

  defp killed_jobs_query do
    sort(KillRun, label)
  end

  defp held_jobs_query do
    sort(HoldRun, label)
  end
end
