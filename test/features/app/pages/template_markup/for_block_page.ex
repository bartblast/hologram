defmodule HologramFeatureTests.TemplateMarkup.ForBlockPage do
  use Hologram.Page

  route "/template-markup/for-block"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~H"""
    {%for n <- [1, 2, 3]}
      <div id="item_{n}" class="item">text_{n}</div>
    {/for}
    """
  end
end
