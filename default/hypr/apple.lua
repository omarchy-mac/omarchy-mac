local paths = require("default.hypr.paths")

local apple_soc = paths.omarchy_path .. "/bin/omarchy-hw-apple-soc"

-- Apple Silicon without a bound Asahi GPU driver: the M3 generation on the
-- public kernel today, any later generation until its driver lands. Hyprland
-- then draws through Mesa's llvmpipe onto the firmware framebuffer
-- (simpledrm), which has no cursor plane and no buffer modifiers to speak of.
-- Asking the SoC command at session start rather than recording it at install
-- means a kernel that binds the GPU driver turns all of this off by itself.
if o.shell_succeeds(o.shell_quote(apple_soc)) and not o.shell_succeeds(o.shell_quote(apple_soc) .. " --gpu") then
  -- aquamarine: do not negotiate DRM format modifiers with a driver that has
  -- none to offer; simpledrm scanout is linear.
  hl.env("AQ_NO_MODIFIERS", "1")

  hl.config({
    cursor = {
      -- No cursor plane on simpledrm; a software cursor is the only kind.
      no_hardware_cursors = true,
    },
    render = {
      -- Direct scanout needs a real display driver to hand buffers to.
      direct_scanout = false,
    },
    misc = {
      -- Repaint only when something changed; llvmpipe pays per frame.
      vfr = true,
    },
  })
end
