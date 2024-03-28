defmodule HologramFeatureTests.TmpLayout do
  use Hologram.Component
  alias Hologram.UI.Runtime

  def template do
    ~H"""
    <html>
      <head>
        <Runtime />
      </head>
      
      <body>
        <div>layout start</div>
        
        <div>
          <slot />
        </div>
        
        <div>layout end</div>
      </body>
    </html>
    """
  end
end
