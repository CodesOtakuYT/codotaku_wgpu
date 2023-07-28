const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");

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

    zgui.init(allocator);
    defer zgui.deinit();

    const scale_factor = scale_factor: {
        const scale = window.getContentScale();
        break :scale_factor @max(scale[0], scale[1]);
    };

    _ = zgui.io.addFontFromFile(
        "Roboto-Medium.ttf",
        std.math.floor(16.0 * scale_factor),
    );

    zgui.backend.init(
        window,
        graphics_context.device,
        @intFromEnum(zgpu.GraphicsContext.swapchain_format),
    );
    defer zgui.backend.deinit();

    zgui.getStyle().scaleAllSizes(scale_factor);

    var color = [_]f32{ 0.0, 0.0, 0.0 };

    while (!window.shouldClose()) {
        zglfw.pollEvents();

        zgui.backend.newFrame(
            graphics_context.swapchain_descriptor.width,
            graphics_context.swapchain_descriptor.height,
        );

        _ = zgui.colorPicker3("Color", .{ .col = &color });

        const current_texture_view = graphics_context.swapchain.getCurrentTextureView();
        defer current_texture_view.release();

        const encoder = graphics_context.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const render_pass_encoder = zgpu.beginRenderPassSimple(
                encoder,
                .clear,
                current_texture_view,
                .{
                    .r = color[0],
                    .g = color[1],
                    .b = color[2],
                    .a = 1.0,
                },
                null,
                null,
            );
            defer {
                render_pass_encoder.end();
                render_pass_encoder.release();
            }
            zgui.backend.draw(render_pass_encoder);
        }

        const command_buffer = encoder.finish(null);
        graphics_context.submit(&.{command_buffer});

        _ = graphics_context.present();
    }
}
