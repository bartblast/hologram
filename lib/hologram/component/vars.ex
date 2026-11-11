defmodule Hologram.Component.Vars do
  @moduledoc false

  # Tags the vars map a template is called with - its props and state, or for a page its params
  # and state. A template reads `@name` as `vars.name`, so a KeyError whose term carries this tag
  # comes from reading a var the template doesn't have, not from a map the template holds or
  # builds. The one way around that is a template handing the bare `vars` on to a helper that
  # reads a missing key from it. The tagged map carries keys this struct doesn't declare, since
  # which vars a template has is only known when it renders.
  defstruct []
end
