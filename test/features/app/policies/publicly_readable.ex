defmodule HologramFeatureTests.Policies.PubliclyReadable do
  use Hologram.Policy

  allow :read, when: public == true
end
