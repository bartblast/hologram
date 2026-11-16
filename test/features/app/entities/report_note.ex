defmodule HologramFeatureTests.Entities.ReportNote do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Report

  attribute :body, :string

  relationship :report, Report

  allow :read
  allow :update, via: {:read, report}
end
