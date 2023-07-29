@group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
@group(0) @binding(1) var<uniform> color: vec3<f32>;

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
}

@vertex fn vertex(
    @location(0) position: vec3<f32>,
) -> VertexOut {
    var output: VertexOut;
    output.position_clip = vec4(position, 1.0) * object_to_clip;
    return output;
}

@fragment fn fragment() -> @location(0) vec4<f32> {
    return vec4(vec3(1.0), 1.0);
}