defmodule HologramFeatureTests.TemplateSyntax.RawBlockPage do
  use Hologram.Page

  route "/template-syntax/raw-block"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"{%raw}{%if false}abc{@var}xyz{/if}{/raw}"
  end
end
