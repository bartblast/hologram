defmodule HologramFeatureTests.TemplateSyntax.IfBlockPage do
  use Hologram.Page

  route "/template-syntax/if-block"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <div id="block_1">
      a{%if true}b{/if}c
    </div>

    <div id="block_2">
      a{%if false}b{%else}c{/if}d
    </div>

    <div id="block_3">
      a{%if false}b{/if}c
    </div>
    """
  end
end
