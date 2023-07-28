const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");

pub fn main() !void {
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(general_purpose_allocator.deinit() == .ok);
    const allocator = general_purpose_allocator.allocator();

    try zglfw.init();
    defer zglfw.terminate();

    const window = try zglfw.Window.create(800, 600, "Salam", null);
    defer window.destroy();

    const graphics_context = try zgpu.GraphicsContext.create(allocator, window);
    defer graphics_context.destroy(allocator);

    while (!window.shouldClose()) {
        zglfw.pollEvents();

        const current_texture_view = graphics_context.swapchain.getCurrentTextureView();
        defer current_texture_view.release();

        const encoder = graphics_context.device.createCommandEncoder(null);
        defer encoder.release();

        const command_buffer = encoder.finish(null);
        graphics_context.submit(&.{command_buffer});

        _ = graphics_context.present();
    }
}
