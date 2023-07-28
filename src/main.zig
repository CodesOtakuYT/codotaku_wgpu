const std = @import("std");
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");
const zmath = @import("zmath");

// zig fmt: off
const vertex_shader_source =
\\  @group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
\\  struct VertexOut {
\\      @builtin(position) position_clip: vec4<f32>,
\\      @location(0) color: vec3<f32>,
\\  }
\\  @vertex fn main(
\\      @location(0) position: vec3<f32>,
\\      @location(1) color: vec3<f32>,
\\  ) -> VertexOut {
\\      var output: VertexOut;
\\      output.position_clip = vec4(position, 1.0) * object_to_clip;
\\      output.color = color;
\\      return output;
\\  }
;
const fragment_shader_source =
\\  @fragment fn main(
\\      @location(0) color: vec3<f32>,
\\  ) -> @location(0) vec4<f32> {
\\      return vec4(color, 1.0);
\\  }
// zig fmt: on
;

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

    const vertex_shader_module = zgpu.createWgslShaderModule(graphics_context.device, vertex_shader_source, "vertex shader");
    defer vertex_shader_module.release();

    const fragment_shader_module = zgpu.createWgslShaderModule(graphics_context.device, fragment_shader_source, "vertex shader");
    defer fragment_shader_module.release();

    const Vertex = struct {
        position: [3]f32,
        color: [3]f32,
    };

    const vertex_attributes = [_]zgpu.wgpu.VertexAttribute{
        .{
            .format = .float32x3,
            .offset = 0,
            .shader_location = 0,
        },
        .{
            .format = .float32x3,
            .offset = @offsetOf(Vertex, "color"),
            .shader_location = 1,
        },
    };

    const vertex_buffer_layouts = [_]zgpu.wgpu.VertexBufferLayout{.{
        .array_stride = @sizeOf(Vertex),
        .attribute_count = vertex_attributes.len,
        .attributes = &vertex_attributes,
    }};

    const bind_group_layout = graphics_context.createBindGroupLayout(&.{
        zgpu.bufferEntry(0, .{ .vertex = true }, .uniform, true, 0),
    });
    defer graphics_context.releaseResource(bind_group_layout);

    const pipeline_layout = graphics_context.createPipelineLayout(&.{bind_group_layout});
    defer graphics_context.releaseResource(pipeline_layout);

    const color_targets = [_]zgpu.wgpu.ColorTargetState{
        .{
            .format = zgpu.GraphicsContext.swapchain_format,
        },
    };

    const pipeline_descriptor = zgpu.wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = vertex_shader_module,
            .entry_point = "main",
            .buffer_count = vertex_buffer_layouts.len,
            .buffers = &vertex_buffer_layouts,
        },
        .fragment = &.{
            .module = fragment_shader_module,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
    };
    const render_pipeline_handle = graphics_context.createRenderPipeline(pipeline_layout, pipeline_descriptor);

    const bind_group_handle = graphics_context.createBindGroup(bind_group_layout, &[_]zgpu.BindGroupEntryInfo{
        .{ .binding = 0, .buffer_handle = graphics_context.uniforms.buffer, .offset = 0, .size = @sizeOf(zmath.Mat) },
    });

    const vertex_buffer = graphics_context.createBuffer(.{
        .usage = .{ .copy_dst = true, .vertex = true },
        .size = 3 * @sizeOf(Vertex),
    });
    const vertex_data = [_]Vertex{
        .{ .position = [3]f32{ 0.0, 0.5, 0.0 }, .color = [3]f32{ 1.0, 0.0, 0.0 } },
        .{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [3]f32{ 0.0, 1.0, 0.0 } },
        .{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [3]f32{ 0.0, 0.0, 1.0 } },
    };
    graphics_context.queue.writeBuffer(
        graphics_context.lookupResource(vertex_buffer).?,
        0,
        Vertex,
        vertex_data[0..],
    );

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

        const camera_world_to_view = zmath.lookAtLh(
            zmath.f32x4(3.0, 3.0, -3.0, 1.0),
            zmath.f32x4(0.0, 0.0, 0.0, 1.0),
            zmath.f32x4(0.0, 1.0, 0.0, 0.0),
        );

        const framebuffer_width = graphics_context.swapchain_descriptor.width;
        const framebuffer_height = graphics_context.swapchain_descriptor.height;

        const camera_view_to_clip = zmath.perspectiveFovLh(
            0.25 * std.math.pi,
            @as(f32, @floatFromInt(framebuffer_width)) / @as(f32, @floatFromInt(framebuffer_height)),
            0.01,
            200.0,
        );
        const camera_world_to_clip = zmath.mul(camera_world_to_view, camera_view_to_clip);

        const current_texture_view = graphics_context.swapchain.getCurrentTextureView();
        defer current_texture_view.release();

        const encoder = graphics_context.device.createCommandEncoder(null);
        defer encoder.release();

        {
            const render_pipeline = graphics_context.lookupResource(render_pipeline_handle).?;
            const vertex_buffer_info = graphics_context.lookupResourceInfo(vertex_buffer).?;
            const bind_group = graphics_context.lookupResource(bind_group_handle).?;

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
            render_pass_encoder.setVertexBuffer(0, vertex_buffer_info.gpuobj.?, 0, vertex_buffer_info.size);
            render_pass_encoder.setPipeline(render_pipeline);

            const object_to_world = zmath.mul(zmath.rotationY(0), zmath.translation(-1.0, 0.0, 0.0));
            const object_to_clip = zmath.mul(object_to_world, camera_world_to_clip);

            const mem = graphics_context.uniformsAllocate(zmath.Mat, 1);
            mem.slice[0] = zmath.transpose(object_to_clip);
            render_pass_encoder.setBindGroup(0, bind_group, &.{mem.offset});
            render_pass_encoder.draw(3, 1, 0, 0);
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
