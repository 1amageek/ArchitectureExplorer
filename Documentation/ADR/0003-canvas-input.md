# Canvas input ownership

The user requires Figma-like trackpad behavior. The renderer adapter owns wheel input within the graph container. Unmodified wheel deltas pan by inverse screen pixels. Shift maps a vertical-only wheel delta to horizontal pan. Control-wheel (browser trackpad pinch) and Command-wheel zoom around the pointer and clamp to renderer zoom bounds. The capture listener prevents browser scrolling/zoom and the renderer's default wheel zoom; Inspector and Navigator retain normal scrolling. Background drag pans through Cytoscape. Diagram updates preserve pan and zoom.

Browser behavioral checks compare rendered node positions and zoom before and after synthetic pixel wheel, diagonal wheel and control-wheel events. Browser screenshot checks cover actual graph layout and clipping.
